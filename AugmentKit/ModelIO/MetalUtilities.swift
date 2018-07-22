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

// MARK: - MetalUtilities

class MetalUtilities {
    
    static func getFuncConstants(forDrawData drawData: DrawData?) -> MTLFunctionConstantValues {
        
        var has_base_color_map = false
        var has_normal_map = false
        var has_metallic_map = false
        var has_roughness_map = false
        var has_ambient_occlusion_map = false
        var has_emission_map = false
        var has_subsurface_map = false
        var has_specular_map = false
        var has_specularTint_map = false
        var has_anisotropic_map = false
        var has_sheen_map = false
        var has_sheenTint_map = false
        var has_clearcoat_map = false
        var has_clearcoatGloss_map = false
        
        if let drawData = drawData {
            has_base_color_map = has_base_color_map || drawData.hasBaseColorMap
            has_normal_map = has_normal_map || drawData.hasNormalMap
            has_metallic_map = has_metallic_map || drawData.hasMetallicMap
            has_roughness_map = has_roughness_map || drawData.hasRoughnessMap
            has_ambient_occlusion_map = has_ambient_occlusion_map || drawData.hasAmbientOcclusionMap
            has_emission_map = has_emission_map || drawData.hasEmissionMap
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
        constantValues.setConstantValue(&has_emission_map, type: .bool, index: Int(kFunctionConstantEmissionMapIndex.rawValue))
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
        case kFunctionConstantEmissionMapIndex:
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

// MARK: - Debugging Extensions

extension MDLObject {
    
    override open var description: String {
        return debugDescription
    }
    
    override open var debugDescription: String {
        var myDescription = "<\(type(of: self)): \(Unmanaged.passUnretained(self).toOpaque())> Name: \(name), Path:\(path), Hidden: \(hidden), Components: \(components)"
        for childIndex in 0..<children.count {
            myDescription += "\n"
            myDescription += "    Child \(childIndex) - \(children[childIndex])"
        }
        return myDescription
    }
    
}

extension MDLAsset {
    
    override open var description: String {
        return debugDescription
    }
    
    override open var debugDescription: String {
        var myDescription = "<\(type(of: self)): \(Unmanaged.passUnretained(self).toOpaque())> URL: \(url?.absoluteString ?? "none"), Count: \(count), VertedDescriptor: \(vertexDescriptor?.debugDescription ?? "none"), Masters: \(masters)"
        for childIndex in 0..<self.count {
            myDescription += "\n"
            myDescription += "    Child \(childIndex) - \(self.object(at: childIndex))"
        }
        return myDescription
    }
    
    public func transformsDescription() -> String {
        var myDescription = "<\(type(of: self)): \(Unmanaged.passUnretained(self).toOpaque())>"
        for childIndex in 0..<self.count {
            myDescription += "\n"
            myDescription += childString(forObject: self.object(at: childIndex), withIndentLevel: 1)
        }
        return myDescription
    }
    
    fileprivate func childString(forObject object: MDLObject, withIndentLevel indentLevel: Int) -> String {
        var myDescription = String(repeating: "   | ", count: indentLevel)
        myDescription += "\(object.name) \(object.transform?.debugDescription ?? "none")"
        for childIndex in 0..<object.children.count {
            myDescription += "\n"
            myDescription += childString(forObject: object.children[childIndex], withIndentLevel: indentLevel + 1)
        }
        return myDescription
    }

}

extension MDLMesh {
    
    override open var description: String {
        return debugDescription
    }
    
    override open var debugDescription: String {
        var myDescription = "\(super.debugDescription), Submeshes: \(submeshes?.debugDescription ?? "none"), VertexCount: \(vertexCount), VertexDescriptor: \(vertexDescriptor)"
        for childIndex in 0..<children.count {
            myDescription += "\n"
            myDescription += "    Child \(childIndex) - \(children[childIndex])"
        }
        return myDescription
    }
    
}

extension MDLMaterial {
    
    override open var description: String {
        return debugDescription
    }
    
    override open var debugDescription: String {
        var myDescription = "<\(type(of: self)): \(Unmanaged.passUnretained(self).toOpaque())> Name: \(name)"
        for childIndex in 0..<count {
            myDescription += "\n"
            myDescription += "    Property \(childIndex) - \(self[childIndex]?.debugDescription ?? "none")"
        }
        return myDescription
    }
    
}

extension MDLMaterialProperty {
    
    override open var description: String {
        return debugDescription
    }
    
    override open var debugDescription: String {
        var myDescription = "<MDLMaterialProperty: \(Unmanaged.passUnretained(self).toOpaque())> Name: \(name), Semantic: \(semantic) "
        switch type {
        case .none:
            myDescription += "Value: none"
        case .string:
            myDescription += "Value: \(stringValue?.debugDescription ?? "none")"
        case .URL:
            myDescription += "Value: \(urlValue?.debugDescription ?? "none")"
        case .texture:
            myDescription += "Value: \(textureSamplerValue?.debugDescription ?? "none")"
        case .color:
            myDescription += "Value: \(color?.debugDescription ?? "none")"
        case .float:
            myDescription += "Value: \(floatValue)"
        case .float2:
            myDescription += "Value: \(float2Value)"
        case .float3:
            myDescription += "Value: \(float3Value)"
        case .float4:
            myDescription += "Value: \(float4Value)"
        case .matrix44:
            myDescription += "Value: \(matrix4x4)"
        }
        return myDescription
    }
    
}

extension MDLMaterialSemantic: CustomDebugStringConvertible, CustomStringConvertible {
    
    public var description: String {
        return debugDescription
    }
    
    public var debugDescription: String {
        var myDescription = ""
        switch self {
        case .none:
            myDescription += "none"
        case .baseColor:
            myDescription += "baseColor"
        case .subsurface:
            myDescription += "subsurface"
        case .metallic:
            myDescription += "metallic"
        case .specular:
            myDescription += "specular"
        case .specularExponent:
            myDescription += "specularExponent"
        case .specularTint:
            myDescription += "specularTint"
        case .roughness:
            myDescription += "roughness"
        case .anisotropic:
            myDescription += "anisotropic"
        case .anisotropicRotation:
            myDescription += "anisotropicRotation"
        case .sheen:
            myDescription += "sheen"
        case .sheenTint:
            myDescription += "sheenTint"
        case .clearcoat:
            myDescription += "clearcoat"
        case .clearcoatGloss:
            myDescription += "clearcoatGloss"
        case .emission:
            myDescription += "emission"
        case .bump:
            myDescription += "bump"
        case .opacity:
            myDescription += "opacity"
        case .interfaceIndexOfRefraction:
            myDescription += "interfaceIndexOfRefraction"
        case .materialIndexOfRefraction:
            myDescription += "materialIndexOfRefraction"
        case .objectSpaceNormal:
            myDescription += "objectSpaceNormal"
        case .tangentSpaceNormal:
            myDescription += "tangentSpaceNormal"
        case .displacement:
            myDescription += "displacement"
        case .displacementScale:
            myDescription += "displacementScale"
        case .ambientOcclusion:
            myDescription += "ambientOcclusion"
        case .ambientOcclusionScale:
            myDescription += "ambientOcclusionScale"
        case .userDefined:
            myDescription += "userDefined"
        }
        return myDescription
    }
    
}

extension MDLTransformStack {
    
    override open var description: String {
        return debugDescription
    }
    
    override open var debugDescription: String {
        let myDescription = "<\(type(of: self)): \(Unmanaged.passUnretained(self).toOpaque())> Matrix: \(float4x4(atTime: 0))"
        return myDescription
    }
    
}

extension MDLTransform {
    
    override open var description: String {
        return debugDescription
    }
    
    override open var debugDescription: String {
        let myDescription = "<\(type(of: self)): \(Unmanaged.passUnretained(self).toOpaque())> Matrix @ 0s: \(matrix))"
        return myDescription
    }
    
}

extension MDLSubmesh {
    
    override open var description: String {
        return debugDescription
    }
    
    override open var debugDescription: String {
        let myDescription = "<\(type(of: self)): \(Unmanaged.passUnretained(self).toOpaque())> Name: \(name), IndexCount: \(indexCount), Material: \(material?.debugDescription ?? "none")"
        return myDescription
    }
    
}

extension MDLObjectContainer {
    
    override open var description: String {
        return debugDescription
    }
    
    override open var debugDescription: String {
        var myDescription = "<\(type(of: self)): \(Unmanaged.passUnretained(self).toOpaque())> Count: \(count)"
        for childIndex in 0..<self.count {
            myDescription += "\n"
            myDescription += "    Child \(childIndex) - \(objects[childIndex])"
        }
        return myDescription
    }
    
}

extension CGColor: CustomDebugStringConvertible, CustomStringConvertible {
    public var description: String {
        return debugDescription
    }
    
    public var debugDescription: String {
        if let components = self.components {
            return "\(components)"
        } else {
            return "unknown"
        }
    }
}

extension simd_float4x4: CustomStringConvertible {
    public var description: String {
        return debugDescription
    }
    
    public var debugDescription: String {
        var myDescription = "\n"
        myDescription += "[\(self.columns.0.x), \(self.columns.1.x), \(self.columns.2.x), \(self.columns.3.x)]"
        myDescription += "\n"
        myDescription += "[\(self.columns.0.y), \(self.columns.1.y), \(self.columns.2.y), \(self.columns.3.y)]"
        myDescription += "\n"
        myDescription += "[\(self.columns.0.z), \(self.columns.1.z), \(self.columns.2.z), \(self.columns.3.z)]"
        myDescription += "\n"
        myDescription += "[\(self.columns.0.w), \(self.columns.1.w), \(self.columns.2.w), \(self.columns.3.w)]"
        return myDescription
    }
}

