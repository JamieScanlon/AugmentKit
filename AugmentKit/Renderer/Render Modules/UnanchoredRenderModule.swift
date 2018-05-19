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
        
        // Create and allocate our uniform buffer objects. Indicate shared storage so that both the
        // CPU can access the buffer
        unanchoredUniformBuffer = device?.makeBuffer(length: unanchoredUniformBufferSize, options: .storageModeShared)
        unanchoredUniformBuffer?.label = "UnanchoredUniformBuffer"
        
        materialUniformBuffer = device?.makeBuffer(length: materialUniformBufferSize, options: .storageModeShared)
        materialUniformBuffer?.label = "MaterialUniformBuffer"
        
        effectsUniformBuffer = device?.makeBuffer(length: effectsUniformBufferSize, options: .storageModeShared)
        effectsUniformBuffer?.label = "EffectsUniformBuffer"
        
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
        
        var hasLoadedTrackerModel = false
        var hasLoadedTargetModel = false
        
        // TODO: Add ability to load multiple models by identifier
        modelProvider.loadModel(forObjectType: UserTracker.type, identifier: nil) { [weak self] model in
            
            hasLoadedTrackerModel = true
            
            guard let model = model else {
                print("Warning (UnanchoredRenderModule) - Failed to get a model for type \(UserTracker.type) from the modelProvider.")
                let newError = AKError.warning(.modelError(.modelNotFound(ModelErrorInfo(type: UserTracker.type))))
                recordNewError(newError)
                if hasLoadedTrackerModel && hasLoadedTargetModel {
                    completion()
                }
                return
            }
            
            self?.trackerModel = model
            
            // TODO: Figure out a way to load a new model per tracker.
            
            if hasLoadedTrackerModel && hasLoadedTargetModel {
                completion()
            }
            
        }
        
        // TODO: Add ability to load multiple models by identifier
        modelProvider.loadModel(forObjectType: GazeTarget.type, identifier: nil) { [weak self] model in
            
            hasLoadedTargetModel = true
            
            guard let model = model else {
                print("Warning (UnanchoredRenderModule) - Failed to get a model for type \(GazeTarget.type) from the modelProvider.")
                let newError = AKError.warning(.modelError(.modelNotFound(ModelErrorInfo(type: GazeTarget.type))))
                recordNewError(newError)
                if hasLoadedTrackerModel && hasLoadedTargetModel {
                    completion()
                }
                return
            }
            
            self?.targetModel = model
            
            // TODO: Figure out a way to load a new model per target.
            
            if hasLoadedTrackerModel && hasLoadedTargetModel {
                completion()
            }
            
        }
        
    }
    
    func loadPipeline(withMetalLibrary metalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider) {
        
        guard let device = device else {
            print("Serious Error - device not found")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeDeviceNotFound, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return
        }
        
        if let trackerModel = trackerModel {
        
            if trackerModel.meshNodeIndices.count > 1 {
                print("WARNING: More than one mesh was found. Currently only one mesh per tracker is supported.")
                let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeModelNotSupported, userInfo: nil)
                let newError = AKError.warning(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
                recordNewError(newError)
            }
            
            trackerMeshGPUData = meshData(from: trackerModel)
            
            guard let trackerMeshGPUData = trackerMeshGPUData else {
                print("Serious Error - ERROR: No meshGPUData found for target when trying to load the pipeline.")
                let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeIntermediateMeshDataNotFound, userInfo: nil)
                let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
                recordNewError(newError)
                return
            }
            
            guard let trackerVertexDescriptor = createMetalVertexDescriptor(withFirstModelIOVertexDescriptorIn: trackerModel.vertexDescriptors) else {
                print("Serious Error - Failed to create a MetalKit vertex descriptor from ModelIO.")
                let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeInvalidMeshData, userInfo: nil)
                let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
                recordNewError(newError)
                return
            }
            
            for (drawIdx, drawData) in trackerMeshGPUData.drawData.enumerated() {
                let trackerPipelineStateDescriptor = MTLRenderPipelineDescriptor()
                do {
                    let funcConstants = MetalUtilities.getFuncConstantsForDrawDataSet(meshData: trackerModel.meshes[drawIdx], useMaterials: usesMaterials)
                    // TODO: Implement a vertex shader with puppet animation support
                    //                let vertexName = (drawData.paletteStartIndex != nil) ? "vertex_skinned" : "trackerGeometryVertexTransform"
                    let vertexName = "anchorGeometryVertexTransform"
                    let fragFunc = try metalLibrary.makeFunction(name: "anchorGeometryFragmentLighting", constantValues: funcConstants)
                    let vertFunc = try metalLibrary.makeFunction(name: vertexName, constantValues: funcConstants)
                    trackerPipelineStateDescriptor.vertexDescriptor = trackerVertexDescriptor
                    trackerPipelineStateDescriptor.vertexFunction = vertFunc
                    trackerPipelineStateDescriptor.fragmentFunction = fragFunc
                    trackerPipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
                    trackerPipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = true
                    trackerPipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                    trackerPipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                    trackerPipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
                    trackerPipelineStateDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
                    trackerPipelineStateDescriptor.sampleCount = renderDestination.sampleCount
                } catch let error {
                    print("Failed to create pipeline state descriptor, error \(error)")
                    let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: error))))
                    recordNewError(newError)
                }
                
                do {
                    try unanchoredPipelineStates.append(device.makeRenderPipelineState(descriptor: trackerPipelineStateDescriptor))
                } catch let error {
                    print("Failed to create pipeline state, error \(error)")
                    let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: error))))
                    recordNewError(newError)
                }
            }
            
        }
        
        if let targetModel = targetModel {
            
            if targetModel.meshNodeIndices.count > 1 {
                print("WARNING: More than one mesh was found. Currently only one mesh per target is supported.")
                let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeModelNotSupported, userInfo: nil)
                let newError = AKError.warning(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
                recordNewError(newError)
            }
            
            targetMeshGPUData = meshData(from: targetModel)
            
            guard let targetMeshGPUData = targetMeshGPUData else {
                print("Serious Error - ERROR: No meshGPUData for target found when trying to load the pipeline.")
                let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeIntermediateMeshDataNotFound, userInfo: nil)
                let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
                recordNewError(newError)
                return
            }
            
            guard let targetVertexDescriptor = createMetalVertexDescriptor(withFirstModelIOVertexDescriptorIn: targetModel.vertexDescriptors) else {
                print("Serious Error - Failed to create a MetalKit vertex descriptor from ModelIO.")
                let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeInvalidMeshData, userInfo: nil)
                let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
                recordNewError(newError)
                return
            }
        
            for (drawIdx, drawData) in targetMeshGPUData.drawData.enumerated() {
                let targetPipelineStateDescriptor = MTLRenderPipelineDescriptor()
                do {
                    let funcConstants = MetalUtilities.getFuncConstantsForDrawDataSet(meshData: targetModel.meshes[drawIdx], useMaterials: usesMaterials)
                    // TODO: Implement a vertex shader with puppet animation support
                    //                let vertexName = (drawData.paletteStartIndex != nil) ? "vertex_skinned" : "targetGeometryVertexTransform"
                    let vertexName = "anchorGeometryVertexTransform"
                    let fragFunc = try metalLibrary.makeFunction(name: "anchorGeometryFragmentLighting", constantValues: funcConstants)
                    let vertFunc = try metalLibrary.makeFunction(name: vertexName, constantValues: funcConstants)
                    targetPipelineStateDescriptor.vertexDescriptor = targetVertexDescriptor
                    targetPipelineStateDescriptor.vertexFunction = vertFunc
                    targetPipelineStateDescriptor.fragmentFunction = fragFunc
                    targetPipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
                    targetPipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = true
                    targetPipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                    targetPipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                    targetPipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
                    targetPipelineStateDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
                    targetPipelineStateDescriptor.sampleCount = renderDestination.sampleCount
                } catch let error {
                    print("Failed to create pipeline state descriptor, error \(error)")
                    let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: error))))
                    recordNewError(newError)
                }
                
                do {
                    try unanchoredPipelineStates.append(device.makeRenderPipelineState(descriptor: targetPipelineStateDescriptor))
                } catch let error {
                    print("Failed to create pipeline state, error \(error)")
                    let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: error))))
                    recordNewError(newError)
                }
                
            }
            
        }
        
        let unanchoredDepthStateDescriptor = MTLDepthStencilDescriptor()
        unanchoredDepthStateDescriptor.depthCompareFunction = .less
        unanchoredDepthStateDescriptor.isDepthWriteEnabled = true
        unanchoredDepthState = device.makeDepthStencilState(descriptor: unanchoredDepthStateDescriptor)
        
        isInitialized = true
        
    }
    
    //
    // Per Frame Updates
    //
    
    func updateBufferState(withBufferIndex bufferIndex: Int) {
        
        unanchoredUniformBufferOffset = Constants.alignedInstanceUniformsSize * bufferIndex
        materialUniformBufferOffset = RenderModuleConstants.alignedMaterialSize * bufferIndex
        effectsUniformBufferOffset = Constants.alignedEffectsUniformSize * bufferIndex
        
        unanchoredUniformBufferAddress = unanchoredUniformBuffer?.contents().advanced(by: unanchoredUniformBufferOffset)
        materialUniformBufferAddress = materialUniformBuffer?.contents().advanced(by: materialUniformBufferOffset)
        effectsUniformBufferAddress = effectsUniformBuffer?.contents().advanced(by: effectsUniformBufferOffset)
        
    }
    
    func updateBuffers(withARFrame frame: ARFrame, cameraProperties: CameraProperties) {
        // Do Nothing
    }
    
    func updateBuffers(withTrackers trackers: [AKAugmentedTracker], targets: [AKTarget], cameraProperties: CameraProperties) {
        
        // Update the uniform buffer with transforms of the current frame's trackers
        
        trackerInstanceCount = 0
        
        for index in 0..<trackers.count {
            
            let tracker = trackers[index]
            
            // Apply the transform of the tracker relative to the reference transform
            let trackerAbsoluteTransform = tracker.position.referenceTransform * tracker.position.transform
            
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
            
            // Flip Z axis to convert geometry from right handed to left handed
            var coordinateSpaceTransform = matrix_identity_float4x4
            coordinateSpaceTransform.columns.2.z = -1.0
            
            let trackerIndex = trackerInstanceCount - 1
            
            if let model = trackerModel {
                
                // Apply the world transform (as defined in the imported model) if applicable
                
                if let modelIndex = modelIndex(in: model, fromIndex: trackerIndex), modelIndex < model.worldTransforms.count {
                    let worldTransform = model.worldTransforms[modelIndex]
                    coordinateSpaceTransform = simd_mul(coordinateSpaceTransform, worldTransform)
                }
                
                let modelMatrix = trackerAbsoluteTransform * coordinateSpaceTransform
                
                let trackerUniforms = unanchoredUniformBufferAddress?.assumingMemoryBound(to: AnchorInstanceUniforms.self).advanced(by: trackerIndex)
                trackerUniforms?.pointee.modelMatrix = modelMatrix
                
            }
            
            //
            // Update the Effects uniform
            //
            
            let effectsUniforms = effectsUniformBufferAddress?.assumingMemoryBound(to: AnchorEffectsUniforms.self).advanced(by: trackerIndex)
            effectsUniforms?.pointee.alpha = 1 // TODO: Implement
            effectsUniforms?.pointee.glow = 0 // TODO: Implement
            effectsUniforms?.pointee.tint = float3(1,1,1) // TODO: Implement
            
        }
        
        // Update the uniform buffer with transforms of the current frame's targets
        
        targetInstanceCount = 0
        
        for index in 0..<targets.count {
            
            //
            // Update the Target uniform
            //
            
            let target = targets[index]
            
            // Apply the transform of the target relative to the reference transform
            let targetAbsoluteTransform = target.position.referenceTransform * target.position.transform
            
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
            
            // Flip Z axis to convert geometry from right handed to left handed
            var coordinateSpaceTransform = matrix_identity_float4x4
            coordinateSpaceTransform.columns.2.z = -1.0
            
            let targetIndex = targetInstanceCount - 1
            let adjustedIndex = targetIndex + trackerInstanceCount
            
            if let model = targetModel {
                
                // Apply the world transform (as defined in the imported model) if applicable
                if let modelIndex = modelIndex(in: model, fromIndex: targetIndex), modelIndex < model.worldTransforms.count {
                    let worldTransform = model.worldTransforms[modelIndex]
                    coordinateSpaceTransform = simd_mul(coordinateSpaceTransform, worldTransform)
                }
                
                let modelMatrix = targetAbsoluteTransform * coordinateSpaceTransform
                
                
                let targetUniforms = unanchoredUniformBufferAddress?.assumingMemoryBound(to: AnchorInstanceUniforms.self).advanced(by: adjustedIndex)
                targetUniforms?.pointee.modelMatrix = modelMatrix
                
            }
            
            //
            // Update the Effects uniform
            //
            
            let effectsUniforms = effectsUniformBufferAddress?.assumingMemoryBound(to: AnchorEffectsUniforms.self).advanced(by: adjustedIndex)
            effectsUniforms?.pointee.alpha = 1 // TODO: Implement
            effectsUniforms?.pointee.glow = 0 // TODO: Implement
            effectsUniforms?.pointee.tint = float3(1,1,1) // TODO: Implement
            
        }
        
    }
    
    func updateBuffers(withPaths: [AKPath], cameraProperties: CameraProperties) {
        // Do Nothing
    }
    
    func draw(withRenderEncoder renderEncoder: MTLRenderCommandEncoder, sharedModules: [SharedRenderModule]?) {
        
        guard trackerInstanceCount > 0 || targetInstanceCount > 0 else {
            return
        }
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("Draw Unanchored")
        
        // Set render command encoder state
        renderEncoder.setCullMode(.back)
        
        guard trackerMeshGPUData != nil || targetMeshGPUData != nil else {
            print("Error: Mesh GPU Data not available a draw time. Aborting")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeIntermediateMeshDataNotAvailable, userInfo: nil)
            let newError = AKError.recoverableError(.renderPipelineError(.drawAborted(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return
        }
        
        if let sharedBuffer = sharedModules?.filter({$0.moduleIdentifier == SharedBuffersRenderModule.identifier}).first {
            
            renderEncoder.pushDebugGroup("Draw Shared Uniforms")
            
            renderEncoder.setVertexBuffer(sharedBuffer.sharedUniformBuffer, offset: sharedBuffer.sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
            renderEncoder.setFragmentBuffer(sharedBuffer.sharedUniformBuffer, offset: sharedBuffer.sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
            
            renderEncoder.popDebugGroup()
            
        }
        
        if let effectsBuffer = effectsUniformBuffer {
            
            renderEncoder.pushDebugGroup("Draw Effects Uniforms")
            renderEncoder.setFragmentBuffer(effectsBuffer, offset: effectsUniformBufferOffset, index: Int(kBufferIndexAnchorEffectsUniforms.rawValue))
            renderEncoder.popDebugGroup()
            
        }
        
        if let trackerMeshGPUData = trackerMeshGPUData {
            
            for (drawDataIdx, drawData) in trackerMeshGPUData.drawData.enumerated() {
                
                if drawDataIdx < unanchoredPipelineStates.count {
                    renderEncoder.setRenderPipelineState(unanchoredPipelineStates[drawDataIdx])
                    renderEncoder.setDepthStencilState(unanchoredDepthState)
                    
                    // Set any buffers fed into our render pipeline
                    renderEncoder.setVertexBuffer(unanchoredUniformBuffer, offset: unanchoredUniformBufferOffset, index: Int(kBufferIndexAnchorInstanceUniforms.rawValue))
                    
                    var mutableDrawData = drawData
                    mutableDrawData.instCount = trackerInstanceCount
                    
                    // Set the mesh's vertex data buffers
                    encode(meshGPUData: trackerMeshGPUData, fromDrawData: mutableDrawData, with: renderEncoder)
                    
                }
                
            }
            
        }
        
        if let targetMeshGPUData = targetMeshGPUData {
            for (drawDataIdx, drawData) in targetMeshGPUData.drawData.enumerated() {
                
                if drawDataIdx < unanchoredPipelineStates.count {
                    renderEncoder.setRenderPipelineState(unanchoredPipelineStates[drawDataIdx + targetMeshGPUData.drawData.count])
                    renderEncoder.setDepthStencilState(unanchoredDepthState)
                    
                    // Set any buffers fed into our render pipeline
                    renderEncoder.setVertexBuffer(unanchoredUniformBuffer, offset: unanchoredUniformBufferOffset, index: Int(kBufferIndexAnchorInstanceUniforms.rawValue))
                    
                    var mutableDrawData = drawData
                    mutableDrawData.instCount = targetInstanceCount
                    
                    // Set the mesh's vertex data buffers
                    encode(meshGPUData: targetMeshGPUData, fromDrawData: mutableDrawData, with: renderEncoder, baseIndex: trackerInstanceCount)
                    
                }
                
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
        static let maxTrackerInstanceCount = 64
        static let maxTargetInstanceCount = 64
        static let alignedInstanceUniformsSize = ((MemoryLayout<AnchorInstanceUniforms>.stride * (Constants.maxTrackerInstanceCount + Constants.maxTargetInstanceCount)) & ~0xFF) + 0x100
        static let alignedEffectsUniformSize = ((MemoryLayout<AnchorEffectsUniforms>.stride * (Constants.maxTrackerInstanceCount + Constants.maxTargetInstanceCount)) & ~0xFF) + 0x100
    }
    
    private var device: MTLDevice?
    private var textureLoader: MTKTextureLoader?
    // TODO: Support per-instance models for trackers and targets
    private var trackerModel: AKModel?
    private var targetModel: AKModel?
    private var unanchoredUniformBuffer: MTLBuffer?
    private var materialUniformBuffer: MTLBuffer?
    private var effectsUniformBuffer: MTLBuffer?
    private var unanchoredPipelineStates = [MTLRenderPipelineState]() // Store multiple states
    private var unanchoredDepthState: MTLDepthStencilState?
    
    // MetalKit meshes containing vertex data and index buffer for our tracker geometry
    // TODO: Support per-instance models for trackers and targets
    private var trackerMeshGPUData: MeshGPUData?
    
    // MetalKit meshes containing vertex data and index buffer for our target geometry
    // TODO: Support per-instance models for trackers and targets
    private var targetMeshGPUData: MeshGPUData?
    
    // Offset within unanchoredUniformBuffer to set for the current frame
    private var unanchoredUniformBufferOffset: Int = 0
    
    // Offset within materialUniformBuffer to set for the current frame
    private var materialUniformBufferOffset: Int = 0
    
    // Offset within effectsUniformBuffer to set for the current frame
    private var effectsUniformBufferOffset: Int = 0
    
    // Addresses to write uniforms to each frame
    private var unanchoredUniformBufferAddress: UnsafeMutableRawPointer?
    
    // Addresses to write material uniforms to each frame
    private var materialUniformBufferAddress: UnsafeMutableRawPointer?
    
    // Addresses to write material uniforms to each frame
    private var effectsUniformBufferAddress: UnsafeMutableRawPointer?
    
    private var usesMaterials = false
    
    // number of frames in the tracker animation by index
    private var trackerAnimationFrameCount = [Int]()
    
    // number of frames in the target animation by index
    private var targetAnimationFrameCount = [Int]()
    
    private func meshData(from aModel: AKModel) -> MeshGPUData {
        
        var myGPUData = MeshGPUData()
        
        // Create Vertex Buffers
        for vtxBuffer in aModel.vertexBuffers {
            vtxBuffer.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) in
                guard let aVTXBuffer = device?.makeBuffer(bytes: bytes, length: vtxBuffer.count, options: .storageModeShared) else {
                    let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeRenderPipelineInitializationFailed, userInfo: nil)
                    let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
                    recordNewError(newError)
                    fatalError("Failed to create a buffer from the device.")
                }
                myGPUData.vtxBuffers.append(aVTXBuffer)
            }
            
        }
        
        // Create Index Buffers
        for idxBuffer in aModel.indexBuffers {
            idxBuffer.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) in
                guard let aIDXBuffer = device?.makeBuffer(bytes: bytes, length: idxBuffer.count, options: .storageModeShared) else {
                    let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeRenderPipelineInitializationFailed, userInfo: nil)
                    let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
                    recordNewError(newError)
                    fatalError("Failed to create a buffer from the device.")
                }
                myGPUData.indexBuffers.append(aIDXBuffer)
            }
        }
        
        // Create Texture Buffers
        for texturePath in aModel.texturePaths {
            myGPUData.textures.append(createMTLTexture(fromAssetPath: texturePath, withTextureLoader: textureLoader))
        }
        
        // Encode the data in the meshes as DrawData objects and store them in the MeshGPUData
        var instStartIdx = 0
        var paletteStartIdx = 0
        for (meshIdx, meshData) in aModel.meshes.enumerated() {
            
            var drawData = DrawData()
            drawData.vbCount = meshData.vbCount
            drawData.vbStartIdx = meshData.vbStartIdx
            drawData.ibStartIdx = meshData.ibStartIdx
            drawData.instCount = !aModel.instanceCount.isEmpty ? aModel.instanceCount[meshIdx] : 1
            drawData.instBufferStartIdx = instStartIdx
            if !aModel.meshSkinIndices.isEmpty,
                let paletteIndex = aModel.meshSkinIndices[instStartIdx] {
                drawData.paletteSize = aModel.skins[paletteIndex].jointPaths.count
                drawData.paletteStartIndex = paletteStartIdx
                paletteStartIdx += drawData.paletteSize * drawData.instCount
            }
            instStartIdx += drawData.instCount
            usesMaterials = (!meshData.materials.isEmpty)
            for subIndex in 0..<meshData.idxCounts.count {
                var subData = DrawSubData()
                subData.idxCount = meshData.idxCounts[subIndex]
                subData.idxType = MetalUtilities.convertToMTLIndexType(from: meshData.idxTypes[subIndex])
                subData.materialUniforms = usesMaterials ? MetalUtilities.convertToMaterialUniform(from: meshData.materials[subIndex])
                    : MaterialUniforms()
                if usesMaterials {
                    
                    guard let materialUniformBuffer = materialUniformBuffer else {
                        print("Serious Error - Material Uniform Buffer is nil")
                        let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeRenderPipelineInitializationFailed, userInfo: nil)
                        let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
                        recordNewError(newError)
                        return myGPUData
                    }
                    
                    MetalUtilities.convertMaterialBuffer(from: meshData.materials[subIndex], with: materialUniformBuffer, offset: materialUniformBufferOffset)
                    subData.materialBuffer = materialUniformBuffer
                    
                }
                subData.baseColorTextureIndex = usesMaterials ? meshData.materials[subIndex].baseColor.1 : nil
                subData.normalTextureIndex = usesMaterials ? meshData.materials[subIndex].normalMap : nil
                subData.ambientOcclusionTextureIndex = usesMaterials ? meshData.materials[subIndex].ambientOcclusionMap.1 : nil
                subData.roughnessTextureIndex = usesMaterials ? meshData.materials[subIndex].roughness.1 : nil
                subData.metallicTextureIndex = usesMaterials ? meshData.materials[subIndex].metallic.1 : nil
                subData.irradianceTextureIndex = usesMaterials ? meshData.materials[subIndex].irradianceColorMap.1 : nil
                subData.subsurfaceTextureIndex = usesMaterials ? meshData.materials[subIndex].subsurface.1 : nil
                subData.specularTextureIndex = usesMaterials ? meshData.materials[subIndex].specular.1 : nil
                subData.specularTintTextureIndex = usesMaterials ? meshData.materials[subIndex].specularTint.1 : nil
                subData.anisotropicTextureIndex = usesMaterials ? meshData.materials[subIndex].anisotropic.1 : nil
                subData.sheenTextureIndex = usesMaterials ? meshData.materials[subIndex].sheen.1 : nil
                subData.sheenTintTextureIndex = usesMaterials ? meshData.materials[subIndex].sheenTint.1 : nil
                subData.clearcoatTextureIndex = usesMaterials ? meshData.materials[subIndex].clearcoat.1 : nil
                subData.clearcoatGlossTextureIndex = usesMaterials ? meshData.materials[subIndex].clearcoatGloss.1 : nil
                drawData.subData.append(subData)
            }
            
            myGPUData.drawData.append(drawData)
            
        }
        
        return myGPUData
        
    }
    
    private func modelIndex(in model: AKModel, fromIndex index: Int) -> Int? {
        if index < model.meshNodeIndices.count, index >= 0 {
            return model.meshNodeIndices[index]
        } else {
            return nil
        }
    }
    
}
