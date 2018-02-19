//
//  RenderModule.swift
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
import Metal
import MetalKit

protocol RenderModule {
    
    //
    // Setup
    //
    
    var moduleIdentifier: String { get }
    var isInitialized: Bool { get }
    // Lower layer modules are rendered first
    var renderLayer: Int { get }
    // An array of shared module identifiers that it this module will rely on in the draw phase.
    var sharedModuleIdentifiers: [String]? { get }
    
    // Initialize the buffers that will me managed and updated in this module.
    func initializeBuffers(withDevice: MTLDevice, maxInFlightBuffers: Int)
    
    // Load the data from the Model Provider.
    func loadAssets(fromModelProvider: ModelProvider?, textureLoader: MTKTextureLoader, completion: (() -> Void))
    
    // This funciton should set up the vertex descriptors, pipeline / depth state descriptors,
    // textures, etc.
    func loadPipeline(withMetalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider)
    
    //
    // Per Frame Updates
    //
    
    // The buffer index is the index into the ring on in flight buffers
    func updateBufferState(withBufferIndex: Int)
    
    // Update the buffer data for anchors
    func updateBuffers(withARFrame: ARFrame, viewportProperties: ViewportProperies)
    
    // Update the buffer data for trackers
    func updateBuffers(withTrackers: [AKAugmentedTracker], viewportProperties: ViewportProperies)
    
    // Update the buffer data for trackers
    func updateBuffers(withPaths: [UUID: [AKAugmentedAnchor]], viewportProperties: ViewportProperies)
    
    // Update the render encoder for the draw call. At the end of this method it is expected that
    // drawPrimatives or drawIndexedPrimatives is called.
    func draw(withRenderEncoder: MTLRenderCommandEncoder, sharedModules: [SharedRenderModule]?)
    
    // Called when Metal and the GPU has fully finished proccssing the commands we're encoding
    // this frame. This indicates when the dynamic buffers, that we're writing to this frame,
    // will no longer be needed by Metal and the GPU. This gets called per frame.
    func frameEncodingComplete()
    
}

extension RenderModule {
    
    func encode(meshGPUData: MeshGPUData, fromDrawData drawData: DrawData, with renderEncoder: MTLRenderCommandEncoder) {
        
        // Set mesh's vertex buffers
        for vtxBufferIdx in 0..<drawData.vbCount {
            renderEncoder.setVertexBuffer(meshGPUData.vtxBuffers[drawData.vbStartIdx + vtxBufferIdx], offset: 0, index: vtxBufferIdx)
        }
        
        // Draw each submesh of our mesh
        for drawDataSubIndex in 0..<drawData.subData.count {
            
            let submeshData = drawData.subData[drawDataSubIndex]
            
            // Sets the weight of values sampled from a texture vs value from a material uniform
            // for a transition between quality levels
            //            submeshData.computeTextureWeights(for: currentQualityLevel, with: globalMapWeight)
            
            let idxCount = Int(submeshData.idxCount)
            let idxType = submeshData.idxType
            let ibOffset = drawData.ibStartIdx
            let indexBuffer = meshGPUData.indexBuffers[ibOffset + drawDataSubIndex]
            var materialUniforms = submeshData.materialUniforms
            
            // Set textures based off material flags
            encodeTextures(with: meshGPUData, renderEncoder: renderEncoder, subData: submeshData)
            
            renderEncoder.setFragmentBytes(&materialUniforms, length: RenderModuleConstants.alignedMaterialSize, index: Int(kBufferIndexMaterialUniforms.rawValue))
            
            renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: idxCount, indexType: idxType, indexBuffer: indexBuffer, indexBufferOffset: 0, instanceCount: drawData.instCount)
        }
        
    }
    
    func encodeTextures(with meshData: MeshGPUData, renderEncoder: MTLRenderCommandEncoder, subData drawSubData: DrawSubData) {
        if let baseColorTextureIndex = drawSubData.baseColorTextureIndex {
            renderEncoder.setFragmentTexture(meshData.textures[baseColorTextureIndex], index: Int(kTextureIndexColor.rawValue))
        }
        
        if let ambientOcclusionTextureIndex = drawSubData.ambientOcclusionTextureIndex {
            renderEncoder.setFragmentTexture(meshData.textures[ambientOcclusionTextureIndex], index: Int(kTextureIndexAmbientOcclusion.rawValue))
        }
        
        if let irradianceTextureIndex = drawSubData.irradianceTextureIndex {
            renderEncoder.setFragmentTexture(meshData.textures[irradianceTextureIndex], index: Int(kTextureIndexIrradianceMap.rawValue))
        }
        
        if let normalTextureIndex = drawSubData.normalTextureIndex {
            renderEncoder.setFragmentTexture(meshData.textures[normalTextureIndex], index: Int(kTextureIndexNormal.rawValue))
        }
        
        if let roughnessTextureIndex = drawSubData.roughnessTextureIndex {
            renderEncoder.setFragmentTexture(meshData.textures[roughnessTextureIndex], index: Int(kTextureIndexRoughness.rawValue))
        }
        
        if let metallicTextureIndex = drawSubData.metallicTextureIndex {
            renderEncoder.setFragmentTexture(meshData.textures[metallicTextureIndex], index: Int(kTextureIndexMetallic.rawValue))
        }
        
    }
    
    func createMTLTexture(fromAssetPath assetPath: String, withTextureLoader textureLoader: MTKTextureLoader?) -> MTLTexture? {
        do {
            
            let textureURL: URL? = {
                guard let aURL = URL(string: assetPath) else {
                    return nil
                }
                if aURL.scheme == nil {
                    // If there is no scheme, assume it's a file in the bundle.
                    let last = aURL.lastPathComponent
                    if let bundleURL = Bundle.main.url(forResource: last, withExtension: nil) {
                        return bundleURL
                    } else {
                        return aURL
                    }
                } else {
                    return aURL
                }
            }()
            
            guard let aURL = textureURL else {
                return nil
            }
            
            return try textureLoader?.newTexture(URL: aURL, options: nil)
            
        } catch {
            print("Unable to loader texture with assetPath \(assetPath) with error \(error)")
        }
        
        return nil
    }
    
    func createMetalVertexDescriptor(withModelIOVertexDescriptor vtxDesc: [MDLVertexDescriptor]) -> MTLVertexDescriptor? {
        guard !vtxDesc.isEmpty else {
            print("WARNING: No Vertex Descriptors found!")
            return nil
        }
        guard let mtlVertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vtxDesc[0]) else {
            return nil
        }
        return mtlVertexDescriptor
    }
    
}

enum RenderModuleConstants {
    static let alignedMaterialSize = (MemoryLayout<MaterialUniforms>.stride & ~0xFF) + 0x100
}

// A shared render module is a render module responsible for setting up and updating
// shared buffers. Although it does have a draw() method, typically this method does
// not do anything. Instead, the module that uses this shared module is responsible
// for encoding the shared buffer and issuing the draw call
protocol SharedRenderModule: RenderModule {
    var sharedUniformBuffer: MTLBuffer? { get }
    var sharedUniformBufferOffset: Int { get }
    var sharedUniformBufferAddress: UnsafeMutableRawPointer? { get }
}
