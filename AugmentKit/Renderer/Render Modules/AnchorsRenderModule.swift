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

// TODO: Support having different models for each AKAugmentedAnchor type
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
    
    // Then indexes of the anchors in the ARFrame.anchors array which contain
    // actual anchors as well as plane anchors
    private(set) var anchorIndexes = [Int]()
    
    func initializeBuffers(withDevice aDevice: MTLDevice, maxInFlightBuffers: Int) {
        
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
        
    }
    
    func loadAssets(fromModelProvider modelProvider: ModelProvider?, textureLoader aTextureLoader: MTKTextureLoader, completion: (() -> Void)) {
        
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
        modelProvider.loadModel(forObjectType:  "AnyAnchor", identifier: nil) { [weak self] model in
            
            guard let model = model else {
                print("Warning (AnchorsRenderModule) - Failed to get a model for type  \"AnyAnchor\") from the modelProvider. Aborting the render phase.")
                let newError = AKError.warning(.modelError(.modelNotFound(ModelErrorInfo(type:  "AnyAnchor"))))
                recordNewError(newError)
                completion()
                return
            }
            
            self?.anchorModel = model
            
            // TODO: Figure out a way to load a new model per anchor.
            
            completion()
            
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
        
        guard let anchorModel = anchorModel else {
            print("Warning (AnchorsRenderModule) - Anchor Model was not found. Aborting the render phase.")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeModelNotFound, userInfo: nil)
            let newError = AKError.warning(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return
        }
        
        if anchorModel.meshNodeIndices.count > 1 {
            print("WARNING: More than one mesh was found. Currently only one mesh per anchor is supported.")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeModelNotSupported, userInfo: nil)
            let newError = AKError.warning(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
        }
        
        anchorMeshGPUData = meshData(from: anchorModel)
        
        guard let meshGPUData = anchorMeshGPUData else {
            print("Serious Error - ERROR: No meshGPUData found when trying to load the pipeline.")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeIntermediateMeshDataNotFound, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return
        }
        
        guard let anchorVertexDescriptor = createMetalVertexDescriptor(withFirstModelIOVertexDescriptorIn: anchorModel.vertexDescriptors) else {
            print("Serious Error - Failed to create a MetalKit vertex descriptor from ModelIO.")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeInvalidMeshData, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return
        }
        
        for (drawIdx, drawData) in meshGPUData.drawData.enumerated() {
            let anchorPipelineStateDescriptor = MTLRenderPipelineDescriptor()
            do {
                let funcConstants = MetalUtilities.getFuncConstantsForDrawDataSet(meshData: anchorModel.meshes[drawIdx], useMaterials: usesMaterials)
                // Specify which shader to use based on if the model has skinned puppet suppot
                let vertexName = (drawData.paletteStartIndex != nil) ? "anchorGeometryVertexTransformSkinned" : "anchorGeometryVertexTransform"
                let fragFunc = try metalLibrary.makeFunction(name: "anchorGeometryFragmentLighting", constantValues: funcConstants)
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
            
            do {
                try anchorPipelineStates.append(device.makeRenderPipelineState(descriptor: anchorPipelineStateDescriptor))
            } catch let error {
                print("Failed to create pipeline state, error \(error)")
                let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: error))))
                recordNewError(newError)
            }
        }
        
        let anchorDepthStateDescriptor = MTLDepthStencilDescriptor()
        anchorDepthStateDescriptor.depthCompareFunction = .less
        anchorDepthStateDescriptor.isDepthWriteEnabled = true
        anchorDepthState = device.makeDepthStencilState(descriptor: anchorDepthStateDescriptor)
        
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
        
        anchorUniformBufferAddress = anchorUniformBuffer?.contents().advanced(by: anchorUniformBufferOffset)
        materialUniformBufferAddress = materialUniformBuffer?.contents().advanced(by: materialUniformBufferOffset)
        paletteBufferAddress = paletteBuffer?.contents().advanced(by: paletteBufferOffset)
        effectsUniformBufferAddress = effectsUniformBuffer?.contents().advanced(by: effectsUniformBufferOffset)
        
    }
    
    func updateBuffers(withARFrame frame: ARFrame, cameraProperties: CameraProperties) {
        
        // Update the anchor uniform buffer with transforms of the current frame's anchors
        anchorInstanceCount = 0
        anchorIndexes = []
        var horizPlaneInstanceCount = 0
        var vertPlaneInstanceCount = 0
        
        for index in 0..<frame.anchors.count {
            
            //
            // Update the Anchor uniform
            //
            
            let anchor = frame.anchors[index]
            var isAnchor = false
            
            if let plane = anchor as? ARPlaneAnchor {
                if plane.alignment == .horizontal {
                    horizPlaneInstanceCount += 1
                } else {
                    vertPlaneInstanceCount += 1
                }
            } else {
                anchorInstanceCount += 1
                anchorIndexes.append(index)
                isAnchor = true
            }
            
            guard isAnchor else {
                continue
            }
            
            // Ignore anchors that are beyond the renderDistance
            let distance = anchorDistance(withTransform: anchor.transform, cameraProperties: cameraProperties)
            guard Double(distance) < renderDistance else {
                continue
            }
            
            guard anchorInstanceCount > 0 else {
                continue
            }
            
            if anchorInstanceCount > Constants.maxAnchorInstanceCount {
                anchorInstanceCount = Constants.maxAnchorInstanceCount
                break
            }
            
            // Flip Z axis to convert geometry from right handed to left handed
            var coordinateSpaceTransform = matrix_identity_float4x4
            coordinateSpaceTransform.columns.2.z = -1.0
            
            let anchorIndex = anchorInstanceCount - 1
            
            if let model = anchorModel {
                
                // Apply the world transform (as defined in the imported model) if applicable
                if let modelIndex = modelIndex(in: model, fromAnchorIndex: anchorIndex), modelIndex < model.worldTransforms.count {
                    let worldTransform = model.worldTransforms[modelIndex]
                    coordinateSpaceTransform = simd_mul(coordinateSpaceTransform, worldTransform)
                }
                
                let modelMatrix = anchor.transform * coordinateSpaceTransform
                let anchorUniforms = anchorUniformBufferAddress?.assumingMemoryBound(to: AnchorInstanceUniforms.self).advanced(by: anchorIndex)
                anchorUniforms?.pointee.modelMatrix = modelMatrix
                
            }
            
            //
            // Update the Effects uniform
            //
            
            let effectsUniforms = effectsUniformBufferAddress?.assumingMemoryBound(to: AnchorEffectsUniforms.self).advanced(by: anchorIndex)
            effectsUniforms?.pointee.alpha = 1 // TODO: Implement
            effectsUniforms?.pointee.glow = 0 // TODO: Implement
            effectsUniforms?.pointee.tint = float3(0,0,0) // TODO: Implement
            
        }
        
        if let model = anchorModel {
            updatePuppetAnimation(from: model, frameNumber: cameraProperties.currentFrame)
        }
        
    }
    
    func updateBuffers(withTrackers: [AKAugmentedTracker], targets: [AKTarget], cameraProperties: CameraProperties) {
        // Do Nothing
    }
    
    func updateBuffers(withPaths: [UUID: [AKAugmentedAnchor]], cameraProperties: CameraProperties) {
        // Do Nothing
    }
    
    func draw(withRenderEncoder renderEncoder: MTLRenderCommandEncoder, sharedModules: [SharedRenderModule]?) {
        
        guard anchorInstanceCount > 0 else {
            return
        }
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("Draw Anchors")
        
        // Set render command encoder state
        renderEncoder.setCullMode(.back)
        
        guard let meshGPUData = anchorMeshGPUData else {
            print("Error: meshGPUData not available a draw time. Aborting")
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
        
        for (drawDataIdx, drawData) in meshGPUData.drawData.enumerated() {
            
            if drawDataIdx < anchorPipelineStates.count {
                renderEncoder.setRenderPipelineState(anchorPipelineStates[drawDataIdx])
                renderEncoder.setDepthStencilState(anchorDepthState)
                
                // Set any buffers fed into our render pipeline
                renderEncoder.setVertexBuffer(anchorUniformBuffer, offset: anchorUniformBufferOffset, index: Int(kBufferIndexAnchorInstanceUniforms.rawValue))
                renderEncoder.setVertexBuffer(paletteBuffer, offset: paletteBufferOffset, index: Int(kBufferIndexMeshPalettes.rawValue))
                
                var mutableDrawData = drawData
                mutableDrawData.instCount = anchorInstanceCount
                
                // Set the mesh's vertex data buffers
                encode(meshGPUData: meshGPUData, fromDrawData: mutableDrawData, with: renderEncoder)
                
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
        static let maxAnchorInstanceCount = 64
        static let maxPaletteSize = 100
        static let alignedAnchorInstanceUniformsSize = ((MemoryLayout<AnchorInstanceUniforms>.stride * Constants.maxAnchorInstanceCount) & ~0xFF) + 0x100
        static let alignedPaletteSize = (MemoryLayout<matrix_float4x4>.stride & ~0xFF) + 0x100
        static let alignedEffectsUniformSize = ((MemoryLayout<AnchorEffectsUniforms>.stride * Constants.maxAnchorInstanceCount) & ~0xFF) + 0x100
    }
    
    private var device: MTLDevice?
    private var textureLoader: MTKTextureLoader?
    private var anchorModel: AKModel?
    private var anchorUniformBuffer: MTLBuffer?
    private var materialUniformBuffer: MTLBuffer?
    private var paletteBuffer: MTLBuffer?
    private var effectsUniformBuffer: MTLBuffer?
    private var anchorPipelineStates = [MTLRenderPipelineState]() // Store multiple states
    private var anchorDepthState: MTLDepthStencilState?
    
    // MetalKit meshes containing vertex data and index buffer for our anchor geometry
    private var anchorMeshGPUData: MeshGPUData?
    
    // Offset within anchorUniformBuffer to set for the current frame
    private var anchorUniformBufferOffset: Int = 0
    
    // Offset within materialUniformBuffer to set for the current frame
    private var materialUniformBufferOffset: Int = 0
    
    // Offset within paletteBuffer to set for the current frame
    private var paletteBufferOffset = 0
    
    // Offset within effectsUniformBuffer to set for the current frame
    private var effectsUniformBufferOffset: Int = 0
    
    // Addresses to write anchor uniforms to each frame
    private var anchorUniformBufferAddress: UnsafeMutableRawPointer?
    
    // Addresses to write anchor uniforms to each frame
    private var materialUniformBufferAddress: UnsafeMutableRawPointer?
    
    // Addresses to write palette to each frame
    private var paletteBufferAddress: UnsafeMutableRawPointer?
    
    // Addresses to write material uniforms to each frame
    private var effectsUniformBufferAddress: UnsafeMutableRawPointer?
    
    private var usesMaterials = false
    
    // number of frames in the anchor animation by anchor index
    private var anchorAnimationFrameCount = [Int]()
    
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
    
    private func modelIndex(in model: AKModel, fromAnchorIndex anchorIndex: Int) -> Int? {
        if anchorIndex < model.meshNodeIndices.count, anchorIndex >= 0 {
            return model.meshNodeIndices[anchorIndex]
        } else {
            return nil
        }
    }
    
    private func updatePuppetAnimation(from aModel: AKModel, frameNumber: Int) {
        
        let capacity = Constants.alignedPaletteSize * Constants.maxPaletteSize
        
        let boundPaletteData = paletteBufferAddress?.bindMemory(to: matrix_float4x4.self, capacity: capacity)
        
        let paletteData = UnsafeMutableBufferPointer<matrix_float4x4>(start: boundPaletteData, count: Constants.maxPaletteSize)
        
        var jointPaletteOffset = 0
        for skin in aModel.skins {
            if let animationIndex = skin.animationIndex {
                let curAnimation = aModel.skeletonAnimations[animationIndex]
                let worldPose = evaluateAnimation(curAnimation, at: (Double(frameNumber) * 1.0 / 60.0))
                let matrixPalette = evaluateMatrixPalette(worldPose, skin)
                
                for k in 0..<matrixPalette.count {
                    paletteData[k + jointPaletteOffset] = matrixPalette[k]
                }
                
                jointPaletteOffset += matrixPalette.count
            }
        }
    }
    
}
