//
//  CameraPlaneRenderModule.swift
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

class CameraPlaneRenderModule: RenderModule {
    
    static var identifier = "CameraPlaneRenderModule"
    
    //
    // Setup
    //
    
    var moduleIdentifier: String {
        return CameraPlaneRenderModule.identifier
    }
    var renderLayer: Int {
        return 0
    }
    var isInitialized: Bool = false
    var sharedModuleIdentifiers: [String]? = nil
    var renderDistance: Double = 500
    var errors = [AKError]()
    
    func initializeBuffers(withDevice aDevice: MTLDevice, maxInFlightBuffers: Int, maxInstances: Int) {
        
        device = aDevice
        
        // Create a vertex buffer with our image plane vertex data.
        let imagePlaneVertexDataCount = Constants.imagePlaneVertexData.count * MemoryLayout<Float>.size
        imagePlaneVertexBuffer = device?.makeBuffer(bytes: Constants.imagePlaneVertexData, length: imagePlaneVertexDataCount, options: [])
        imagePlaneVertexBuffer?.label = "ImagePlaneVertexBuffer"
        
    }
    
    func loadAssets(forGeometricEntities: [AKGeometricEntity], fromModelProvider: ModelProvider?, textureLoader: MTKTextureLoader, completion: (() -> Void)) {
        completion()
    }
    
    func loadPipeline(withMetalLibrary metalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider, textureBundle: Bundle, forRenderPass renderPass: RenderPass? = nil) -> [DrawCallGroup] {
        
        guard let device = device else {
            print("Serious Error - device not found")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeDeviceNotFound, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return []
        }
        
        // Check to make sure this geometry should be rendered in this render pass
        if let geometryFilterFunction = renderPass?.geometryFilterFunction {
            guard geometryFilterFunction(nil) else {
                return []
            }
        }
        
        guard let capturedImageVertexTransform = metalLibrary.makeFunction(name: "capturedImageVertexTransform") else {
            print("Serious Error - failed to create the capturedImageVertexTransform function")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeShaderInitializationFailed, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return []
        }
        
        guard let capturedImageFragmentShader = metalLibrary.makeFunction(name: "capturedImageFragmentShader") else {
            print("Serious Error - failed to create the capturedImageFragmentShader function")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeShaderInitializationFailed, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return []
        }
        
        let capturedImageVertexFunction = capturedImageVertexTransform
        let capturedImageFragmentFunction = capturedImageFragmentShader
        
        // Create a vertex descriptor for our image plane vertex buffer
        let imagePlaneVertexDescriptor = MTLVertexDescriptor()
        
        // Positions.
        imagePlaneVertexDescriptor.attributes[Int(kVertexAttributePosition.rawValue)].format = .float2
        imagePlaneVertexDescriptor.attributes[Int(kVertexAttributePosition.rawValue)].offset = 0
        imagePlaneVertexDescriptor.attributes[Int(kVertexAttributePosition.rawValue)].bufferIndex = Int(kBufferIndexMeshPositions.rawValue)
        
        // Texture coordinates.
        imagePlaneVertexDescriptor.attributes[Int(kVertexAttributeTexcoord.rawValue)].format = .float2
        imagePlaneVertexDescriptor.attributes[Int(kVertexAttributeTexcoord.rawValue)].offset = 8
        imagePlaneVertexDescriptor.attributes[Int(kVertexAttributeTexcoord.rawValue)].bufferIndex = Int(kBufferIndexMeshPositions.rawValue)
        
        // Buffer Layout
        imagePlaneVertexDescriptor.layouts[0].stride = 16
        imagePlaneVertexDescriptor.layouts[0].stepRate = 1
        imagePlaneVertexDescriptor.layouts[0].stepFunction = .perVertex
        
        // Create a pipeline state for rendering the captured image
        let capturedImagePipelineStateDescriptor = MTLRenderPipelineDescriptor()
        capturedImagePipelineStateDescriptor.label = "MyCapturedImagePipeline"
        capturedImagePipelineStateDescriptor.sampleCount = renderDestination.sampleCount
        capturedImagePipelineStateDescriptor.vertexFunction = capturedImageVertexFunction
        capturedImagePipelineStateDescriptor.fragmentFunction = capturedImageFragmentFunction
        capturedImagePipelineStateDescriptor.vertexDescriptor = imagePlaneVertexDescriptor
        capturedImagePipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        capturedImagePipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        capturedImagePipelineStateDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        
//        do {
//            try capturedImagePipelineState = device.makeRenderPipelineState(descriptor: capturedImagePipelineStateDescriptor)
//        } catch let error {
//            print("Serious Error - Failed to create captured image pipeline state, error \(error)")
//            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeRenderPipelineInitializationFailed, userInfo: nil)
//            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
//            recordNewError(newError)
//            return []
//        }
        
        let capturedImageDepthStateDescriptor = MTLDepthStencilDescriptor()
        capturedImageDepthStateDescriptor.depthCompareFunction = .always
        capturedImageDepthStateDescriptor.isDepthWriteEnabled = false
        
        // Create captured image texture cache
        var textureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        capturedImageTextureCache = textureCache
        
        let drawCall = DrawCall(withDevice: device, renderPipelineDescriptor: capturedImagePipelineStateDescriptor, depthStencilDescriptor: capturedImageDepthStateDescriptor, cullMode: .none)
        let drawCallGroup = DrawCallGroup(drawCalls: [drawCall])
        drawCallGroup.moduleIdentifier = moduleIdentifier
        
        isInitialized = true
        
        return [drawCallGroup]
        
    }
    
    //
    // Per Frame Updates
    //
    
    func updateBufferState(withBufferIndex: Int) {
        
        // Retain our CVMetalTextures for the duration of the rendering cycle. The MTLTextures
        // we use from the CVMetalTextures are not valid unless their parent CVMetalTextures
        // are retained. Since we may release our CVMetalTexture ivars during the rendering
        // cycle, we must retain them separately here.
        textureReferences = [capturedImageTextureY, capturedImageTextureCbCr]
        
    }
    
    func updateBuffers(withAllGeometricEntities: [AKGeometricEntity], moduleGeometricEntities: [AKGeometricEntity], cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties, shadowProperties: ShadowProperties, forRenderPass renderPass: RenderPass) {
        
        // Create two textures (Y and CbCr) from the provided frame's captured image
        let pixelBuffer = cameraProperties.capturedImage
        
        if (CVPixelBufferGetPlaneCount(pixelBuffer) < 2) {
            return
        }
        
        capturedImageTextureY = createTexture(fromPixelBuffer: pixelBuffer, pixelFormat:.r8Unorm, planeIndex:0)
        capturedImageTextureCbCr = createTexture(fromPixelBuffer: pixelBuffer, pixelFormat:.rg8Unorm, planeIndex:1)
        
        if cameraProperties.viewportSizeDidChange {
            // Update the texture coordinates of our image plane to aspect fill the viewport
            let displayToCameraTransform = cameraProperties.displayTransform.inverted()
            
            if let vertexData = imagePlaneVertexBuffer?.contents().assumingMemoryBound(to: Float.self) {
                for index in 0...3 {
                    let textureCoordIndex = 4 * index + 2
                    let textureCoord = CGPoint(x: CGFloat(Constants.imagePlaneVertexData[textureCoordIndex]), y: CGFloat(Constants.imagePlaneVertexData[textureCoordIndex + 1]))
                    let transformedCoord = textureCoord.applying(displayToCameraTransform)
                    vertexData[textureCoordIndex] = Float(transformedCoord.x)
                    vertexData[textureCoordIndex + 1] = Float(transformedCoord.y)
                }
            }
        }
        
    }
    
    func draw(withRenderPass renderPass: RenderPass, sharedModules: [SharedRenderModule]?) {
        
        guard renderPass.usesCameraOutput else {
            return
        }
        
        guard let renderEncoder = renderPass.renderCommandEncoder else {
            return
        }
        
        guard let textureY = capturedImageTextureY, let textureCbCr = capturedImageTextureCbCr else {
            return
        }
        
        for drawCallGroup in renderPass.drawCallGroups.filter({ $0.moduleIdentifier == moduleIdentifier }) {
            
            // Geometry Draw Calls
            for drawCall in drawCallGroup.drawCalls {
                
                // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
                renderEncoder.pushDebugGroup("Draw Captured Image")
                
                // Set render command encoder state
                drawCall.prepareDrawCall(withRenderPass: renderPass)
                
                // Set mesh's vertex buffers
                renderEncoder.setVertexBuffer(imagePlaneVertexBuffer, offset: 0, index: Int(kBufferIndexMeshPositions.rawValue))
                
                // Set any textures read/sampled from our render pipeline
                renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(textureY), index: Int(kTextureIndexY.rawValue))
                renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(textureCbCr), index: Int(kTextureIndexCbCr.rawValue))
                
                // Draw each submesh of our mesh
                renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                
                renderEncoder.popDebugGroup()
                
            }
            
        }
        
        
        
    }
    
    func frameEncodingComplete() {
        textureReferences.removeAll()
    }
    
    //
    // Util
    //
    
    func recordNewError(_ akError: AKError) {
        errors.append(akError)
    }
    
    // MARK: - Private
    
    private enum Constants {
        
        // Captured Image Plane
        static let imagePlaneVertexData: [Float] = [
            -1.0, -1.0,  0.0, 1.0,
            1.0, -1.0,  1.0, 1.0,
            -1.0,  1.0,  0.0, 0.0,
            1.0,  1.0,  1.0, 0.0,
        ]
        
    }
    
    private var device: MTLDevice?
    private var imagePlaneVertexBuffer: MTLBuffer?
//    private var capturedImagePipelineState: MTLRenderPipelineState?
    private var capturedImageTextureCache: CVMetalTextureCache?
    private var capturedImageTextureY: CVMetalTexture?
    private var capturedImageTextureCbCr: CVMetalTexture?
    
    private var textureReferences = [CVMetalTexture?]()
    
    private func createTexture(fromPixelBuffer pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat, planeIndex: Int) -> CVMetalTexture? {
        
        guard let capturedImageTextureCache = capturedImageTextureCache else {
            print("Serious Error - Captured Image Texture Cache is nil")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeRenderPipelineInitializationFailed, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return nil
        }
        
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        
        var texture: CVMetalTexture? = nil
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, capturedImageTextureCache, pixelBuffer, nil, pixelFormat, width, height, planeIndex, &texture)
        
        if status != kCVReturnSuccess {
            texture = nil
        }
        
        return texture
    }
    
}
