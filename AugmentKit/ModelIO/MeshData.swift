//
//  MeshData.swift
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
//
//  Contains data structures for the render engine. The structure of these data
//  objects are intended to contain all the data needed to set up the Metal pipline
//  in a way that is easy to fetch. There is not suppose to be much, if any,
//  translation required between the properties here and the properties of the
//  render pipleine objects.
//

import Foundation
import simd
import ModelIO
import MetalKit
import AugmentKitShader

// MARK: - Mesh Data

// MARK: DrawSubData
/**
 Data for an individual submesh.
 `DrawSubData` is a data structure for the render engine. The structure of this data object is intended to contain all the data needed to set up the Metal pipline in a way where there is not much, if any, translation required between the properties here and the properties of the render pipleine objects.
 */
public struct DrawSubData {
    /**
     The number of indices in the submesh’s index buffer.
     */
    var indexCount = 0
    /**
     The data type for each element in the submesh’s index buffer.
     */
    var indexType = MTLIndexType.uint16
    var indexBuffer: MTLBuffer?
    var baseColorTexture: MTLTexture?
    var normalTexture: MTLTexture?
    var ambientOcclusionTexture: MTLTexture?
    var metallicTexture: MTLTexture?
    var roughnessTexture: MTLTexture?
    var emissionTexture: MTLTexture?
    var subsurfaceTexture: MTLTexture?
    var specularTexture: MTLTexture?
    var specularTintTexture: MTLTexture?
    var anisotropicTexture: MTLTexture?
    var sheenTexture: MTLTexture?
    var sheenTintTexture: MTLTexture?
    var clearcoatTexture: MTLTexture?
    var clearcoatGlossTexture: MTLTexture?
    
    var materialUniforms = MaterialUniforms()
    var materialBuffer: MTLBuffer?
    
    public mutating func updateMaterialTextures(from mdlMaterial: MDLMaterial, textureBundle: Bundle? = nil, textureLoader: MTKTextureLoader? = nil) {
        
        var material = MaterialUniforms()
        
        let myMaterialProperties = ModelIOTools.materialProperties(from: mdlMaterial, textureLoader: textureLoader, bundle: textureBundle)
        let allProperties = myMaterialProperties.properties
        
        // Encode the texture indexes corresponding to the texture maps. If a property has no texture map this value will be nil
        baseColorTexture = allProperties[.baseColor]?.texture
        if AKCapabilities.MetallicMap {
            metallicTexture = allProperties[.metallic]?.texture
        }
        if AKCapabilities.AmbientOcclusionMap {
            ambientOcclusionTexture = allProperties[.ambientOcclusion]?.texture
        }
        if AKCapabilities.RoughnessMap {
            roughnessTexture = allProperties[.roughness]?.texture
        }
        if AKCapabilities.NormalMap {
            normalTexture = allProperties[.tangentSpaceNormal]?.texture
        }
        if AKCapabilities.EmissionMap {
            emissionTexture = allProperties[.emission]?.texture
        }
        if AKCapabilities.SubsurfaceMap {
            subsurfaceTexture = allProperties[.subsurface]?.texture
        }
        if AKCapabilities.SpecularMap {
            specularTexture = allProperties[.specular]?.texture
        }
        if AKCapabilities.SpecularTintMap {
            specularTintTexture = allProperties[.specularTint]?.texture
        }
        if AKCapabilities.AnisotropicMap {
            anisotropicTexture = allProperties[.anisotropic]?.texture
        }
        if AKCapabilities.SheenMap {
            sheenTexture = allProperties[.sheen]?.texture
        }
        if AKCapabilities.SheenTintMap {
            sheenTintTexture = allProperties[.sheenTint]?.texture
        }
        if AKCapabilities.ClearcoatMap {
            clearcoatTexture = allProperties[.clearcoat]?.texture
        }
        if AKCapabilities.ClearcoatGlossMap {
            clearcoatGlossTexture = allProperties[.clearcoatGloss]?.texture
        }
        
        // Encode the uniform values
        
        // The inherent color of a surface, to be used as a modulator during shading.
        material.baseColor = (allProperties[.baseColor]?.uniform as? SIMD4<Float>) ?? SIMD4<Float>(repeating: 1)
        // The degree to which a material appears as a dielectric surface (lower values) or as a metal (higher values).
        material.metalness = (allProperties[.metallic]?.uniform as? Float) ?? 0.0
        // The degree to which a material appears smooth, affecting both diffuse and specular response.
        material.roughness = (allProperties[.roughness]?.uniform as? Float) ?? 0.9
        // The attenuation of ambient light due to local geometry variations on a surface.
        material.ambientOcclusion  = (allProperties[.ambientOcclusion]?.uniform as? Float) ?? 1.0
        // The color emitted as radiance from a material’s surface.
        material.emissionColor = (allProperties[.emission]?.uniform as? SIMD4<Float>) ?? SIMD4<Float>(repeating: 0)
        // The degree to which light scatters under the surface of a material.
        material.subsurface = (allProperties[.subsurface]?.uniform as? Float) ?? 0.0
        // The intensity of specular highlights that appear on the material’s surface.
        material.specular = (allProperties[.specular]?.uniform as? Float) ?? 0.0
        // The balance of color for specular highlights, between the light color (lower values) and the material’s base color (at higher values).
        material.specularTint = (allProperties[.specularTint]?.uniform as? Float) ?? 0.0
        // The angle at which anisotropic effects are rotated relative to the local tangent basis.
        material.anisotropic = (allProperties[.anisotropic]?.uniform as? Float) ?? 0.0
        // The intensity of highlights that appear only at glancing angles on a material’s surface.
        material.sheen = (allProperties[.sheen]?.uniform as? Float) ?? 0.0
        // The balance of color for highlights that appear only at glancing angles, between the light color (lower values) and the material’s base color (at higher values).
        material.sheenTint = (allProperties[.sheenTint]?.uniform as? Float) ?? 0.0
        // The intensity of a second specular highlight, similar to the gloss that results from a clear coat on an automotive finish.
        material.clearcoat = (allProperties[.clearcoat]?.uniform as? Float) ?? 0.0
        // The spread of a second specular highlight, similar to the gloss that results from a clear coat on an automotive finish.
        material.clearcoatGloss = (allProperties[.clearcoatGloss]?.uniform as? Float) ?? 0.0
        material.opacity = (allProperties[.opacity]?.uniform as? Float) ?? 1.0
        //                    material.opacity = 1.0
        materialUniforms = material
        
    }
    
    public func markTexturesAsVolitile() {
        
        baseColorTexture?.setPurgeableState(.volatile)
        normalTexture?.setPurgeableState(.volatile)
        ambientOcclusionTexture?.setPurgeableState(.volatile)
        metallicTexture?.setPurgeableState(.volatile)
        roughnessTexture?.setPurgeableState(.volatile)
        emissionTexture?.setPurgeableState(.volatile)
        subsurfaceTexture?.setPurgeableState(.volatile)
        specularTexture?.setPurgeableState(.volatile)
        specularTintTexture?.setPurgeableState(.volatile)
        anisotropicTexture?.setPurgeableState(.volatile)
        sheenTexture?.setPurgeableState(.volatile)
        sheenTintTexture?.setPurgeableState(.volatile)
        clearcoatTexture?.setPurgeableState(.volatile)
        clearcoatGlossTexture?.setPurgeableState(.volatile)
    }
    
    public func markTexturesAsNonVolitile() {
        
        baseColorTexture?.setPurgeableState(.nonVolatile)
        normalTexture?.setPurgeableState(.nonVolatile)
        ambientOcclusionTexture?.setPurgeableState(.nonVolatile)
        metallicTexture?.setPurgeableState(.nonVolatile)
        roughnessTexture?.setPurgeableState(.nonVolatile)
        emissionTexture?.setPurgeableState(.nonVolatile)
        subsurfaceTexture?.setPurgeableState(.nonVolatile)
        specularTexture?.setPurgeableState(.nonVolatile)
        specularTintTexture?.setPurgeableState(.nonVolatile)
        anisotropicTexture?.setPurgeableState(.nonVolatile)
        sheenTexture?.setPurgeableState(.nonVolatile)
        sheenTintTexture?.setPurgeableState(.nonVolatile)
        clearcoatTexture?.setPurgeableState(.nonVolatile)
        clearcoatGlossTexture?.setPurgeableState(.nonVolatile)
    }

    static func mapTextureBindPoint(to textureIndex: TextureIndices) -> FunctionConstantIndices {
        switch textureIndex {
        case kTextureIndexColor:
            return kFunctionConstantBaseColorMapIndex
        case kTextureIndexNormal:
            return kFunctionConstantNormalMapIndex
        case kTextureIndexMetallic:
            return kFunctionConstantMetallicMapIndex
        case kTextureIndexAmbientOcclusion:
            return kFunctionConstantAmbientOcclusionMapIndex
        case kTextureIndexEmissionMap:
            return kFunctionConstantEmissionMapIndex
        case kTextureIndexRoughness:
            return kFunctionConstantRoughnessMapIndex
        case kTextureIndexSubsurfaceMap:
            return kFunctionConstantSubsurfaceMapIndex
        case kTextureIndexSpecularMap:
            return kFunctionConstantSpecularMapIndex
        case kTextureIndexSpecularTintMap:
            return kFunctionConstantSpecularTintMapIndex
        case kTextureIndexAnisotropicMap:
            return kFunctionConstantAnisotropicMapIndex
        case kTextureIndexSheenMap:
            return kFunctionConstantSheenMapIndex
        case kTextureIndexSheenTintMap:
            return kFunctionConstantSheenTintMapIndex
        case kTextureIndexClearcoatMap:
            return kFunctionConstantClearcoatMapIndex
        case kTextureIndexClearcoatGlossMap:
            return kFunctionConstantClearcoatGlossMapIndex
        default:
            return kFunctionConstantBaseColorMapIndex
        }
    }
}

// MARK: DrawData
/**
 Data for an individual mesh.
 `DrawData` is a data structure for the render engine. The structure of this data object is intended to contain all the data needed to set up the Metal pipline in a way where there is not much, if any, translation required between the properties here and the properties of the render pipleine objects.
 */
public struct DrawData {
    /// A buffer contining Vertex Buffer data
    var vertexBuffers = [MTLBuffer]()
    /// A buffer contining `RawVertexBuffer` uniforms. If this buffer is populated, it will be used instead of `vertexBuffers`
    var rawVertexBuffers = [MTLBuffer]()
    /// Used in the render pipeline to store the number of instances of this type to render
    var instanceCount = 0
    var subData = [DrawSubData]()
    var worldTransform: matrix_float4x4 = matrix_identity_float4x4
    var worldTransformAnimations: [matrix_float4x4] = []
    var skeleton: SkeletonData?
    var hasBaseColorMap = false
    var hasNormalMap = false
    var hasMetallicMap = false
    var hasRoughnessMap = false
    var hasAmbientOcclusionMap = false
    var hasEmissionMap = false
    var hasSubsurfaceMap = false
    var hasSpecularMap = false
    var hasSpecularTintMap = false
    var hasAnisotropicMap = false
    var hasSheenMap = false
    var hasSheenTintMap = false
    var hasClearcoatMap = false
    var hasClearcoatGlossMap = false
    var hasSkeleton: Bool {
        return skeleton != nil
    }
    var isRaw: Bool {
        return rawVertexBuffers.count > 0
    }
    
    public func markTexturesAsVolitile() {
        subData.forEach{ $0.markTexturesAsVolitile() }
    }
    
    public func markTexturesAsNonVolitile() {
        subData.forEach{ $0.markTexturesAsNonVolitile() }
    }
}

// MARK: MeshGPUData
/**
 Data for an object containing one or more meshes.
 `MeshGPUData` is a data structure for the render engine. The structure of this data object is intended to contain all the data needed to set up the Metal pipline in a way where there is not much, if any, translation required between the properties here and the properties of the render pipleine objects.
 */
public struct MeshGPUData {
    var drawData = [DrawData]()
    var vertexDescriptor: MTLVertexDescriptor?
    var shaderPreference: ShaderPreference = .pbr
    
    public func markTexturesAsVolitile() {
        drawData.forEach{ $0.markTexturesAsVolitile() }
    }
    
    public func markTexturesAsNonVolitile() {
        drawData.forEach{ $0.markTexturesAsNonVolitile() }
    }
}

// MARK: MeshGPUData
/**
 Specified the prefered shader to use for rendering.
 */
public enum ShaderPreference {
    /**
     A simple shader that only uses base color. Objects rendered with the simple shader are not intended to look real and the lighting properties are not affected at all by the environment.
     */
    case simple
    /**
     A phisically based shader that is intended to render an object realistically in the environment.
     */
    case pbr
    /**
     A Blinn-Phong shader.
     */
    case blinn
}

// MARK: - Skeletons

// MARK: SkeletonData

/**
 Data that stores skeleton data as well as its time-sampled animation.
 `SkeletonData` is a data structure for the render engine. The structure of this data object is intended to contain all the data needed to set up the Metal pipline in a way where there is not much, if any, translation required between the properties here and the properties of the render pipleine objects.
 */
public struct SkeletonData: JointPathRemappable {
    var jointPaths = [String]()
    var jointNames = [String]()
    var parentIndices = [Int?]()
    var animations = [SkeletonAnimation]()
    var inverseBindTransforms = [matrix_float4x4]() // The starting set of transforms from each node to it's parent. The number of items should be jointCount
    var restTransforms = [matrix_float4x4]() // The number of items should be jointCount
    var jointCount: Int {
        return jointPaths.count
    }
    var timeSampleCount: Int {
        return animations.count
    }
}

// MARK: SkeletonAnimation

public struct SkeletonAnimation {
    var keyTime: Double
    var translations = [SIMD3<Float>]() // An array of translations. One for each joint
    var rotations = [simd_quatf]() // An array of rotations. One for each joint
}

// MARK: - Environment
// MARK: EnvironmentData
/**
 Data that stores any parameters related to the environment that may affect the rendered objects.
 `EnvironmentData` is a data structure for the render engine. The structure of this data object is intended to contain all the data needed to set up the Metal pipline in a way where there is not much, if any, translation required between the properties here and the properties of the render pipleine objects.
 */
public struct EnvironmentData {
    var hasEnvironmentMap = false
    var environmentTexture: MTLTexture?
    var diffuseIBLTexture: MTLTexture?
    var specularIBLTexture: MTLTexture?
    var bdrfLookupTexture: MTLTexture?
}
