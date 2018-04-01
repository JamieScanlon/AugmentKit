//
//  SurfacesRenderModule.swift
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
    
    // The number of surface instances to render
    private(set) var surfaceInstanceCount: Int = 0
    
    // Then indexes of the surface in the ARFrame.anchors array which contain
    // actual anchors as well as surfaces
    private(set) var surfaceIndexes = [Int]()
    
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
        
        // Create and allocate our uniform buffer objects. Indicate shared storage so that both the
        // CPU can access the buffer
        surfaceUniformBuffer = device?.makeBuffer(length: surfaceUniformBufferSize, options: .storageModeShared)
        surfaceUniformBuffer?.label = "SurfaceUniformBuffer"
        
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
        
        // TODO: Ability to load multiple surface types / models.
        modelProvider.loadModel(forObjectType: GuideSurfaceAnchor.type) { [weak self] model in

            guard let model = model else {
                print("Warning (SurfacesRenderModule) - Failed to get a model for type \(GuideSurfaceAnchor.type) from the modelProvider. Aborting the render phase.")
                completion()
                return
            }

            self?.surfaceModel = model

            completion()

        }
        
    }
    
    func loadPipeline(withMetalLibrary metalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider) {
        
        guard let device = device else {
            print("Serious Error - device not found")
            return
        }
        
        guard let surfaceModel = surfaceModel else {
            print("Serious Error - surfaceModel not found")
            return
        }
        
        if surfaceModel.meshNodeIndices.count > 1 {
            print("WARNING: More than one mesh was found. Currently only one mesh per anchor is supported.")
        }
        
        surfaceMeshGPUData = meshData(from: surfaceModel)
        
        guard let meshGPUData = surfaceMeshGPUData else {
            print("Serious Error - ERROR: No meshGPUData found when trying to load the pipeline.")
            return
        }
        
        guard let surfaceVertexDescriptor = createMetalVertexDescriptor(withFirstModelIOVertexDescriptorIn: surfaceModel.vertexDescriptors) else {
            print("Serious Error - Failed to create a MetalKit vertex descriptor from ModelIO.")
            return
        }
        
        for (drawIdx, drawData) in meshGPUData.drawData.enumerated() {
            let surfacePipelineStateDescriptor = MTLRenderPipelineDescriptor()
            do {
                let funcConstants = MetalUtilities.getFuncConstantsForDrawDataSet(meshData: surfaceModel.meshes[drawIdx], useMaterials: usesMaterials)
                let vertexName = "anchorGeometryVertexTransform"
                let fragFunc = try metalLibrary.makeFunction(name: "anchorGeometryFragmentLighting", constantValues: funcConstants)
                let vertFunc = try metalLibrary.makeFunction(name: vertexName, constantValues: funcConstants)
                surfacePipelineStateDescriptor.vertexDescriptor = surfaceVertexDescriptor
                surfacePipelineStateDescriptor.vertexFunction = vertFunc
                surfacePipelineStateDescriptor.fragmentFunction = fragFunc
                surfacePipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
                surfacePipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
                surfacePipelineStateDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
                surfacePipelineStateDescriptor.sampleCount = renderDestination.sampleCount
            } catch let error {
                print("Failed to create pipeline state descriptor, error \(error)")
            }
            
            do {
                try surfacePipelineStates.append(device.makeRenderPipelineState(descriptor: surfacePipelineStateDescriptor))
            } catch let error {
                print("Failed to create pipeline state, error \(error)")
            }
        }
        
        let surfaceDepthStateDescriptor = MTLDepthStencilDescriptor()
        surfaceDepthStateDescriptor.depthCompareFunction = .less
        surfaceDepthStateDescriptor.isDepthWriteEnabled = true
        surfaceDepthState = device.makeDepthStencilState(descriptor: surfaceDepthStateDescriptor)
        
        isInitialized = true
        
    }
    
    //
    // Per Frame Updates
    //
    
    func updateBufferState(withBufferIndex bufferIndex: Int) {
        
        surfaceUniformBufferOffset = Constants.alignedSurfaceInstanceUniformsSize * bufferIndex
        materialUniformBufferOffset = RenderModuleConstants.alignedMaterialSize * bufferIndex
        
        surfaceUniformBufferAddress = surfaceUniformBuffer?.contents().advanced(by: surfaceUniformBufferOffset)
        materialUniformBufferAddress = materialUniformBuffer?.contents().advanced(by: materialUniformBufferOffset)
        
    }
    
    func updateBuffers(withARFrame frame: ARFrame, cameraProperties: CameraProperties) {
        
        // Update the anchor uniform buffer with transforms of the current frame's anchors
        surfaceInstanceCount = 0
        surfaceIndexes = []
        var anchorInstanceCount = 0
        
        for index in 0..<frame.anchors.count {
            
            let anchor = frame.anchors[index]
            var isSurface = false
            
            if let _ = anchor as? ARPlaneAnchor {
                surfaceInstanceCount += 1
                surfaceIndexes.append(index)
                isSurface = true
            } else {
                anchorInstanceCount += 1
            }
            
            guard isSurface else {
                continue
            }
            
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
            
            // Flip Z axis to convert geometry from right handed to left handed
            var coordinateSpaceTransform = matrix_identity_float4x4
            //coordinateSpaceTransform.columns.2.z = -1.0
            
            if let model = surfaceModel {
                
                // Apply the world transform (as defined in the imported model) if applicable
                let surfaceIndex = surfaceInstanceCount - 1
                if let modelIndex = modelIndex(in: model, fromSurfaceIndex: surfaceIndex), modelIndex < model.worldTransforms.count {
                    let worldTransform = model.worldTransforms[modelIndex]
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
                
            }
            
        }
        
    }
    
    func updateBuffers(withTrackers: [AKAugmentedTracker], cameraProperties: CameraProperties) {
        // Do Nothing
    }
    
    func updateBuffers(withPaths: [UUID: [AKAugmentedAnchor]], cameraProperties: CameraProperties) {
        // Do Nothing
    }
    
    func draw(withRenderEncoder renderEncoder: MTLRenderCommandEncoder, sharedModules: [SharedRenderModule]?) {
        
        guard surfaceInstanceCount > 0 else {
            return
        }
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("Draw Surfaces")
        
        // Set render command encoder state
        renderEncoder.setCullMode(.none)
        
        guard let meshGPUData = surfaceMeshGPUData else {
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
            
            if drawDataIdx < surfacePipelineStates.count {
                renderEncoder.setRenderPipelineState(surfacePipelineStates[drawDataIdx])
                renderEncoder.setDepthStencilState(surfaceDepthState)
                
                // Set any buffers fed into our render pipeline
                renderEncoder.setVertexBuffer(surfaceUniformBuffer, offset: surfaceUniformBufferOffset, index: Int(kBufferIndexAnchorInstanceUniforms.rawValue))
                
                var mutableDrawData = drawData
                mutableDrawData.instCount = surfaceInstanceCount
                
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
        static let maxSurfaceInstanceCount = 64
        // Surfaces use the same uniform struct as anchors
        static let alignedSurfaceInstanceUniformsSize = ((MemoryLayout<AnchorInstanceUniforms>.stride * Constants.maxSurfaceInstanceCount) & ~0xFF) + 0x100
    }
    
    private var device: MTLDevice?
    private var textureLoader: MTKTextureLoader?
    private var surfaceModel: AKModel?
    private var surfaceUniformBuffer: MTLBuffer?
    private var materialUniformBuffer: MTLBuffer?
    private var surfacePipelineStates = [MTLRenderPipelineState]() // Store multiple states
    private var surfaceDepthState: MTLDepthStencilState?
    
    // MetalKit meshes containing vertex data and index buffer for our surface geometry
    private var surfaceMeshGPUData: MeshGPUData?
    
    // Offset within surfaceUniformBuffer to set for the current frame
    private var surfaceUniformBufferOffset: Int = 0
    
    // Offset within materialUniformBuffer to set for the current frame
    private var materialUniformBufferOffset: Int = 0
    
    // Addresses to write surface uniforms to each frame
    private var surfaceUniformBufferAddress: UnsafeMutableRawPointer?
    
    // Addresses to write surface uniforms to each frame
    private var materialUniformBufferAddress: UnsafeMutableRawPointer?
    
    private var usesMaterials = false
    
    // number of frames in the surface animation by surface index
    private var surfaceAnimationFrameCount = [Int]()
    
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
    
    private func modelIndex(in model: AKModel, fromSurfaceIndex surfaceIndex: Int) -> Int? {
        if surfaceIndex < model.meshNodeIndices.count, surfaceIndex >= 0 {
            return model.meshNodeIndices[surfaceIndex]
        } else {
            return nil
        }
    }
    
}
