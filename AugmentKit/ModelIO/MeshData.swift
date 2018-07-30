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
//  Data for an individual submesh
public struct DrawSubData {
    var idxCount = 0
    var idxType = MTLIndexType.uint16
    
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

    // TODO: Implement for Quality level
    func computeTextureWeights(for quality: QualityLevel, with globalWeight:Float) {
        for textureIndex in 0..<kNumTextureIndices.rawValue {
            let constantIndex = mapTextureBindPoint(to: TextureIndices(rawValue:textureIndex))

            if MetalUtilities.isTexturedProperty(constantIndex, at: quality) && !MetalUtilities.isTexturedProperty(constantIndex, at: QualityLevel(rawValue: quality.rawValue + 1)) {
                //materialUniforms.mapWeights[textureIndex] = globalWeight
            } else {
                //materialUniforms.mapWeights[textureIndex] = 1.0
            }
        }
    }

    func mapTextureBindPoint(to textureIndex: TextureIndices) -> FunctionConstantIndices {
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
            assert(false)
        }
    }
}

// MARK: DrawData
//  Data for an individual mesh
public struct DrawData {
    var vbCount = 0
    var vbStartIdx = 0
    var ibStartIdx = 0
    var instBufferStartIdx = 0
    var instCount = 0
    var paletteStartIndex: Int?
    var paletteSize = 0
    var subData = [DrawSubData]()
    var worldTransform: matrix_float4x4 = matrix_identity_float4x4
    var worldTransformAnimations: [matrix_float4x4] = []
    var skins = [SkinData]()
    var skeletonAnimations = [AnimatedSkeleton]()
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
}

// MARK: DrawData
//  Data for an object containing one or more meshes
public struct MeshGPUData {
    var vertexBuffers = [MTLBuffer]()
    var vertexDescriptors = [MTLVertexDescriptor]()
    var indexBuffers = [MTLBuffer]()
    var drawData = [DrawData]()
}

// MARK: - Puppet Animation (Not currently supported by renderer)

// MARK: SkinData
//  Describes how a mesh is bound to a skeleton
public struct SkinData: JointPathRemappable {
    var jointPaths = [String]()
    var skinToSkeletonMap = [Int]()
    var inverseBindTransforms = [matrix_float4x4]()
    var animationIndex: Int?
}

// MARK: AnimatedSkeleton
//  Stores skeleton data as well as its time-sampled animation
public struct AnimatedSkeleton: JointPathRemappable {
    var jointPaths = [String]()
    var parentIndices = [Int?]()
    var keyTimes = [Double]()
    var translations = [vector_float3]()
    var rotations = [simd_quatf]()
    var jointCount: Int {
        return jointPaths.count
    }
    var timeSampleCount: Int {
        return keyTimes.count
    }
}

// MARK: - Environment
// MARK: EnvironmentData
//  Stores any parameters rlated to the environment that may affect the rendered objects
public struct EnvironmentData {
    var hasEnvironmentMap = false
    var environmentTexture: MTLTexture?
}
