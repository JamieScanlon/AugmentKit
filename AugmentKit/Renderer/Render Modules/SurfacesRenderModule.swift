//
//  SurfacesRenderModule.swift
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

// TODO: Veritical Surface support
class SurfacesRenderModule: RenderModule {
    
    static var identifier = "SurfacesRenderModule"
    
    //
    // Setup
    //
    
    var moduleIdentifier: String {
        return SurfacesRenderModule.identifier
    }
    var renderLayer: Int {
        return 2
    }
    var isInitialized: Bool = false
    var sharedModuleIdentifiers: [String]? = [SharedBuffersRenderModule.identifier]
    var renderDistance: Double = 500
    var errors = [AKError]()
    
    // The number of surface instances to render
    private(set) var surfaceInstanceCount: Int = 0
    
    func initializeBuffers(withDevice aDevice: MTLDevice, maxInFlightBuffers: Int) {
        
        device = aDevice
        
        // Calculate our uniform buffer sizes. We allocate Constants.maxBuffersInFlight instances for uniform
        // storage in a single buffer. This allows us to update uniforms in a ring (i.e. triple
        // buffer the uniforms) so that the GPU reads from one slot in the ring wil the CPU writes
        // to another. Surface uniforms should be specified with a max instance count for instancing.
        // Also uniform storage must be aligned (to 256 bytes) to meet the requirements to be an
        // argument in the constant address space of our shading functions.
        let surfaceUniformBufferSize = Constants.alignedSurfaceInstanceUniformsSize * maxInFlightBuffers
        let materialUniformBufferSize = RenderModuleConstants.alignedMaterialSize * maxInFlightBuffers
        let effectsUniformBufferSize = Constants.alignedEffectsUniformSize * maxInFlightBuffers
        let environmentUniformBufferSize = Constants.alignedEnvironmentUniformSize * maxInFlightBuffers
        
        // Create and allocate our uniform buffer objects. Indicate shared storage so that both the
        // CPU can access the buffer
        surfaceUniformBuffer = device?.makeBuffer(length: surfaceUniformBufferSize, options: .storageModeShared)
        surfaceUniformBuffer?.label = "SurfaceUniformBuffer"
        
        materialUniformBuffer = device?.makeBuffer(length: materialUniformBufferSize, options: .storageModeShared)
        materialUniformBuffer?.label = "MaterialUniformBuffer"
        
        effectsUniformBuffer = device?.makeBuffer(length: effectsUniformBufferSize, options: .storageModeShared)
        effectsUniformBuffer?.label = "EffectsUniformBuffer"
        
        environmentUniformBuffer = device?.makeBuffer(length: environmentUniformBufferSize, options: .storageModeShared)
        environmentUniformBuffer?.label = "EnvironemtUniformBuffer"
        
    }
    
    func loadAssets(forGeometricEntities: [AKGeometricEntity], fromModelProvider modelProvider: ModelProvider?, textureLoader aTextureLoader: MTKTextureLoader, completion: (() -> Void)) {
        
        guard let modelProvider = modelProvider else {
            print("Serious Error - Model Provider not found.")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeModelProviderNotFound, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            completion()
            return
        }
        
        textureLoader = aTextureLoader
        
        //
        // Create and load our models
        //
        
        // TODO: Add ability to load multiple models by identifier
        modelProvider.loadAsset(forObjectType: GuideSurfaceAnchor.type, identifier: nil) { [weak self] asset in
            
            guard let asset = asset else {
                print("Warning (SurfacesRenderModule) - Failed to get a model for type \(GuideSurfaceAnchor.type) from the modelProvider. Aborting the render phase.")
                let newError = AKError.warning(.modelError(.modelNotFound(ModelErrorInfo(type: GuideSurfaceAnchor.type))))
                recordNewError(newError)
                completion()
                return
            }
            
            self?.surfaceAsset = asset
            
            completion()
            
        }
        
    }
    
    func loadPipeline(withMetalLibrary metalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider, textureBundle: Bundle, forRenderPass renderPass: RenderPass? = nil) -> [RenderPass.DrawCallGroup] {
        
        guard let device = device else {
            print("Serious Error - device not found")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeDeviceNotFound, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return []
        }
        
        guard let surfaceAsset = surfaceAsset else {
            print("Serious Error - surfaceModel not found")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeModelNotFound, userInfo: nil)
            let newError = AKError.warning(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return []
        }
        
        surfaceMeshGPUData = ModelIOTools.meshGPUData(from: surfaceAsset, device: device, textureBundle: textureBundle, vertexDescriptor: RenderUtilities.createStandardVertexDescriptor())
        
        guard let surfaceMeshGPUData = surfaceMeshGPUData else {
            print("Serious Error - ERROR: No meshGPUData found for target when trying to load the pipeline.")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeIntermediateMeshDataNotFound, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return []
        }
        
        if surfaceMeshGPUData.drawData.count > 1 {
            print("WARNING: More than one mesh was found. Currently only one mesh per anchor is supported.")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeModelNotSupported, userInfo: nil)
            let newError = AKError.warning(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
        }
        
        let myVertexDescriptor = surfaceMeshGPUData.vertexDescriptor
        
        guard let surfaceVertexDescriptor = myVertexDescriptor else {
            print("Serious Error - Failed to create a MetalKit vertex descriptor from ModelIO.")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeInvalidMeshData, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return []
        }
        
        let surfaceDepthStateDescriptor = MTLDepthStencilDescriptor()
        surfaceDepthStateDescriptor.depthCompareFunction = .less
        surfaceDepthStateDescriptor.isDepthWriteEnabled = true
        surfaceDepthState = device.makeDepthStencilState(descriptor: surfaceDepthStateDescriptor)
        
        var drawCalls = [RenderPass.DrawCall]()
        
        for drawData in surfaceMeshGPUData.drawData {
            let surfacePipelineStateDescriptor = MTLRenderPipelineDescriptor()
            do {
                let funcConstants = RenderUtilities.getFuncConstants(forDrawData: drawData)
                // Specify which shader to use based on if the model has skinned puppet suppot
                let vertexName = (drawData.paletteStartIndex != nil) ? "anchorGeometryVertexTransformSkinned" : "anchorGeometryVertexTransform"
                let fragFunc = try metalLibrary.makeFunction(name: "anchorGeometryFragmentLighting", constantValues: funcConstants)
                let vertFunc = try metalLibrary.makeFunction(name: vertexName, constantValues: funcConstants)
                surfacePipelineStateDescriptor.vertexDescriptor = surfaceVertexDescriptor
                surfacePipelineStateDescriptor.vertexFunction = vertFunc
                surfacePipelineStateDescriptor.fragmentFunction = fragFunc
                surfacePipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
                surfacePipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
                surfacePipelineStateDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
                surfacePipelineStateDescriptor.sampleCount = renderDestination.sampleCount
                
                var drawCall = RenderPass.DrawCall(withDevice: device, renderPipelineDescriptor: surfacePipelineStateDescriptor)
                drawCall.depthStencilState = surfaceDepthState
                drawCalls.append(drawCall)
                
            } catch let error {
                print("Failed to create pipeline state descriptor, error \(error)")
                let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: error))))
                recordNewError(newError)
            }
            
            do {
                let surfacePiplineState = try device.makeRenderPipelineState(descriptor: surfacePipelineStateDescriptor)
                surfacePipelineStates.append(surfacePiplineState)
            } catch let error {
                print("Failed to create pipeline state, error \(error)")
                let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: error))))
                recordNewError(newError)
            }
        }
        
        isInitialized = true
        
        let drawCallGroup = RenderPass.DrawCallGroup(drawCalls: drawCalls)
        drawCallGroup.moduleIdentifier = moduleIdentifier
        return [drawCallGroup]
        
    }
    
    //
    // Per Frame Updates
    //
    
    func updateBufferState(withBufferIndex bufferIndex: Int) {
        
        surfaceUniformBufferOffset = Constants.alignedSurfaceInstanceUniformsSize * bufferIndex
        materialUniformBufferOffset = RenderModuleConstants.alignedMaterialSize * bufferIndex
        effectsUniformBufferOffset = Constants.alignedEffectsUniformSize * bufferIndex
        environmentUniformBufferOffset = Constants.alignedEnvironmentUniformSize * bufferIndex
        
        surfaceUniformBufferAddress = surfaceUniformBuffer?.contents().advanced(by: surfaceUniformBufferOffset)
        materialUniformBufferAddress = materialUniformBuffer?.contents().advanced(by: materialUniformBufferOffset)
        effectsUniformBufferAddress = effectsUniformBuffer?.contents().advanced(by: effectsUniformBufferOffset)
        environmentUniformBufferAddress = environmentUniformBuffer?.contents().advanced(by: environmentUniformBufferOffset)
        
    }
    
    func updateBuffers(withAugmentedAnchors anchors: [AKAugmentedAnchor], cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties, shadowProperties: ShadowProperties) {
        // Do Nothing
    }
    
    func updateBuffers(withRealAnchors anchors: [AKRealAnchor], cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties, shadowProperties: ShadowProperties) {
        
        // Update the anchor uniform buffer with transforms of the current frame's anchors
        surfaceInstanceCount = 0
        environmentTextureByUUID = [:]
        
        for akAnchor in anchors {
            
            guard let anchor = akAnchor.arAnchor else {
                continue
            }
            
            surfaceInstanceCount += 1
            
            // Ignore anchors that are beyond the renderDistance
            let distance = anchorDistance(withTransform: anchor.transform, cameraProperties: cameraProperties)
            guard Double(distance) < renderDistance else {
                continue
            }
            
            guard surfaceInstanceCount > 0 else {
                continue
            }
            
            if surfaceInstanceCount > Constants.maxSurfaceInstanceCount {
                surfaceInstanceCount = Constants.maxSurfaceInstanceCount
                break
            }
            
            guard let uuid = akAnchor.identifier else {
                continue
            }
            
            // Flip Z axis to convert geometry from right handed to left handed
            var coordinateSpaceTransform = matrix_identity_float4x4
            //coordinateSpaceTransform.columns.2.z = -1.0
            
            let surfaceIndex = surfaceInstanceCount - 1
            
            // Apply the world transform (as defined in the imported model) if applicable
            // We currenly only support a single mesh so we just use the first item
            if let drawData = surfaceMeshGPUData?.drawData.first {
                let worldTransform: matrix_float4x4 = {
                    if drawData.worldTransformAnimations.count > 0 {
                        let index = Int(cameraProperties.currentFrame % UInt(drawData.worldTransformAnimations.count))
                        return drawData.worldTransformAnimations[index]
                    } else {
                        return drawData.worldTransform
                    }
                }()
                coordinateSpaceTransform = simd_mul(coordinateSpaceTransform, worldTransform)
            }
            
            var modelMatrix = anchor.transform * coordinateSpaceTransform
            if let plane = anchor as? ARPlaneAnchor {
                if plane.alignment == .horizontal {
                    // Do Nothing
                } else {
                    modelMatrix = modelMatrix.rotate(radians: Float.pi, x: 1, y: 0, z: 0)
                }
                modelMatrix = modelMatrix.scale(x: plane.extent.x, y: plane.extent.y, z: plane.extent.z)
                modelMatrix = modelMatrix.translate(x: -plane.center.x/2.0, y: -plane.center.y/2.0, z: -plane.center.z/2.0)
                
            }
            
            // Surfaces use the same uniform struct as anchors
            let surfaceUniforms = surfaceUniformBufferAddress?.assumingMemoryBound(to: AnchorInstanceUniforms.self).advanced(by: surfaceIndex)
            surfaceUniforms?.pointee.modelMatrix = modelMatrix
            surfaceUniforms?.pointee.normalMatrix = modelMatrix.normalMatrix
            
            //
            // Update Environment
            //
            
            let environmentProperty = environmentProperties.environmentAnchorsWithReatedAnchors.first(where: {
                $0.value.contains(uuid)
            })
            
            if let environmentProbeAnchor = environmentProperty?.key, let texture = environmentProbeAnchor.environmentTexture {
                environmentTextureByUUID[uuid] = texture
            }
            
            environmentData = {
                var myEnvironmentData = EnvironmentData()
                if let texture = environmentTextureByUUID[uuid] {
                    myEnvironmentData.environmentTexture = texture
                    myEnvironmentData.hasEnvironmentMap = true
                    return myEnvironmentData
                } else {
                    myEnvironmentData.hasEnvironmentMap = false
                }
                return myEnvironmentData
            }()
            
            let environmentUniforms = environmentUniformBufferAddress?.assumingMemoryBound(to: EnvironmentUniforms.self).advanced(by: surfaceIndex)
            
            // Set up lighting for the scene using the ambient intensity if provided
            let ambientIntensity: Float = {
                if let lightEstimate = environmentProperties.lightEstimate {
                    return Float(lightEstimate.ambientIntensity) / 1000.0
                } else {
                    return 1
                }
            }()
            
            let ambientLightColor: vector_float3 = {
                if let lightEstimate = environmentProperties.lightEstimate {
                    return getRGB(from: lightEstimate.ambientColorTemperature)
                } else {
                    return vector3(0.5, 0.5, 0.5)
                }
            }()
            
            environmentUniforms?.pointee.ambientLightColor = ambientLightColor// * ambientIntensity
            
            var directionalLightDirection : vector_float3 = environmentProperties.directionalLightDirection
            directionalLightDirection = simd_normalize(directionalLightDirection)
            environmentUniforms?.pointee.directionalLightDirection = directionalLightDirection
            
            let directionalLightColor: vector_float3 = vector3(0.6, 0.6, 0.6)
            environmentUniforms?.pointee.directionalLightColor = directionalLightColor * ambientIntensity
            
            environmentUniforms?.pointee.directionalLightMVP = environmentProperties.directionalLightMVP
            environmentUniforms?.pointee.shadowMVPTransformMatrix = shadowProperties.shadowMVPTransformMatrix
            
            if environmentData?.hasEnvironmentMap == true {
                environmentUniforms?.pointee.hasEnvironmentMap = 1
            } else {
                environmentUniforms?.pointee.hasEnvironmentMap = 0
            }
            
            //
            // Update Effects uniform
            //
            
            let effectsUniforms = effectsUniformBufferAddress?.assumingMemoryBound(to: AnchorEffectsUniforms.self).advanced(by: surfaceIndex)
            var hasSetAlpha = false
            var hasSetGlow = false
            var hasSetTint = false
            var hasSetScale = false
            if let effects = akAnchor.effects {
                let currentTime: TimeInterval = Double(cameraProperties.currentFrame) / cameraProperties.frameRate
                for effect in effects {
                    switch effect.effectType {
                    case .alpha:
                        if let value = effect.value(forTime: currentTime) as? Float {
                            effectsUniforms?.pointee.alpha = value
                            hasSetAlpha = true
                        }
                    case .glow:
                        if let value = effect.value(forTime: currentTime) as? Float {
                            effectsUniforms?.pointee.glow = value
                            hasSetGlow = true
                        }
                    case .tint:
                        if let value = effect.value(forTime: currentTime) as? float3 {
                            effectsUniforms?.pointee.tint = value
                            hasSetTint = true
                        }
                    case .scale:
                        if let value = effect.value(forTime: currentTime) as? Float {
                            let scaleMatrix = matrix_identity_float4x4
                            effectsUniforms?.pointee.scale = scaleMatrix.scale(x: value, y: value, z: value)
                            hasSetScale = true
                        }
                    }
                }
            }
            if !hasSetAlpha {
                effectsUniforms?.pointee.alpha = 1
            }
            if !hasSetGlow {
                effectsUniforms?.pointee.glow = 0
            }
            if !hasSetTint {
                effectsUniforms?.pointee.tint = float3(1,1,1)
            }
            if !hasSetScale {
                effectsUniforms?.pointee.scale = matrix_identity_float4x4
            }
            
        }
        
    }
    
    func updateBuffers(withTrackers: [AKAugmentedTracker], targets: [AKTarget], cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties, shadowProperties: ShadowProperties) {
        // Do Nothing
    }
    
    func updateBuffers(withPaths: [AKPath], cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties, shadowProperties: ShadowProperties) {
        // Do Nothing
    }
    
    func draw(withRenderPass renderPass: RenderPass, sharedModules: [SharedRenderModule]?) {
        
        guard let renderEncoder = renderPass.renderCommandEncoder else {
            return
        }
        
        guard surfaceInstanceCount > 0 else {
            return
        }
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("Draw Surfaces")
        
        // Set render command encoder state
        renderEncoder.setCullMode(.none)
        
        guard let meshGPUData = surfaceMeshGPUData else {
            print("Error: meshGPUData not available a draw time. Aborting")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeIntermediateMeshDataNotAvailable, userInfo: nil)
            let newError = AKError.recoverableError(.renderPipelineError(.drawAborted(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return
        }
        
        if let sharedBuffer = sharedModules?.first(where: {$0.moduleIdentifier == SharedBuffersRenderModule.identifier}) {
            
            renderEncoder.pushDebugGroup("Draw Shared Uniforms")
            
            renderEncoder.setVertexBuffer(sharedBuffer.sharedUniformBuffer, offset: sharedBuffer.sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
            renderEncoder.setFragmentBuffer(sharedBuffer.sharedUniformBuffer, offset: sharedBuffer.sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
            
            renderEncoder.popDebugGroup()
            
        }
        
        if let effectsBuffer = effectsUniformBuffer {
            
            renderEncoder.pushDebugGroup("Draw Effects Uniforms")
            renderEncoder.setVertexBuffer(effectsBuffer, offset: effectsUniformBufferOffset, index: Int(kBufferIndexAnchorEffectsUniforms.rawValue))
            renderEncoder.setFragmentBuffer(effectsBuffer, offset: effectsUniformBufferOffset, index: Int(kBufferIndexAnchorEffectsUniforms.rawValue))
            renderEncoder.popDebugGroup()
            
        }
        
        if let environmentUniformBuffer = environmentUniformBuffer {
            
            renderEncoder.pushDebugGroup("Draw Environment Uniforms")
            if let environmentTexture = environmentData?.environmentTexture, environmentData?.hasEnvironmentMap == true {
                renderEncoder.setFragmentTexture(environmentTexture, index: Int(kTextureIndexEnvironmentMap.rawValue))
            }
            renderEncoder.setFragmentBuffer(environmentUniformBuffer, offset: environmentUniformBufferOffset, index: Int(kBufferIndexEnvironmentUniforms.rawValue))
            renderEncoder.popDebugGroup()
            
        }
        
        for drawCallGroup in renderPass.drawCallGroups.filter({ $0.moduleIdentifier == moduleIdentifier }) {
            
            // Geometry Draw Calls
            for (index, drawCall) in drawCallGroup.drawCalls.enumerated() {
            
                drawCall.prepareDrawCall(withRenderPass: renderPass)
                    
                // Set any buffers fed into our render pipeline
                renderEncoder.setVertexBuffer(surfaceUniformBuffer, offset: surfaceUniformBufferOffset, index: Int(kBufferIndexAnchorInstanceUniforms.rawValue))
                
                var mutableDrawData = meshGPUData.drawData[index]
                mutableDrawData.instanceCount = surfaceInstanceCount
                
                // Set the mesh's vertex data buffers and draw
                draw(withDrawData: mutableDrawData, with: renderEncoder)
                
            }
            
        }
        
        renderEncoder.popDebugGroup()
        
    }
    
    func frameEncodingComplete() {
        //
    }
    
    //
    // Util
    //
    
    func recordNewError(_ akError: AKError) {
        errors.append(akError)
    }
    
    // MARK: - Private
    
    private enum Constants {
        static let maxSurfaceInstanceCount = 64
        // Surfaces use the same uniform struct as anchors
        static let alignedSurfaceInstanceUniformsSize = ((MemoryLayout<AnchorInstanceUniforms>.stride * Constants.maxSurfaceInstanceCount) & ~0xFF) + 0x100
        static let alignedEffectsUniformSize = ((MemoryLayout<AnchorEffectsUniforms>.stride * Constants.maxSurfaceInstanceCount) & ~0xFF) + 0x100
        static let alignedEnvironmentUniformSize = ((MemoryLayout<EnvironmentUniforms>.stride * Constants.maxSurfaceInstanceCount) & ~0xFF) + 0x100
    }
    
    private var device: MTLDevice?
    private var textureLoader: MTKTextureLoader?
    private var surfaceAsset: MDLAsset?
    private var surfaceUniformBuffer: MTLBuffer?
    private var materialUniformBuffer: MTLBuffer?
    private var effectsUniformBuffer: MTLBuffer?
    private var environmentUniformBuffer: MTLBuffer?
    private var surfacePipelineStates = [MTLRenderPipelineState]() // Store multiple states
    private var surfaceDepthState: MTLDepthStencilState?
    private var environmentData: EnvironmentData?
    
    // MetalKit meshes containing vertex data and index buffer for our surface geometry
    private var surfaceMeshGPUData: MeshGPUData?
    
    // Offset within surfaceUniformBuffer to set for the current frame
    private var surfaceUniformBufferOffset: Int = 0
    
    // Offset within materialUniformBuffer to set for the current frame
    private var materialUniformBufferOffset: Int = 0
    
    // Offset within effectsUniformBuffer to set for the current frame
    private var effectsUniformBufferOffset: Int = 0
    
    // Offset within environmentUniformBuffer to set for the current frame
    private var environmentUniformBufferOffset: Int = 0
    
    // Addresses to write surface uniforms to each frame
    private var surfaceUniformBufferAddress: UnsafeMutableRawPointer?
    
    // Addresses to write surface uniforms to each frame
    private var materialUniformBufferAddress: UnsafeMutableRawPointer?
    
    // Addresses to write effects uniforms to each frame
    private var effectsUniformBufferAddress: UnsafeMutableRawPointer?
    
    // Addresses to write environment uniforms to each frame
    private var environmentUniformBufferAddress: UnsafeMutableRawPointer?
    
    // number of frames in the surface animation by surface index
    private var surfaceAnimationFrameCount = [Int]()
    
    private var environmentTextureByUUID = [UUID: MTLTexture]()
    
}
