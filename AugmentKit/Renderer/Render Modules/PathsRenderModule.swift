//
//  PathsRenderModule.swift
//  AugmentKit
//
//  Created by Jamie Scanlon on 1/28/18.
//  Copyright © 2018 TenthLetterMade. All rights reserved.
//

import Foundation
import ARKit
import AugmentKitShader
import MetalKit

class PathsRenderModule: RenderModule {
    
    static var identifier = "PathsRenderModule"
    
    //
    // Setup
    //
    
    var moduleIdentifier: String {
        return PathsRenderModule.identifier
    }
    var renderLayer: Int {
        return 10
    }
    var isInitialized: Bool = false
    var sharedModuleIdentifiers: [String]? = [SharedBuffersRenderModule.identifier]
    
    // The number of path instances to render
    private(set) var pathSegmentInstanceCount: Int = 0
    
    // The UUID's of the anchors in the ARFrame.anchors array which mark the path.
    // Indexed by path
    private(set) var anchorIdentifiers = [Int: [UUID]]()
    
    func initializeBuffers(withDevice aDevice: MTLDevice, maxInFlightBuffers: Int) {
        
        device = aDevice
        
        // Calculate our uniform buffer sizes. We allocate Constants.maxBuffersInFlight instances for uniform
        // storage in a single buffer. This allows us to update uniforms in a ring (i.e. triple
        // buffer the uniforms) so that the GPU reads from one slot in the ring wil the CPU writes
        // to another. Path uniforms should be specified with a max instance count for instancing.
        // Also uniform storage must be aligned (to 256 bytes) to meet the requirements to be an
        // argument in the constant address space of our shading functions.
        let pathUniformBufferSize = Constants.alignedPathSegmentInstanceUniformsSize * maxInFlightBuffers
        let materialUniformBufferSize = RenderModuleConstants.alignedMaterialSize * maxInFlightBuffers
        
        // Create and allocate our uniform buffer objects. Indicate shared storage so that both the
        // CPU can access the buffer
        pathUniformBuffer = device?.makeBuffer(length: pathUniformBufferSize, options: .storageModeShared)
        pathUniformBuffer?.label = "PathUniformBuffer"
        
        materialUniformBuffer = device?.makeBuffer(length: materialUniformBufferSize, options: .storageModeShared)
        materialUniformBuffer?.label = "MaterialUniformBuffer"
        
    }
    
    func loadAssets(fromModelProvider: ModelProvider?, textureLoader: MTKTextureLoader, completion: (() -> Void)) {
        
        guard let device = device else {
            print("Serious Error - device not found")
            completion()
            return
        }
        
        // Create a MetalKit mesh buffer allocator so that ModelIO will load mesh data directly into
        // Metal buffers accessible by the GPU
        let metalAllocator = MTKMeshBufferAllocator(device: device)
        
        let mesh = MDLMesh.newCylinder(withHeight: 1, radii: vector2(0.01, 0.01), radialSegments: 6, verticalSegments: 1, geometryType: .triangles, inwardNormals: false, allocator: metalAllocator)
        let asset = MDLAsset(bufferAllocator: metalAllocator)
        asset.add(mesh)
        
        let myModel = AKMDLAssetModel(asset: asset)
        pathSegmentModel = myModel
    
        completion()
        
    }
    
    func loadPipeline(withMetalLibrary metalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider) {
        
        guard let device = device else {
            print("Serious Error - device not found")
            return
        }
        
        guard let pathSegmentModel = pathSegmentModel else {
            print("Serious Error - pathSegmentModel not found")
            return
        }
        
        if pathSegmentModel.meshNodeIndices.count > 1 {
            print("WARNING: More than one mesh was found. Currently only one mesh per anchor is supported.")
        }
        
        pathMeshGPUData = meshData(from: pathSegmentModel)
        
        guard let meshGPUData = pathMeshGPUData else {
            print("Serious Error - ERROR: No meshGPUData found when trying to load the pipeline.")
            return
        }
        
        guard let pathVertexDescriptor = createMetalVertexDescriptor(withModelIOVertexDescriptor: pathSegmentModel.vertexDescriptors) else {
            print("Serious Error - Failed to create a MetalKit vertex descriptor from ModelIO.")
            return
        }
        
        for (drawIdx, drawData) in meshGPUData.drawData.enumerated() {
            let pathPipelineStateDescriptor = MTLRenderPipelineDescriptor()
            do {
                let funcConstants = MetalUtilities.getFuncConstantsForDrawDataSet(meshData: pathSegmentModel.meshes[drawIdx], useMaterials: usesMaterials)
                let vertexName = "anchorGeometryVertexTransform"
                let fragFunc = try metalLibrary.makeFunction(name: "anchorGeometryFragmentLighting", constantValues: funcConstants)
                let vertFunc = try metalLibrary.makeFunction(name: vertexName, constantValues: funcConstants)
                pathPipelineStateDescriptor.vertexDescriptor = pathVertexDescriptor
                pathPipelineStateDescriptor.vertexFunction = vertFunc
                pathPipelineStateDescriptor.fragmentFunction = fragFunc
                pathPipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
                pathPipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
                pathPipelineStateDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
                pathPipelineStateDescriptor.sampleCount = renderDestination.sampleCount
            } catch let error {
                print("Failed to create pipeline state descriptor, error \(error)")
            }
            
            do {
                try pathPipelineStates.append(device.makeRenderPipelineState(descriptor: pathPipelineStateDescriptor))
            } catch let error {
                print("Failed to create pipeline state, error \(error)")
            }
        }
        
        let pathDepthStateDescriptor = MTLDepthStencilDescriptor()
        pathDepthStateDescriptor.depthCompareFunction = .less
        pathDepthStateDescriptor.isDepthWriteEnabled = true
        pathDepthState = device.makeDepthStencilState(descriptor: pathDepthStateDescriptor)
        
        isInitialized = true
        
    }
    
    //
    // Per Frame Updates
    //
    
    func updateBufferState(withBufferIndex bufferIndex: Int) {
        
        pathUniformBufferOffset = Constants.alignedPathSegmentInstanceUniformsSize * bufferIndex
        materialUniformBufferOffset = RenderModuleConstants.alignedMaterialSize * bufferIndex
        
        pathUniformBufferAddress = pathUniformBuffer?.contents().advanced(by: pathUniformBufferOffset)
        materialUniformBufferAddress = materialUniformBuffer?.contents().advanced(by: materialUniformBufferOffset)
        
    }
    
    func updateBuffers(withARFrame frame: ARFrame, viewportProperties: ViewportProperies) {
        // Do Nothing
    }
    
    func updateBuffers(withTrackers: [AKAugmentedTracker], viewportProperties: ViewportProperies) {
        // Do Nothing
    }
    
    func updateBuffers(withPaths paths: [UUID: [AKAugmentedAnchor]], viewportProperties: ViewportProperies) {
        
        // Update the anchor uniform buffer with transforms of the current frame's anchors
        pathSegmentInstanceCount = 0
        anchorIdentifiers = [:]
        
        guard let model = pathSegmentModel else {
            return
        }
        
        for path in paths {
            
            var lastAnchor: AKAugmentedAnchor?
            var uuids = [UUID]()
            
            for anchor in path.value {
                
                guard let myLastAnchor = lastAnchor else {
                    lastAnchor = anchor
                    continue
                }
                
                pathSegmentInstanceCount += 1
                
                if pathSegmentInstanceCount > Constants.maxPathSegmentInstanceCount {
                    pathSegmentInstanceCount = Constants.maxPathSegmentInstanceCount
                    break
                }
                
                if let identifier = anchor.identifier {
                    uuids.append(identifier)
                }
                
                // Flip Z axis to convert geometry from right handed to left handed
                var coordinateSpaceTransform = matrix_identity_float4x4
                coordinateSpaceTransform.columns.2.z = -1.0
                
                // Rotate and scale coordinateSpaceTransform so that it is oriented from
                // myLastAnchor to anchor
                let finalTransform = anchor.worldLocation.transform
                let initialTransform = myLastAnchor.worldLocation.transform
                let distance = sqrtf(
                    (finalTransform.columns.3.x - initialTransform.columns.3.x) * (finalTransform.columns.3.x - initialTransform.columns.3.x) +
                    (finalTransform.columns.3.y - initialTransform.columns.3.y) * (finalTransform.columns.3.y - initialTransform.columns.3.y) +
                    (finalTransform.columns.3.z - initialTransform.columns.3.z) * (finalTransform.columns.3.z - initialTransform.columns.3.z)
                )
                coordinateSpaceTransform = coordinateSpaceTransform.scale(x: 1, y: distance, z: 1)

                let rotX = dot(float4(finalTransform.columns.3.x,0,0,0), initialTransform.columns.3) - Float.pi
                coordinateSpaceTransform = coordinateSpaceTransform.rotate(radians: rotX, x: 1, y: 0, z: 0)

                let rotY = dot(float4(0,finalTransform.columns.3.y,0,0), initialTransform.columns.3) - Float.pi
                coordinateSpaceTransform = coordinateSpaceTransform.rotate(radians: rotY, x: 0, y: 1, z: 0)

                let rotZ = dot(float4(0,0,finalTransform.columns.3.z,0), initialTransform.columns.3) - Float.pi
                coordinateSpaceTransform = coordinateSpaceTransform.rotate(radians: rotZ, x: 0, y: 0, z: 1)
                
                // Apply the world transform (as defined in the imported model) if applicable
                let pathSegmentIndex = pathSegmentInstanceCount - 1
                if let modelIndex = modelIndex(in: model, fromPathSegmentIndex: pathSegmentIndex), modelIndex < model.worldTransforms.count {
                    let worldTransform = model.worldTransforms[modelIndex]
                    coordinateSpaceTransform = simd_mul(coordinateSpaceTransform, worldTransform)
                }
                
                // Create the final transform matrix
                let modelMatrix = anchor.worldLocation.transform * coordinateSpaceTransform
                
                // Paths use the same uniform struct as anchors
                let pathUniforms = pathUniformBufferAddress?.assumingMemoryBound(to: AnchorInstanceUniforms.self).advanced(by: pathSegmentIndex)
                pathUniforms?.pointee.modelMatrix = modelMatrix
                
            }
            
            if pathSegmentInstanceCount > 0 && pathSegmentInstanceCount < Constants.maxPathSegmentInstanceCount {
                anchorIdentifiers[pathSegmentInstanceCount - 1] = uuids
            }
            
        }
        
    }
    
    func draw(withRenderEncoder renderEncoder: MTLRenderCommandEncoder, sharedModules: [SharedRenderModule]?) {
        
        guard pathSegmentInstanceCount > 0 else {
            return
        }
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("Draw Paths")
        
        // Set render command encoder state
        renderEncoder.setCullMode(.back)
        
        guard let meshGPUData = pathMeshGPUData else {
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
            
            if drawDataIdx < pathPipelineStates.count {
                renderEncoder.setRenderPipelineState(pathPipelineStates[drawDataIdx])
                renderEncoder.setDepthStencilState(pathDepthState)
                
                // Set any buffers fed into our render pipeline
                renderEncoder.setVertexBuffer(pathUniformBuffer, offset: pathUniformBufferOffset, index: Int(kBufferIndexAnchorInstanceUniforms.rawValue))
                
                var mutableDrawData = drawData
                mutableDrawData.instCount = pathSegmentInstanceCount
                
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
    
    private var device: MTLDevice?
    private var textureLoader: MTKTextureLoader?
    private var pathSegmentModel: AKModel?
    private var pathUniformBuffer: MTLBuffer?
    private var materialUniformBuffer: MTLBuffer?
    private var pathPipelineStates = [MTLRenderPipelineState]() // Store multiple states
    private var pathDepthState: MTLDepthStencilState?
    
    // MetalKit meshes containing vertex data and index buffer for our geometry
    private var pathMeshGPUData: MeshGPUData?
    
    // Offset within pathUniformBuffer to set for the current frame
    private var pathUniformBufferOffset: Int = 0
    
    // Offset within materialUniformBuffer to set for the current frame
    private var materialUniformBufferOffset: Int = 0
    
    // Addresses to write path uniforms to each frame
    private var pathUniformBufferAddress: UnsafeMutableRawPointer?
    
    // Addresses to write material uniforms to each frame
    private var materialUniformBufferAddress: UnsafeMutableRawPointer?
    
    private enum Constants {
        static let maxPathSegmentInstanceCount = 2048
        // Paths use the same uniform struct as anchors
        static let alignedPathSegmentInstanceUniformsSize = ((MemoryLayout<AnchorInstanceUniforms>.stride * Constants.maxPathSegmentInstanceCount) & ~0xFF) + 0x100
    }
    
    private var usesMaterials = false
    
    // number of frames in the path animation by path index
    private var pathAnimationFrameCount = [Int]()
    
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
                subData.baseColorTexIdx = usesMaterials ? meshData.materials[subIndex].baseColor.1 : nil
                subData.normalTexIdx = usesMaterials ? meshData.materials[subIndex].normalMap : nil
                subData.aoTexIdx = usesMaterials ? meshData.materials[subIndex].ambientOcclusionMap : nil
                subData.roughTexIdx = usesMaterials ? meshData.materials[subIndex].roughness.1 : nil
                subData.metalTexIdx = usesMaterials ? meshData.materials[subIndex].metallic.1 : nil
                drawData.subData.append(subData)
            }
            
            myGPUData.drawData.append(drawData)
            
        }
        
        return myGPUData
        
    }
    
    private func modelIndex(in model: AKModel, fromPathSegmentIndex pathIndex: Int) -> Int? {
        if pathIndex < model.meshNodeIndices.count, pathIndex >= 0 {
            return model.meshNodeIndices[pathIndex]
        } else {
            return nil
        }
    }
    
    
}
