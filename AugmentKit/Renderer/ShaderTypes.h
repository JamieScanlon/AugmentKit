//
//  ShaderTypes.h
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
    kBufferIndexMaterialUniforms,
    kBufferIndexTrackingPointData,
    kBufferIndexMeshPalettes,
    kBufferIndexMeshPaletteIndex,
    kBufferIndexMeshPaletteSize,
    kBufferIndexAnchorEffectsUniforms,
};

// Attribute index values shared between shader and C code to ensure Metal shader vertex
//   attribute indices match the Metal API vertex descriptor attribute indices
// See https://developer.apple.com/documentation/modelio/mdlvertexattribute/vertex_attributes for a
// full list of attributes supported by ModelIO. The commented out attributes below
// are the ones that are not yet supported here.
enum VertexAttributes {
    kVertexAttributePosition  = 0,  // Used by all shaders
    kVertexAttributeTexcoord,       // Used by the Image Capture, Anchor, and Path shaders
    kVertexAttributeNormal,         // Used by the Anchor and Path shaders
    kVertexAttributeJointIndices,   // Used by the Anchor shaders only
    kVertexAttributeJointWeights,   // Used by the Anchor shaders only
    kVertexAttributeColor,          // User by the Point and Path shaders
    //kVertexAttributeAnisotropy,
    //kVertexAttributeBinormal,
    //kVertexAttributeBitangent,
    //kVertexAttributeEdgeCrease,
    //kVertexAttributeOcclusionValue,
    //kVertexAttributeShadingBasisU,
    //kVertexAttributeShadingBasisV,
    //kVertexAttributeSubdivisionStencil,
    //kVertexAttributeTangent,
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
    kTextureIndexIrradianceMap,
    kTextureIndexSubsurfaceMap,
    kTextureIndexSpecularMap,
    kTextureIndexSpecularTintMap,
    kTextureIndexAnisotropicMap,
    kTextureIndexSheenMap,
    kTextureIndexSheenTintMap,
    kTextureIndexClearcoatMap,
    kTextureIndexClearcoatGlossMap,
    kNumTextureIndices,
};

enum FunctionConstantIndices {
    kFunctionConstantBaseColorMapIndex = 0,
    kFunctionConstantNormalMapIndex,
    kFunctionConstantMetallicMapIndex,
    kFunctionConstantRoughnessMapIndex,
    kFunctionConstantAmbientOcclusionMapIndex,
    kFunctionConstantIrradianceMapIndex,
    kFunctionConstantSubsurfaceMapIndex,
    kFunctionConstantSpecularMapIndex,
    kFunctionConstantSpecularTintMapIndex,
    kFunctionConstantAnisotropicMapIndex,
    kFunctionConstantSheenMapIndex,
    kFunctionConstantSheenTintMapIndex,
    kFunctionConstantClearcoatMapIndex,
    kFunctionConstantClearcoatGlossMapIndex,
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
    // Camera (eye) Position Uniforms
    matrix_float4x4 projectionMatrix; // A transform matrix to convert to 'clip space' for the devices screen taking into account the properties of the camera.
    matrix_float4x4 viewMatrix; // A transform matrix for converting from world space to camera (eye) space.
    
    // Lighting Properties
    vector_float3 ambientLightColor;
    vector_float3 directionalLightDirection;
    vector_float3 directionalLightColor;
};

// Structure shared between shader and C code to ensure the layout of instance uniform data accessed in
//    Metal shaders matches the layout of uniform data set in C code
struct AnchorInstanceUniforms {
    matrix_float4x4 modelMatrix; // A transform matrix for the anchor model in world space.
};

struct AnchorEffectsUniforms {
    float glow;
};

struct MaterialUniforms {
    vector_float4 baseColor;
    vector_float3 irradiatedColor;
    float roughness;
    float metalness;
    float ambientOcclusion;
    float opacity;
    float subsurface;
    float specular;
    float specularTint;
    float anisotropic;
    float sheen;
    float sheenTint;
    float clearcoat;
    float clearcoatGloss;
};

#endif /* ShaderTypes_h */
