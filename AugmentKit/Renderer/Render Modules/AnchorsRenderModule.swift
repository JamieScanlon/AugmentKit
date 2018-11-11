//
//  AnchorsRenderModule.swift
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

class AnchorsRenderModule: RenderModule, SkinningModule {
    
    static var identifier = "AnchorsRenderModule"
    
    //
    // Setup
    //
    
    var moduleIdentifier: String {
        return AnchorsRenderModule.identifier
    }
    var renderLayer: Int {
        return 11
    }
    var isInitialized: Bool = false
    var sharedModuleIdentifiers: [String]? = [SharedBuffersRenderModule.identifier]
    var renderDistance: Double = 500
    var errors = [AKError]()
    
    // The number of anchor instances to render
    private(set) var anchorInstanceCount: Int = 0
    
    private(set) var drawCallGroups = [RenderPass.DrawCallGroup]()
    
    func initializeBuffers(withDevice aDevice: MTLDevice, maxInFlightBuffers: Int) {
        
        guard device == nil else {
            return
        }
        
        device = aDevice
        
        // Calculate our uniform buffer sizes. We allocate Constants.maxBuffersInFlight instances for uniform
        // storage in a single buffer. This allows us to update uniforms in a ring (i.e. triple
        // buffer the uniforms) so that the GPU reads from one slot in the ring wil the CPU writes
        // to another. Anchor uniforms should be specified with a max instance count for instancing.
        // Also uniform storage must be aligned (to 256 bytes) to meet the requirements to be an
        // argument in the constant address space of our shading functions.
        let anchorUniformBufferSize = Constants.alignedAnchorInstanceUniformsSize * maxInFlightBuffers
        let materialUniformBufferSize = RenderModuleConstants.alignedMaterialSize * maxInFlightBuffers
        let paletteBufferSize = Constants.alignedPaletteSize * Constants.maxPaletteSize * maxInFlightBuffers
        let effectsUniformBufferSize = Constants.alignedEffectsUniformSize * maxInFlightBuffers
        let environmentUniformBufferSize = Constants.alignedEnvironmentUniformSize * maxInFlightBuffers
        
        // Create and allocate our uniform buffer objects. Indicate shared storage so that both the
        // CPU can access the buffer
        anchorUniformBuffer = device?.makeBuffer(length: anchorUniformBufferSize, options: .storageModeShared)
        anchorUniformBuffer?.label = "AnchorUniformBuffer"
        
        materialUniformBuffer = device?.makeBuffer(length: materialUniformBufferSize, options: .storageModeShared)
        materialUniformBuffer?.label = "MaterialUniformBuffer"
        
        paletteBuffer = device?.makeBuffer(length: paletteBufferSize, options: [])
        paletteBuffer?.label = "PaletteBuffer"
        
        effectsUniformBuffer = device?.makeBuffer(length: effectsUniformBufferSize, options: .storageModeShared)
        effectsUniformBuffer?.label = "EffectsUniformBuffer"
        
        environmentUniformBuffer = device?.makeBuffer(length: environmentUniformBufferSize, options: .storageModeShared)
        environmentUniformBuffer?.label = "EnvironemtUniformBuffer"
        
    }
    
    func loadAssets(forGeometricEntities geometricEntities: [AKGeometricEntity], fromModelProvider modelProvider: ModelProvider?, textureLoader aTextureLoader: MTKTextureLoader, completion: (() -> Void)) {
        
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
        
        var numModels = geometricEntities.count
        
        // Load the default model
        modelProvider.loadAsset(forObjectType: "AnyAnchor", identifier: nil) { [weak self] asset in
            
            guard let asset = asset else {
                print("Warning (AnchorsRenderModule) - Failed to get a MDLAsset for type  \"AnyAnchor\") from the modelProvider. Aborting the render phase.")
                let newError = AKError.warning(.modelError(.modelNotFound(ModelErrorInfo(type:  "AnyAnchor"))))
                recordNewError(newError)
                completion()
                return
            }
            
            self?.modelAssetsForAnchorsByUUID[generalUUID] = asset
            
            if numModels == 0 {
                completion()
            }
            
        }
        
        // Load the per-geometry models
        for geometricEntity in geometricEntities {
            
            if let identifier = geometricEntity.identifier {
                modelProvider.loadAsset(forObjectType:  "AnyAnchor", identifier: identifier) { [weak self] asset in
                    
                    guard let asset = asset else {
                        print("Warning (AnchorsRenderModule) - Failed to get a MDLAsset for type \"AnyAnchor\") with identifier \(identifier) from the modelProvider. Aborting the render phase.")
                        let newError = AKError.warning(.modelError(.modelNotFound(ModelErrorInfo(type:  "AnyAnchor", identifier: identifier))))
                        recordNewError(newError)
                        completion()
                        return
                    }
                    
                    self?.modelAssetsForAnchorsByUUID[identifier] = asset
                    self?.shaderPreferenceForAnchorsByUUID[identifier] = geometricEntity.shaderPreference
                }
            }
            
            numModels -= 1
            if numModels <= 0 {
                completion()
            }
            
        }
        
    }
    
    func loadPipeline(withMetalLibrary metalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider, textureBundle: Bundle) {
        
        guard let device = device else {
            print("Serious Error - device not found")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeDeviceNotFound, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return
        }
            
        // Make sure there is at least one general purpose model
        guard modelAssetsForAnchorsByUUID[generalUUID] != nil else {
            print("Warning (AnchorsRenderModule) - Anchor Model was not found. Aborting the render phase.")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeModelNotFound, userInfo: nil)
            let newError = AKError.warning(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return
        }
        
        let anchorDepthStateDescriptor = MTLDepthStencilDescriptor()
        anchorDepthStateDescriptor.depthCompareFunction = .less
        anchorDepthStateDescriptor.isDepthWriteEnabled = true
        anchorDepthState = device.makeDepthStencilState(descriptor: anchorDepthStateDescriptor)
        
        for item in modelAssetsForAnchorsByUUID {
            
            let uuid = item.key
            let mdlAsset = item.value
            let shaderPreference: ShaderPreference = {
                if let prefernece = shaderPreferenceForAnchorsByUUID[uuid] {
                    return prefernece
                } else {
                    return .pbr
                }
            }()
            
            meshGPUDataForAnchorsByUUID[uuid] = ModelIOTools.meshGPUData(from: mdlAsset, device: device, textureBundle: textureBundle, vertexDescriptor: RenderUtilities.createStandardVertexDescriptor(), frameRate: 60, shaderPreference: shaderPreference)
            
            let drawCalls = createPipelineStates(forUUID: uuid, withMetalLibrary: metalLibrary, renderDestination: renderDestination)
            drawCallsByUUID[uuid] = drawCalls.map{
                var mutableDrawCall = $0
                mutableDrawCall.depthStencilState = anchorDepthState
                return mutableDrawCall
            }
            
        }
        
        isInitialized = true
        
    }
    
    //
    // Per Frame Updates
    //
    
    func updateBufferState(withBufferIndex bufferIndex: Int) {
        
        anchorUniformBufferOffset = Constants.alignedAnchorInstanceUniformsSize * bufferIndex
        materialUniformBufferOffset = RenderModuleConstants.alignedMaterialSize * bufferIndex
        paletteBufferOffset = Constants.alignedPaletteSize * Constants.maxPaletteSize * bufferIndex
        effectsUniformBufferOffset = Constants.alignedEffectsUniformSize * bufferIndex
        environmentUniformBufferOffset = Constants.alignedEnvironmentUniformSize * bufferIndex
        
        anchorUniformBufferAddress = anchorUniformBuffer?.contents().advanced(by: anchorUniformBufferOffset)
        materialUniformBufferAddress = materialUniformBuffer?.contents().advanced(by: materialUniformBufferOffset)
        paletteBufferAddress = paletteBuffer?.contents().advanced(by: paletteBufferOffset)
        effectsUniformBufferAddress = effectsUniformBuffer?.contents().advanced(by: effectsUniformBufferOffset)
        environmentUniformBufferAddress = environmentUniformBuffer?.contents().advanced(by: environmentUniformBufferOffset)
        
    }
    
    func updateBuffers(withAugmentedAnchors anchors: [AKAugmentedAnchor], cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties) {
        
        // Update the anchor uniform buffer with transforms of the current frame's anchors
        anchorInstanceCount = 0
        anchorsByUUID = [:]
        environmentTextureByUUID = [:]
        
        //
        // Gather the UUID's
        //
        
        drawCallGroups = [RenderPass.DrawCallGroup]()
        
        for akAnchor in anchors {
            
            guard let anchor = akAnchor.arAnchor else {
                continue
            }
            
            // Ignore anchors that are beyond the renderDistance
            let distance = anchorDistance(withTransform: anchor.transform, cameraProperties: cameraProperties)
            guard Double(distance) < renderDistance else {
                continue
            }
            
            anchorInstanceCount += 1
            
            if anchorInstanceCount > Constants.maxAnchorInstanceCount {
                anchorInstanceCount = Constants.maxAnchorInstanceCount
                break
            }
            
            let uuid: UUID = {
                if modelAssetsForAnchorsByUUID[anchor.identifier] != nil {
                    return anchor.identifier
                } else {
                    return generalUUID
                }
            }()
            
            if let currentAnchors = anchorsByUUID[uuid] {
                var mutableCurrentAnchors = currentAnchors
                mutableCurrentAnchors.append(akAnchor)
                anchorsByUUID[uuid] = mutableCurrentAnchors
            } else {
                anchorsByUUID[uuid] = [akAnchor]
            }
            
            let environmentProperty = environmentProperties.environmentAnchorsWithReatedAnchors.first(where: {
                $0.value.contains(uuid)
            })
            
            if let environmentProbeAnchor = environmentProperty?.key, let texture = environmentProbeAnchor.environmentTexture {
                environmentTextureByUUID[uuid] = texture
            }
            
            let drawCallGroup = RenderPass.DrawCallGroup(drawCalls: drawCallsByUUID[uuid] ?? [], uuid: uuid)
            drawCallGroups.append(drawCallGroup)
            
        }
        
        // In the buffer, the anchors are layed out by UUID in sorted order. So if there are
        // 5 anchors with UUID = "A..." and 3 UUIDs = "B..." and 1 UUID = "C..." then that's
        // how they will layed out in memory. Therefore updating the buffers is a 2 step process.
        // First, loop through all of the ARAnchors and gather the UUIDs as well as the counts for each.
        // Second, layout and update the buffers in the desired order.
        drawCallGroups.sort { $0.uuid.uuidString < $1.uuid.uuidString }
        
        //
        // Update the Anchor uniform
        //
        
        var anchorMeshIndex = 0
        
        for drawCallGroup in drawCallGroups {
            
            let uuid = drawCallGroup.uuid
            let akAnchors = anchorsByUUID[uuid] ?? []
            
            for akAnchor in akAnchors {
                
                guard let arAnchor = akAnchor.arAnchor else {
                    continue
                }
                
                // allDrawData contains the meshGPUData for all of the meshes associated with this anchor
                guard let allDrawData = meshGPUDataForAnchorsByUUID[uuid]?.drawData else {
                    continue
                }
                
                for drawData in allDrawData {
                
                    // Flip Z axis to convert geometry from right handed to left handed
                    var coordinateSpaceTransform = matrix_identity_float4x4
                    coordinateSpaceTransform.columns.2.z = -1.0
                    
                    // Apply the world transform (as defined in the imported model) if applicable
                    let worldTransform: matrix_float4x4 = {
                        if drawData.worldTransformAnimations.count > 0 {
                            let index = Int(cameraProperties.currentFrame % UInt(drawData.worldTransformAnimations.count))
                            return drawData.worldTransformAnimations[index]
                        } else {
                            return drawData.worldTransform
                        }
                    }()
                    coordinateSpaceTransform = simd_mul(coordinateSpaceTransform, worldTransform)
                    
                    // Update Heading
                    var newTransform = akAnchor.heading.offsetRotation.quaternion.toMatrix4()
                    
                    if akAnchor.heading.type == .absolute {
                        newTransform = newTransform * float4x4(
                            float4(coordinateSpaceTransform.columns.0.x, 0, 0, 0),
                            float4(0, coordinateSpaceTransform.columns.1.y, 0, 0),
                            float4(0, 0, coordinateSpaceTransform.columns.2.z, 0),
                            float4(coordinateSpaceTransform.columns.3.x, coordinateSpaceTransform.columns.3.y, coordinateSpaceTransform.columns.3.z, 1)
                        )
                        coordinateSpaceTransform = newTransform
                    } else if akAnchor.heading.type == .relative {
                        coordinateSpaceTransform = coordinateSpaceTransform * newTransform
                    }
                    
                    let modelMatrix = arAnchor.transform * coordinateSpaceTransform
                    let anchorUniforms = anchorUniformBufferAddress?.assumingMemoryBound(to: AnchorInstanceUniforms.self).advanced(by: anchorMeshIndex)
                    anchorUniforms?.pointee.modelMatrix = modelMatrix
                    anchorUniforms?.pointee.normalMatrix = modelMatrix.normalMatrix
                    
                    //
                    // Update puppet animation
                    //
                    
                    let uuid: UUID = {
                        if modelAssetsForAnchorsByUUID[uuid] != nil {
                            return arAnchor.identifier
                        } else {
                            return generalUUID
                        }
                    }()
                    updatePuppetAnimation(from: drawData, frameNumber: cameraProperties.currentFrame, frameRate: cameraProperties.frameRate)
                    
                    //
                    // Update Environment
                    //
                    
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
                    
                    let environmentUniforms = environmentUniformBufferAddress?.assumingMemoryBound(to: EnvironmentUniforms.self).advanced(by: anchorMeshIndex)
                    
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
                    
                    if environmentData?.hasEnvironmentMap == true {
                        environmentUniforms?.pointee.hasEnvironmentMap = 1
                    } else {
                        environmentUniforms?.pointee.hasEnvironmentMap = 0
                    }
                    
                    //
                    // Update Effects uniform
                    //
                    
                    let effectsUniforms = effectsUniformBufferAddress?.assumingMemoryBound(to: AnchorEffectsUniforms.self).advanced(by: anchorMeshIndex)
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
                    
                    anchorMeshIndex += 1
                    
                }
                
            }
            
        }
        
    }
    
    func updateBuffers(withRealAnchors: [AKRealAnchor], cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties) {
        // Do Nothing
    }
    
    func updateBuffers(withTrackers: [AKAugmentedTracker], targets: [AKTarget], cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties) {
        // Do Nothing
    }
    
    func updateBuffers(withPaths: [AKPath], cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties) {
        // Do Nothing
    }
    
    func draw(withRenderPass renderPass: RenderPass, sharedModules: [SharedRenderModule]?) {
        
        guard anchorInstanceCount > 0 else {
            return
        }
        
        guard let renderEncoder = renderPass.renderCommandEncoder else {
            return
        }
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("Draw Anchors")
        
        if let sharedBuffer = sharedModules?.first(where: {$0.moduleIdentifier == SharedBuffersRenderModule.identifier}), renderPass.usesSharedBuffer {
            
            renderEncoder.pushDebugGroup("Draw Shared Uniforms")
            
            renderEncoder.setVertexBuffer(sharedBuffer.sharedUniformBuffer, offset: sharedBuffer.sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
            renderEncoder.setFragmentBuffer(sharedBuffer.sharedUniformBuffer, offset: sharedBuffer.sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
            
            renderEncoder.popDebugGroup()
            
        }
        
        if let environmentUniformBuffer = environmentUniformBuffer, renderPass.usesEnvironmentBuffer {
            
            renderEncoder.pushDebugGroup("Draw Environment Uniforms")
            if let environmentTexture = environmentData?.environmentTexture, environmentData?.hasEnvironmentMap == true {
                renderEncoder.setFragmentTexture(environmentTexture, index: Int(kTextureIndexEnvironmentMap.rawValue))
            }
            renderEncoder.setFragmentBuffer(environmentUniformBuffer, offset: environmentUniformBufferOffset, index: Int(kBufferIndexEnvironmentUniforms.rawValue))
            renderEncoder.popDebugGroup()
            
        }
        
        if let effectsBuffer = effectsUniformBuffer, renderPass.usesEffectsBuffer {
            
            renderEncoder.pushDebugGroup("Draw Effects Uniforms")
            renderEncoder.setVertexBuffer(effectsBuffer, offset: effectsUniformBufferOffset, index: Int(kBufferIndexAnchorEffectsUniforms.rawValue))
            renderEncoder.setFragmentBuffer(effectsBuffer, offset: effectsUniformBufferOffset, index: Int(kBufferIndexAnchorEffectsUniforms.rawValue))
            renderEncoder.popDebugGroup()
            
        }
        
        var baseIndex = 0
        
        for drawCallGroup in renderPass.drawCallGroups {
            
            let uuid = drawCallGroup.uuid
            
            guard let meshGPUData = meshGPUDataForAnchorsByUUID[uuid] else {
                print("Error: Could not find meshGPUData for UUID: \(uuid)")
                let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeIntermediateMeshDataNotAvailable, userInfo: nil)
                let newError = AKError.recoverableError(.renderPipelineError(.drawAborted(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
                recordNewError(newError)
                continue
            }
            
            let anchorcount = (anchorsByUUID[uuid] ?? []).count
            
            // Geometry Draw Calls
            for (index, drawCall) in drawCallGroup.drawCalls.enumerated() {
                
                drawCall.prepareDrawCall(withRenderPass: renderPass)
                
                // Set any buffers fed into our render pipeline
                renderEncoder.setVertexBuffer(anchorUniformBuffer, offset: anchorUniformBufferOffset, index: Int(kBufferIndexAnchorInstanceUniforms.rawValue))
                renderEncoder.setVertexBuffer(paletteBuffer, offset: paletteBufferOffset, index: Int(kBufferIndexMeshPalettes.rawValue))
                
                var mutableDrawData = meshGPUData.drawData[index]
                mutableDrawData.instanceCount = anchorcount
                
                // Set the mesh's vertex data buffers and draw
                draw(withDrawData: mutableDrawData, with: renderEncoder, baseIndex: baseIndex)
                
                baseIndex += anchorcount
                
            }
            
//            baseIndex += anchorcount
            
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
        static let maxAnchorInstanceCount = 256
        static let maxPaletteSize = 100
        static let alignedAnchorInstanceUniformsSize = ((MemoryLayout<AnchorInstanceUniforms>.stride * Constants.maxAnchorInstanceCount) & ~0xFF) + 0x100
        static let alignedPaletteSize = (MemoryLayout<matrix_float4x4>.stride & ~0xFF) + 0x100
        static let alignedEffectsUniformSize = ((MemoryLayout<AnchorEffectsUniforms>.stride * Constants.maxAnchorInstanceCount) & ~0xFF) + 0x100
        static let alignedEnvironmentUniformSize = ((MemoryLayout<EnvironmentUniforms>.stride * Constants.maxAnchorInstanceCount) & ~0xFF) + 0x100
    }
    
    private var device: MTLDevice?
    private var textureLoader: MTKTextureLoader?
    private var generalUUID = UUID()
    private var modelAssetsForAnchorsByUUID = [UUID: MDLAsset]()
    private var drawCallsByUUID = [UUID: [RenderPass.DrawCall]]()
    private var shaderPreferenceForAnchorsByUUID = [UUID: ShaderPreference]()
    private var anchorUniformBuffer: MTLBuffer?
    private var materialUniformBuffer: MTLBuffer?
    private var paletteBuffer: MTLBuffer?
    private var effectsUniformBuffer: MTLBuffer?
    private var environmentUniformBuffer: MTLBuffer?
    private var pipelineStatesForAnchorsByUUID = [UUID: [MTLRenderPipelineState]]()
    private var anchorDepthState: MTLDepthStencilState?
    private var environmentData: EnvironmentData?
    
    // MetalKit meshes containing vertex data and index buffer for our anchor geometry
    private var meshGPUDataForAnchorsByUUID = [UUID: MeshGPUData]()
    
    // Offset within anchorUniformBuffer to set for the current frame
    private var anchorUniformBufferOffset: Int = 0
    
    // Offset within materialUniformBuffer to set for the current frame
    private var materialUniformBufferOffset: Int = 0
    
    // Offset within paletteBuffer to set for the current frame
    private var paletteBufferOffset = 0
    
    // Offset within effectsUniformBuffer to set for the current frame
    private var effectsUniformBufferOffset: Int = 0
    
    // Offset within environmentUniformBuffer to set for the current frame
    private var environmentUniformBufferOffset: Int = 0
    
    // Addresses to write anchor uniforms to each frame
    private var anchorUniformBufferAddress: UnsafeMutableRawPointer?
    
    // Addresses to write anchor uniforms to each frame
    private var materialUniformBufferAddress: UnsafeMutableRawPointer?
    
    // Addresses to write palette to each frame
    private var paletteBufferAddress: UnsafeMutableRawPointer?
    
    // Addresses to write effects uniforms to each frame
    private var effectsUniformBufferAddress: UnsafeMutableRawPointer?
    
    // Addresses to write environment uniforms to each frame
    private var environmentUniformBufferAddress: UnsafeMutableRawPointer?
    
    // number of frames in the anchor animation by anchor index
    private var anchorAnimationFrameCount = [Int]()
    
    private var anchorsByUUID = [UUID: [AKAugmentedAnchor]]()
    private var environmentTextureByUUID = [UUID: MTLTexture]()
    
    private func createPipelineStates(forUUID uuid: UUID, withMetalLibrary metalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider) -> [RenderPass.DrawCall] {
        
        guard let device = device else {
            print("Serious Error - device not found")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeDeviceNotFound, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return []
        }
        
        guard let meshGPUData = meshGPUDataForAnchorsByUUID[uuid] else {
            print("Serious Error - ERROR: No meshGPUData found when trying to load the pipeline.")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeIntermediateMeshDataNotFound, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return []
        }
        
        let myVertexDescriptor: MTLVertexDescriptor? = meshGPUData.vertexDescriptor
        
        guard let anchorVertexDescriptor = myVertexDescriptor else {
            print("Serious Error - Failed to create a MetalKit vertex descriptor from ModelIO.")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeInvalidMeshData, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return []
        }
        
        let shaderPreference = meshGPUData.shaderPreference
        
        // Saving all of the states for each mesh in the myPipelineStates array.
        var myPipelineStates = [MTLRenderPipelineState]()
        var drawCalls = [RenderPass.DrawCall]()
        for (_ , drawData) in meshGPUData.drawData.enumerated() {
            let anchorPipelineStateDescriptor = MTLRenderPipelineDescriptor()
            do {
                let funcConstants = RenderUtilities.getFuncConstants(forDrawData: drawData)
                // Specify which shader to use based on if the model has skinned puppet suppot
                let vertexName = (drawData.paletteStartIndex != nil) ? "anchorGeometryVertexTransformSkinned" : "anchorGeometryVertexTransform"
                let fragmentShaderName: String = {
                    if shaderPreference == .simple {
                        return "anchorGeometryFragmentLightingSimple"
                    } else {
                        return "anchorGeometryFragmentLighting"
                    }
                }()
                let fragFunc = try metalLibrary.makeFunction(name: fragmentShaderName, constantValues: funcConstants)
                let vertFunc = try metalLibrary.makeFunction(name: vertexName, constantValues: funcConstants)
                anchorPipelineStateDescriptor.vertexDescriptor = anchorVertexDescriptor
                anchorPipelineStateDescriptor.vertexFunction = vertFunc
                anchorPipelineStateDescriptor.fragmentFunction = fragFunc
                anchorPipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
                anchorPipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = true
                anchorPipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                anchorPipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                anchorPipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
                anchorPipelineStateDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
                anchorPipelineStateDescriptor.sampleCount = renderDestination.sampleCount
            } catch let error {
                print("Failed to create pipeline state descriptor, error \(error)")
                let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: error))))
                recordNewError(newError)
            }
            
            let drawCall = RenderPass.DrawCall(withDevice: device, renderPipelineDescriptor: anchorPipelineStateDescriptor)
            drawCalls.append(drawCall)
            
            do {
                try myPipelineStates.append(device.makeRenderPipelineState(descriptor: anchorPipelineStateDescriptor))
            } catch let error {
                print("Failed to create pipeline state, error \(error)")
                let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: error))))
                recordNewError(newError)
            }
        }
        
        pipelineStatesForAnchorsByUUID[uuid] = myPipelineStates
        
        return drawCalls
        
    }
    
    private func updatePuppetAnimation(from drawData: DrawData, frameNumber: UInt, frameRate: Double = 60) {
        
        let capacity = Constants.alignedPaletteSize * Constants.maxPaletteSize
        
        let boundPaletteData = paletteBufferAddress?.bindMemory(to: matrix_float4x4.self, capacity: capacity)
        
        let paletteData = UnsafeMutableBufferPointer<matrix_float4x4>(start: boundPaletteData, count: Constants.maxPaletteSize)
        
        var jointPaletteOffset = 0
        for skin in drawData.skins {
            if let animationIndex = skin.animationIndex {
                let curAnimation = drawData.skeletonAnimations[animationIndex]
                let worldPose = evaluateAnimation(curAnimation, at: (Double(frameNumber) * 1.0 / frameRate))
                let matrixPalette = evaluateMatrixPalette(worldPose, skin)
                
                for k in 0..<matrixPalette.count {
                    paletteData[k + jointPaletteOffset] = matrixPalette[k]
                }
                
                jointPaletteOffset += matrixPalette.count
            }
        }
    }
    
}
