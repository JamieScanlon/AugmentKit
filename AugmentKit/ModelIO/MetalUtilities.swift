//
//  MetalUtilities.swift
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
//  Metal utility functions for setting up the render engine state
//

import Foundation
import MetalKit
import simd
import GLKit
import AugmentKitShader

class MetalUtilities {
    
    static func getFuncConstantsForDrawDataSet(meshData: MeshData?, useMaterials: Bool) -> MTLFunctionConstantValues {
        
        var has_base_color_map = false
        var has_normal_map = false
        var has_metallic_map = false
        var has_roughness_map = false
        var has_ambient_occlusion_map = false
        var has_irradiance_map = false
        var has_subsurface_map = false
        var has_specular_map = false
        var has_specularTint_map = false
        var has_anisotropic_map = false
        var has_sheen_map = false
        var has_sheenTint_map = false
        var has_clearcoat_map = false
        var has_clearcoatGloss_map = false

        // Condition all subdata since we only do a pipelinestate once per DrawData
        if let meshData = meshData, useMaterials {
            for material in meshData.materials {
                has_base_color_map = has_base_color_map || (material.baseColor.1 != nil)
                has_normal_map = has_normal_map || (material.normalMap != nil)
                has_metallic_map = has_metallic_map || (material.metallic.1 != nil)
                has_roughness_map = has_roughness_map || (material.roughness.1 != nil)
                has_ambient_occlusion_map = has_ambient_occlusion_map || (material.ambientOcclusionMap.1 != nil)
                has_irradiance_map = has_irradiance_map || (material.irradianceColorMap.1 != nil)
                has_subsurface_map = has_subsurface_map || (material.subsurface.1 != nil)
                has_specular_map = has_specular_map || (material.specular.1 != nil)
                has_specularTint_map = has_specularTint_map || (material.specularTint.1 != nil)
                has_anisotropic_map = has_anisotropic_map || (material.anisotropic.1 != nil)
                has_sheen_map = has_sheen_map || (material.sheen.1 != nil)
                has_sheenTint_map = has_sheenTint_map || (material.sheenTint.1 != nil)
                has_clearcoat_map = has_clearcoat_map || (material.clearcoat.1 != nil)
                has_clearcoatGloss_map = has_clearcoatGloss_map || (material.clearcoatGloss.1 != nil)
            }
        }

        let constantValues = MTLFunctionConstantValues()
        constantValues.setConstantValue(&has_base_color_map, type: .bool, index: Int(kFunctionConstantBaseColorMapIndex.rawValue))
        constantValues.setConstantValue(&has_normal_map, type: .bool, index: Int(kFunctionConstantNormalMapIndex.rawValue))
        constantValues.setConstantValue(&has_metallic_map, type: .bool, index: Int(kFunctionConstantMetallicMapIndex.rawValue))
        constantValues.setConstantValue(&has_roughness_map, type: .bool, index: Int(kFunctionConstantRoughnessMapIndex.rawValue))
        constantValues.setConstantValue(&has_ambient_occlusion_map, type: .bool, index: Int(kFunctionConstantAmbientOcclusionMapIndex.rawValue))
        constantValues.setConstantValue(&has_irradiance_map, type: .bool, index: Int(kFunctionConstantIrradianceMapIndex.rawValue))
        constantValues.setConstantValue(&has_subsurface_map, type: .bool, index: Int(kFunctionConstantSubsurfaceMapIndex.rawValue))
        constantValues.setConstantValue(&has_specular_map, type: .bool, index: Int(kFunctionConstantSpecularMapIndex.rawValue))
        constantValues.setConstantValue(&has_specularTint_map, type: .bool, index: Int(kFunctionConstantSpecularTintMapIndex.rawValue))
        constantValues.setConstantValue(&has_anisotropic_map, type: .bool, index: Int(kFunctionConstantAnisotropicMapIndex.rawValue))
        constantValues.setConstantValue(&has_sheen_map, type: .bool, index: Int(kFunctionConstantSheenMapIndex.rawValue))
        constantValues.setConstantValue(&has_sheenTint_map, type: .bool, index: Int(kFunctionConstantSheenTintMapIndex.rawValue))
        constantValues.setConstantValue(&has_clearcoat_map, type: .bool, index: Int(kFunctionConstantClearcoatMapIndex.rawValue))
        constantValues.setConstantValue(&has_clearcoatGloss_map, type: .bool, index: Int(kFunctionConstantClearcoatGlossMapIndex.rawValue))
            
        return constantValues
    }
    
    static func convertToMTLIndexType(from mdlIdxBitDepth: MDLIndexBitDepth) -> MTLIndexType {
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
    
    static func convertToMaterialUniform(from material: Material) -> MaterialUniforms {
        var matUniforms = MaterialUniforms()
        let baseColor = material.baseColor.0 ?? float3(1.0, 1.0, 1.0)
        matUniforms.baseColor = float4(baseColor.x, baseColor.y, baseColor.z, 1.0)
        matUniforms.roughness = material.roughness.0 ?? 1.0
        matUniforms.ambientOcclusion = material.ambientOcclusionMap.0 ?? 1.0
        matUniforms.irradiatedColor = material.irradianceColorMap.0 ?? float3(1.0, 1.0, 1.0)
        matUniforms.metalness = material.metallic.0 ?? 0.0
        matUniforms.opacity = material.opacity ?? 1.0
        matUniforms.subsurface = material.subsurface.0 ?? 0.0
        matUniforms.specular = material.specular.0 ?? 0.0
        matUniforms.specularTint = material.specularTint.0 ?? 0.0
        matUniforms.anisotropic = material.anisotropic.0 ?? 0.0
        matUniforms.sheen = material.sheen.0 ?? 0.0
        matUniforms.sheenTint = material.sheenTint.0 ?? 0.0
        matUniforms.clearcoat = material.clearcoat.0 ?? 0.0
        matUniforms.clearcoatGloss = material.clearcoatGloss.0 ?? 0.0
        return matUniforms
    }
    
    static func convertMaterialBuffer(from material: Material, with materialBuffer: MTLBuffer, offset: Int) {
        
        let theBuffer = materialBuffer.contents().assumingMemoryBound(to: MaterialUniforms.self).advanced(by: offset)
        let baseColor = material.baseColor.0 ?? float3(1.0, 1.0, 1.0)
        theBuffer.pointee.baseColor = float4(baseColor.x, baseColor.y, baseColor.z, 1.0)
        theBuffer.pointee.roughness = material.roughness.0 ?? 1.0
        theBuffer.pointee.ambientOcclusion = material.ambientOcclusionMap.0 ?? 1.0
        theBuffer.pointee.irradiatedColor = material.irradianceColorMap.0 ?? float3(1.0, 1.0, 1.0)
        theBuffer.pointee.metalness = material.metallic.0 ?? 0.0
        theBuffer.pointee.opacity = material.opacity ?? 1.0
        theBuffer.pointee.subsurface = material.subsurface.0 ?? 0.0
        theBuffer.pointee.specular = material.specular.0 ?? 0.0
        theBuffer.pointee.specularTint = material.specularTint.0 ?? 0.0
        theBuffer.pointee.anisotropic = material.anisotropic.0 ?? 0.0
        theBuffer.pointee.sheen = material.sheen.0 ?? 0.0
        theBuffer.pointee.sheenTint = material.sheenTint.0 ?? 0.0
        theBuffer.pointee.clearcoat = material.clearcoat.0 ?? 0.0
        theBuffer.pointee.clearcoatGloss = material.clearcoatGloss.0 ?? 0.0
        
    }
    
    static func isTexturedProperty(_ propertyIndex: FunctionConstantIndices, at quality: QualityLevel) -> Bool {
        var minLevelForProperty = kQualityLevelHigh
        switch propertyIndex {
        case kFunctionConstantBaseColorMapIndex:
            fallthrough
        case kFunctionConstantIrradianceMapIndex:
            minLevelForProperty = kQualityLevelMedium
        default:
            break
        }
        return quality.rawValue <= minLevelForProperty.rawValue
    }
    
}

// MARK: - float4x4

public extension float4x4 {
    
    public static func makeScale(x: Float, y: Float, z: Float) -> float4x4 {
        return unsafeBitCast(GLKMatrix4MakeScale(x, y, z), to: float4x4.self)
    }
    
    public static func makeRotate(radians: Float, x: Float, y: Float, z: Float) -> float4x4 {
        return unsafeBitCast(GLKMatrix4MakeRotation(radians, x, y, z), to: float4x4.self)
    }
    
    public static func makeTranslation(x: Float, y: Float, z: Float) -> float4x4 {
        return unsafeBitCast(GLKMatrix4MakeTranslation(x, y, z), to: float4x4.self)
    }
    
    public static func makePerspective(fovyRadians: Float, aspect: Float, nearZ: Float, farZ: Float) -> float4x4 {
        return unsafeBitCast(GLKMatrix4MakePerspective(fovyRadians, aspect, nearZ, farZ), to: float4x4.self)
    }
    
    public static func makeFrustum(left: Float, right: Float, bottom: Float, top: Float, nearZ: Float, farZ: Float) -> float4x4 {
        return unsafeBitCast(GLKMatrix4MakeFrustum(left, right, bottom, top, nearZ, farZ), to: float4x4.self)
    }
    
    public static func makeOrtho(left: Float, right: Float, bottom: Float, top: Float, nearZ: Float, farZ: Float) -> float4x4 {
        return unsafeBitCast(GLKMatrix4MakeOrtho(left, right, bottom, top, nearZ, farZ), to: float4x4.self)
    }
    
    public static func makeLookAt(eyeX: Float, eyeY: Float, eyeZ: Float, centerX: Float, centerY: Float, centerZ: Float, upX: Float, upY: Float, upZ: Float) -> float4x4 {
        return unsafeBitCast(GLKMatrix4MakeLookAt(eyeX, eyeY, eyeZ, centerX, centerY, centerZ, upX, upY, upZ), to: float4x4.self)
    }
    
    public static func makeQuaternion(from: float4x4) -> GLKQuaternion {
        return GLKQuaternionMakeWithMatrix4(unsafeBitCast(from, to: GLKMatrix4.self))
    }
    
    public func scale(x: Float, y: Float, z: Float) -> float4x4 {
        return self * float4x4.makeScale(x: x, y: y, z: z)
    }
    
    public func rotate(radians: Float, x: Float, y: Float, z: Float) -> float4x4 {
        return self * float4x4.makeRotate(radians: radians, x: x, y: y, z: z)
    }
    
    public func translate(x: Float, y: Float, z: Float) -> float4x4 {
        return self * float4x4.makeTranslation(x: x, y: y, z: z)
    }
    
    public func quaternion() -> GLKQuaternion {
        return float4x4.makeQuaternion(from: self)
    }
    
}

public extension simd_float4 {
    static let zero = simd_float4(0.0, 0.0, 0.0, 0.0)
    
    static func ==(left: simd_float4, right: simd_float4) -> simd_int4 {
        return simd_int4(left.x == right.x ? -1: 0, left.y == right.y ? -1: 0, left.z == right.z ? -1: 0, left.w == right.w ? -1: 0)
    }
    var xyz: simd_float3 {
        get {
            return simd_float3(x, y, z)
        }
        set {
            x = newValue.x
            y = newValue.y
            z = newValue.z
        }
    }
}

// MARK: - EulerAngles

struct EulerAngles {
    var roll: Float
    var pitch: Float
    var yaw: Float
}

// MARK: - QuaternionUtilities

class QuaternionUtilities {
    
    static func quaternionFromEulerAngles(eulerAngles: EulerAngles) -> GLKQuaternion {
        
        // This is taken from https://en.wikipedia.org/wiki/Conversion_between_quaternions_and_Euler_angles
        // but on that example they use a different coordinate system. In this implementation
        // pitch, roll, and yaw have been translated to our coordinate system.
        
        let cy = cos(eulerAngles.yaw * 0.5)
        let sy = sin(eulerAngles.yaw * 0.5)
        let cr = cos(eulerAngles.roll * 0.5)
        let sr = sin(eulerAngles.roll * 0.5)
        let cp = cos(eulerAngles.pitch * 0.5)
        let sp = sin(eulerAngles.pitch * 0.5)
        
        let w = cr * cy * cp + sr * sy * sp
        let x = cr * sy * cp - sr * cy * sp
        let y = cr * cy * sp + sr * sy * cp
        let z = sr * cy * cp - cr * sy * sp
        
        return GLKQuaternionMake(x, y, z, w)
        
    }
    
    static func quaternionToEulerAngle(quaternion: GLKQuaternion) -> EulerAngles {
        
        // (z-axis rotation)
        let siny = 2 * (quaternion.w * quaternion.x + quaternion.y * quaternion.z)
        let cosy = 1 - 2 * (quaternion.x * quaternion.x + quaternion.y * quaternion.y)
        let roll = atan2(siny, cosy)
        
        // (y-axis rotation)
        let sinp = 2 * (quaternion.w * quaternion.y - quaternion.z * quaternion.x)
        let yaw: Float = {
            if fabs(sinp) >= 1 {
                return copysign(Float.pi / 2, sinp) // use 90 degrees if out of range
            } else {
                return asin(sinp)
            }
        }()
        
        
        // (x-axis rotation)
        let sinr = 2 * (quaternion.w * quaternion.z + quaternion.x * quaternion.y)
        let cosr = 1 - 2 * (quaternion.y * quaternion.y + quaternion.z * quaternion.z)
        let pitch = atan2(sinr, cosr)
        
        return EulerAngles(roll: roll, pitch: pitch, yaw: yaw)
        
    }
    
}

