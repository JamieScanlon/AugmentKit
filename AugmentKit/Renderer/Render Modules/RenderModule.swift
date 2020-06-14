//
//  RenderModule.swift
//  AugmentKit
//
//  MIT License
//
//  Copyright (c) 2019 JamieScanlon
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
import MetalKit
import AugmentKitShader

// MARK: - RenderModule protocol

protocol RenderModule: ShaderModule {
    
    //
    // State
    //
    
    var renderDistance: Double { get set }
    
    
    //
    // Bootstrap
    //
    
    // Load the data from the Model Provider.
    func loadAssets(forGeometricEntities: [AKGeometricEntity], fromModelProvider: ModelProvider?, textureLoader: MTKTextureLoader, completion: (() -> Void))
    
    /// After this function is called, The Render Pass Desciptors, Textures, Buffers, Render Pipeline State Descriptors, and Depth Stencil Descriptors should all be set up.
    func loadPipeline(withModuleEntities: [AKEntity], metalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider, modelManager: ModelManager, renderPass: RenderPass?, numQualityLevels: Int, completion: (([DrawCallGroup]) -> Void)?)
    
    //
    // Per Frame Updates
    //
    
    // Update the buffer data for the geometric entities
    func updateBuffers(withModuleEntities: [AKEntity], cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties, shadowProperties: ShadowProperties, argumentBufferProperties: ArgumentBufferProperties, forRenderPass renderPass: RenderPass)
    
    // Update the render encoder for the draw call. At the end of this method it is expected that
    // drawPrimatives or drawIndexedPrimatives is called.
    func draw(withRenderPass renderPass: RenderPass, sharedModules: [SharedRenderModule]?)
    
    
    
}

// MARK: - RenderModule extensions

extension RenderModule {
    
    /// Calls `drawIndexedPrimitives` for every submesh in the `drawData`
    func draw(withDrawData drawData: DrawData, with renderEncoder: MTLRenderCommandEncoder, baseIndex: Int = 0, environmentData: EnvironmentData? = nil, includeGeometry: Bool = true, includeSkeleton: Bool = false, includeLighting: Bool = true) {
        
        if includeGeometry {
            // Set mesh's vertex buffers
            for (index, vertexBuffer) in drawData.vertexBuffers.enumerated() {
                renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: index)
            }
            // Set mesh's raw vertex buffer
            if let vertexBuffer = drawData.rawVertexBuffers.first {
                renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: Int(kBufferIndexRawVertexData.rawValue))
            }
        
            if includeSkeleton {
                var jointCount = drawData.skeleton?.jointCount ?? 0
                renderEncoder.setVertexBytes(&jointCount, length: 8, index: Int(kBufferIndexMeshJointCount.rawValue))
            }
            
        }
        
        // Draw each submesh of our mesh
        for submeshData in drawData.subData {
            
            guard drawData.instanceCount > 0 else {
                continue
            }
            
            guard let indexBuffer = submeshData.indexBuffer else {
                continue
            }
            
            let indexCount = Int(submeshData.indexCount)
            let indexType = submeshData.indexType
            
            var materialUniforms = submeshData.materialUniforms
            
            if includeLighting {
                // Set textures based off material flags
                encodeTextures(for: renderEncoder, subData: submeshData, environmentData: environmentData)
                
                renderEncoder.setFragmentBytes(&materialUniforms, length: RenderModuleConstants.alignedMaterialSize, index: Int(kBufferIndexMaterialUniforms.rawValue))
            }
            
            if includeGeometry {
                renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: indexType, indexBuffer: indexBuffer, indexBufferOffset: 0, instanceCount: drawData.instanceCount, baseVertex: 0, baseInstance: baseIndex)
            }
        }
        
    }
    
    // MARK: Encoding Textures
    
    func encodeTextures(for renderEncoder: MTLRenderCommandEncoder, subData drawSubData: DrawSubData, environmentData: EnvironmentData? = nil) {
        if let baseColorTexture = drawSubData.baseColorTexture {
            renderEncoder.setFragmentTexture(baseColorTexture, index: Int(kTextureIndexColor.rawValue))
        }
        
        if let ambientOcclusionTexture = drawSubData.ambientOcclusionTexture, AKCapabilities.AmbientOcclusionMap {
            renderEncoder.setFragmentTexture(ambientOcclusionTexture, index: Int(kTextureIndexAmbientOcclusion.rawValue))
        }
        
        if let emissionTexture = drawSubData.emissionTexture, AKCapabilities.EmissionMap {
            renderEncoder.setFragmentTexture(emissionTexture, index: Int(kTextureIndexEmissionMap.rawValue))
        }
        
        if let normalTexture = drawSubData.normalTexture, AKCapabilities.NormalMap {
            renderEncoder.setFragmentTexture(normalTexture, index: Int(kTextureIndexNormal.rawValue))
        }
        
        if let roughnessTexture = drawSubData.roughnessTexture, AKCapabilities.RoughnessMap {
            renderEncoder.setFragmentTexture(roughnessTexture, index: Int(kTextureIndexRoughness.rawValue))
        }
        
        if let metallicTexture = drawSubData.metallicTexture, AKCapabilities.MetallicMap {
            renderEncoder.setFragmentTexture(metallicTexture, index: Int(kTextureIndexMetallic.rawValue))
        }
        
        if let subsurfaceTexture = drawSubData.subsurfaceTexture, AKCapabilities.SubsurfaceMap {
            renderEncoder.setFragmentTexture(subsurfaceTexture, index: Int(kTextureIndexSubsurfaceMap.rawValue))
        }
        
        if let specularTexture = drawSubData.specularTexture, AKCapabilities.SpecularMap {
            renderEncoder.setFragmentTexture(specularTexture, index: Int(kTextureIndexSpecularMap.rawValue))
        }
        
        if let specularTintTexture = drawSubData.specularTintTexture, AKCapabilities.SpecularTintMap {
            renderEncoder.setFragmentTexture(specularTintTexture, index: Int(kTextureIndexSpecularTintMap.rawValue))
        }
        
        if let anisotropicTexture = drawSubData.anisotropicTexture, AKCapabilities.AnisotropicMap {
            renderEncoder.setFragmentTexture(anisotropicTexture, index: Int(kTextureIndexAnisotropicMap.rawValue))
        }
        
        if let sheenTexture = drawSubData.sheenTexture, AKCapabilities.SheenMap {
            renderEncoder.setFragmentTexture(sheenTexture, index: Int(kTextureIndexSheenMap.rawValue))
        }
        
        if let sheenTintTexture = drawSubData.sheenTintTexture, AKCapabilities.SheenTintMap {
            renderEncoder.setFragmentTexture(sheenTintTexture, index: Int(kTextureIndexSheenTintMap.rawValue))
        }
        
        if let clearcoatTexture = drawSubData.clearcoatTexture, AKCapabilities.ClearcoatMap {
            renderEncoder.setFragmentTexture(clearcoatTexture, index: Int(kTextureIndexClearcoatMap.rawValue))
        }
        
        if let clearcoatGlossTexture = drawSubData.clearcoatGlossTexture, AKCapabilities.ClearcoatGlossMap {
            renderEncoder.setFragmentTexture(clearcoatGlossTexture, index: Int(kTextureIndexClearcoatGlossMap.rawValue))
        }
        
        if let texture = environmentData?.environmentTexture, AKCapabilities.EnvironmentMap {
            renderEncoder.setFragmentTexture(texture, index: Int(kTextureIndexEnvironmentMap.rawValue))
        }
        if let texture = environmentData?.diffuseIBLTexture, AKCapabilities.ImageBasedLighting {
            renderEncoder.setFragmentTexture(texture, index: Int(kTextureIndexDiffuseIBLMap.rawValue))
        }
        if let texture = environmentData?.specularIBLTexture, AKCapabilities.ImageBasedLighting {
            renderEncoder.setFragmentTexture(texture, index: Int(kTextureIndexSpecularIBLMap.rawValue))
        }
        if let texture = environmentData?.bdrfLookupTexture, AKCapabilities.ImageBasedLighting {
            renderEncoder.setFragmentTexture(texture, index: Int(kTextureIndexBDRFLookupMap.rawValue))
        }
    }
    
    func createMTLTexture(inBundle bundle: Bundle, fromAssetPath assetPath: String, withTextureLoader textureLoader: MTKTextureLoader?) -> MTLTexture? {
        do {
            
            let textureURL: URL? = {
                guard let aURL = URL(string: assetPath) else {
                    return nil
                }
                if aURL.scheme == nil {
                    // If there is no scheme, assume it's a file in the bundle.
                    let last = aURL.lastPathComponent
                    if let bundleURL = bundle.url(forResource: last, withExtension: nil) {
                        return bundleURL
                    } else if let bundleURL = bundle.url(forResource: aURL.path, withExtension: nil) {
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
            let newError = AKError.recoverableError(.modelError(.unableToLoadTexture(AssetErrorInfo(path: assetPath, underlyingError: error))))
            recordNewError(newError)
        }
        
        return nil
    }
    
    // MARK: Render Distance
    
    func anchorDistance(withTransform transform: matrix_float4x4, cameraProperties: CameraProperties?) -> Float {
        guard let cameraProperties = cameraProperties else {
            return 0
        }
        let point = SIMD3<Float>(transform.columns.3.x, transform.columns.3.x, transform.columns.3.z)
        return length(point - cameraProperties.position)
    }
    
    // MARK: Util
    
    func getRGB(from colorTemperature: CGFloat) -> SIMD3<Float> {
        
        let temp = Float(colorTemperature) / 100
        
        var red: Float = 127
        var green: Float = 127
        var blue: Float = 127
        
        if temp <= 66 {
            red = 255
            green = temp
            green = 99.4708025861 * log(green) - 161.1195681661
            if temp <= 19 {
                blue = 0
            } else {
                blue = temp - 10
                blue = 138.5177312231 * log(blue) - 305.0447927307
            }
        } else {
            red = temp - 60
            red = 329.698727446 * pow(red, -0.1332047592)
            green = temp - 60
            green = 288.1221695283 * pow(green, -0.0755148492 )
            blue = 255
        }
        
        let clamped = clamp(SIMD3<Float>(red, green, blue), min: 0, max: 255) / 255
        return SIMD3<Float>(clamped.x, clamped.y, clamped.z)
    }
}

// MARK: - RenderModuleConstants

enum RenderModuleConstants {
    static let alignedMaterialSize = (MemoryLayout<MaterialUniforms>.stride & ~0xFF) + 0x100
}

// MARK: - SharedRenderModule protocol

/// A shared render module is a `RenderModule` responsible for setting up and updating shared buffers. Although it does have a draw() method, typically this method does not do anything. Instead, the module that uses this shared module is responsible for encoding the shared buffer and issuing the draw call
protocol SharedRenderModule: RenderModule {
    var sharedUniformsBuffer: GPUPassBuffer<SharedUniforms>? { get }
}
