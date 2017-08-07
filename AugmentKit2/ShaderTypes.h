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
    kVertexAttributePosition  = 0,
    kVertexAttributeTexcoord,
    kVertexAttributeNormal,
    kVertexAttributeJointIndices,
    kVertexAttributeJointWeights
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

// MARK: - Uniforms

// Structure shared between shader and C code to ensure the layout of shared uniform data accessed in
//    Metal shaders matches the layout of uniform data set in C code
struct SharedUniforms {
    // Camera Uniforms
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 viewMatrix;
    
    // Lighting Properties
    vector_float3 ambientLightColor;
    vector_float3 directionalLightDirection;
    vector_float3 directionalLightColor;
    float materialShininess;
};

// Structure shared between shader and C code to ensure the layout of instance uniform data accessed in
//    Metal shaders matches the layout of uniform data set in C code
struct AnchorInstanceUniforms {
    matrix_float4x4 modelMatrix;
};

struct MaterialUniforms {
    vector_float4 baseColor;
    vector_float4 irradiatedColor;
    float roughness;
    float metalness;
};

#endif /* ShaderTypes_h */
