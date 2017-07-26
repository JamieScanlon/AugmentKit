/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Contains datastructures for the game engine
*/

import Foundation
import simd
import ModelIO
import MetalKit

// MARK: - Material Data

struct Material {
    var baseColor: (float3?, Int?) = (float3(1, 1, 1), nil)
    var metallic: (Float?, Int?) = (0, nil)
    var roughness: (Float?, Int?) = (0, nil)
    var normalMap: Int?
    var ambientOcclusionMap: Int?
}

// MARK: - Mesh Data that will be converted into GPU Data

struct MeshData {
    var vbCount = 0
    var vbStartIdx = 0
    var ibStartIdx = 0
    var idxCounts = [Int]()
    var idxTypes = [MDLIndexBitDepth]()
    var materials = [Material]()
}

// MARK: - Data that will be submitted to the GPU

struct DrawSubData {
    var idxCount = 0
    var idxType = MTLIndexType.uint16
    var baseColorTexIdx: Int?
    var normalTexIdx: Int?
    var aoTexIdx: Int?
    var metalTexIdx: Int?
    var roughTexIdx: Int?
    var materialUniforms = MaterialUniforms()
}

struct DrawData {
    var vbCount = 0
    var vbStartIdx = 0
    var ibStartIdx = 0
    var instBufferStartIdx = 0
    var instCount = 0
    var paletteStartIndex: Int?
    var paletteSize = 0
    var subData = [DrawSubData]()
}

struct MeshGPUData {
    var vtxBuffers = [MTLBuffer]()
    var indexBuffers = [MTLBuffer]()
    var textures = [MTLTexture?]()
    var drawData = [DrawData]()
}

// MARK: - Puppet Animation (Not currently supported by renderer)

/// Describes how a mesh is bound to a skeleton
struct SkinData: JointPathRemappable {
    var jointPaths = [String]()
    
    var skinToSkeletonMap = [Int]()
    var inverseBindTransforms = [matrix_float4x4]()
    var animationIndex: Int?
}

/// Stores skeleton data as well as its time-sampled animation
struct AnimatedSkeleton: JointPathRemappable {
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
