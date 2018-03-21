//
//  Shaders.metal
//  AugmentKit2
//
//  MIT License
//
//  Copyright (c) 2017 JamieScanlon
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
//  Shaders that render anchors in 3D space.
//
// References --
// See: https://developer.apple.com/documentation/metal/advanced_techniques/lod_with_function_specialization#//apple_ref/doc/uid/TP40016233
// Sample Code: LODwithFunctionSpecialization
//
// See: https://developer.apple.com/videos/play/wwdc2017/610/
// Sample Code: ModelIO-from-MDLAsset-to-Game-Engine
//
// See MetalKitEssentialsUsingtheMetalKitViewTextureLoaderandModelIO
// https://developer.apple.com/videos/play/wwdc2015/607/
//

#include <metal_stdlib>
#include <simd/simd.h>

// Include header shared between this Metal shader code and C code executing Metal API commands
#import "../ShaderTypes.h"

using namespace metal;

// MARK: - Constants

constant bool has_base_color_map [[ function_constant(kFunctionConstantBaseColorMapIndex) ]];
constant bool has_normal_map [[ function_constant(kFunctionConstantNormalMapIndex) ]];
constant bool has_metallic_map [[ function_constant(kFunctionConstantMetallicMapIndex) ]];
constant bool has_roughness_map [[ function_constant(kFunctionConstantRoughnessMapIndex) ]];
constant bool has_ambient_occlusion_map [[ function_constant(kFunctionConstantAmbientOcclusionMapIndex) ]];
constant bool has_irradiance_map [[ function_constant(kFunctionConstantIrradianceMapIndex) ]];
constant bool has_subsurface_map [[ function_constant(kFunctionConstantSubsurfaceMapIndex) ]];
constant bool has_specular_map [[ function_constant(kFunctionConstantSpecularMapIndex) ]];
constant bool has_specularTint_map [[ function_constant(kFunctionConstantSpecularTintMapIndex) ]];
constant bool has_anisotropic_map [[ function_constant(kFunctionConstantAnisotropicMapIndex) ]];
constant bool has_sheen_map [[ function_constant(kFunctionConstantSheenMapIndex) ]];
constant bool has_sheenTint_map [[ function_constant(kFunctionConstantSheenTintMapIndex) ]];
constant bool has_clearcoat_map [[ function_constant(kFunctionConstantClearcoatMapIndex) ]];
constant bool has_clearcoatGloss_map [[ function_constant(kFunctionConstantClearcoatGlossMapIndex) ]];
constant bool has_any_map = has_base_color_map || has_normal_map || has_metallic_map || has_roughness_map || has_ambient_occlusion_map || has_irradiance_map || has_subsurface_map || has_specular_map || has_specularTint_map || has_anisotropic_map || has_sheen_map || has_sheenTint_map || has_clearcoat_map || has_clearcoatGloss_map;

constant float PI = 3.1415926535897932384626433832795;

// MARK: - Structs

// MARK: Anchors Vertex In
// Per-vertex inputs fed by vertex buffer laid out with MTLVertexDescriptor in Metal API
struct Vertex {
    float3 position      [[attribute(kVertexAttributePosition)]];
    float2 texCoord      [[attribute(kVertexAttributeTexcoord)]];
    float3 normal        [[attribute(kVertexAttributeNormal)]];
    ushort4 jointIndices [[attribute(kVertexAttributeJointIndices)]];
    float4 jointWeights  [[attribute(kVertexAttributeJointWeights)]];
//    float3 tangent;
//    float3 bitangent;
//    float3 anisotropy,
//    float3 binormal,
//    float3 edgeCrease,
//    float3 occlusionValue,
//    float3 shadingBasisU,
//    float3 shadingBasisV,
//    float3 subdivisionStencil,
};

// MARK: Anchors Vertex Out / Fragment In
// Vertex shader outputs and per-fragmeht inputs.  Includes clip-space position and vertex outputs
//  interpolated by rasterizer and fed to each fragment genterated by clip-space primitives.
struct ColorInOut {
    float4 position [[position]];
    float3 eyePosition;
    float3 normal;
    float2 texCoord [[ function_constant(has_any_map) ]];
};

// MARK: - Pipeline Functions

// MARK: Lighting Parameters

struct LightingParameters {
    float3  lightDir;
    float3  lightCol;
    float3  viewDir;
    float3  halfVector;
    float3  reflectedVector;
    float3  normal;
    float3  reflectedColor;
    float3  irradiatedColor;
    float3  ambientOcclusion;
    float4  baseColor;
    float   baseColorLuminance;
    float3  baseColorHueSat;
    float   nDoth;
    float   nDotv;
    float   nDotl;
    float   lDoth;
    float   fresnelL;
    float   fresnelV;
    float   fresnelH;
    float   metalness;
    float   roughness;
    float   subsurface;
    float   specular;
    float   specularTint;
    float   anisotropic;
    float   sheen;
    float   sheenTint;
    float   clearcoat;
    float   clearcoatGloss;
};

constexpr sampler linearSampler (mip_filter::linear,
                                 mag_filter::linear,
                                 address::repeat,
                                 min_filter::linear);

constexpr sampler nearestSampler(min_filter::linear, mag_filter::linear, mip_filter::none, address::repeat);

constexpr sampler mipSampler(address::clamp_to_edge, min_filter::linear, mag_filter::linear, mip_filter::linear);

LightingParameters calculateParameters(ColorInOut in,
                                       constant SharedUniforms & uniforms,
                                       constant MaterialUniforms & materialUniforms,
                                       texture2d<float> baseColorMap [[ function_constant(has_base_color_map) ]],
                                       texture2d<float> normalMap [[ function_constant(has_normal_map) ]],
                                       texture2d<float> metallicMap [[ function_constant(has_metallic_map) ]],
                                       texture2d<float> roughnessMap [[ function_constant(has_roughness_map) ]],
                                       texture2d<float> ambientOcclusionMap [[ function_constant(has_ambient_occlusion_map) ]],
                                       texturecube<float> irradianceMap [[ function_constant(has_irradiance_map) ]],
                                       texture2d<float> subsurfaceMap [[ function_constant(has_subsurface_map) ]],
                                       texture2d<float> specularMap [[ function_constant(has_specular_map) ]],
                                       texture2d<float> specularTintMap [[ function_constant(has_specularTint_map) ]],
                                       texture2d<float> anisotropicMap [[ function_constant(has_anisotropic_map) ]],
                                       texture2d<float> sheenMap [[ function_constant(has_sheen_map) ]],
                                       texture2d<float> sheenTintMap [[ function_constant(has_sheenTint_map) ]],
                                       texture2d<float> clearcoatMap [[ function_constant(has_clearcoat_map) ]],
                                       texture2d<float> clearcoatGlossMap [[ function_constant(has_clearcoatGloss_map) ]]);

// Schlick Fresnel
float4 srgbToLinear(float4 c);
float4 linearToSrgba(float4 c);
inline float Fresnel(float dotProduct);
inline float sqr(float a);
float Geometry(float Ndotv, float alphaG);
float Distribution(float NdotH, float roughness);
float smithG_GGX(float nDotv, float alphaG);
float GTR1(float nDoth, float a);
float GTR2_aniso(float nDoth, float HdotX, float HdotY, float ax, float ay);
float3 computeNormalMap(ColorInOut in, texture2d<float> normalMapTexture);
float3 computeDiffuse(LightingParameters parameters);
float3 computeSpecular(LightingParameters parameters);
float3 computeClearcoat(LightingParameters parameters);
float3 computeSheen(LightingParameters parameters);
float4 illuminate(LightingParameters parameters);

float4 srgbToLinear(float4 c) {
    float4 gamma = float4(1.0/2.2);
    return pow(c, gamma);
}

float4 linearToSrgba(float4 c) {
    float4 gamma = float4(2.2);
    return pow(c, gamma);
}

inline float Fresnel(float dotProduct) {
    return pow(clamp(1.0 - dotProduct, 0.0, 1.0), 5.0);
}

inline float sqr(float a) {
    return a * a;
}

float Geometry(float Ndotv, float alphaG) {
    float a = alphaG * alphaG;
    float b = Ndotv * Ndotv;
    return (float)(1.0 / (Ndotv + sqrt(a + b - a*b)));
}

float Distribution(float NdotH, float roughness) {
    if (roughness >= 1.0)
        return 1.0 / PI;
    
    float roughnessSqr = pow(roughness, 2);
    
    float d = (NdotH * roughnessSqr - NdotH) * NdotH + 1;
    return roughnessSqr / (PI * d * d);
}

float smithG_GGX(float nDotv, float alphaG) {
    float a = alphaG*alphaG;
    float b = nDotv * nDotv;
    return 1.0 / (nDotv + sqrt(a + b - a*b));
}

// Generalized Trowbridge-Reitz
float GTR1(float nDoth, float a) {
    if (a >= 1.0) return 1.0/PI;
    float a2 = a*a;
    float t = 1.0 + (a2-1.0) * nDoth * nDoth;
    return (a2-1.0) / (PI*log(a2)*t);
}

// Generalized Trowbridge-Reitz, with GGX divided out
float GTR2_aniso(float nDoth, float HdotX, float HdotY, float ax, float ay) {
    return 1.0 / ( PI * ax*ay * sqr( sqr(HdotX/ax) + sqr(HdotY/ay) + nDoth * nDoth ));
}

float3 computeNormalMap(ColorInOut in, texture2d<float> normalMapTexture) {
    float4 normalMap = float4((float4(normalMapTexture.sample(nearestSampler, float2(in.texCoord)).rgb, 0.0)));
    return float3(normalize(in.normal * normalMap.z));
}

float3 computeDiffuse(LightingParameters parameters) {
    
    // Diffuse fresnel - go from 1 at normal incidence to .5 at grazing
    // and mix in diffuse retro-reflection based on roughness
    float Fd90 = 0.5 + 2.0 * sqr(parameters.lDoth) * parameters.roughness;
    float Fd = mix(1.0, Fd90, parameters.fresnelL) + mix(1.0, Fd90, parameters.fresnelV);

    // Based on Hanrahan-Krueger brdf approximation of isotropic bssrdf
    // 1.25 scale is used to (roughly) preserve albedo
    // Fss90 used to "flatten" retroreflection based on roughness
    float Fss90 = sqr(parameters.lDoth) * parameters.roughness;
    float Fss = mix(1.0, Fss90, parameters.fresnelL) * mix(1.0, Fss90, parameters.fresnelV);
    // 1.25 scale is used to (roughly) preserve albedo
    float ss = 1.25 * (Fss * (1.0 / (parameters.nDotl + parameters.nDotv) - 0.5) + 0.5);

    float subsurface = 0.0; // TODO: parameters.subsurface
    float3 diffuseOutput = ((1.0/PI) * mix(Fd, ss, subsurface) * parameters.baseColor.rgb) * (1.0 - parameters.metalness);
    return parameters.lightCol * diffuseOutput;
    
}

float3 computeSpecular(LightingParameters parameters) {
    
    //float specularRoughness = parameters.roughness * (1.0 - parameters.metalness) + parameters.metalness;
    float specularRoughness = parameters.roughness * 0.5 + 0.5;
    float aspect = sqrt(1.0 - parameters.anisotropic * 0.9);
    //float alphaAniso = specularRoughness;
    float alphaAniso = sqr(specularRoughness);
    float ax = max(0.0001, alphaAniso / aspect);
    float ay = max(0.0001, alphaAniso * aspect);
    // TODO: Support shading basis - float Ds = GTR2_aniso(parameters.nDoth, dot(parameters.halfVector, parameters.shadingBasisU), dot(dsv.halfVector, parameters.shadingBasisV), ax, ay);
    float3 shadingBasisX = float3(1,0,0);
    float3 shadingBasisY = float3(0,1,0);
    float Ds = GTR2_aniso(parameters.nDoth, dot(parameters.halfVector, shadingBasisX), dot(parameters.halfVector, shadingBasisY), ax, ay);
    float3 Cspec0 = parameters.specular * mix(float3(1.0), parameters.baseColorHueSat, parameters.specularTint);
    float3 Fs = mix(Cspec0, float3(1), parameters.fresnelH);
    float alphaG = sqr(specularRoughness * 0.5 + 0.5);
    float Gs = smithG_GGX(parameters.nDotl, alphaG) * smithG_GGX(parameters.nDotv, alphaG);

    float3 specularOutput = (Ds * Gs * Fs * parameters.irradiatedColor) * (1.0 + parameters.metalness * parameters.baseColor.rgb) + parameters.metalness * parameters.irradiatedColor * parameters.baseColor.rgb;
    return specularOutput;
    
}

float3 computeClearcoat(LightingParameters parameters) {
    
    // clearcoat (ior = 1.5 -> F0 = 0.04)
    float Dr = GTR1(parameters.nDoth, mix(.6, 0.001, parameters.clearcoatGloss));
    float Fr = mix(0.1, 0.4, parameters.fresnelH);
    float clearcoatRoughness = sqr(parameters.roughness * 0.5 + 0.5);
    float Gr = smithG_GGX(parameters.nDotl, clearcoatRoughness) * smithG_GGX(parameters.nDotv, clearcoatRoughness);
    
    float3 clearcoatOutput = parameters.clearcoat * Gr * Fr * Dr * parameters.lightCol;
    return clearcoatOutput;
}

float3 computeSheen(LightingParameters parameters) {
    
    float3 Csheen = mix(float3(1.0), parameters.baseColorHueSat, parameters.sheenTint);
    float3 Fsheen = Csheen * parameters.fresnelV * parameters.sheen;
    
    //float3 light_color = float3(6.0) * parameters.nDotl + (float3(3.0) * parameters.irradiatedColor * (1.0 - parameters.nDotl));
    //float3 sheenOutput = Fsheen * (1.0 - parameters.metalness);
    float3 sheenOutput = Fsheen;
    return sheenOutput;
    
}

// all input colors must be linear, not SRGB.
float4 illuminate(LightingParameters parameters) {
    
    // DIFFUSE
    // 2pi to integrate the entire dome, 0.5 as intensity
    float3 light_color = float3(2.0 * PI * 0.3) * (parameters.nDotl + parameters.irradiatedColor * (1.0 - parameters.nDotl) * parameters.ambientOcclusion);
    float3 diffuseOut = computeDiffuse(parameters) * light_color;
    
    // AMBIENCE
    const float environmentContribution = 0.0;
    float3 ambienceOutput = parameters.baseColor.rgb * parameters.lightCol * environmentContribution * parameters.ambientOcclusion;
    
    // CLEARCOAT
    float3 clearcoatOut = computeClearcoat(parameters);
    
    // SPECULAR
    float3 specularOut = computeSpecular(parameters);
    
    // SHEEN
    float3 sheenOut = computeSheen(parameters) * light_color;
    
    return float4(diffuseOut + ambienceOutput + clearcoatOut + specularOut + sheenOut, 1);
}

LightingParameters calculateParameters(ColorInOut in,
                                       constant SharedUniforms & sharedUniforms,
                                       constant MaterialUniforms & materialUniforms,
                                       texture2d<float> baseColorMap [[ function_constant(has_base_color_map) ]],
                                       texture2d<float> normalMap [[ function_constant(has_normal_map) ]],
                                       texture2d<float> metallicMap [[ function_constant(has_metallic_map) ]],
                                       texture2d<float> roughnessMap [[ function_constant(has_roughness_map) ]],
                                       texture2d<float> ambientOcclusionMap [[ function_constant(has_ambient_occlusion_map) ]],
                                       texturecube<float> irradianceMap [[ function_constant(has_irradiance_map) ]],
                                       texture2d<float> subsurfaceMap [[ function_constant(has_subsurface_map) ]],
                                       texture2d<float> specularMap [[ function_constant(has_specular_map) ]],
                                       texture2d<float> specularTintMap [[ function_constant(has_specularTint_map) ]],
                                       texture2d<float> anisotropicMap [[ function_constant(has_anisotropic_map) ]],
                                       texture2d<float> sheenMap [[ function_constant(has_sheen_map) ]],
                                       texture2d<float> sheenTintMap [[ function_constant(has_sheenTint_map) ]],
                                       texture2d<float> clearcoatMap [[ function_constant(has_clearcoat_map) ]],
                                       texture2d<float> clearcoatGlossMap [[ function_constant(has_clearcoatGloss_map) ]]
                                       ) {
    LightingParameters parameters;
    
    float4 baseColor = has_base_color_map ? srgbToLinear(baseColorMap.sample(linearSampler, in.texCoord.xy)) : materialUniforms.baseColor;
    parameters.baseColor = float4(baseColor.xyz, baseColor.w * materialUniforms.opacity);
    
    parameters.baseColorLuminance = 0.3 * parameters.baseColor.x + 0.6 * parameters.baseColor.y + 0.1 * parameters.baseColor.z; // approximation of luminanc
    parameters.baseColorHueSat = parameters.baseColorLuminance > 0.0 ? parameters.baseColor.rgb / parameters.baseColorLuminance : float3(1); // remove luminance
    
    parameters.subsurface = has_subsurface_map ? subsurfaceMap.sample(linearSampler, in.texCoord.xy).x : materialUniforms.subsurface;
    
    parameters.specular = has_specular_map ? specularMap.sample(linearSampler, in.texCoord.xy).x : materialUniforms.specular;
    
    parameters.specularTint = has_specularTint_map ? specularTintMap.sample(linearSampler, in.texCoord.xy).x : materialUniforms.specularTint;
    
    parameters.sheen = has_sheen_map ? sheenMap.sample(linearSampler, in.texCoord.xy).x : materialUniforms.sheen;
    
    parameters.sheenTint = has_sheenTint_map ? sheenTintMap.sample(linearSampler, in.texCoord.xy).x : materialUniforms.sheenTint;
    
    parameters.anisotropic = has_anisotropic_map ? anisotropicMap.sample(linearSampler, in.texCoord.xy).x : materialUniforms.anisotropic;
    
    parameters.clearcoat = has_clearcoat_map ? clearcoatMap.sample(linearSampler, in.texCoord.xy).x : materialUniforms.clearcoat;
    
    parameters.clearcoatGloss = has_clearcoatGloss_map ? clearcoatGlossMap.sample(linearSampler, in.texCoord.xy).x : materialUniforms.clearcoatGloss;
    
    parameters.normal = has_normal_map ? computeNormalMap(in, normalMap) : float3(in.normal);
    
    // TODO: ??? - not sure if this is correct. float3(in.eyePosition) or -float3(in.eyePosition) ?
    parameters.viewDir = float3(in.eyePosition);
    parameters.reflectedVector = reflect(-parameters.viewDir, parameters.normal);
    parameters.reflectedColor = float3(0, 0, 0); // reflectionMap.sample(reflectiveEnvironmentSampler, dsv.reflectedVector).xyz;
    
    parameters.roughness = has_roughness_map ? max(roughnessMap.sample(linearSampler, in.texCoord.xy).x, 0.001f) : materialUniforms.roughness;
    parameters.metalness = has_metallic_map ? metallicMap.sample(linearSampler, in.texCoord.xy).x : materialUniforms.metalness;
    
    uint8_t mipLevel = parameters.roughness * irradianceMap.get_num_mip_levels();
    parameters.irradiatedColor = has_irradiance_map ? irradianceMap.sample(mipSampler, parameters.reflectedVector, level(mipLevel)).xyz : materialUniforms.irradiatedColor.xyz;
    parameters.ambientOcclusion = has_ambient_occlusion_map ? max(srgbToLinear(ambientOcclusionMap.sample(linearSampler, in.texCoord.xy)).x, 0.001f) : materialUniforms.ambientOcclusion;
    
    parameters.lightCol = sharedUniforms.directionalLightColor;
    parameters.lightDir = -sharedUniforms.directionalLightDirection;
    
    // Light falls off based on how closely aligned the surface normal is to the light direction.
    // This is the dot product of the light direction vector and vertex normal.
    // The smaller the angle between those two vectors, the higher this value,
    // and the stronger the diffuse lighting effect should be.
    parameters.nDotl = max(0.001f, saturate(dot(parameters.normal, parameters.lightDir)));
    
    // Calculate the halfway vector between the light direction and the direction they eye is looking
    parameters.halfVector = normalize(parameters.lightDir + parameters.viewDir);
    
    parameters.nDoth = max(0.001f,saturate(dot(parameters.normal, parameters.halfVector)));
    parameters.nDotv = max(0.001f,saturate(dot(parameters.normal, parameters.viewDir)));
    parameters.lDoth = max(0.001f,saturate(dot(parameters.lightDir, parameters.halfVector)));
    
    parameters.fresnelL = Fresnel(parameters.nDotl);
    parameters.fresnelV = Fresnel(parameters.nDotv);
    parameters.fresnelH = Fresnel(parameters.lDoth);
    
    return parameters;
    
}

// MARK: - Anchor Shaders

// MARK: Anchor vertex function
vertex ColorInOut anchorGeometryVertexTransform(Vertex in [[stage_in]],
                                                constant SharedUniforms &sharedUniforms [[ buffer(kBufferIndexSharedUniforms) ]],
                                                constant AnchorInstanceUniforms *anchorInstanceUniforms [[ buffer(kBufferIndexAnchorInstanceUniforms) ]],
                                                uint vid [[vertex_id]],
                                                ushort iid [[instance_id]]) {
    ColorInOut out;
    
    // Make position a float4 to perform 4x4 matrix math on it
    float4 position = float4(in.position, 1.0);
    
    // Get the anchor model's orientation in world space
    float4x4 modelMatrix = anchorInstanceUniforms[iid].modelMatrix;
    
    // Transform the model's orientation from world space to camera space.
    float4x4 modelViewMatrix = sharedUniforms.viewMatrix * modelMatrix;
    
    // Calculate the position of our vertex in clip space and output for clipping and rasterization
    out.position = sharedUniforms.projectionMatrix * modelViewMatrix * position;
    
    // Calculate the positon of our vertex in eye space
    out.eyePosition = float3((modelViewMatrix * position).xyz);
    
    // Rotate our normals to world coordinates
    float4 normal = modelMatrix * float4(in.normal.x, in.normal.y, in.normal.z, 0.0f);
    out.normal = normalize(float3(normal.xyz));
    
    // Pass along the texture coordinate of our vertex such which we'll use to sample from texture's
    //   in our fragment function, if we need it
    if (has_any_map) {
        out.texCoord = float2(in.texCoord.x, 1.0f - in.texCoord.y);
    }
    
    return out;
}

// MARK: Anchor vertex function with skinning
vertex ColorInOut anchorGeometryVertexTransformSkinned(Vertex in [[stage_in]],
                                                       constant SharedUniforms &sharedUniforms [[ buffer(kBufferIndexSharedUniforms) ]],
                                                       constant float4x4 *palette [[buffer(kBufferIndexMeshPalettes)]],
                                                       constant int &paletteStartIndex [[buffer(kBufferIndexMeshPaletteIndex)]],
                                                       constant int &paletteSize [[buffer(kBufferIndexMeshPaletteSize)]],
                                                       constant AnchorInstanceUniforms *anchorInstanceUniforms [[ buffer(kBufferIndexAnchorInstanceUniforms) ]],
                                                       uint vid [[vertex_id]],
                                                       ushort iid [[instance_id]]) {
    
    ColorInOut out;
    
    // Make position a float4 to perform 4x4 matrix math on it
    float4 position = float4(in.position, 1.0f);
    
    // Get the anchor model's orientation in world space
    float4x4 modelMatrix = anchorInstanceUniforms[iid].modelMatrix;
    
    // Transform the model's orientation from world space to camera space.
    float4x4 modelViewMatrix = sharedUniforms.viewMatrix * modelMatrix;
    
    ushort4 jointIndex = in.jointIndices + paletteStartIndex + iid * paletteSize;
    float4 weights = in.jointWeights;
    
    float4 skinnedPosition = weights[0] * (palette[jointIndex[0]] * position) +
        weights[1] * (palette[jointIndex[1]] * position) +
        weights[2] * (palette[jointIndex[2]] * position) +
        weights[3] * (palette[jointIndex[3]] * position);
    
    float4 modelNormal = float4(in.normal, 0.0f);
    float4 skinnedNormal = weights[0] * (palette[jointIndex[0]] * modelNormal) +
        weights[1] * (palette[jointIndex[1]] * modelNormal) +
        weights[2] * (palette[jointIndex[2]] * modelNormal) +
        weights[3] * (palette[jointIndex[3]] * modelNormal);
    
    // Calculate the position of our vertex in clip space and output for clipping and rasterization
    out.position = sharedUniforms.projectionMatrix * modelViewMatrix * skinnedPosition;
    
    // Calculate the positon of our vertex in eye space
    out.eyePosition = float3((modelViewMatrix * skinnedPosition).xyz);
    
    // Rotate our normals to world coordinates
    float4 normal = modelMatrix * skinnedNormal;
    out.normal = normalize(float3(normal.xyz));
    
    // Pass along the texture coordinate of our vertex such which we'll use to sample from texture's
    //   in our fragment function, if we need it
    if (has_any_map) {
        out.texCoord = float2(in.texCoord.x, 1.0f - in.texCoord.y);
    }
    
    return out;
    
}

// MARK: Anchor fragment function with materials

fragment float4 anchorGeometryFragmentLighting(ColorInOut in [[stage_in]],
                                               constant SharedUniforms &uniforms [[ buffer(kBufferIndexSharedUniforms) ]],
                                               constant MaterialUniforms &materialUniforms [[ buffer(kBufferIndexMaterialUniforms) ]],
                                               texture2d<float> baseColorMap [[ texture(kTextureIndexColor), function_constant(has_base_color_map) ]],
                                               texture2d<float> normalMap    [[ texture(kTextureIndexNormal), function_constant(has_normal_map) ]],
                                               texture2d<float> metallicMap  [[ texture(kTextureIndexMetallic), function_constant(has_metallic_map) ]],
                                               texture2d<float> roughnessMap  [[ texture(kTextureIndexRoughness), function_constant(has_roughness_map) ]],
                                               texture2d<float> ambientOcclusionMap  [[ texture(kTextureIndexAmbientOcclusion), function_constant(has_ambient_occlusion_map) ]],
                                               texturecube<float> irradianceMap [[texture(kTextureIndexIrradianceMap), function_constant(has_irradiance_map)]],
                                               texture2d<float> subsurfaceMap [[texture(kTextureIndexSubsurfaceMap), function_constant(has_subsurface_map)]],
                                               texture2d<float> specularMap [[  texture(kTextureIndexSpecularMap), function_constant(has_specular_map) ]],
                                               texture2d<float> specularTintMap [[  texture(kTextureIndexSpecularTintMap), function_constant(has_specularTint_map) ]],
                                               texture2d<float> anisotropicMap [[  texture(kTextureIndexAnisotropicMap), function_constant(has_anisotropic_map) ]],
                                               texture2d<float> sheenMap [[  texture(kTextureIndexSheenMap), function_constant(has_sheen_map) ]],
                                               texture2d<float> sheenTintMap [[  texture(kTextureIndexSheenTintMap), function_constant(has_sheenTint_map) ]],
                                               texture2d<float> clearcoatMap [[  texture(kTextureIndexClearcoatMap), function_constant(has_clearcoat_map) ]],
                                               texture2d<float> clearcoatGlossMap [[  texture(kTextureIndexClearcoatGlossMap), function_constant(has_clearcoatGloss_map) ]]
                                               ) {
    
    float4 final_color = float4(0);
    
    LightingParameters parameters = calculateParameters(in,
                                                        uniforms,
                                                        materialUniforms,
                                                        baseColorMap,
                                                        normalMap,
                                                        metallicMap,
                                                        roughnessMap,
                                                        ambientOcclusionMap,
                                                        irradianceMap,
                                                        subsurfaceMap,
                                                        specularMap,
                                                        specularTintMap,
                                                        anisotropicMap,
                                                        sheenMap,
                                                        sheenTintMap,
                                                        clearcoatMap,
                                                        clearcoatGlossMap);
    
    
    // FIXME: discard_fragment may have performance implications.
    // see: http://metalbyexample.com/translucency-and-transparency/
    if ( parameters.baseColor.w <= 0.01f ) {
        discard_fragment();
    }
    
    final_color = illuminate(parameters);
    
    return final_color;
    
}

