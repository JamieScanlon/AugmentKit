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

/// Buffer index values shared between shader and C code to ensure Metal shader buffer inputs match Metal API buffer set calls
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
    kBufferIndexEnvironmentUniforms,
    kBufferIndexPrecalculationOutputBuffer,
    kBufferIndexDrawCallIndex, // The index into the draw call. Used for the precalcualted arguments buffer
    kBufferIndexDrawCallGroupIndex, // The index into the draw call group. Used for the environment and effects buffers
    kBufferIndexRawVertexData,
    kBufferIndexCameraVertices,
    kBufferIndexSceneVerticies,
    kBufferIndexLODRoughness,
    kBufferIndexInstanceCount,
    kBufferIndexCommandBufferContainer,
};

/// Argument buffer ID for the ICB encoded by the compute kernel
enum ICBArgumentBufferIndices {
    kICBArgumentBufferIndexCommandBuffer,
};

/**
 Attribute index values shared between shader and C code to ensure Metal shader vertex attribute indices match the Metal API vertex descriptor attribute indices
 See https://developer.apple.com/documentation/modelio/mdlvertexattribute/vertex_attributes for a full list of attributes supported by ModelIO. The commented out attributes below are the ones that are not yet supported here.
 */
enum VertexAttributes {
    kVertexAttributePosition  = 0,  // Used by all shaders
    kVertexAttributeTexcoord,       // Used by the Image Capture, Anchor, and Path shaders
    kVertexAttributeNormal,         // Used by the Anchor and Path shaders
    kVertexAttributeTangent,
    kVertexAttributeJointIndices,   // Used by the Anchor shaders only
    kVertexAttributeJointWeights,   // Used by the Anchor shaders only
    kVertexAttributeColor,          // User by the Point and Path shaders
    //kVertexAttributeAnisotropy,
    //kVertexAttributeBinormal,
    //kVertexAttributeEdgeCrease,
    //kVertexAttributeOcclusionValue,
    //kVertexAttributeShadingBasisU,
    //kVertexAttributeShadingBasisV,
    //kVertexAttributeSubdivisionStencil,
    kVertexArguments, 
};

/// Texture index values shared between shader and C code to ensure Metal shader texture indices match indices of Metal API texture set calls
enum TextureIndices {
    // Base Color
    kTextureIndexColor = 0,
    // Vid Capture Color Space Conversion
    kTextureIndexY,
    kTextureIndexCbCr,
    // Materials
    kTextureIndexMetallic,
    kTextureIndexRoughness,
    kTextureIndexNormal,
    kTextureIndexAmbientOcclusion,
    kTextureIndexEmissionMap,
    kTextureIndexSubsurfaceMap,
    kTextureIndexSpecularMap,
    kTextureIndexSpecularTintMap,
    kTextureIndexAnisotropicMap,
    kTextureIndexSheenMap,
    kTextureIndexSheenTintMap,
    kTextureIndexClearcoatMap,
    kTextureIndexClearcoatGlossMap,
    // Environment
    kTextureIndexEnvironmentMap,
    // IBL
    kTextureIndexDiffuseIBLMap,
    kTextureIndexSpecularIBLMap,
    kTextureIndexBDRFLookupMap,
    // Shadow
    kTextureIndexShadowMap,
    // Composite
    kTextureIndexSceneColor,
    kTextureIndexSceneDepth,
    kTextureIndexAlpha,
    kTextureIndexDialatedDepth,
    kNumTextureIndices,
};

enum FunctionConstantIndices {
    kFunctionConstantBaseColorMapIndex = 0,
    kFunctionConstantNormalMapIndex,
    kFunctionConstantMetallicMapIndex,
    kFunctionConstantRoughnessMapIndex,
    kFunctionConstantAmbientOcclusionMapIndex,
    kFunctionConstantEmissionMapIndex,
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

enum ArgumentBufferIndices {
//    kArgumentBufferTextureIndex = 0,
//    kArgumentBufferSamplerIndex,
    kArgumentBufferPrecalculationBufferIndex,
//    kArgumentBufferConstantIndex,
};

// MARK: - AR/VR goggle support for left and right eyes.

enum Viewports {
    kViewportLeft  = 0,
    kViewportRight,
    kViewportNumViewports
};

// MARK: - Leavel of Detail (LOD)

enum QualityLevel {
    kQualityLevelHigh   = 0,
    kQualityLevelMedium,
    kQualityLevelLow,
    kQualityNumLevels
};

// MARK: - HeadingType

enum HeadingType {
    kAbsolute   = 0,
    kRelative
};

// MARK: - Uniforms

/// Used for constructing raw vertex buffers
struct RawVertexBuffer {
    vector_float3 position;
    vector_float2 texCoord;
    vector_float3 normal;
    vector_float3 tangent;
};

/// Structure shared between shader and C code that contains general information like camera (eye) transforms
struct SharedUniforms {
    // Camera (eye) Position Uniforms
    matrix_float4x4 projectionMatrix; // A transform matrix to convert to 'clip space' for the devices screen taking into account the properties of the camera.
    matrix_float4x4 viewMatrix; // A transform matrix for converting from world space to camera (eye) space.
    
    // Matting
    int useDepth;
};

/// Structure shared between shader and C code that contains information about the environment like lighting and environment texture cubemaps
struct EnvironmentUniforms {
    // Lighting Properties
    float ambientLightIntensity;
    vector_float3 ambientLightColor;
    vector_float3 directionalLightDirection;
    vector_float3 directionalLightColor;
    matrix_float4x4 directionalLightMVP;
    // Environment
    int hasEnvironmentMap;
    // Shadow transfor matrix
    matrix_float4x4 shadowMVPTransformMatrix;
};

/// Structure shared between shader and C code that contains information pertaining to a single model like the model matrix transform
struct AnchorInstanceUniforms {
    int hasGeometry;
    int hasHeading;
    matrix_float4x4 headingTransform;
    int headingType;
    
    matrix_float4x4 locationTransform;
    matrix_float4x4 worldTransform; // A transform matrix for the anchor model in world space.
    
    // Used for LOD calculations to seamlessly transition from one LOD to another
    // The lengh of the array should match the number of properties in MaterialUniforms
    float mapWeights[14];
};

/// Structure shared between shader and C code that contains information about effects that should be applied to a model
struct AnchorEffectsUniforms {
    float alpha;
    float glow;
    vector_float3 tint;
    matrix_float4x4 scale;
};

/// Structure shared between shader and C code that contains information about the material that should be used to render a model
struct MaterialUniforms {
    vector_float4 baseColor;
    vector_float4 emissionColor;
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

// MARK: Lighting Parameters

struct LightingParameters {
    vector_float3   lightDirection;
    vector_float3   directionalLightCol;
    vector_float3   ambientLightCol;
    float           ambientIntensity;
    vector_float3   viewDir;
    vector_float3   halfVector;
    vector_float3   reflectedVector;
    vector_float3   normal;
    vector_float3   reflectedColor;
    vector_float4   emissionColor;
    vector_float3   ambientOcclusion;
    vector_float4   baseColor;
    float           baseColorLuminance;
    vector_float3   baseColorHueSat;
    float           nDoth;
    float           nDotv;
    float           nDotl;
    float           lDoth;
    vector_float3   fresnelNDotL;
    vector_float3   fresnelNDotV;
    vector_float3   fresnelLDotH;
    vector_float3   f0;
    float           metalness;
    float           roughness;
    float           perceptualRoughness;
    float           subsurface;
    float           specular;
    float           specularTint;
    float           anisotropic;
    float           sheen;
    float           sheenTint;
    float           clearcoat;
    float           clearcoatGloss;
};

// MARK: Precalculated Parameters

/// Calculated on a per-draw basis
struct PrecalculatedParameters {
    int hasGeometry;
    matrix_float4x4 worldTransform;
    int hasHeading;
    matrix_float4x4 headingTransform;
    int headingType;
    matrix_float4x4 coordinateSpaceTransform; // calculated using worldTransform and headingTransform
    matrix_float4x4 locationTransform;
    
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 modelMatrix; // locationTransform * coordinateSpaceTransform. A transform matrix for the anchor model in world space.
    matrix_float3x3 normalMatrix;
    matrix_float4x4 modelViewMatrix; // scaledModelMatrix * viewMatrix
    matrix_float4x4 modelViewProjectionMatrix; // projectionMatrix * modelViewMatrix
    matrix_float4x4 shadowMVPTransformMatrix;
    matrix_float4x4 directionalLightMVP;
    
    // Matting
    int useDepth;
    
    // Used for LOD calculations to seamlessly transition from one LOD to another
    // The lengh of the array should match the number of properties in MaterialUniforms
    float mapWeights[14];
};

// MARK: Argument Buffers

typedef struct VertexShaderArguments {
//    texture2d<half> exampleTexture  [[ id(AAPLArgumentBufferIDExampleTexture)  ]];
//    sampler         exampleSampler  [[ id(AAPLArgumentBufferIDExampleSampler)  ]];
//    device PrecalculatedParameters *precalculationBuffer [[ id(kArgumentBufferPrecalculationBufferIndex) ]];
//    uint32_t        exampleConstant [[ id(AAPLArgumentBufferIDExampleConstant) ]];
} VertexShaderArguments;

typedef struct FragmentShaderArguments {
//    texture2d<half> exampleTexture  [[ id(AAPLArgumentBufferIDExampleTexture)  ]];
//    sampler         exampleSampler  [[ id(AAPLArgumentBufferIDExampleSampler)  ]];
//    device float   *exampleBuffer   [[ id(AAPLArgumentBufferIDExampleBuffer)   ]];
//    uint32_t        exampleConstant [[ id(AAPLArgumentBufferIDExampleConstant) ]];
} FragmentShaderArguments;

#endif /* ShaderTypes_h */
