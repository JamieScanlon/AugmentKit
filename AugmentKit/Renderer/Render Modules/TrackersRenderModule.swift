//
//  TrackersRenderModule.swift
//  AugmentKit
//
//  MIT License
//
//  Copyright (c) 2017 JamieScanlon
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

class TrackersRenderModule: RenderModule {
    
    static var identifier = "TrackersRenderModule"
    
    //
    // Setup
    //
    
    var moduleIdentifier: String {
        return TrackersRenderModule.identifier
    }
    var renderLayer: Int {
        return 12
    }
    var isInitialized: Bool = false
    var sharedModuleIdentifiers: [String]? = [SharedBuffersRenderModule.identifier]
    var renderDistance: Double = 500
    
    // The number of tracker instances to render
    private(set) var trackerInstanceCount: Int = 0
    
    func initializeBuffers(withDevice aDevice: MTLDevice, maxInFlightBuffers: Int) {
        
        device = aDevice
        
        // Calculate our uniform buffer sizes. We allocate Constants.maxBuffersInFlight instances for uniform
        // storage in a single buffer. This allows us to update uniforms in a ring (i.e. triple
        // buffer the uniforms) so that the GPU reads from one slot in the ring wil the CPU writes
        // to another. Tracker uniforms should be specified with a max instance count for instancing.
        // Also uniform storage must be aligned (to 256 bytes) to meet the requirements to be an
        // argument in the constant address space of our shading functions.
        let trackerUniformBufferSize = Constants.alignedTrackerInstanceUniformsSize * maxInFlightBuffers
        let materialUniformBufferSize = RenderModuleConstants.alignedMaterialSize * maxInFlightBuffers
        
        // Create and allocate our uniform buffer objects. Indicate shared storage so that both the
        // CPU can access the buffer
        trackerUniformBuffer = device?.makeBuffer(length: trackerUniformBufferSize, options: .storageModeShared)
        trackerUniformBuffer?.label = "TrackerUniformBuffer"
        
        materialUniformBuffer = device?.makeBuffer(length: materialUniformBufferSize, options: .storageModeShared)
        materialUniformBuffer?.label = "MaterialUniformBuffer"
        
    }
    
    func loadAssets(fromModelProvider modelProvider: ModelProvider?, textureLoader aTextureLoader: MTKTextureLoader, completion: (() -> Void)) {
        
        guard let modelProvider = modelProvider else {
            print("Serious Error - Model Provider not found.")
            completion()
            return
        }
        
        textureLoader = aTextureLoader
        
        //
        // Create and load our models
        //
        
        modelProvider.loadModel(forObjectType: AKUserTracker.type) { [weak self] model in
            
            guard let model = model else {
                print("Warning (TrackersRenderModule) - Failed to get a model for type \(AKObject.type) from the modelProvider. Aborting the render phase.")
                completion()
                return
            }
            
            self?.trackerModel = model
            
            // TODO: Figure out a way to load a new model per tracker.
            
            completion()
            
        }
        
    }
    
    func loadPipeline(withMetalLibrary metalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider) {
        
        guard let device = device else {
            print("Serious Error - device not found")
            return
        }
        
        guard let trackerModel = trackerModel else {
            print("Serious Error - trackerModel not found")
            return
        }
        
        if trackerModel.meshNodeIndices.count > 1 {
            print("WARNING: More than one mesh was found. Currently only one mesh per tracker is supported.")
        }
        
        trackerMeshGPUData = meshData(from: trackerModel)
        
        guard let meshGPUData = trackerMeshGPUData else {
            print("Serious Error - ERROR: No meshGPUData found when trying to load the pipeline.")
            return
        }
        
        guard let trackerVertexDescriptor = createMetalVertexDescriptor(withModelIOVertexDescriptor: trackerModel.vertexDescriptors) else {
            print("Serious Error - Failed to create a MetalKit vertex descriptor from ModelIO.")
            return
        }
        
        for (drawIdx, drawData) in meshGPUData.drawData.enumerated() {
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
                trackerPipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
                trackerPipelineStateDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
                trackerPipelineStateDescriptor.sampleCount = renderDestination.sampleCount
            } catch let error {
                print("Failed to create pipeline state descriptor, error \(error)")
            }
            
            do {
                try trackerPipelineStates.append(device.makeRenderPipelineState(descriptor: trackerPipelineStateDescriptor))
            } catch let error {
                print("Failed to create pipeline state, error \(error)")
            }
        }
        
        let trackerDepthStateDescriptor = MTLDepthStencilDescriptor()
        trackerDepthStateDescriptor.depthCompareFunction = .less
        trackerDepthStateDescriptor.isDepthWriteEnabled = true
        trackerDepthState = device.makeDepthStencilState(descriptor: trackerDepthStateDescriptor)
        
        isInitialized = true
        
    }
    
    //
    // Per Frame Updates
    //
    
    func updateBufferState(withBufferIndex bufferIndex: Int) {
        
        trackerUniformBufferOffset = Constants.alignedTrackerInstanceUniformsSize * bufferIndex
        materialUniformBufferOffset = RenderModuleConstants.alignedMaterialSize * bufferIndex
        
        trackerUniformBufferAddress = trackerUniformBuffer?.contents().advanced(by: trackerUniformBufferOffset)
        materialUniformBufferAddress = materialUniformBuffer?.contents().advanced(by: materialUniformBufferOffset)
        
    }
    
    func updateBuffers(withARFrame frame: ARFrame, cameraProperties: CameraProperties) {
        // Do Nothing
    }
    
    func updateBuffers(withTrackers trackers: [AKAugmentedTracker], cameraProperties: CameraProperties) {
        
        // Update the tracker uniform buffer with transforms of the current frame's trackers
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
            
            if let model = trackerModel {
                
                // Apply the world transform (as defined in the imported model) if applicable
                let trackerIndex = trackerInstanceCount - 1
                if let modelIndex = modelIndex(in: model, fromTrackerIndex: trackerIndex), modelIndex < model.worldTransforms.count {
                    let worldTransform = model.worldTransforms[modelIndex]
                    coordinateSpaceTransform = simd_mul(coordinateSpaceTransform, worldTransform)
                }
                
                let modelMatrix = trackerAbsoluteTransform * coordinateSpaceTransform
                
                let trackerUniforms = trackerUniformBufferAddress?.assumingMemoryBound(to: AnchorInstanceUniforms.self).advanced(by: trackerIndex)
                trackerUniforms?.pointee.modelMatrix = modelMatrix
                
            }
            
        }
        
    }
    
    func updateBuffers(withPaths: [UUID: [AKAugmentedAnchor]], cameraProperties: CameraProperties) {
        // Do Nothing
    }
    
    func draw(withRenderEncoder renderEncoder: MTLRenderCommandEncoder, sharedModules: [SharedRenderModule]?) {
        
        guard trackerInstanceCount > 0 else {
            return
        }
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("Draw Trackers")
        
        // Set render command encoder state
        renderEncoder.setCullMode(.back)
        
        guard let meshGPUData = trackerMeshGPUData else {
            print("Error: meshGPUData not available a draw time. Aborting")
            return
        }
        
        if let sharedBuffer = sharedModules?.filter({$0.moduleIdentifier == SharedBuffersRenderModule.identifier}).first {
            
            renderEncoder.pushDebugGroup("Draw Shared Uniforms")
            
            renderEncoder.setVertexBuffer(sharedBuffer.sharedUniformBuffer, offset: sharedBuffer.sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
            renderEncoder.setFragmentBuffer(sharedBuffer.sharedUniformBuffer, offset: sharedBuffer.sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
            
            renderEncoder.popDebugGroup()
            
        }
        
        for (drawDataIdx, drawData) in meshGPUData.drawData.enumerated() {
            
            if drawDataIdx < trackerPipelineStates.count {
                renderEncoder.setRenderPipelineState(trackerPipelineStates[drawDataIdx])
                renderEncoder.setDepthStencilState(trackerDepthState)
                
                // Set any buffers fed into our render pipeline
                renderEncoder.setVertexBuffer(trackerUniformBuffer, offset: trackerUniformBufferOffset, index: Int(kBufferIndexAnchorInstanceUniforms.rawValue))
                
                var mutableDrawData = drawData
                mutableDrawData.instCount = trackerInstanceCount
                
                // Set the mesh's vertex data buffers
                encode(meshGPUData: meshGPUData, fromDrawData: mutableDrawData, with: renderEncoder)
                
            }
            
        }
        
        renderEncoder.popDebugGroup()
        
    }
    
    func frameEncodingComplete() {
        //
    }
    
    // MARK: - Private
    
    private enum Constants {
        static let maxTrackerInstanceCount = 64
        static let alignedTrackerInstanceUniformsSize = ((MemoryLayout<AnchorInstanceUniforms>.stride * Constants.maxTrackerInstanceCount) & ~0xFF) + 0x100
    }
    
    private var device: MTLDevice?
    private var textureLoader: MTKTextureLoader?
    private var trackerModel: AKModel?
    private var trackerUniformBuffer: MTLBuffer?
    private var materialUniformBuffer: MTLBuffer?
    private var trackerPipelineStates = [MTLRenderPipelineState]() // Store multiple states
    private var trackerDepthState: MTLDepthStencilState?
    
    // MetalKit meshes containing vertex data and index buffer for our tracker geometry
    private var trackerMeshGPUData: MeshGPUData?
    
    // Offset within trackerUniformBuffer to set for the current frame
    private var trackerUniformBufferOffset: Int = 0
    
    // Offset within materialUniformBuffer to set for the current frame
    private var materialUniformBufferOffset: Int = 0
    
    // Addresses to write tracker uniforms to each frame
    private var trackerUniformBufferAddress: UnsafeMutableRawPointer?
    
    // Addresses to write tracker uniforms to each frame
    private var materialUniformBufferAddress: UnsafeMutableRawPointer?
    
    private var usesMaterials = false
    
    // number of frames in the tracker animation by tracker index
    private var trackerAnimationFrameCount = [Int]()
    
    private func meshData(from aModel: AKModel) -> MeshGPUData {
        
        var myGPUData = MeshGPUData()
        
        // Create Vertex Buffers
        for vtxBuffer in aModel.vertexBuffers {
            vtxBuffer.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) in
                guard let aVTXBuffer = device?.makeBuffer(bytes: bytes, length: vtxBuffer.count, options: .storageModeShared) else {
                    fatalError("Failed to create a buffer from the device.")
                }
                myGPUData.vtxBuffers.append(aVTXBuffer)
            }
            
        }
        
        // Create Index Buffers
        for idxBuffer in aModel.indexBuffers {
            idxBuffer.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) in
                guard let aIDXBuffer = device?.makeBuffer(bytes: bytes, length: idxBuffer.count, options: .storageModeShared) else {
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
                        return myGPUData
                    }
                    
                    MetalUtilities.convertMaterialBuffer(from: meshData.materials[subIndex], with: materialUniformBuffer, offset: materialUniformBufferOffset)
                    subData.materialBuffer = materialUniformBuffer
                    
                }
                subData.baseColorTextureIndex = usesMaterials ? meshData.materials[subIndex].baseColor.1 : nil
                subData.normalTextureIndex = usesMaterials ? meshData.materials[subIndex].normalMap : nil
                subData.ambientOcclusionTextureIndex = usesMaterials ? meshData.materials[subIndex].ambientOcclusionMap : nil
                subData.roughnessTextureIndex = usesMaterials ? meshData.materials[subIndex].roughness.1 : nil
                subData.metallicTextureIndex = usesMaterials ? meshData.materials[subIndex].metallic.1 : nil
                subData.irradianceTextureIndex = usesMaterials ? meshData.materials[subIndex].irradianceColorMap.1 : nil
                drawData.subData.append(subData)
            }
            
            myGPUData.drawData.append(drawData)
            
        }
        
        return myGPUData
        
    }
    
    private func modelIndex(in model: AKModel, fromTrackerIndex trackerIndex: Int) -> Int? {
        if trackerIndex < model.meshNodeIndices.count, trackerIndex >= 0 {
            return model.meshNodeIndices[trackerIndex]
        } else {
            return nil
        }
    }
    
}
