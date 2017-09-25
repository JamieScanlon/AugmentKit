//
//  ShaderTypes.h
//  AugmentKit2
//
//  Created by Jamie Scanlon on 7/3/17.
//  Copyright © 2017 TenthLetterMade. All rights reserved.
//

//
//  Header containing types and enum constants shared between Metal shaders and C/ObjC source
//
#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

// MARK: - Indexes

// Buffer index values shared between shader and C code to ensure Metal shader buffer inputs match
//   Metal API buffer set calls
enum BufferIndices {
    kBufferIndexMeshPositions    = 0,
    kBufferIndexMeshGenerics,
    kBufferIndexAnchorInstanceUniforms,
    kBufferIndexSharedUniforms,
    kBufferIndexMaterialUniforms
};

// Attribute index values shared between shader and C code to ensure Metal shader vertex
//   attribute indices match the Metal API vertex descriptor attribute indices
enum VertexAttributes {
    kVertexAttributePosition  = 0,  // Used by both Image Render and Anchor Render
    kVertexAttributeTexcoord,       // Used by both Image Render and Anchor Render
    kVertexAttributeNormal,         // Used by Anchor Render only
    kVertexAttributeJointIndices,   // Used by Anchor Render only
    kVertexAttributeJointWeights    // Used by Anchor Render only
    //kVertexAttributeTangent,
    //kVertexAttributeBitangent
};

// Texture index values shared between shader and C code to ensure Metal shader texture indices
//   match indices of Metal API texture set calls
enum TextureIndices {
    // Base Color
    kTextureIndexColor    = 0,
    // Vid Capture Color Space Conversion
    kTextureIndexY,
    kTextureIndexCbCr,
    // Materials
    kTextureIndexMetallic,
    kTextureIndexRoughness,
    kTextureIndexNormal,
    kTextureIndexAmbientOcclusion,
    //kTextureIndexIrradianceMap,
    kNumTextureIndices
};

enum SceneTextureIndices {
    kTextureIndexIrradianceMap = kNumTextureIndices
};

enum FunctionConstantIndices {
    kFunctionConstantBaseColorMapIndex = 0,
    kFunctionConstantNormalMapIndex,
    kFunctionConstantMetallicMapIndex,
    kFunctionConstantRoughnessMapIndex,
    kFunctionConstantAmbientOcclusionMapIndex,
    kFunctionConstantIrradianceMapIndex,
    kNumFunctionConstantIndices
};

enum VertexConstantIndices {
    kVertexConstantPosition = kNumFunctionConstantIndices,
    kVertexConstantTexcoord,
    kVertexConstantNormal,
    kVertexConstantTangent,
    kVertexConstantBitangent
};

// MARK: AR/VR goggle support for left and right eyes.

enum Viewports {
    kViewportLeft  = 0,
    kViewportRight,
    kViewportNumViewports
};

// MARK: Leavel of Detail (LOD)

enum QualityLevel {
    kQualityLevelHigh   = 0,
    kQualityLevelMedium,
    kQualityLevelLow,
    kQualityNumLevels
};

// MARK: - Uniforms

// Structure shared between shader and C code to ensure the layout of shared uniform data accessed in
//    Metal shaders matches the layout of uniform data set in C code
struct SharedUniforms {
    // Camera (Device) Position Uniforms
    matrix_float4x4 projectionMatrix; // A transform matrix to convert to 'clip space' for the devices screen taking into account the properties of the camera.
    matrix_float4x4 viewMatrix; // A transform matrix for converting from world space to camera (eye) space.
    
    // Lighting Properties
    vector_float3 ambientLightColor;
    vector_float3 directionalLightDirection;
    vector_float3 directionalLightColor;
    float materialShininess;
    //float irradianceMapWeight;
};

// Structure shared between shader and C code to ensure the layout of instance uniform data accessed in
//    Metal shaders matches the layout of uniform data set in C code
struct AnchorInstanceUniforms {
    matrix_float4x4 modelMatrix; // A transform matrix for the anchor model in world space.
};

struct MaterialUniforms {
    vector_float4 baseColor;
    vector_float4 irradiatedColor;
    float roughness;
    float metalness;
    //float ambientOcclusion;
    //float mapWeights[kNumMeshTextureIndices];
};

#endif /* ShaderTypes_h */
