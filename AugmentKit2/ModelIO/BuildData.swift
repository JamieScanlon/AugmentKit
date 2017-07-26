/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Contains runtime data for engine
*/

import Foundation
import simd
import MetalKit

func convertToMtlIndexType(mdlIdxBitDepth: MDLIndexBitDepth) -> MTLIndexType {
    switch mdlIdxBitDepth {
    case .uInt16:
        return .uint16
    case .uInt32:
        return .uint32
    case .uInt8:
        print("UInt8 unsupported, defaulting to uint16")
        return .uint16
    case .invalid:
        print("Invalid MTLIndexType, defaulting to uint16")
        return .uint16
    }
}

func convertToMaterialUniform(_ material: Material) -> MaterialUniforms {
    var matUniforms = MaterialUniforms()
    let baseColor = material.baseColor.0 ?? float3(1.0, 1.0, 1.0)
    matUniforms.baseColor = float4(baseColor.x, baseColor.y, baseColor.z, 1.0)
    matUniforms.roughness = material.roughness.0 ?? 1.0
    matUniforms.irradiatedColor = float4(1.0, 1.0, 1.0, 1.0)
    matUniforms.metalness = material.metallic.0 ?? 0.0
    return matUniforms
}

struct NodeTransform {
    var worldMatrix = matrix_float4x4()
}

struct MeshUniforms {
    var worldMatrix = matrix_float4x4()
    var normalMatrix = matrix_float3x3()
}

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
