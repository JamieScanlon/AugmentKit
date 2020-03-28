//
//  Shaders.metal
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
#import "../BRDFFunctions.h"
#import "../Common.h"

using namespace metal;

//
// Physically Based Shader
//
// This shader uses the following parameters following Disney's "principled" BDRF and
// Which are supported by ModelIO
// see: https://disney-animation.s3.amazonaws.com/library/s2012_pbs_disney_brdf_notes_v2.pdf
// • baseColor - the surface color, usually supplied by texture maps.
// • subsurface - controls diffuse shape using a subsurface approximation.
// • metallic - the metallic-ness (0 = dielectric, 1 = metallic). This is a linear blend between two different models. The metallic model has no diffuse component and also has a tinted incident specular, equal to the base color.
// • specular - incident specular amount. This is in lieu of an explicit index-of-refraction. 12
// • specularTint - a concession for artistic control that tints incident specular towards the base color. Grazing specular is still achromatic.
// • roughness - surface roughness, controls both diffuse and specular response. This is perceptual Roughness. actual roughness = (perceptual roughness)^2
// • anisotropic - degree of anisotropy. This controls the aspect ratio of the specular highlight. (0 = isotropic, 1 = maximally anisotropic).
// • sheen - an additional grazing component, primarily intended for cloth.
// • sheenTint - amount to tint sheen towards base color.
// • clearcoat - a second, special-purpose specular lobe.
// • clearcoatGloss - controls clearcoat glossiness (0 = a “satin” appearance, 1 = a “gloss” appearance). Roughness is 1 - glossiness.
//

#define SPECULAR_ENV_MIP_LEVELS 6

// MARK: - Constants

constant bool has_base_color_map [[ function_constant(kFunctionConstantBaseColorMapIndex) ]];
constant bool has_normal_map [[ function_constant(kFunctionConstantNormalMapIndex) ]];
constant bool has_metallic_map [[ function_constant(kFunctionConstantMetallicMapIndex) ]];
constant bool has_roughness_map [[ function_constant(kFunctionConstantRoughnessMapIndex) ]];
constant bool has_ambient_occlusion_map [[ function_constant(kFunctionConstantAmbientOcclusionMapIndex) ]];
constant bool has_emission_map [[ function_constant(kFunctionConstantEmissionMapIndex) ]];
constant bool has_subsurface_map [[ function_constant(kFunctionConstantSubsurfaceMapIndex) ]];
constant bool has_specular_map [[ function_constant(kFunctionConstantSpecularMapIndex) ]];
constant bool has_specularTint_map [[ function_constant(kFunctionConstantSpecularTintMapIndex) ]];
constant bool has_anisotropic_map [[ function_constant(kFunctionConstantAnisotropicMapIndex) ]];
constant bool has_sheen_map [[ function_constant(kFunctionConstantSheenMapIndex) ]];
constant bool has_sheenTint_map [[ function_constant(kFunctionConstantSheenTintMapIndex) ]];
constant bool has_clearcoat_map [[ function_constant(kFunctionConstantClearcoatMapIndex) ]];
constant bool has_clearcoatGloss_map [[ function_constant(kFunctionConstantClearcoatGlossMapIndex) ]];
constant bool has_any_map = has_base_color_map || has_normal_map || has_metallic_map || has_roughness_map || has_ambient_occlusion_map || has_emission_map || has_subsurface_map || has_specular_map || has_specularTint_map || has_anisotropic_map || has_sheen_map || has_sheenTint_map || has_clearcoat_map || has_clearcoatGloss_map;

// MARK: - Structs

// MARK: Anchors Vertex In
// Per-vertex inputs fed by vertex buffer laid out with MTLVertexDescriptor in Metal API
struct Vertex {
    float3 position      [[attribute(kVertexAttributePosition)]];
    float2 texCoord      [[attribute(kVertexAttributeTexcoord)]];
    float3 normal        [[attribute(kVertexAttributeNormal)]];
    ushort4 jointIndices [[attribute(kVertexAttributeJointIndices)]];
    float4 jointWeights  [[attribute(kVertexAttributeJointWeights)]];
    float3 tangent       [[attribute(kVertexAttributeTangent)]];
//    float3 bitangent
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
    float3 bitangent;
    float3 tangent;
    float2 texCoord [[ function_constant(has_any_map) ]];
    float3 shadowCoord;
    ushort iid;
    float baseMapWeight; // Used in LOD calculations
    float normalMapWeight; // Used in LOD calculations
    float metallicMapWeight; // Used in LOD calculations
    float roughnessMapWeight; // Used in LOD calculations
    float ambientOcclusionMapWeight; // Used in LOD calculations
    float emissionMapWeight; // Used in LOD calculations
    float subsurfaceMapWeight; // Used in LOD calculations
    float specularMapWeight; // Used in LOD calculations
    float specularTintMapWeight; // Used in LOD calculations
    float anisotropicMapWeight; // Used in LOD calculations
    float sheenMapWeight; // Used in LOD calculations
    float sheenTintMapWeight; // Used in LOD calculations
    float clearcoatMapWeight; // Used in LOD calculations
    float clearcoatMapWeightGlossMapWeight; // Used in LOD calculations
};

// MARK: - Pipeline Functions

constexpr sampler linearSampler (address::repeat, min_filter::linear, mag_filter::linear, mip_filter::linear);
constexpr sampler nearestSampler(address::repeat, min_filter::linear, mag_filter::linear, mip_filter::none);
//constexpr sampler mipSampler(address::clamp_to_edge, min_filter::linear, mag_filter::linear, mip_filter::linear);
constexpr sampler reflectiveEnvironmentSampler(address::clamp_to_edge, min_filter::nearest, mag_filter::linear, mip_filter::none);
constexpr sampler cubeSampler(coord::normalized, filter::linear, mip_filter::linear);

float3 computeNormalMap(ColorInOut in, texture2d<float> normalMapTexture) {
    float4 normalMap = float4((float4(normalMapTexture.sample(nearestSampler, float2(in.texCoord)).rgb, 0.0)));
    float3x3 tbn = float3x3(in.tangent, in.bitangent, in.normal);
    return float3(normalize(tbn * normalMap.xyz));
}

float3 computeIsotropicSpecular(LightingParameters parameters) {
    
    // Normal Distribution Function (NDF):
    // The NDF, also known as the specular distribution, describes the distribution of microfacets for the surface.
    // Determines the size and shape of the highlight.
    float D = distribution(parameters.roughness, parameters.nDoth);
    
    // Geometric Shadowing:
    // The geometric shadowing term describes the shadowing from the microfacets.
    // This means ideally it should depend on roughness and the microfacet distribution.
    // The following geometric shadowing models use Smith's method for their respective NDF.
    // Smith breaks G into two components: light and view, and uses the same equation for both.
    float V = visibility(parameters.roughness, parameters.nDotv, parameters.nDotl);
    
    // Fresnel Reflectance:
    // The fraction of incoming light that is reflected as opposed to refracted from a flat surface at a given lighting angle.
    // Fresnel Reflectance goes to 1 as the angle of incidence goes to 90º. The value of Fresnel Reflectance at 0º
    // is the specular reflectance color.
    float3 F = Fresnel(parameters.f0, parameters.lDoth);
    
    return (D * V) * F;
}

/// From Filament implementation
// TODO: Implement. Needs camera position and vertex world position to be passed
//float3 computeAnisotropicSpecular(LightingParameters parameters) {
//
//    float3 l = parameters.lightDirection;
//    float3 t = parameters.anisotropicT;
//    float3 b = parameters.anisotropicB;
//    float3 v = normalize(cameraPosition - worldPosition);
//    float3 h = parameters.halfVector
//
//    float tDotv = dot(t, v);
//    float bDotv = dot(b, v);
//    float tDotl = dot(t, l);
//    float bDotl = dot(b, l);
//    float tDoth = dot(t, h);
//    float bDoth = dot(b, h);
//
//    // Anisotropic parameters: at and ab are the roughness along the tangent and bitangent
//    // to simplify materials, we derive them from a single roughness parameter
//    // Kulla 2017, "Revisiting Physically Based Shading at Imageworks"
//    // MIN_LINEAR_ROUGHNESS = 0.002025
//    float at = max(parameters.roughness * (1.0 + pixel.anisotropy), 0.002025);
//    float ab = max(pixel.roughness * (1.0 - pixel.anisotropy), 0.002025);
//
//    // specular anisotropic BRDF
//    float D = distributionAnisotropic(at, ab, tDoth, bDoth, parameters.nDoth);
//    float V = visibilityAnisotropic(parameters.roughness, at, ab, tDotv, bDotv, tDotl, bDotl, parameters.nDotv, parameters.nDotl);
//    float3  F = fresnel(parameters.f0, parameters.lDoth);
//
//    return (D * V) * F;
//}

float3 computeDiffuse(LightingParameters parameters) {
    
    // Filament implementation
    
    // For Cloth or Clearcoat Gloss use the following
//    float3 diffuseColor = (1.0 - parameters.metalness) * parameters.baseColor.rgb;
    
    // For standard model diffuse color use the following
    float3 diffuseColor = parameters.baseColor.rgb;
    
    diffuseColor = diffuseColor * diffuse(parameters.roughness, parameters.nDotv, parameters.nDotl, parameters.lDoth);
    return diffuseColor;
    
}

float3 computeIBLDiffuse(LightingParameters parameters, texturecube<float> diffuseEnvTexture) {
    
    float3 diffuseColor = (1.0 - parameters.metalness) * parameters.baseColor.rgb;
    float3 diffuseLight = diffuseEnvTexture.sample(cubeSampler, parameters.normal).rgb;
    diffuseLight *= parameters.ambientIntensity;
    
    float3 iblContribution = diffuseLight * diffuseColor;
    return iblContribution;
}

float3 computeSpecular(LightingParameters parameters) {
    
    // Filament implementation
    
    // Calculate BDRF
    // B-idirectional
    // R-eflectance
    // D-istribution
    // F-unction
    // BDRF is a function of light direction and view (camera/eye) direction
    // See: https://www.youtube.com/watch?v=j-A0mwsJRmk
    
    // TODO: Anisotropic
    
    return computeIsotropicSpecular(parameters);
}

//float3 computeIBLSpecular(LightingParameters parameters, texturecube<float> specularEnvTexture, texturecube<float> brdfLUT) {
//    
//    float mipCount = SPECULAR_ENV_MIP_LEVELS;
//    float lod = parameters.perceptualRoughness * (mipCount - 1);
//    float2 brdf = brdfLUT.sample(cubeSampler, float2(parameters.nDotv, parameters.perceptualRoughness)).xy;
//    
//    float3 specularLight(0);
//    if (mipCount > 1) {
//        specularLight = specularEnvTexture.sample(cubeSampler, parameters.reflectedVector, level(lod)).rgb;
//    } else {
//        specularLight = specularEnvTexture.sample(cubeSampler, parameters.reflectedVector).rgb;
//    }
//    specularLight *= parameters.ambientIntensity;
//    
//    float3 specularColor = mix(0.04, parameters.baseColor.rgb, parameters.metalness);
//    
//    float3 iblContribution = specularLight * ((specularColor * brdf.x) + brdf.y);
//    return iblContribution;
//}

/// From filament implementation
float2 computeClearcoatLobe(LightingParameters parameters) {
    
    // clear coat specular lobe
    float clearCoatRoughness = (1.0 - parameters.clearcoatGloss) * (1.0 - parameters.clearcoatGloss);
    float D = distributionClearCoat(clearCoatRoughness, parameters.nDoth);
    float V = visibilityClearCoat(parameters.lDoth);
    float F = F_Schlick(0.04, 1.0, parameters.lDoth) * parameters.clearcoat; // fix IOR to 1.5
    
    float clearCoat = D * V * F;
    return float2(clearCoat, F);
    
}

float3 computeClearcoat(LightingParameters parameters) {
    
    return float3(0);
    
    // Method 1: filament implementation:
//    float clearCoat = computeClearcoatLobe(parameters).x;
//    return float3(clearCoat);
    
    // Method 2
    
    // For Dielectics (non-metals) the Fresnel for 0º typically ranges from 0.02 (water) to 0.1 (diamond) but for
    // the sake of simplicity, it is common to set this value as a constant of 0.04 (plastic/glass) for all materials.
    //    float3 Fr = mix(0.1, 0.04, parameters.fresnelLDotH);
    //    float Dr = TrowbridgeReitzNDF(mix(.6, 0.001, parameters.clearcoatGloss), parameters.nDoth);
    //    float clearcoatRoughness = sqr(parameters.roughness * 0.5 + 0.5);
    //    float Gr = V_SmithG_GGX(parameters.nDotl, clearcoatRoughness) * V_SmithG_GGX(parameters.nDotv, clearcoatRoughness);
    //
    //    float3 clearcoatOutput = parameters.clearcoat * Gr * Fr * Dr * parameters.directionalLightCol;
    //    return clearcoatOutput;
    
}

float3 computeSheen(LightingParameters parameters) {
    
    // Bypassed for now
    return float3(0);
    
    // Method 1
    float3 Csheen = mix(float3(1.0), parameters.baseColorHueSat, parameters.sheenTint);
    float3 Fsheen = Csheen * parameters.fresnelNDotV * parameters.sheen;

//    float3 light_color = float3(2.0 * M_PI_F * 0.3) * (parameters.nDotl + parameters.emissionColor - parameters.ambientOcclusion);
    float3 sheenOutput = Fsheen; // * light_color;
    return sheenOutput;
    
}

// all input colors must be linear, not SRGB.
float4 illuminate(LightingParameters parameters) {
    
    // DIFFUSE
    float3 diffuseOut = computeDiffuse(parameters);
    
    // SPECULAR
    float3 specularOut = computeSpecular(parameters);
    
//    float3 color;
//    if clearcoat {
//        float2 ccResult = computeClearcoatLobe(parameters)
//        float Fcc = ccResult.y;
//        float clearCoat = ccResult.x;
//        // Energy compensation and absorption; the clear coat Fresnel term is
//        // squared to take into account both entering through and exiting through
//        // the clear coat layer
//        float attenuation = 1.0 - Fcc;
//
//        if hasNormal {
//            float3 color = (diffuseOut + specularOut * (parameters.energyCompensation * attenuation)) * attenuation * parameters.nDotl;
//
//            // If the material has a normal map, we want to use the geometric normal
//            // instead to avoid applying the normal map details to the clear coat layer
//            float clearCoatNoL = saturate(dot(shading_clearCoatNormal, light.l));
//            color += clearCoat * clearCoatNoL;
//
//            // Early exit to avoid the extra multiplication by NoL
//            return (color * parameters.colorIntensity.rgb) * (parameters.colorIntensity.w * parameters.attenuation * parameters.ambientOcclusion);
//        } else {
//            color = (diffuseOut + specularOut * (parameters.energyCompensation * attenuation)) * attenuation + clearCoat;
//        }
//    } else {
//        // The energy compensation term is used to counteract the darkening effect
//        // at high roughness
//        color = diffuseOut + specularOut * parameters.energyCompensation;
//    }
//    return (color * parameters.colorIntensity.rgb) * (parameters.colorIntensity.w * parameters.attenuation * parameters.nDotl * parameters.ambientOcclusion);

    return float4(parameters.ambientOcclusion, 1) * float4(diffuseOut + specularOut + parameters.emissionColor.xyz, 1) * float4(1.0, 1.0, 1.0, parameters.baseColor.w);

}

LightingParameters calculateParameters(ColorInOut in,
                                       constant MaterialUniforms & materialUniforms,
                                       constant EnvironmentUniforms *environmentUniforms,
                                       texture2d<float> baseColorMap [[ function_constant(has_base_color_map) ]],
                                       texture2d<float> normalMap [[ function_constant(has_normal_map) ]],
                                       texture2d<float> metallicMap [[ function_constant(has_metallic_map) ]],
                                       texture2d<float> roughnessMap [[ function_constant(has_roughness_map) ]],
                                       texture2d<float> ambientOcclusionMap [[ function_constant(has_ambient_occlusion_map) ]],
                                       texture2d<float> emissionMap [[ function_constant(has_emission_map) ]],
                                       texture2d<float> subsurfaceMap [[ function_constant(has_subsurface_map) ]],
                                       texture2d<float> specularMap [[ function_constant(has_specular_map) ]],
                                       texture2d<float> specularTintMap [[ function_constant(has_specularTint_map) ]],
                                       texture2d<float> anisotropicMap [[ function_constant(has_anisotropic_map) ]],
                                       texture2d<float> sheenMap [[ function_constant(has_sheen_map) ]],
                                       texture2d<float> sheenTintMap [[ function_constant(has_sheenTint_map) ]],
                                       texture2d<float> clearcoatMap [[ function_constant(has_clearcoat_map) ]],
                                       texture2d<float> clearcoatGlossMap [[ function_constant(has_clearcoatGloss_map) ]],
                                       texturecube<float> environmentCubemap [[ texture(kTextureIndexEnvironmentMap) ]]
                                       ) {
    LightingParameters parameters;
    
    // Base Color
    if(has_base_color_map) {
        float mapWeight = in.baseMapWeight;
        float4 baseColor = baseColorMap.sample(linearSampler, in.texCoord.xy);
        baseColor *= mapWeight;
        float4 uniformContribution = (1.f - mapWeight) * materialUniforms.baseColor;
        baseColor += uniformContribution;
        parameters.baseColor = float4(baseColor.xyz, baseColor.w * materialUniforms.opacity);
    } else {
        float4 baseColor = materialUniforms.baseColor;
        parameters.baseColor = float4(baseColor.xyz, baseColor.w * materialUniforms.opacity);
    }
    
    // Normal
    if(has_normal_map) {
        float mapWeight = in.normalMapWeight;
        float3 normal = computeNormalMap(in, normalMap);
        normal *= mapWeight;
        float3 uniformContribution = (1.f - mapWeight) * normalize(in.normal);
        normal += uniformContribution;
        parameters.normal = normal;
    } else {
        float3 normal = normalize(in.normal);
        parameters.normal = normal;
    }
    
    // Matallic
    if(has_metallic_map) {
        float mapWeight = in.metallicMapWeight;
        float metalness = metallicMap.sample(linearSampler, in.texCoord.xy).x;
        metalness *= mapWeight;
        float uniformContribution = (1.f - mapWeight) * materialUniforms.metalness;
        metalness += uniformContribution;
        parameters.metalness = metalness;
    } else {
        float metalness = materialUniforms.metalness;
        parameters.metalness = metalness;
    }
    
    // Roughness
    if(has_roughness_map) {
        float mapWeight = in.roughnessMapWeight;
        float perceptualRoughness = max(roughnessMap.sample(linearSampler, in.texCoord.xy).x, 0.001f);
        perceptualRoughness *= mapWeight;
        float uniformContribution = (1.f - mapWeight) * materialUniforms.roughness;
        perceptualRoughness += uniformContribution;
        parameters.perceptualRoughness = clamp(perceptualRoughness, 0.045, 1.0);
    } else {
        float perceptualRoughness = materialUniforms.roughness;
        parameters.perceptualRoughness = clamp(perceptualRoughness, 0.045, 1.0);
    }
    
    // Subsurface
    if(has_subsurface_map) {
        float mapWeight = in.subsurfaceMapWeight;
        float subsurface = subsurfaceMap.sample(linearSampler, in.texCoord.xy).x;
        subsurface *= mapWeight;
        float uniformContribution = (1.f - mapWeight) * materialUniforms.subsurface;
        subsurface += uniformContribution;
        parameters.subsurface = subsurface;
    } else {
        float subsurface = materialUniforms.subsurface;
        parameters.subsurface = subsurface;
    }
    
    // Ambient Occlusion
    if(has_ambient_occlusion_map) {
        float mapWeight = in.ambientOcclusionMapWeight;
        float ambientOcclusion = ambientOcclusionMap.sample(linearSampler, in.texCoord.xy).x;
        ambientOcclusion *= mapWeight;
        float uniformContribution = (1.f - mapWeight) * materialUniforms.ambientOcclusion;
        ambientOcclusion += uniformContribution;
        parameters.ambientOcclusion = ambientOcclusion;
    } else {
        float ambientOcclusion = materialUniforms.ambientOcclusion;
        parameters.ambientOcclusion = ambientOcclusion;
    }
    
    // Emission
    if(has_emission_map) {
        float mapWeight = in.emissionMapWeight;
        float4 emissionColor = emissionMap.sample(linearSampler, in.texCoord.xy);
        emissionColor *= mapWeight;
        float4 uniformContribution = (1.f - mapWeight) * materialUniforms.emissionColor;
        emissionColor += uniformContribution;
        parameters.emissionColor = emissionColor;
    } else {
        float4 emissionColor = materialUniforms.emissionColor;
        parameters.emissionColor = emissionColor;
    }
    
    // Specular
    if(has_specular_map) {
        float mapWeight = in.specularMapWeight;
        float specular = specularMap.sample(linearSampler, in.texCoord.xy).x;
        specular *= mapWeight;
        float uniformContribution = (1.f - mapWeight) * materialUniforms.specular;
        specular += uniformContribution;
        parameters.specular = specular;
    } else {
        float specular = materialUniforms.specular;
        parameters.specular = specular;
    }
    
    // Specular Tint
    if(has_specularTint_map) {
        float mapWeight = in.specularTintMapWeight;
        float specularTint = specularTintMap.sample(linearSampler, in.texCoord.xy).x;
        specularTint *= mapWeight;
        float uniformContribution = (1.f - mapWeight) * materialUniforms.specularTint;
        specularTint += uniformContribution;
        parameters.specularTint = specularTint;
    } else {
        float specularTint = materialUniforms.specularTint;
        parameters.specularTint = specularTint;
    }
    
    // Sheen
    if(has_sheen_map) {
        float mapWeight = in.sheenMapWeight;
        float sheen = sheenMap.sample(linearSampler, in.texCoord.xy).x;
        sheen *= mapWeight;
        float uniformContribution = (1.f - mapWeight) * materialUniforms.sheen;
        sheen += uniformContribution;
        parameters.sheen = sheen;
    } else {
        float sheen = materialUniforms.sheen;
        parameters.sheen = sheen;
    }
    
    // Sheen Tint
    if(has_sheenTint_map) {
        float mapWeight = in.sheenTintMapWeight;
        float sheenTint = sheenTintMap.sample(linearSampler, in.texCoord.xy).x;
        sheenTint *= mapWeight;
        float uniformContribution = (1.f - mapWeight) * materialUniforms.sheenTint;
        sheenTint += uniformContribution;
        parameters.sheenTint = sheenTint;
    } else {
        float sheenTint = materialUniforms.sheenTint;
        parameters.sheenTint = sheenTint;
    }
    
    // Anisotropic
    if(has_anisotropic_map) {
        float mapWeight = in.anisotropicMapWeight;
        float anisotropic = anisotropicMap.sample(linearSampler, in.texCoord.xy).x;
        anisotropic *= mapWeight;
        float uniformContribution = (1.f - mapWeight) * materialUniforms.anisotropic;
        anisotropic += uniformContribution;
        parameters.anisotropic = anisotropic;
    } else {
        float anisotropic = materialUniforms.anisotropic;
        parameters.anisotropic = anisotropic;
    }
    
    // Clearcoat
    if(has_clearcoat_map) {
        float mapWeight = in.clearcoatMapWeight;
        float clearcoat = clearcoatMap.sample(linearSampler, in.texCoord.xy).x;
        clearcoat *= mapWeight;
        float uniformContribution = (1.f - mapWeight) * materialUniforms.clearcoat;
        clearcoat += uniformContribution;
        parameters.clearcoat = clearcoat;
    } else {
        float clearcoat = materialUniforms.clearcoat;
        parameters.clearcoat = clearcoat;
    }
    
    // Clearcoat Gloss
    if(has_clearcoatGloss_map) {
        float mapWeight = in.clearcoatMapWeightGlossMapWeight;
        float clearcoatGloss = clearcoatGlossMap.sample(linearSampler, in.texCoord.xy).x;
        clearcoatGloss *= mapWeight;
        float uniformContribution = (1.f - mapWeight) * materialUniforms.clearcoatGloss;
        clearcoatGloss += uniformContribution;
        parameters.clearcoatGloss = clearcoatGloss;
    } else {
        float clearcoatGloss = materialUniforms.clearcoatGloss;
        parameters.clearcoatGloss = clearcoatGloss;
    }
    
    parameters.baseColorLuminance = 0.3 * parameters.baseColor.x + 0.6 * parameters.baseColor.y + 0.1 * parameters.baseColor.z; // approximation of luminanc
    parameters.baseColorHueSat = parameters.baseColorLuminance > 0.0 ? parameters.baseColor.rgb / parameters.baseColorLuminance : float3(1); // remove luminance
    parameters.viewDir = -normalize(in.eyePosition);
    parameters.reflectedVector = reflect(-parameters.viewDir, parameters.normal);
    parameters.reflectedColor = (environmentUniforms[in.iid].hasEnvironmentMap == 1) ? environmentCubemap.sample(reflectiveEnvironmentSampler, parameters.reflectedVector).xyz : float3(0, 0, 0);
    // clamp to minimum roucgness. MIN_PERCEPTUAL_ROUGHNESS = 0.045, MIN_ROUGHNESS = 0.002025
//    float perceptualRoughness = has_roughness_map ? max(roughnessMap.sample(linearSampler, in.texCoord.xy).x, 0.001f) : materialUniforms.roughness;
//    parameters.perceptualRoughness = clamp(perceptualRoughness, 0.045, 1.0);
    float roughness = parameters.perceptualRoughness * parameters.perceptualRoughness;
    parameters.roughness = clamp(roughness, 0.002025, 1.0);
//    uint8_t mipLevel = parameters.roughness * emissionMap.get_num_mip_levels();
//    parameters.emissionColor = has_emission_map ? emissionMap.sample(mipSampler, parameters.reflectedVector, level(mipLevel)).xyz : materialUniforms.emissionColor.xyz;
//    parameters.emissionColor = has_emission_map ? emissionMap.sample(linearSampler, in.texCoord.xy) : materialUniforms.emissionColor;
    parameters.directionalLightCol = environmentUniforms[in.iid].directionalLightColor;
    parameters.ambientLightCol = environmentUniforms[in.iid].ambientLightColor;
    parameters.ambientIntensity = environmentUniforms[in.iid].ambientLightIntensity;
    parameters.lightDirection = normalize(in.eyePosition - environmentUniforms[in.iid].directionalLightDirection);
    // Light falls off based on how closely aligned the surface normal is to the light direction.
    // This is the dot product of the light direction vector and vertex normal.
    // The smaller the angle between those two vectors, the higher this value,
    // and the stronger the diffuse lighting effect should be.
    parameters.nDotl = max(0.001f,saturate(dot(parameters.normal, parameters.lightDirection)));
    // Calculate the halfway vector between the light direction and the direction they eye is looking
    parameters.halfVector = normalize(parameters.lightDirection + parameters.viewDir);
    parameters.nDoth = max(0.001f,saturate(dot(parameters.normal, parameters.halfVector)));
    parameters.nDotv = max(0.001f,saturate(dot(parameters.normal, parameters.viewDir)));
    parameters.lDoth = max(0.001f,saturate(dot(parameters.lightDirection, parameters.halfVector)));
    parameters.f0 = parameters.specular * mix(float3(1.0), parameters.baseColorHueSat, parameters.specularTint);
    parameters.fresnelNDotL = Fresnel(parameters.f0, parameters.nDotl);
    parameters.fresnelNDotV = Fresnel(parameters.f0, parameters.nDotv);
    parameters.fresnelLDotH = Fresnel(parameters.f0, parameters.lDoth);
    
    return parameters;
    
}

// MARK: - AugmentKit Shaders

// MARK: Geometry vertex function

/// Used to render Models generated by Raw Vertex Buffers
vertex ColorInOut rawGeometryVertexTransform(Vertex in [[stage_in]],
                                             device RawVertexBuffer *vertexData [[ buffer(kBufferIndexRawVertexData) ]],
                                             device PrecalculatedParameters *arguments [[ buffer(kBufferIndexPrecalculationOutputBuffer) ]],
                                             constant int &drawCallIndex [[ buffer(kBufferIndexDrawCallIndex) ]],
                                             constant int &drawCallGroupIndex [[ buffer(kBufferIndexDrawCallGroupIndex) ]],
                                             uint vid [[vertex_id]],
                                             ushort iid [[instance_id]]) {
    ColorInOut out;
    
    // Make position a float4 to perform 4x4 matrix math on it
    float4 position = float4(vertexData[vid].position, 1.0);
    int argumentBufferIndex = drawCallIndex;
    
    float3x3 normalMatrix = arguments[argumentBufferIndex].normalMatrix;
    float4x4 modelViewMatrix = arguments[argumentBufferIndex].modelViewMatrix;
    float4x4 modelViewProjectionMatrix = arguments[argumentBufferIndex].modelViewProjectionMatrix;
    
    // Calculate the position of our vertex in clip space and output for clipping and rasterization
    out.position = modelViewProjectionMatrix * position;
    
    // Calculate the positon of our vertex in eye space
    out.eyePosition = float3((modelViewMatrix * position).xyz);
    
    // Rotate our normals to world coordinates
    out.normal = normalMatrix * vertexData[vid].normal;
    out.tangent = normalMatrix * vertexData[vid].tangent;
    out.bitangent = normalMatrix * cross(vertexData[vid].normal, vertexData[vid].tangent);
    
    // Texture Coord
    // Pass along the texture coordinate of our vertex such which we'll use to sample from texture's
    //   in our fragment function, if we need it
    if (has_any_map) {
        out.texCoord = float2(vertexData[vid].texCoord.x, 1.0f - vertexData[vid].texCoord.y);
    }
    
    // Shadow Coord
    out.shadowCoord = (arguments[argumentBufferIndex].shadowMVPTransformMatrix * out.position).xyz;
    
    // Instance ID
    out.iid = iid;
    
    // LOD
    out.baseMapWeight = arguments[argumentBufferIndex].mapWeights[0];
    out.normalMapWeight = arguments[argumentBufferIndex].mapWeights[1];
    out.metallicMapWeight = arguments[argumentBufferIndex].mapWeights[2];
    out.roughnessMapWeight = arguments[argumentBufferIndex].mapWeights[3];
    out.ambientOcclusionMapWeight = arguments[argumentBufferIndex].mapWeights[4];
    out.emissionMapWeight = arguments[argumentBufferIndex].mapWeights[5];
    out.subsurfaceMapWeight = arguments[argumentBufferIndex].mapWeights[6];
    out.specularMapWeight = arguments[argumentBufferIndex].mapWeights[7];
    out.specularTintMapWeight = arguments[argumentBufferIndex].mapWeights[8];
    out.anisotropicMapWeight = arguments[argumentBufferIndex].mapWeights[9];
    out.sheenMapWeight = arguments[argumentBufferIndex].mapWeights[10];
    out.sheenTintMapWeight = arguments[argumentBufferIndex].mapWeights[11];
    out.clearcoatMapWeight = arguments[argumentBufferIndex].mapWeights[12];
    out.clearcoatMapWeightGlossMapWeight = arguments[argumentBufferIndex].mapWeights[13];
    
    return out;
}

/// Used to render Models generated by MDLAssets
vertex ColorInOut anchorGeometryVertexTransform(Vertex in [[stage_in]],
                                                device PrecalculatedParameters *arguments [[ buffer(kBufferIndexPrecalculationOutputBuffer) ]],
                                                constant int &drawCallIndex [[ buffer(kBufferIndexDrawCallIndex) ]],
                                                constant int &drawCallGroupIndex [[ buffer(kBufferIndexDrawCallGroupIndex) ]],
                                                uint vid [[vertex_id]],
                                                ushort iid [[instance_id]]) {
    ColorInOut out;
    
    // Make position a float4 to perform 4x4 matrix math on it
    float4 position = float4(in.position, 1.0);
    int argumentBufferIndex = drawCallIndex;
    
    float3x3 normalMatrix = arguments[argumentBufferIndex].normalMatrix;
    float4x4 modelViewMatrix = arguments[argumentBufferIndex].modelViewMatrix;
    float4x4 modelViewProjectionMatrix = arguments[argumentBufferIndex].modelViewProjectionMatrix;
    
    // Calculate the position of our vertex in clip space and output for clipping and rasterization
    out.position = modelViewProjectionMatrix * position;
    
    // Calculate the positon of our vertex in eye space
    out.eyePosition = float3((modelViewMatrix * position).xyz);
    
    // Rotate our normals to world coordinates
    out.normal = normalMatrix * in.normal;
    out.tangent = normalMatrix * in.tangent;
    out.bitangent = normalMatrix * cross(in.normal, in.tangent);
    
    // Texture Coord
    // Pass along the texture coordinate of our vertex such which we'll use to sample from texture's
    //   in our fragment function, if we need it
    if (has_any_map) {
        out.texCoord = float2(in.texCoord.x, 1.0f - in.texCoord.y);
    }
    
    // Shadow Coord
    out.shadowCoord = (arguments[argumentBufferIndex].shadowMVPTransformMatrix * out.position).xyz;
    
    // Instance ID
    out.iid = iid;
    
    // LOD
    out.baseMapWeight = arguments[argumentBufferIndex].mapWeights[0];
    out.normalMapWeight = arguments[argumentBufferIndex].mapWeights[1];
    out.metallicMapWeight = arguments[argumentBufferIndex].mapWeights[2];
    out.roughnessMapWeight = arguments[argumentBufferIndex].mapWeights[3];
    out.ambientOcclusionMapWeight = arguments[argumentBufferIndex].mapWeights[4];
    out.emissionMapWeight = arguments[argumentBufferIndex].mapWeights[5];
    out.subsurfaceMapWeight = arguments[argumentBufferIndex].mapWeights[6];
    out.specularMapWeight = arguments[argumentBufferIndex].mapWeights[7];
    out.specularTintMapWeight = arguments[argumentBufferIndex].mapWeights[8];
    out.anisotropicMapWeight = arguments[argumentBufferIndex].mapWeights[9];
    out.sheenMapWeight = arguments[argumentBufferIndex].mapWeights[10];
    out.sheenTintMapWeight = arguments[argumentBufferIndex].mapWeights[11];
    out.clearcoatMapWeight = arguments[argumentBufferIndex].mapWeights[12];
    out.clearcoatMapWeightGlossMapWeight = arguments[argumentBufferIndex].mapWeights[13];
    
    return out;
}

// MARK: Geometry vertex function with skinning

/// Used to render Models generated by MDLAssets with skin animation
vertex ColorInOut anchorGeometryVertexTransformSkinned(Vertex in [[stage_in]],
                                                       constant float4x4 *palette [[ buffer(kBufferIndexMeshPalettes) ]],
                                                       constant int &paletteStartIndex [[ buffer(kBufferIndexMeshPaletteIndex) ]],
                                                       constant int &paletteSize [[ buffer(kBufferIndexMeshPaletteSize) ]],
                                                       device PrecalculatedParameters *arguments [[ buffer(kBufferIndexPrecalculationOutputBuffer) ]],
                                                       constant int &drawCallIndex [[ buffer(kBufferIndexDrawCallIndex) ]],
                                                       constant int &drawCallGroupIndex [[ buffer(kBufferIndexDrawCallGroupIndex) ]],
                                                       uint vid [[vertex_id]],
                                                       ushort iid [[instance_id]]) {
    
    ColorInOut out;
    
    // Make position a float4 to perform 4x4 matrix math on it
    float4 position = float4(in.position, 1.0f);
    int argumentBufferIndex = drawCallIndex;
    
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
    
    float4 modelTangent = float4(in.tangent, 0.0f);
    float4 skinnedTangent = weights[0] * (palette[jointIndex[0]] * modelTangent) +
        weights[1] * (palette[jointIndex[1]] * modelTangent) +
        weights[2] * (palette[jointIndex[2]] * modelTangent) +
        weights[3] * (palette[jointIndex[3]] * modelTangent);
    

    float3x3 normalMatrix = arguments[argumentBufferIndex].normalMatrix;
    float4x4 modelViewMatrix = arguments[argumentBufferIndex].modelViewMatrix;
    float4x4 modelViewProjectionMatrix = arguments[argumentBufferIndex].modelViewProjectionMatrix;
    
    // Calculate the position of our vertex in clip space and output for clipping and rasterization
    out.position = modelViewProjectionMatrix * skinnedPosition;
    
    // Calculate the positon of our vertex in eye space
    out.eyePosition = float3((modelViewMatrix * skinnedPosition).xyz);
    
    // Rotate our normals to world coordinates
    out.normal = normalMatrix * skinnedNormal.xyz;
    out.tangent = normalMatrix * skinnedTangent.xyz;
    out.bitangent = normalMatrix * cross(skinnedNormal.xyz, skinnedTangent.xyz);
    
    // Pass along the texture coordinate of our vertex such which we'll use to sample from texture's
    //   in our fragment function, if we need it
    if (has_any_map) {
        out.texCoord = float2(in.texCoord.x, 1.0f - in.texCoord.y);
    }
    
    // Shadow Coord
    out.shadowCoord = (arguments[argumentBufferIndex].shadowMVPTransformMatrix * out.position).xyz;
    
    // Instance ID
    out.iid = iid;
    
    // LOD
    out.baseMapWeight = arguments[argumentBufferIndex].mapWeights[0];
    out.normalMapWeight = arguments[argumentBufferIndex].mapWeights[1];
    out.metallicMapWeight = arguments[argumentBufferIndex].mapWeights[2];
    out.roughnessMapWeight = arguments[argumentBufferIndex].mapWeights[3];
    out.ambientOcclusionMapWeight = arguments[argumentBufferIndex].mapWeights[4];
    out.emissionMapWeight = arguments[argumentBufferIndex].mapWeights[5];
    out.subsurfaceMapWeight = arguments[argumentBufferIndex].mapWeights[6];
    out.specularMapWeight = arguments[argumentBufferIndex].mapWeights[7];
    out.specularTintMapWeight = arguments[argumentBufferIndex].mapWeights[8];
    out.anisotropicMapWeight = arguments[argumentBufferIndex].mapWeights[9];
    out.sheenMapWeight = arguments[argumentBufferIndex].mapWeights[10];
    out.sheenTintMapWeight = arguments[argumentBufferIndex].mapWeights[11];
    out.clearcoatMapWeight = arguments[argumentBufferIndex].mapWeights[12];
    out.clearcoatMapWeightGlossMapWeight = arguments[argumentBufferIndex].mapWeights[13];
    
    return out;
    
}

// MARK: Anchor fragment function with materials

fragment float4 anchorGeometryFragmentLighting(ColorInOut in [[stage_in]],
                                               constant MaterialUniforms &materialUniforms [[ buffer(kBufferIndexMaterialUniforms) ]],
                                               constant EnvironmentUniforms *environmentUniforms [[ buffer(kBufferIndexEnvironmentUniforms) ]],
                                               constant AnchorEffectsUniforms *anchorEffectsUniforms [[ buffer(kBufferIndexAnchorEffectsUniforms) ]],
                                               texture2d<float> baseColorMap [[ texture(kTextureIndexColor), function_constant(has_base_color_map) ]],
                                               texture2d<float> normalMap    [[ texture(kTextureIndexNormal), function_constant(has_normal_map) ]],
                                               texture2d<float> metallicMap  [[ texture(kTextureIndexMetallic), function_constant(has_metallic_map) ]],
                                               texture2d<float> roughnessMap  [[ texture(kTextureIndexRoughness), function_constant(has_roughness_map) ]],
                                               texture2d<float> ambientOcclusionMap  [[ texture(kTextureIndexAmbientOcclusion), function_constant(has_ambient_occlusion_map) ]],
                                               texture2d<float> emissionMap [[texture(kTextureIndexEmissionMap), function_constant(has_emission_map)]],
                                               texture2d<float> subsurfaceMap [[texture(kTextureIndexSubsurfaceMap), function_constant(has_subsurface_map)]],
                                               texture2d<float> specularMap [[  texture(kTextureIndexSpecularMap), function_constant(has_specular_map) ]],
                                               texture2d<float> specularTintMap [[  texture(kTextureIndexSpecularTintMap), function_constant(has_specularTint_map) ]],
                                               texture2d<float> anisotropicMap [[  texture(kTextureIndexAnisotropicMap), function_constant(has_anisotropic_map) ]],
                                               texture2d<float> sheenMap [[  texture(kTextureIndexSheenMap), function_constant(has_sheen_map) ]],
                                               texture2d<float> sheenTintMap [[  texture(kTextureIndexSheenTintMap), function_constant(has_sheenTint_map) ]],
                                               texture2d<float> clearcoatMap [[  texture(kTextureIndexClearcoatMap), function_constant(has_clearcoat_map) ]],
                                               texture2d<float> clearcoatGlossMap [[  texture(kTextureIndexClearcoatGlossMap), function_constant(has_clearcoatGloss_map) ]],
                                               texturecube<float> environmentCubemap [[  texture(kTextureIndexEnvironmentMap) ]],
                                               depth2d<float> shadowMap [[ texture(kTextureIndexShadowMap) ]],
                                               texturecube<float> diffuseEnvTexture [[ texture(kTextureIndexDiffuseIBLMap) ]],
                                               texturecube<float> specularEnvTexture [[ texture(kTextureIndexSpecularIBLMap) ]],
                                               texture2d<float> brdfLUT [[ texture(kTextureIndexBDRFLookupMap)] ]
                                               ) {
    
    ushort iid = in.iid;
    
    LightingParameters parameters = calculateParameters(in,
                                                        materialUniforms,
                                                        environmentUniforms,
                                                        baseColorMap,
                                                        normalMap,
                                                        metallicMap,
                                                        roughnessMap,
                                                        ambientOcclusionMap,
                                                        emissionMap,
                                                        subsurfaceMap,
                                                        specularMap,
                                                        specularTintMap,
                                                        anisotropicMap,
                                                        sheenMap,
                                                        sheenTintMap,
                                                        clearcoatMap,
                                                        clearcoatGlossMap,
                                                        environmentCubemap);
    
    
    // FIXME: discard_fragment may have performance implications.
    // see: http://metalbyexample.com/translucency-and-transparency/
    if ( parameters.baseColor.w <= 0.01f ) {
        discard_fragment();
    }

    float4 intermediateColor = illuminate(parameters);
    
    // Apply effects
    float4 finalColor = float4(intermediateColor.rgb * anchorEffectsUniforms[iid].tint, intermediateColor.a * anchorEffectsUniforms[iid].alpha);
    
    return finalColor;
    
}

// MARK: Anchor fragment shader that uses the base color only

fragment float4 anchorGeometryFragmentLightingSimple(ColorInOut in [[stage_in]],
                                               constant MaterialUniforms &materialUniforms [[ buffer(kBufferIndexMaterialUniforms) ]],
                                               constant EnvironmentUniforms *environmentUniforms [[ buffer(kBufferIndexEnvironmentUniforms) ]],
                                               constant AnchorEffectsUniforms *anchorEffectsUniforms [[ buffer(kBufferIndexAnchorEffectsUniforms) ]],
                                               texture2d<float> baseColorMap [[ texture(kTextureIndexColor), function_constant(has_base_color_map) ]],
                                               texture2d<float> normalMap    [[ texture(kTextureIndexNormal), function_constant(has_normal_map) ]],
                                               texture2d<float> metallicMap  [[ texture(kTextureIndexMetallic), function_constant(has_metallic_map) ]],
                                               texture2d<float> roughnessMap  [[ texture(kTextureIndexRoughness), function_constant(has_roughness_map) ]],
                                               texture2d<float> ambientOcclusionMap  [[ texture(kTextureIndexAmbientOcclusion), function_constant(has_ambient_occlusion_map) ]],
                                               texture2d<float> emissionMap [[texture(kTextureIndexEmissionMap), function_constant(has_emission_map)]],
                                               texture2d<float> subsurfaceMap [[texture(kTextureIndexSubsurfaceMap), function_constant(has_subsurface_map)]],
                                               texture2d<float> specularMap [[  texture(kTextureIndexSpecularMap), function_constant(has_specular_map) ]],
                                               texture2d<float> specularTintMap [[  texture(kTextureIndexSpecularTintMap), function_constant(has_specularTint_map) ]],
                                               texture2d<float> anisotropicMap [[  texture(kTextureIndexAnisotropicMap), function_constant(has_anisotropic_map) ]],
                                               texture2d<float> sheenMap [[  texture(kTextureIndexSheenMap), function_constant(has_sheen_map) ]],
                                               texture2d<float> sheenTintMap [[  texture(kTextureIndexSheenTintMap), function_constant(has_sheenTint_map) ]],
                                               texture2d<float> clearcoatMap [[  texture(kTextureIndexClearcoatMap), function_constant(has_clearcoat_map) ]],
                                               texture2d<float> clearcoatGlossMap [[  texture(kTextureIndexClearcoatGlossMap), function_constant(has_clearcoatGloss_map) ]],
                                               texturecube<float> environmentCubemap [[  texture(kTextureIndexEnvironmentMap) ]]
                                               ) {
    
    ushort iid = in.iid;
    
    float4 intermediateColor = has_base_color_map ? baseColorMap.sample(linearSampler, in.texCoord.xy) : materialUniforms.baseColor;
    
    // FIXME: discard_fragment may have performance implications.
    // see: http://metalbyexample.com/translucency-and-transparency/
    if ( intermediateColor.w <= 0.01f ) {
        discard_fragment();
    }
    
    // Apply effects
    float4 finalColor = float4(intermediateColor.rgb * anchorEffectsUniforms[iid].tint, intermediateColor.a * anchorEffectsUniforms[iid].alpha);
    
    return finalColor;
    
}

fragment float4 anchorGeometryFragmentLightingBlinnPhong(ColorInOut in [[stage_in]],
                                   constant MaterialUniforms &materialUniforms [[ buffer(kBufferIndexMaterialUniforms) ]],
                                   constant EnvironmentUniforms *environmentUniforms [[ buffer(kBufferIndexEnvironmentUniforms) ]],
                                   constant AnchorEffectsUniforms *anchorEffectsUniforms [[ buffer(kBufferIndexAnchorEffectsUniforms) ]],
                                   texture2d<float> baseColorMap [[ texture(kTextureIndexColor), function_constant(has_base_color_map) ]],
                                   texture2d<float> normalMap    [[ texture(kTextureIndexNormal), function_constant(has_normal_map) ]],
                                   texture2d<float> metallicMap  [[ texture(kTextureIndexMetallic), function_constant(has_metallic_map) ]],
                                   texture2d<float> roughnessMap  [[ texture(kTextureIndexRoughness), function_constant(has_roughness_map) ]],
                                   texture2d<float> ambientOcclusionMap  [[ texture(kTextureIndexAmbientOcclusion), function_constant(has_ambient_occlusion_map) ]],
                                   texture2d<float> emissionMap [[texture(kTextureIndexEmissionMap), function_constant(has_emission_map)]],
                                   texture2d<float> subsurfaceMap [[texture(kTextureIndexSubsurfaceMap), function_constant(has_subsurface_map)]],
                                   texture2d<float> specularMap [[  texture(kTextureIndexSpecularMap), function_constant(has_specular_map) ]],
                                   texture2d<float> specularTintMap [[  texture(kTextureIndexSpecularTintMap), function_constant(has_specularTint_map) ]],
                                   texture2d<float> anisotropicMap [[  texture(kTextureIndexAnisotropicMap), function_constant(has_anisotropic_map) ]],
                                   texture2d<float> sheenMap [[  texture(kTextureIndexSheenMap), function_constant(has_sheen_map) ]],
                                   texture2d<float> sheenTintMap [[  texture(kTextureIndexSheenTintMap), function_constant(has_sheenTint_map) ]],
                                   texture2d<float> clearcoatMap [[  texture(kTextureIndexClearcoatMap), function_constant(has_clearcoat_map) ]],
                                   texture2d<float> clearcoatGlossMap [[  texture(kTextureIndexClearcoatGlossMap), function_constant(has_clearcoatGloss_map) ]],
                                   texturecube<float> environmentCubemap [[  texture(kTextureIndexEnvironmentMap) ]],
                                   depth2d<float> shadowMap [[ texture(kTextureIndexShadowMap) ]]
                                   )
{
    
    ushort iid = in.iid;
    
    LightingParameters parameters = calculateParameters(in,
                                                        materialUniforms,
                                                        environmentUniforms,
                                                        baseColorMap,
                                                        normalMap,
                                                        metallicMap,
                                                        roughnessMap,
                                                        ambientOcclusionMap,
                                                        emissionMap,
                                                        subsurfaceMap,
                                                        specularMap,
                                                        specularTintMap,
                                                        anisotropicMap,
                                                        sheenMap,
                                                        sheenTintMap,
                                                        clearcoatMap,
                                                        clearcoatGlossMap,
                                                        environmentCubemap);

    float ambient = 0.1;
    float diffuse = parameters.nDotl;
    float specular = pow(parameters.nDoth, 64);
    float4 baseColor = float4(parameters.baseColor.rgb, parameters.baseColor.a * materialUniforms.opacity);
    float3 diffuseColor = baseColor.rgb;
    
    float4 intermediateColor = float4((ambient + diffuse) * diffuseColor + specular, baseColor.a);
    float4 finalColor = float4(intermediateColor.rgb * anchorEffectsUniforms[iid].tint, intermediateColor.a * anchorEffectsUniforms[iid].alpha);
    return finalColor;
}

fragment float4 fragmentNone(ColorInOut in [[stage_in]]) {
    return float4(0.0, 0.0, 0.0, 0.0);
}

