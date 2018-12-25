//
//  UnanchoredRenderModule.swift
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

class UnanchoredRenderModule: RenderModule {
    
    static var identifier = "UnanchoredRenderModule"
    
    //
    // Setup
    //
    
    var moduleIdentifier: String {
        return UnanchoredRenderModule.identifier
    }
    var renderLayer: Int {
        return 12
    }
    var isInitialized: Bool = false
    var sharedModuleIdentifiers: [String]? = [SharedBuffersRenderModule.identifier]
    var renderDistance: Double = 500
    var errors = [AKError]()
    
    // The number of tracker instances to render
    private(set) var trackerInstanceCount: Int = 0
    
    // The number of target instances to render
    private(set) var targetInstanceCount: Int = 0
    
    func initializeBuffers(withDevice aDevice: MTLDevice, maxInFlightBuffers: Int) {
        
        device = aDevice
        
        // Calculate our uniform buffer sizes. We allocate Constants.maxBuffersInFlight instances for uniform
        // storage in a single buffer. This allows us to update uniforms in a ring (i.e. triple
        // buffer the uniforms) so that the GPU reads from one slot in the ring wil the CPU writes
        // to another. Uniforms should be specified with a max instance count for instancing.
        // Also uniform storage must be aligned (to 256 bytes) to meet the requirements to be an
        // argument in the constant address space of our shading functions.
        let unanchoredUniformBufferSize = Constants.alignedInstanceUniformsSize * maxInFlightBuffers
        let materialUniformBufferSize = RenderModuleConstants.alignedMaterialSize * maxInFlightBuffers
        let effectsUniformBufferSize = Constants.alignedEffectsUniformSize * maxInFlightBuffers
        let environmentUniformBufferSize = Constants.alignedEnvironmentUniformSize * maxInFlightBuffers
        
        // Create and allocate our uniform buffer objects. Indicate shared storage so that both the
        // CPU can access the buffer
        unanchoredUniformBuffer = device?.makeBuffer(length: unanchoredUniformBufferSize, options: .storageModeShared)
        unanchoredUniformBuffer?.label = "UnanchoredUniformBuffer"
        
        materialUniformBuffer = device?.makeBuffer(length: materialUniformBufferSize, options: .storageModeShared)
        materialUniformBuffer?.label = "MaterialUniformBuffer"
        
        effectsUniformBuffer = device?.makeBuffer(length: effectsUniformBufferSize, options: .storageModeShared)
        effectsUniformBuffer?.label = "EffectsUniformBuffer"
        
        environmentUniformBuffer = device?.makeBuffer(length: environmentUniformBufferSize, options: .storageModeShared)
        environmentUniformBuffer?.label = "EnvironmentUniformBuffer"
        
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
            
        var hasLoadedTrackerAsset = false
        var hasLoadedTargetAsset = false
        
        // TODO: Add ability to load multiple models by identifier
        modelProvider.loadAsset(forObjectType: UserTracker.type, identifier: nil) { [weak self] asset in
            
            hasLoadedTrackerAsset = true
            
            guard let asset = asset else {
                print("Warning (UnanchoredRenderModule) - Failed to get a MDLAsset for type \(UserTracker.type) from the modelProvider.")
                let newError = AKError.warning(.modelError(.modelNotFound(ModelErrorInfo(type: UserTracker.type))))
                recordNewError(newError)
                if hasLoadedTrackerAsset && hasLoadedTargetAsset {
                    completion()
                }
                return
            }
            
            self?.modelAssetsByUUID[generalTrackerUUID] = asset
            
            // TODO: Figure out a way to load a new model per tracker.
            
            if hasLoadedTrackerAsset && hasLoadedTargetAsset {
                completion()
            }
            
        }
        
        // TODO: Add ability to load multiple models by identifier
        modelProvider.loadAsset(forObjectType: GazeTarget.type, identifier: nil) { [weak self] asset in
            
            hasLoadedTargetAsset = true
            
            guard let asset = asset else {
                print("Warning (UnanchoredRenderModule) - Failed to get a MDLAsset for type \(GazeTarget.type) from the modelProvider.")
                let newError = AKError.warning(.modelError(.modelNotFound(ModelErrorInfo(type: GazeTarget.type))))
                recordNewError(newError)
                if hasLoadedTrackerAsset && hasLoadedTargetAsset {
                    completion()
                }
                return
            }
            
            self?.modelAssetsByUUID[generalTargetUUID] = asset
            
            // TODO: Figure out a way to load a new model per target.
            
            if hasLoadedTrackerAsset && hasLoadedTargetAsset {
                completion()
            }
            
        }
        
    }
    
    func loadPipeline(withMetalLibrary metalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider, textureBundle: Bundle, forRenderPass renderPass: RenderPass? = nil) -> [DrawCallGroup] {
        
        guard let device = device else {
            print("Serious Error - device not found")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeDeviceNotFound, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return []
        }
        
        var drawCallGroups = [DrawCallGroup]()
        
        for item in modelAssetsByUUID {
            
            let uuid = item.key
            let mdlAsset = item.value
            let shaderPreference: ShaderPreference = {
                if let prefernece = shaderPreferenceByUUID[uuid] {
                    return prefernece
                } else {
                    return .pbr
                }
            }()
            
            meshGPUDataByUUID[uuid] = ModelIOTools.meshGPUData(from: mdlAsset, device: device, textureBundle: textureBundle, vertexDescriptor: RenderUtilities.createStandardVertexDescriptor(), frameRate: 60, shaderPreference: shaderPreference)
            
            let drawCallGroup = createPipelineStates(forUUID: uuid, withMetalLibrary: metalLibrary, renderDestination: renderDestination, renderPass: renderPass)
            drawCallGroup.moduleIdentifier = moduleIdentifier
            drawCallGroups.append(drawCallGroup)
            
        }
        
        // In the buffer, the anchors are layed out by UUID in sorted order. So if there are
        // 5 anchors with UUID = "A..." and 3 UUIDs = "B..." and 1 UUID = "C..." then that's
        // how they will layed out in memory. Therefore updating the buffers is a 2 step process.
        // First, loop through all of the ARAnchors and gather the UUIDs as well as the counts for each.
        // Second, layout and update the buffers in the desired order.
        drawCallGroups.sort { $0.uuid.uuidString < $1.uuid.uuidString }
        sortedUUIDs = drawCallGroups.map { $0.uuid }
        isInitialized = true
        
        return drawCallGroups
        
    }
    
    //
    // Per Frame Updates
    //
    
    func updateBufferState(withBufferIndex bufferIndex: Int) {
        
        unanchoredUniformBufferOffset = Constants.alignedInstanceUniformsSize * bufferIndex
        materialUniformBufferOffset = RenderModuleConstants.alignedMaterialSize * bufferIndex
        effectsUniformBufferOffset = Constants.alignedEffectsUniformSize * bufferIndex
        environmentUniformBufferOffset = Constants.alignedEnvironmentUniformSize * bufferIndex
        
        unanchoredUniformBufferAddress = unanchoredUniformBuffer?.contents().advanced(by: unanchoredUniformBufferOffset)
        materialUniformBufferAddress = materialUniformBuffer?.contents().advanced(by: materialUniformBufferOffset)
        effectsUniformBufferAddress = effectsUniformBuffer?.contents().advanced(by: effectsUniformBufferOffset)
        environmentUniformBufferAddress = environmentUniformBuffer?.contents().advanced(by: environmentUniformBufferOffset)
        
    }
    
    func updateBuffers(withAugmentedAnchors anchors: [AKAugmentedAnchor], cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties, shadowProperties: ShadowProperties) {
        // Do Nothing
    }
    
    func updateBuffers(withRealAnchors: [AKRealAnchor], cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties, shadowProperties: ShadowProperties) {
        // Do Nothing
    }
    
    func updateBuffers(withTrackers trackers: [AKAugmentedTracker], targets: [AKTarget], cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties, shadowProperties: ShadowProperties) {
        
        // Update the uniform buffer with transforms of the current frame's trackers
        
        trackerInstanceCount = 0
        targetInstanceCount = 0
        geometriesByUUID = [:]
        environmentTextureByUUID = [:]
        
        // Set up lighting for the scene using the ambient intensity if provided
        ambientIntensity = {
            if let lightEstimate = environmentProperties.lightEstimate {
                return Float(lightEstimate.ambientIntensity) / 1000.0
            } else {
                return 1
            }
        }()
        
        ambientLightColor = {
            if let lightEstimate = environmentProperties.lightEstimate {
                return getRGB(from: lightEstimate.ambientColorTemperature)
            } else {
                return vector3(0.5, 0.5, 0.5)
            }
        }()
        
        var index = 0
        var trackerUUIDs = trackers.map({$0.identifier})
        trackerUUIDs.append(generalTrackerUUID)
        var targetUUIDs = targets.map({$0.identifier})
        targetUUIDs.append(generalTargetUUID)
        
        // Build the geometriesByUUID map
        
        trackers.forEach { tracker in
            let uuid: UUID = {
                if let identifier = tracker.identifier, modelAssetsByUUID[identifier] != nil {
                    return identifier
                } else {
                    return generalTrackerUUID
                }
            }()
            if let currentGeometries = geometriesByUUID[uuid] {
                var mutableCurrentGeometries = currentGeometries
                mutableCurrentGeometries.append(tracker)
                geometriesByUUID[uuid] = mutableCurrentGeometries
            } else {
                geometriesByUUID[uuid] = [tracker]
            }
        }
        
        targets.forEach { target in
            let uuid: UUID = {
                if let identifier = target.identifier, modelAssetsByUUID[identifier] != nil {
                    return identifier
                } else {
                    return generalTargetUUID
                }
            }()
            if let currentGeometries = geometriesByUUID[uuid] {
                var mutableCurrentGeometries = currentGeometries
                mutableCurrentGeometries.append(target)
                geometriesByUUID[uuid] = mutableCurrentGeometries
            } else {
                geometriesByUUID[uuid] = [target]
            }
        }
        
        for uuid in sortedUUIDs {
            
            if trackerUUIDs.contains(uuid) {
                
                let akTrackers = geometriesByUUID[uuid] as! [AKTracker]
                
                for akTracker in akTrackers {
                    
                    // allDrawData contains the meshGPUData for all of the meshes associated with this anchor
                    guard let allDrawData = meshGPUDataByUUID[uuid]?.drawData else {
                        continue
                    }
                    
                    // Apply the transform of the target relative to the reference transform
                    let trackerAbsoluteTransform = akTracker.position.referenceTransform * akTracker.position.transform
                    
                    // Ignore anchors that are beyond the renderDistance
                    let distance = anchorDistance(withTransform: trackerAbsoluteTransform, cameraProperties: cameraProperties)
                    guard Double(distance) < renderDistance else {
                        continue
                    }
                    
                    trackerInstanceCount += 1
                    
                    if trackerInstanceCount > Constants.maxTrackerInstanceCount {
                        trackerInstanceCount = Constants.maxTrackerInstanceCount
                        break
                    }
                    
                    for drawData in allDrawData {
                        
                        // Flip Z axis to convert geometry from right handed to left handed
                        var coordinateSpaceTransform = matrix_identity_float4x4
                        coordinateSpaceTransform.columns.2.z = -1.0
                        
                        let worldTransform: matrix_float4x4 = {
                            if drawData.worldTransformAnimations.count > 0 {
                                let index = Int(cameraProperties.currentFrame % UInt(drawData.worldTransformAnimations.count))
                                return drawData.worldTransformAnimations[index]
                            } else {
                                return drawData.worldTransform
                            }
                        }()
                        coordinateSpaceTransform = simd_mul(coordinateSpaceTransform, worldTransform)
                
                        let modelMatrix = trackerAbsoluteTransform * coordinateSpaceTransform
                        
                        let trackerUniforms = unanchoredUniformBufferAddress?.assumingMemoryBound(to: AnchorInstanceUniforms.self).advanced(by: index)
                        trackerUniforms?.pointee.modelMatrix = modelMatrix
                        trackerUniforms?.pointee.normalMatrix = modelMatrix.normalMatrix
                        
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
                        
                        let environmentUniforms = environmentUniformBufferAddress?.assumingMemoryBound(to: EnvironmentUniforms.self).advanced(by: index)
                        
                        environmentUniforms?.pointee.ambientLightColor = ambientLightColor ?? vector3(0.5, 0.5, 0.5)
                        
                        var directionalLightDirection : vector_float3 = environmentProperties.directionalLightDirection
                        directionalLightDirection = simd_normalize(directionalLightDirection)
                        environmentUniforms?.pointee.directionalLightDirection = directionalLightDirection
                        
                        let directionalLightColor: vector_float3 = vector3(0.6, 0.6, 0.6)
                        environmentUniforms?.pointee.directionalLightColor = directionalLightColor * (ambientIntensity ?? 1)
                        
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
                        
                        let effectsUniforms = effectsUniformBufferAddress?.assumingMemoryBound(to: AnchorEffectsUniforms.self).advanced(by: index)
                        var hasSetAlpha = false
                        var hasSetGlow = false
                        var hasSetTint = false
                        var hasSetScale = false
                        if let effects = akTracker.effects {
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
                        
                        index += 1
                        
                    }
                    
                }
                
            } else if targetUUIDs.contains(uuid) {
                
                let akTargets = geometriesByUUID[uuid] as! [AKTarget]
                
                for akTarget in akTargets {
                    
                    // allDrawData contains the meshGPUData for all of the meshes associated with this anchor
                    guard let allDrawData = meshGPUDataByUUID[uuid]?.drawData else {
                        continue
                    }
                    
                    // Apply the transform of the target relative to the reference transform
                    let targetAbsoluteTransform = akTarget.position.referenceTransform * akTarget.position.transform
                    
                    // Ignore anchors that are beyond the renderDistance
                    let distance = anchorDistance(withTransform: targetAbsoluteTransform, cameraProperties: cameraProperties)
                    guard Double(distance) < renderDistance else {
                        continue
                    }
                    
                    targetInstanceCount += 1
                    
                    if targetInstanceCount > Constants.maxTargetInstanceCount {
                        targetInstanceCount = Constants.maxTargetInstanceCount
                        break
                    }
                    
                    for drawData in allDrawData {
                    
                        // Flip Z axis to convert geometry from right handed to left handed
                        var coordinateSpaceTransform = matrix_identity_float4x4
                        coordinateSpaceTransform.columns.2.z = -1.0
                        
                        let worldTransform: matrix_float4x4 = {
                            if drawData.worldTransformAnimations.count > 0 {
                                let index = Int(cameraProperties.currentFrame % UInt(drawData.worldTransformAnimations.count))
                                return drawData.worldTransformAnimations[index]
                            } else {
                                return drawData.worldTransform
                            }
                        }()
                        coordinateSpaceTransform = simd_mul(coordinateSpaceTransform, worldTransform)
                        
                        let modelMatrix = targetAbsoluteTransform * coordinateSpaceTransform
                        
                        let targetUniforms = unanchoredUniformBufferAddress?.assumingMemoryBound(to: AnchorInstanceUniforms.self).advanced(by: index)
                        targetUniforms?.pointee.modelMatrix = modelMatrix
                        targetUniforms?.pointee.normalMatrix = modelMatrix.normalMatrix
                        
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
                        
                        let environmentUniforms = environmentUniformBufferAddress?.assumingMemoryBound(to: EnvironmentUniforms.self).advanced(by: index)
                        
                        environmentUniforms?.pointee.ambientLightColor = ambientLightColor ?? vector3(0.5, 0.5, 0.5)
                        
                        var directionalLightDirection : vector_float3 = environmentProperties.directionalLightDirection
                        directionalLightDirection = simd_normalize(directionalLightDirection)
                        environmentUniforms?.pointee.directionalLightDirection = directionalLightDirection
                        
                        let directionalLightColor: vector_float3 = vector3(0.6, 0.6, 0.6)
                        environmentUniforms?.pointee.directionalLightColor = directionalLightColor * (ambientIntensity ?? 1)
                        
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
                        
                        let effectsUniforms = effectsUniformBufferAddress?.assumingMemoryBound(to: AnchorEffectsUniforms.self).advanced(by: index)
                        var hasSetAlpha = false
                        var hasSetGlow = false
                        var hasSetTint = false
                        var hasSetScale = false
                        if let effects = akTarget.effects {
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
                        
                        index += 1
                        
                    }
                    
                }
                
            }
            
        }

        //
        // Update the shadow map
        //
        shadowMap = shadowProperties.shadowMap
        
    }
    
    func updateBuffers(withPaths: [AKPath], cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties, shadowProperties: ShadowProperties) {
        // Do Nothing
    }
    
    func draw(withRenderPass renderPass: RenderPass, sharedModules: [SharedRenderModule]?) {
        
        guard let renderEncoder = renderPass.renderCommandEncoder else {
            return
        }
        
        guard trackerInstanceCount > 0 || targetInstanceCount > 0 else {
            return
        }
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("Draw Unanchored")
        
        // Set render command encoder state
        renderEncoder.setCullMode(.back)
        
        if let sharedBuffer = sharedModules?.first(where: {$0.moduleIdentifier == SharedBuffersRenderModule.identifier}), renderPass.usesSharedBuffer  {
            
            renderEncoder.pushDebugGroup("Draw Shared Uniforms")
            
            renderEncoder.setVertexBuffer(sharedBuffer.sharedUniformBuffer, offset: sharedBuffer.sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
            renderEncoder.setFragmentBuffer(sharedBuffer.sharedUniformBuffer, offset: sharedBuffer.sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
            
            renderEncoder.popDebugGroup()
            
        }
        
        if let environmentUniformBuffer = environmentUniformBuffer, renderPass.usesEnvironment  {
            
            renderEncoder.pushDebugGroup("Draw Environment Uniforms")
            if let environmentTexture = environmentData?.environmentTexture, environmentData?.hasEnvironmentMap == true {
                renderEncoder.setFragmentTexture(environmentTexture, index: Int(kTextureIndexEnvironmentMap.rawValue))
            }
            renderEncoder.setVertexBuffer(environmentUniformBuffer, offset: environmentUniformBufferOffset, index: Int(kBufferIndexEnvironmentUniforms.rawValue))
            renderEncoder.setFragmentBuffer(environmentUniformBuffer, offset: environmentUniformBufferOffset, index: Int(kBufferIndexEnvironmentUniforms.rawValue))
            renderEncoder.popDebugGroup()
            
        }
        
        if let effectsBuffer = effectsUniformBuffer, renderPass.usesEffects {
            
            renderEncoder.pushDebugGroup("Draw Effects Uniforms")
            renderEncoder.setVertexBuffer(effectsBuffer, offset: effectsUniformBufferOffset, index: Int(kBufferIndexAnchorEffectsUniforms.rawValue))
            renderEncoder.setFragmentBuffer(effectsBuffer, offset: effectsUniformBufferOffset, index: Int(kBufferIndexAnchorEffectsUniforms.rawValue))
            renderEncoder.popDebugGroup()
            
        }
        
        if let shadowMap = shadowMap {
            
            renderEncoder.pushDebugGroup("Attach Shadow Buffer")
            renderEncoder.setFragmentTexture(shadowMap, index: Int(kTextureIndexShadowMap.rawValue))
            renderEncoder.popDebugGroup()
            
        }
        
        var baseIndex = 0
            
        for drawCallGroup in renderPass.drawCallGroups.filter({ $0.moduleIdentifier == moduleIdentifier }) {
            
            let uuid = drawCallGroup.uuid
            
            guard let meshGPUData = meshGPUDataByUUID[uuid] else {
                print("Error: Could not find meshGPUData for UUID: \(uuid)")
                let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeIntermediateMeshDataNotAvailable, userInfo: nil)
                let newError = AKError.recoverableError(.renderPipelineError(.drawAborted(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
                recordNewError(newError)
                continue
            }
            
            let geometryCount = (geometriesByUUID[uuid] ?? []).count
            
            // Geometry Draw Calls
            for (index, drawCall) in drawCallGroup.drawCalls.enumerated() {
                
                drawCall.prepareDrawCall(withRenderPass: renderPass)
                
                // Set any buffers fed into our render pipeline
                renderEncoder.setVertexBuffer(unanchoredUniformBuffer, offset: unanchoredUniformBufferOffset, index: Int(kBufferIndexAnchorInstanceUniforms.rawValue))
                
                var mutableDrawData = meshGPUData.drawData[index]
                mutableDrawData.instanceCount = trackerInstanceCount
                
                // Set the mesh's vertex data buffers and draw
                draw(withDrawData: mutableDrawData, with: renderEncoder, baseIndex: baseIndex)
                
                baseIndex += geometryCount
                
            }
            
//            baseIndex += geometryCount
            
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
        static let maxTrackerInstanceCount = 64
        static let maxTargetInstanceCount = 64
        static let alignedInstanceUniformsSize = ((MemoryLayout<AnchorInstanceUniforms>.stride * (Constants.maxTrackerInstanceCount + Constants.maxTargetInstanceCount)) & ~0xFF) + 0x100
        static let alignedEffectsUniformSize = ((MemoryLayout<AnchorEffectsUniforms>.stride * (Constants.maxTrackerInstanceCount + Constants.maxTargetInstanceCount)) & ~0xFF) + 0x100
        static let alignedEnvironmentUniformSize = ((MemoryLayout<EnvironmentUniforms>.stride * (Constants.maxTrackerInstanceCount + Constants.maxTargetInstanceCount)) & ~0xFF) + 0x100
    }
    
    private var device: MTLDevice?
    private var textureLoader: MTKTextureLoader?
    private var generalTrackerUUID = UUID()
    private var generalTargetUUID = UUID()
    private var sortedUUIDs = [UUID]()
    private var modelAssetsByUUID = [UUID: MDLAsset]()
    private var shaderPreferenceByUUID = [UUID: ShaderPreference]()
    private var environmentTextureByUUID = [UUID: MTLTexture]()
    // MetalKit meshes containing vertex data and index buffer for our anchor geometry
    private var meshGPUDataByUUID = [UUID: MeshGPUData]()
    private var geometriesByUUID = [UUID: [AKGeometricEntity]]()
    private var ambientIntensity: Float?
    private var ambientLightColor: vector_float3?
    private var unanchoredUniformBuffer: MTLBuffer?
    private var materialUniformBuffer: MTLBuffer?
    private var effectsUniformBuffer: MTLBuffer?
    private var environmentUniformBuffer: MTLBuffer?
    private var environmentData: EnvironmentData?
    private var shadowMap: MTLTexture?
    
    // Offset within unanchoredUniformBuffer to set for the current frame
    private var unanchoredUniformBufferOffset: Int = 0
    
    // Offset within materialUniformBuffer to set for the current frame
    private var materialUniformBufferOffset: Int = 0
    
    // Offset within effectsUniformBuffer to set for the current frame
    private var effectsUniformBufferOffset: Int = 0
    
    // Offset within environmentUniformBuffer to set for the current frame
    private var environmentUniformBufferOffset: Int = 0
    
    // Addresses to write uniforms to each frame
    private var unanchoredUniformBufferAddress: UnsafeMutableRawPointer?
    
    // Addresses to write material uniforms to each frame
    private var materialUniformBufferAddress: UnsafeMutableRawPointer?
    
    // Addresses to write effects uniforms to each frame
    private var effectsUniformBufferAddress: UnsafeMutableRawPointer?
    
    // Addresses to write environment uniforms to each frame
    private var environmentUniformBufferAddress: UnsafeMutableRawPointer?
    
    // number of frames in the tracker animation by index
    private var trackerAnimationFrameCount = [Int]()
    
    // number of frames in the target animation by index
    private var targetAnimationFrameCount = [Int]()
    
    private func createPipelineStates(forUUID uuid: UUID, withMetalLibrary metalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider, renderPass: RenderPass?) -> DrawCallGroup {
        
        guard let device = device else {
            print("Serious Error - device not found")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeDeviceNotFound, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return DrawCallGroup(drawCalls: [], uuid: uuid)
        }
        
        guard let meshGPUData = meshGPUDataByUUID[uuid] else {
            print("Serious Error - ERROR: No meshGPUData found when trying to load the pipeline.")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeIntermediateMeshDataNotFound, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return DrawCallGroup(drawCalls: [], uuid: uuid)
        }
        
        guard let aVertexDescriptor = meshGPUData.vertexDescriptor else {
            print("Serious Error - Failed to create a MetalKit vertex descriptor from ModelIO.")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeInvalidMeshData, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return DrawCallGroup(drawCalls: [], uuid: uuid)
        }
        
        let shaderPreference = meshGPUData.shaderPreference
        
        var drawCalls = [DrawCall]()
        for drawData in meshGPUData.drawData {
            
            let funcConstants = RenderUtilities.getFuncConstants(forDrawData: drawData)
            
            let fragFunc: MTLFunction = {
                do {
                    let fragmentShaderName: String = {
                        if shaderPreference == .simple {
                            return "anchorGeometryFragmentLightingSimple"
                        } else {
                            return "anchorGeometryFragmentLighting"
                        }
                    }()
                    return try metalLibrary.makeFunction(name: fragmentShaderName, constantValues: funcConstants)
                } catch let error {
                    print("Failed to create fragment function for pipeline state descriptor, error \(error)")
                    let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: error))))
                    recordNewError(newError)
                    fatalError()
                }
            }()
            
            let vertFunc: MTLFunction = {
                do {
                    // Specify which shader to use based on if the model has skinned puppet suppot
                    let vertexName = drawData.isSkinned ? "anchorGeometryVertexTransformSkinned" : "anchorGeometryVertexTransform"
                    return try metalLibrary.makeFunction(name: vertexName, constantValues: funcConstants)
                } catch let error {
                    print("Failed to create vertex function for pipeline state descriptor, error \(error)")
                    let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: error))))
                    recordNewError(newError)
                    fatalError()
                }
            }()
            
            let pipelineStateDescriptor: MTLRenderPipelineDescriptor = {
                
                if let renderPass = renderPass, let aPipelineDescriptor = renderPass.renderPipelineDescriptor(withVertexDescriptor: aVertexDescriptor, vertexFunction: vertFunc, fragmentFunction: fragFunc) {
                    return aPipelineDescriptor
                } else {
                    let aPipelineDescriptor = MTLRenderPipelineDescriptor()
                    aPipelineDescriptor.vertexDescriptor = aVertexDescriptor
                    aPipelineDescriptor.vertexFunction = vertFunc
                    aPipelineDescriptor.fragmentFunction = fragFunc
                    aPipelineDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
                    aPipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
                    aPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                    aPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                    aPipelineDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
                    aPipelineDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
                    aPipelineDescriptor.sampleCount = renderDestination.sampleCount
                    return aPipelineDescriptor
                }
                
            }()
            
            let unanchoredDepthStateDescriptor: MTLDepthStencilDescriptor = {
                if let renderPass = renderPass {
                    let aDepthStateDescriptor = renderPass.depthStencilDescriptor(withDepthComareFunction: .less, isDepthWriteEnabled: true)
                    return aDepthStateDescriptor
                } else {
                    let aDepthStateDescriptor = MTLDepthStencilDescriptor()
                    aDepthStateDescriptor.depthCompareFunction = .less
                    aDepthStateDescriptor.isDepthWriteEnabled = true
                    return aDepthStateDescriptor
                }
            }()
            
            if let drawCall = renderPass?.drawCall(withRenderPipelineDescriptor: pipelineStateDescriptor, depthStencilDescriptor: unanchoredDepthStateDescriptor) {
                drawCalls.append(drawCall)
            }
            
        }
        
        let drawCallGroup = DrawCallGroup(drawCalls: drawCalls, uuid: uuid)
        return drawCallGroup
        
    }
    
}
