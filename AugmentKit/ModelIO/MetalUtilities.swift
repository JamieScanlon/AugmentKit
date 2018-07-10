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
    
    static func getFuncConstants(forDrawData drawData: DrawData?, useMaterials: Bool) -> MTLFunctionConstantValues {
        
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
        
        if let drawData = drawData, useMaterials {
            has_base_color_map = has_base_color_map || drawData.hasBaseColorMap
            has_normal_map = has_normal_map || drawData.hasNormalMap
            has_metallic_map = has_metallic_map || drawData.hasMetallicMap
            has_roughness_map = has_roughness_map || drawData.hasRoughnessMap
            has_ambient_occlusion_map = has_ambient_occlusion_map || drawData.hasAmbientOcclusionMap
            has_irradiance_map = has_irradiance_map || drawData.hasIrradianceMap
            has_subsurface_map = has_subsurface_map || drawData.hasSubsurfaceMap
            has_specular_map = has_specular_map || drawData.hasSpecularMap
            has_specularTint_map = has_specularTint_map || drawData.hasSpecularTintMap
            has_anisotropic_map = has_anisotropic_map || drawData.hasAnisotropicMap
            has_sheen_map = has_sheen_map || drawData.hasSheenMap
            has_sheenTint_map = has_sheenTint_map || drawData.hasSheenTintMap
            has_clearcoat_map = has_clearcoat_map || drawData.hasClearcoatMap
            has_clearcoatGloss_map = has_clearcoatGloss_map || drawData.hasClearcoatGlossMap
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
    
    //  Create a vertex descriptor for our Metal pipeline. Specifies the layout of vertices the
    //  pipeline should expect.
    
    //  TODO: To maximize pipeline efficiency, The layout should keep attributes used to calculate
    //  vertex shader output position (world position, skinning, tweening weights) separate from other
    //  attributes (texture coordinates, normals).
    static func createStandardVertexDescriptor() -> MDLVertexDescriptor {
            
        let geometryVertexDescriptor = MTLVertexDescriptor()
        
        //
        // Attributes
        //
        
        // -------- Buffer 0 --------
        
        // Positions.
        geometryVertexDescriptor.attributes[0].format = .float3 // 12 bytes
        geometryVertexDescriptor.attributes[0].offset = 0
        geometryVertexDescriptor.attributes[0].bufferIndex = Int(kBufferIndexMeshPositions.rawValue)
        
        // -------- Buffer 1 --------
        
        // Texture coordinates.
        geometryVertexDescriptor.attributes[1].format = .float2 // 8 bytes
        geometryVertexDescriptor.attributes[1].offset = 0
        geometryVertexDescriptor.attributes[1].bufferIndex = Int(kBufferIndexMeshGenerics.rawValue)
        
        // Normals.
        geometryVertexDescriptor.attributes[2].format = .float3 // 12 bytes
        geometryVertexDescriptor.attributes[2].offset = 8
        geometryVertexDescriptor.attributes[2].bufferIndex = Int(kBufferIndexMeshGenerics.rawValue)
        
        // JointIndices (Puppet animations)
        geometryVertexDescriptor.attributes[3].format = .ushort4 // 8 bytes
        geometryVertexDescriptor.attributes[3].offset = 20
        geometryVertexDescriptor.attributes[3].bufferIndex = Int(kBufferIndexMeshGenerics.rawValue)
        
        // JointWeights (Puppet animations)
        geometryVertexDescriptor.attributes[4].format = .float4 // 16 bytes
        geometryVertexDescriptor.attributes[4].offset = 28
        geometryVertexDescriptor.attributes[4].bufferIndex = Int(kBufferIndexMeshGenerics.rawValue)
        
        //
        // Layouts
        //
        
        // Position Buffer Layout
        geometryVertexDescriptor.layouts[0].stride = 12
        geometryVertexDescriptor.layouts[0].stepRate = 1
        geometryVertexDescriptor.layouts[0].stepFunction = .perVertex
        
        // Generic Attribute Buffer Layout
        geometryVertexDescriptor.layouts[1].stride = 44
        geometryVertexDescriptor.layouts[1].stepRate = 1
        geometryVertexDescriptor.layouts[1].stepFunction = .perVertex
        
        // Creata a Model IO vertexDescriptor so that we format/layout our model IO mesh vertices to
        // fit our Metal render pipeline's vertex descriptor layout
        let vertexDescriptor = MTKModelIOVertexDescriptorFromMetal(geometryVertexDescriptor)
        
        // Indicate how each Metal vertex descriptor attribute maps to each ModelIO attribute
        // See: https://developer.apple.com/documentation/modelio/mdlvertexattribute/vertex_attributes
        (vertexDescriptor.attributes[Int(kVertexAttributePosition.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributePosition
        (vertexDescriptor.attributes[Int(kVertexAttributeTexcoord.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributeTextureCoordinate
        (vertexDescriptor.attributes[Int(kVertexAttributeNormal.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributeNormal
        (vertexDescriptor.attributes[Int(kVertexAttributeJointIndices.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributeJointIndices
        (vertexDescriptor.attributes[Int(kVertexAttributeJointWeights.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributeJointWeights
        
        return vertexDescriptor
        
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
    
    public func isZero() -> Bool {
        if let max = self.columns.0.max(), max > 0.0001 {
            return false
        }
        if let max = self.columns.1.max(), max > 0.0001 {
            return false
        }
        if let max = self.columns.2.max(), max > 0.0001 {
            return false
        }
        if let max = self.columns.3.max(), max > 0.0001 {
            return false
        }
        return true
    }
    
}

// MARK: - simd_float4

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

