//
//  RenderUtilities.swift
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

import AugmentKitShader
import Foundation
import MetalKit

// MARK: - RenderUtilities

///  Metal utility functions for setting up the render engine state
class RenderUtilities {
    
    static func hasTexture(for textureIndex: TextureIndices, qualityLevel: QualityLevel) -> Bool {
        let qualityLevelRawValue = qualityLevel.rawValue
        switch textureIndex {
        case kTextureIndexColor:
            return qualityLevelRawValue < 2 // Render texture up to medium quality
        case kTextureIndexEmissionMap:
            return qualityLevelRawValue < 2 // Render texture up to medium quality
        case kTextureIndexNormal:
            return qualityLevelRawValue < 1 // Render texture in high quality only
        case kTextureIndexMetallic:
            return qualityLevelRawValue < 1 // Render texture in high quality only
        case kTextureIndexRoughness:
            return qualityLevelRawValue < 1 // Render texture in high quality only
        case kTextureIndexAmbientOcclusion:
            return qualityLevelRawValue < 1 // Render texture in high quality only
        case kTextureIndexSubsurfaceMap:
            return qualityLevelRawValue < 1 // Render texture in high quality only
        case kTextureIndexSpecularMap:
            return qualityLevelRawValue < 1 // Render texture in high quality only
        case kTextureIndexSpecularTintMap:
            return qualityLevelRawValue < 1 // Render texture in high quality only
        case kTextureIndexAnisotropicMap:
            return qualityLevelRawValue < 1 // Render texture in high quality only
        case kTextureIndexSheenMap:
            return qualityLevelRawValue < 1 // Render texture in high quality only
        case kTextureIndexSheenTintMap:
            return qualityLevelRawValue < 1 // Render texture in high quality only
        case kTextureIndexClearcoatMap:
            return qualityLevelRawValue < 1 // Render texture in high quality only
        case kTextureIndexClearcoatGlossMap:
            return qualityLevelRawValue < 1 // Render texture in high quality only
        default:
            return true
        }
    }
    
    /// Determine the quality level we want given the model's distance from the camera, Also, when close to a the bounds of a quality level, calculate a weight to transition between the two quality levels
    /// - Parameter distance: Distance in meters from the camera. Can not be negative
    /// - Returns: A `QualityLevel`
    static func getQualityLevel(for distance: Float) -> QualityLevel {
        
        guard AKCapabilities.LevelOfDetail else {
            return kQualityLevelHigh
        }
        
        guard distance > 0 else {
            return kQualityLevelHigh
        }
        
        // In meters
        let MediumQualityDepth: Float = 15
        let LowQualityDepth: Float = 65
        
        if distance < MediumQualityDepth {
            return kQualityLevelHigh
        } else if distance < LowQualityDepth {
            return kQualityLevelMedium
        } else {
            return kQualityLevelLow
        }
    }
    
    static func getFuncConstants(forDrawData drawData: DrawData?, qualityLevel: QualityLevel = kQualityLevelHigh) -> MTLFunctionConstantValues {
        
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
            has_base_color_map = drawData.hasBaseColorMap && hasTexture(for: kTextureIndexColor, qualityLevel: qualityLevel)
            has_emission_map = drawData.hasEmissionMap && hasTexture(for: kTextureIndexEmissionMap, qualityLevel: qualityLevel)
            has_normal_map = drawData.hasNormalMap && hasTexture(for: kTextureIndexNormal, qualityLevel: qualityLevel)
            has_metallic_map = drawData.hasMetallicMap && hasTexture(for: kTextureIndexMetallic, qualityLevel: qualityLevel)
            has_roughness_map = drawData.hasRoughnessMap && hasTexture(for: kTextureIndexRoughness, qualityLevel: qualityLevel)
            has_ambient_occlusion_map = drawData.hasAmbientOcclusionMap && hasTexture(for: kTextureIndexAmbientOcclusion, qualityLevel: qualityLevel)
            has_subsurface_map = drawData.hasSubsurfaceMap && hasTexture(for: kTextureIndexSubsurfaceMap, qualityLevel: qualityLevel)
            has_specular_map = drawData.hasSpecularMap && hasTexture(for: kTextureIndexSpecularMap, qualityLevel: qualityLevel)
            has_specularTint_map = drawData.hasSpecularTintMap && hasTexture(for: kTextureIndexSpecularTintMap, qualityLevel: qualityLevel)
            has_anisotropic_map = drawData.hasAnisotropicMap && hasTexture(for: kTextureIndexAnisotropicMap, qualityLevel: qualityLevel)
            has_sheen_map = drawData.hasSheenMap && hasTexture(for: kTextureIndexSheenMap, qualityLevel: qualityLevel)
            has_sheenTint_map = drawData.hasSheenTintMap && hasTexture(for: kTextureIndexSheenTintMap, qualityLevel: qualityLevel)
            has_clearcoat_map = drawData.hasClearcoatMap && hasTexture(for: kTextureIndexClearcoatMap, qualityLevel: qualityLevel)
            has_clearcoatGloss_map = drawData.hasClearcoatGlossMap && hasTexture(for: kTextureIndexClearcoatGlossMap, qualityLevel: qualityLevel)
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
    
    static func convertToMTLIndexType(from mdlIndexBitDepth: MDLIndexBitDepth) -> MTLIndexType {
        switch mdlIndexBitDepth {
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
        @unknown default:
            fatalError("Unhandled mdlIndexBitDepth")
        }
    }
    
    //  Create a vertex descriptor for our Metal pipeline. Specifies the layout of vertices the
    //  pipeline should expect.
    
    //  To maximize pipeline efficiency, The layout should keep attributes used to calculate
    //  vertex shader output position (world position, skinning, tweening weights) separate from other
    //  attributes (texture coordinates, normals).
    static func createStandardVertexDescriptor() -> MDLVertexDescriptor {
        
        let geometryVertexDescriptor = MTLVertexDescriptor()
        
        //
        // Attributes
        //
        
        // -------- Buffer 0 --------
        
        // Positions.
        geometryVertexDescriptor.attributes[Int(kVertexAttributePosition.rawValue)].format = .float3 // 12 bytes
        geometryVertexDescriptor.attributes[Int(kVertexAttributePosition.rawValue)].offset = 0
        geometryVertexDescriptor.attributes[Int(kVertexAttributePosition.rawValue)].bufferIndex = Int(kBufferIndexMeshPositions.rawValue)
        
        // JointIndices (Puppet animations)
        geometryVertexDescriptor.attributes[Int(kVertexAttributeJointIndices.rawValue)].format = .ushort4 // 8 bytes
        geometryVertexDescriptor.attributes[Int(kVertexAttributeJointIndices.rawValue)].offset = 12
        geometryVertexDescriptor.attributes[Int(kVertexAttributeJointIndices.rawValue)].bufferIndex = Int(kBufferIndexMeshPositions.rawValue)
        
        // JointWeights (Puppet animations)
        geometryVertexDescriptor.attributes[Int(kVertexAttributeJointWeights.rawValue)].format = .float4 // 16 bytes
        geometryVertexDescriptor.attributes[Int(kVertexAttributeJointWeights.rawValue)].offset = 20
        geometryVertexDescriptor.attributes[Int(kVertexAttributeJointWeights.rawValue)].bufferIndex = Int(kBufferIndexMeshPositions.rawValue)
        
        // -------- Buffer 1 --------
        
        // Texture coordinates.
        geometryVertexDescriptor.attributes[Int(kVertexAttributeTexcoord.rawValue)].format = .float2 // 8 bytes
        geometryVertexDescriptor.attributes[Int(kVertexAttributeTexcoord.rawValue)].offset = 0
        geometryVertexDescriptor.attributes[Int(kVertexAttributeTexcoord.rawValue)].bufferIndex = Int(kBufferIndexMeshGenerics.rawValue)
        
        // Normals.
        geometryVertexDescriptor.attributes[Int(kVertexAttributeNormal.rawValue)].format = .float3 // 12 bytes
        geometryVertexDescriptor.attributes[Int(kVertexAttributeNormal.rawValue)].offset = 8
        geometryVertexDescriptor.attributes[Int(kVertexAttributeNormal.rawValue)].bufferIndex = Int(kBufferIndexMeshGenerics.rawValue)
        
        // Tangent
        geometryVertexDescriptor.attributes[Int(kVertexAttributeTangent.rawValue)].format = .float3 // 12 bytes
        geometryVertexDescriptor.attributes[Int(kVertexAttributeTangent.rawValue)].offset = 20
        geometryVertexDescriptor.attributes[Int(kVertexAttributeTangent.rawValue)].bufferIndex = Int(kBufferIndexMeshGenerics.rawValue)
        
        //
        // Layouts
        //
        
        // Vertex Position Buffer Layout
        geometryVertexDescriptor.layouts[0].stride = 36
        geometryVertexDescriptor.layouts[0].stepRate = 1
        geometryVertexDescriptor.layouts[0].stepFunction = .perVertex
        
        // Pixel Shader Buffer Layout
        geometryVertexDescriptor.layouts[1].stride = 32
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
        (vertexDescriptor.attributes[Int(kVertexAttributeTangent.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributeTangent
        
        return vertexDescriptor
        
    }
    
}
