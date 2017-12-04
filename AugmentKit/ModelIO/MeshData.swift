//
//  MeshData.swift
//  AugmentKit2
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
//
//  Contains data structures for the render engine
//

import Foundation
import simd
import ModelIO
import MetalKit
import AugmentKitShader

// MARK: - Material Data. Intermediate format sutable for serialization and transport.

public struct Material {
    var baseColor: (float3?, Int?) = (float3(1, 1, 1), nil)
    var metallic: (Float?, Int?) = (0, nil)
    var roughness: (Float?, Int?) = (0, nil)
    var normalMap: Int?
    var ambientOcclusionMap: Int?
    //var irradiatedColor: float3? // TODO: Add
}

// MARK: - Mesh Data that will be converted into GPU Data

public struct MeshData {
    var vbCount = 0
    var vbStartIdx = 0
    var ibStartIdx = 0
    var idxCounts = [Int]()
    var idxTypes = [MDLIndexBitDepth]()
    var materials = [Material]()
}

// MARK: - Data that will be submitted to the GPU

public struct DrawSubData {
    var idxCount = 0
    var idxType = MTLIndexType.uint16
    var baseColorTexIdx: Int?
    var normalTexIdx: Int?
    var aoTexIdx: Int?
    var metalTexIdx: Int?
    var roughTexIdx: Int?
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
        case kTextureIndexRoughness:
            return kFunctionConstantRoughnessMapIndex
        default:
            assert(false)
        }
    }
}

public struct DrawData {
    var vbCount = 0
    var vbStartIdx = 0
    var ibStartIdx = 0
    var instBufferStartIdx = 0
    var instCount = 0
    var paletteStartIndex: Int?
    var paletteSize = 0
    var subData = [DrawSubData]()
}

public struct MeshGPUData {
    var vtxBuffers = [MTLBuffer]()
    var indexBuffers = [MTLBuffer]()
    var textures = [MTLTexture?]()
    var drawData = [DrawData]()
}

// MARK: - Puppet Animation (Not currently supported by renderer)

//  Describes how a mesh is bound to a skeleton
public struct SkinData: JointPathRemappable {
    var jointPaths = [String]()
    
    var skinToSkeletonMap = [Int]()
    var inverseBindTransforms = [matrix_float4x4]()
    var animationIndex: Int?
}

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
