//
//  TrackingPointsRenderModule.swift
//  AugmentKit
//
//  MIT License
//
//  Copyright (c) 2018 JamieScanlon
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Foundation
import ARKit
import AugmentKitShader
import MetalKit
import simd

class TrackingPointsRenderModule: RenderModule {
    
    static var identifier = "TrackingPointsRenderModule"
    
    //
    // Setup
    //
    
    var moduleIdentifier: String {
        return TrackingPointsRenderModule.identifier
    }
    var renderLayer: Int {
        return Int.max
    }
    var state: ShaderModuleState = .uninitialized
    var sharedModuleIdentifiers: [String]? = [SharedBuffersRenderModule.identifier]
    var renderDistance: Double = 500
    var errors = [AKError]()
    
    // The number of tracking points to render
    private(set) var trackingPointCount: Int = 0

    func initializeBuffers(withDevice aDevice: MTLDevice, maxInFlightFrames: Int, maxInstances: Int) {
        
        state = .initializing
        
        device = aDevice
        
        // Calculate our uniform buffer sizes. We allocate `maxInFlightFrames` instances for uniform
        // storage in a single buffer. This allows us to update uniforms in a ring (i.e. triple
        // buffer the uniforms) so that the GPU reads from one slot in the ring wil the CPU writes
        // to another. Anchor uniforms should be specified with a max instance count for instancing.
        // Also uniform storage must be aligned (to 256 bytes) to meet the requirements to be an
        // argument in the constant address space of our shading functions.
        let trackingPointDataBufferSize = Constants.alignedTrackingPointDataSize * maxInFlightFrames
        trackingPointDataBuffer = device?.makeBuffer(length: trackingPointDataBufferSize, options: .storageModeShared)
        trackingPointDataBuffer?.label = "TrackingPointDataBuffer"
        
    }
    
    // Load the data from the Model Provider.
    func loadAssets(forGeometricEntities: [AKGeometricEntity], fromModelProvider: ModelProvider?, textureLoader: MTKTextureLoader, completion: (() -> Void)) {
        completion()
    }
    
    // This funciton should set up the vertex descriptors, pipeline / depth state descriptors,
    // textures, etc.
    func loadPipeline(withModuleEntities: [AKEntity], metalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider, modelManager: ModelManager, renderPass: RenderPass? = nil, numQualityLevels: Int = 1, completion: (([DrawCallGroup]) -> Void)? = nil) {
        
        guard let pointVertexShader = metalLibrary.makeFunction(name: "pointVertexShader") else {
            print("Serious Error - failed to create the pointVertexShader function")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeShaderInitializationFailed, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            completion?([])
            return
        }
        
        guard let pointFragmentShader = metalLibrary.makeFunction(name: "pointFragmentShader") else {
            print("Serious Error - failed to create the pointFragmentShader function")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeShaderInitializationFailed, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            completion?([])
            return
        }
        
        DispatchQueue.global(qos: .default).async { [weak self] in
        
            // Create a vertex descriptor for our image plane vertex buffer
            let trackingPointVertexDescriptor = MTLVertexDescriptor()
            
            // Positions
            trackingPointVertexDescriptor.attributes[Int(kVertexAttributePosition.rawValue)].format = .float4
            trackingPointVertexDescriptor.attributes[Int(kVertexAttributePosition.rawValue)].offset = 0
            trackingPointVertexDescriptor.attributes[Int(kVertexAttributePosition.rawValue)].bufferIndex = Int(kBufferIndexTrackingPointData.rawValue)
            
            // Color
            trackingPointVertexDescriptor.attributes[Int(kVertexAttributeColor.rawValue)].format = .float4
            trackingPointVertexDescriptor.attributes[Int(kVertexAttributeColor.rawValue)].offset = 16
            trackingPointVertexDescriptor.attributes[Int(kVertexAttributeColor.rawValue)].bufferIndex = Int(kBufferIndexTrackingPointData.rawValue)
            
            // Buffer Layout
            trackingPointVertexDescriptor.layouts[Int(kBufferIndexTrackingPointData.rawValue)].stride = 32
            trackingPointVertexDescriptor.layouts[Int(kBufferIndexTrackingPointData.rawValue)].stepRate = 1
            trackingPointVertexDescriptor.layouts[Int(kBufferIndexTrackingPointData.rawValue)].stepFunction = .perVertex
            
            let trackingPointPipelineStateDescriptor = MTLRenderPipelineDescriptor()
            trackingPointPipelineStateDescriptor.label = "TrackingPointPipeline"
            trackingPointPipelineStateDescriptor.vertexFunction = pointVertexShader
            trackingPointPipelineStateDescriptor.fragmentFunction = pointFragmentShader
            trackingPointPipelineStateDescriptor.vertexDescriptor = trackingPointVertexDescriptor
            trackingPointPipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
            trackingPointPipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = true
            trackingPointPipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one
            trackingPointPipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
            trackingPointPipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = .add
            trackingPointPipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = .add
            trackingPointPipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
            trackingPointPipelineStateDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
            trackingPointPipelineStateDescriptor.sampleCount = renderDestination.sampleCount
            
            let trackingPointDepthStateDescriptor = MTLDepthStencilDescriptor()
            trackingPointDepthStateDescriptor.depthCompareFunction = .always
            trackingPointDepthStateDescriptor.isDepthWriteEnabled = true
            
            var drawCallGroups = [DrawCallGroup]()
            if let drawCall = renderPass?.drawCall(withRenderPipelineDescriptor: trackingPointPipelineStateDescriptor, depthStencilDescriptor: trackingPointDepthStateDescriptor) {
                let drawCallGroup = DrawCallGroup(drawCalls: [drawCall])
                drawCallGroup.moduleIdentifier = TrackingPointsRenderModule.identifier
                drawCallGroups = [drawCallGroup]
            }
            
            DispatchQueue.main.async { [weak self] in
                self?.state = .ready
                completion?(drawCallGroups)
            }
        }
        
    }
    
    //
    // Per Frame Updates
    //
    
    // The buffer index is the index into the ring on in flight buffers
    func updateBufferState(withBufferIndex bufferIndex: Int) {
        
        trackingPointDataBufferOffset = Constants.alignedTrackingPointDataSize * bufferIndex
        trackingPointDataBufferAddress = trackingPointDataBuffer?.contents().advanced(by: trackingPointDataBufferOffset)
        
    }
    
    // Update the buffer data
    
    func updateBuffers(withModuleEntities: [AKEntity], cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties, shadowProperties: ShadowProperties, argumentBufferProperties: ArgumentBufferProperties, forRenderPass renderPass: RenderPass) {
        
        trackingPointCount = 0
        
        guard let rawFeaturePoints = cameraProperties.rawFeaturePoints else {
            return
        }
        
        for index in 0..<rawFeaturePoints.points.count {
            
            if index >= Constants.maxTrackingPointCount {
                break
            }
            
            /**
             * Memory layout of struct PointVertexIn struct:
             *  float4 position
             *  float4 color
             */
            
            let point = rawFeaturePoints.points[index]
            let trackingPointData = trackingPointDataBufferAddress?.assumingMemoryBound(to: SIMD4<Float>.self).advanced(by: index * 2)
            trackingPointData?.pointee = SIMD4<Float>(point.x, point.y, point.z, 1.0)
            
            let colorData = trackingPointDataBufferAddress?.assumingMemoryBound(to: SIMD4<Float>.self).advanced(by: index * 2 + 1)
            colorData?.pointee = SIMD4<Float>(0.5, 1.0, 1.0, 1.0) // Light blue
            
            trackingPointCount += 1
            
            if trackingPointCount > Constants.maxTrackingPointCount {
                break
            }
        }
        
    }
    
    func draw(withRenderPass renderPass: RenderPass, sharedModules: [SharedRenderModule]?) {
        
        guard let renderEncoder = renderPass.renderCommandEncoder else {
            return
        }
        
        guard trackingPointCount > 0 else {
            return
        }
        
        for drawCallGroup in renderPass.drawCallGroups {
            
            guard drawCallGroup.moduleIdentifier == moduleIdentifier else {
                continue
            }
            
            // Geometry Draw Calls
            for drawCall in drawCallGroup.drawCalls {
        
                // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
                renderEncoder.pushDebugGroup("Draw Tracking Points")
                
                drawCall.prepareDrawCall(withRenderPass: renderPass)
                
                renderEncoder.setVertexBuffer(trackingPointDataBuffer, offset: trackingPointDataBufferOffset, index: Int(kBufferIndexTrackingPointData.rawValue))
                if let sharedRenderModule = sharedModules?.first(where: {$0.moduleIdentifier == SharedBuffersRenderModule.identifier}), let sharedBuffer = sharedRenderModule.sharedUniformsBuffer?.buffer, let sharedBufferOffset = sharedRenderModule.sharedUniformsBuffer?.currentBufferFrameOffset {
                    renderEncoder.pushDebugGroup("Draw Shared Uniforms")
                    renderEncoder.setVertexBuffer(sharedBuffer, offset: sharedBufferOffset, index: sharedRenderModule.sharedUniformsBuffer?.shaderAttributeIndex ?? 0)
                    renderEncoder.popDebugGroup()
                }
                renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: trackingPointCount)
                
                renderEncoder.popDebugGroup()
                
            }
            
        }
        
    }
    
    // Called when Metal and the GPU has fully finished proccssing the commands we're encoding
    // this frame. This indicates when the dynamic buffers, that we're writing to this frame,
    // will no longer be needed by Metal and the GPU. This gets called per frame
    func frameEncodingComplete(renderPasses: [RenderPass]) {
        
    }
    
    //
    // Util
    //
    
    func recordNewError(_ akError: AKError) {
        errors.append(akError)
    }
    
    // MARK: - Private
    
    private enum Constants {
        static let maxTrackingPointCount = 256
        static let alignedTrackingPointDataSize = ((MemoryLayout<SIMD3<Float>>.stride * maxTrackingPointCount) & ~0xFF) + 0x100
    }
    
    private var device: MTLDevice?
    private var trackingPointDataBuffer: MTLBuffer?
    
    // Offset within trackingPointDataBuffer to set for the current frame
    private var trackingPointDataBufferOffset: Int = 0
    
    // Addresses to write anchor uniforms to each frame
    private var trackingPointDataBufferAddress: UnsafeMutableRawPointer?
    
}
