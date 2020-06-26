//
//  IBLFunctions.metal
//  AugmentKit
//
//  Created by Marvin Scanlon on 7/9/19.
//  Copyright © 2019 TenthLetterMade. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

#import "../ShaderTypes.h"
#import "../Common.h"
#import "../BRDFFunctions.h"

#ifndef AK_SHADERS_IBLFUNCTIONS
#define AK_SHADERS_IBLFUNCTIONS

float radicalInverse_VdC(uint bits) {
    
    bits = (bits << 16u) | (bits >> 16u);
    bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
    bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
    bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
    bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);
    return float(bits) * 2.3283064365386963e-10; // / 0x100000000
}

float2 hammersley(uint i, uint N) {
    return float2(float(i) / float(N), radicalInverse_VdC(i));
}


//------------------------------------------------------------------------------
// IBL utilities
//------------------------------------------------------------------------------

float3 decodeDataForIBL(float4 data) {
    return data.rgb;
}

//------------------------------------------------------------------------------
// IBL prefiltered DFG term implementations
//------------------------------------------------------------------------------

//float3 PrefilteredDFG_LUT(float lod, float nDotv) {
//    // coord = sqrt(linear_roughness), which is the mapping used by cmgen.
//    return textureLod(light_iblDFG, float2(nDotv, lod), 0.0).rgb;
//}

//------------------------------------------------------------------------------
// IBL environment BRDF dispatch
//------------------------------------------------------------------------------

//float3 prefilteredDFG(float perceptualRoughness, float nDotv) {
//    // PrefilteredDFG_LUT() takes a LOD, which is sqrt(roughness) = perceptualRoughness
//    return PrefilteredDFG_LUT(perceptualRoughness, nDotv);
//}

//------------------------------------------------------------------------------
// IBL irradiance implementations
//------------------------------------------------------------------------------

//float3 Irradiance_SphericalHarmonics(float3 n) {
//    return max(
//               frameUniforms.iblSH[0]
//               + frameUniforms.iblSH[4] * (n.y * n.x)
//               + frameUniforms.iblSH[5] * (n.y * n.z)
//               + frameUniforms.iblSH[6] * (3.0 * n.z * n.z - 1.0)
//               + frameUniforms.iblSH[7] * (n.z * n.x)
//               + frameUniforms.iblSH[8] * (n.x * n.x - n.y * n.y)
//               , 0.0);
//}

//------------------------------------------------------------------------------
// IBL irradiance dispatch
//------------------------------------------------------------------------------

//float3 diffuseIrradiance(float3 n) {
//    return Irradiance_SphericalHarmonics(n);
//}

//------------------------------------------------------------------------------
// IBL specular
//------------------------------------------------------------------------------

//float3 prefilteredRadiance(float3 r, float perceptualRoughness) {
//    // lod = lod_count * sqrt(roughness), which is the mapping used by cmgen
//    // where roughness = perceptualRoughness^2
//    // using all the mip levels requires seamless cubemap sampling
//    float lod = frameUniforms.iblMaxMipLevel.x * perceptualRoughness;
//    return decodeDataForIBL(textureLod(light_iblSpecular, r, lod));
//}

//float3 prefilteredRadiance(float3 r, float roughness, float offset) {
//    float lod = frameUniforms.iblMaxMipLevel.x * roughness;
//    return decodeDataForIBL(textureLod(light_iblSpecular, r, lod + offset));
//}

//float3 specularDFG(PixelParams pixel) {
//    // Cloth
////    return pixel.f0 * pixel.dfg.z;
//    // without multi-scattering compensation
////    return pixel.f0 * pixel.dfg.x + pixel.dfg.y;
//    return mix(pixel.dfg.xxx, pixel.dfg.yyy, pixel.f0);
//}

/**
 * Returns the reflected vector at the current shading point. The reflected vector
 * return by this function might be different from shading_reflected:
 * - For anisotropic material, we bend the reflection vector to simulate
 *   anisotropic indirect lighting
 * - The reflected vector may be modified to point towards the dominant specular
 *   direction to match reference renderings when the roughness increases
 */

float3 getReflectedVector(LightingParameters parameters, float3 v, float3 n) {
    // HAS ANISOTROPY
//    float3  anisotropyDirection = pixel.anisotropy >= 0.0 ? pixel.anisotropicB : pixel.anisotropicT;
//    float3  anisotropicTangent  = cross(anisotropyDirection, v);
//    float3  anisotropicNormal   = cross(anisotropicTangent, anisotropyDirection);
//    float bendFactor          = abs(pixel.anisotropy) * saturate(5.0 * pixel.perceptualRoughness);
//    float3  bentNormal          = normalize(mix(n, anisotropicNormal, bendFactor));
//
//    float3 r = reflect(-v, bentNormal);
    // Without ANISOTROPY
    float3 r = reflect(-v, n);

    return r;
}

//float3 getReflectedVector(LightingParameters parameters, float3 n) {
//    // HAS ANISOTROPY
////    float3 r = getReflectedVector(pixel, shading_view, n);
//    // Without ANISOTROPY
//    float3 r = shading_reflected;
//
//    return r;
//}

//------------------------------------------------------------------------------
// Prefiltered importance sampling
//------------------------------------------------------------------------------

//#if IBL_INTEGRATION == IBL_INTEGRATION_IMPORTANCE_SAMPLING
//float2 hammersley(uint index) {
//    // Compute Hammersley sequence
//    // TODO: these should come from uniforms
//    // TODO: we should do this with logical bit operations
//    const uint numSamples = uint(IBL_INTEGRATION_IMPORTANCE_SAMPLING_COUNT);
//    const uint numSampleBits = uint(log2(float(numSamples)));
//    const float invNumSamples = 1.0 / float(numSamples);
//    uint i = uint(index);
//    uint t = i;
//    uint bits = 0u;
//    for (uint j = 0u; j < numSampleBits; j++) {
//        bits = bits * 2u + (t - (2u * (t / 2u)));
//        t /= 2u;
//    }
//    return float2(float(i), float(bits)) * invNumSamples;
//}
//
float3 importanceSamplingNdfDggx(float2 u, float3 n, float roughness) {
    // Importance sampling D_GGX
    float a2 = roughness * roughness;
    float phi = 2.0 * M_PI_F * u.x;
    float cosTheta2 = (1.0 - u.y) / (1.0 + (a2 - 1.0) * u.y);
    float cosTheta = sqrt(cosTheta2);
    float sinTheta = sqrt(1.0 - cosTheta2);
    float3 h = (cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);
    
    float3 up = fabs(n.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
    float3x3 tangentToWorld;
    tangentToWorld[0] = normalize(cross(up, n));
    tangentToWorld[1] = cross(n, tangentToWorld[0]);
    tangentToWorld[2] = n;
    return tangentToWorld * h;
}

float3 importanceSamplingVNdfDggx(float2 u, float roughness, float3 v) {
    // See: "A Simpler and Exact Sampling Routine for the GGX Distribution of Visible Normals", Eric Heitz
    float alpha = roughness;

    // stretch view
    v = normalize(float3(alpha * v.x, alpha * v.y, v.z));

    // orthonormal basis
    float3 up = abs(v.z) < 0.9999 ? float3(0.0, 0.0, 1.0) : float3(1.0, 0.0, 0.0);
    float3 t = normalize(cross(up, v));
    float3 b = cross(t, v);

    // sample point with polar coordinates (r, phi)
    float a = 1.0 / (1.0 + v.z);
    float r = sqrt(u.x);
    float phi = (u.y < a) ? u.y / a * M_PI_F : M_PI_F + (u.y - a) / (1.0 - a) * M_PI_F;
    float p1 = r * cos(phi);
    float p2 = r * sin(phi) * ((u.y < a) ? 1.0 : v.z);

    // compute normal
    float3 h = p1 * t + p2 * b + sqrt(max(0.0, 1.0 - p1 * p1 - p2 * p2)) * v;

    // unstretch
    h = normalize(float3(alpha * h.x, alpha * h.y, max(0.0, h.z)));
    return h;
}

float prefilteredImportanceSampling(float ipdf, float2 iblMaxMipLevel) {
    // See: "Real-time Shading with Filtered Importance Sampling", Jaroslav Krivanek
    // Prefiltering doesn't work with anisotropy
    const float numSamples = 1024;
    const float invNumSamples = 1.0 / float(numSamples);
    const float dim = iblMaxMipLevel.y;
    const float omegaP = (4.0 * M_PI_F) / (6.0 * dim * dim);
    const float invOmegaP = 1.0 / omegaP;
    const float K = 4.0;
    float omegaS = invNumSamples * ipdf;
    float mipLevel = clamp(log2(K * omegaS * invOmegaP) * 0.5, 0.0, iblMaxMipLevel.x);
    return mipLevel;
}

//float3 isEvaluateIBL(LightingParameters parameters, float3 n, float3 v, float nDotv) {
//    // TODO: for a true anisotropic BRDF, we need a real tangent space;
//
//    float2 iblMaxMipLevel = float2(9, 9);//frameUniforms.iblMaxMipLevel;
//    const uint numSamples = 1024;
//    const float invNumSamples = 1.0 / float(numSamples);
//
//    float3 indirectSpecular = float3(0.0);
//    for (uint i = 0u; i < numSamples; i++) {
//        float2 u = hammersley(i, numSamples);
//        float3 h = importanceSamplingNdfDggx(u, n, parameters.roughness);
//
//        // Since anisotropy doesn't work with prefiltering, we use the same "faux" anisotropy
//        // we do when we use the prefiltered cubemap
//        float3 l = getReflectedVector(parameters, v, h);
//
//        // Compute this sample's contribution to the brdf
//        float nDotl = dot(n, l);
//        if (nDotl > 0.0) {
//            float nDoth = dot(n, h);
//            float lDoth = max(dot(l, h), 0.0);
//
//            // PDF inverse (we must use D_GGX() here, which is used to generate samples)
//            float ipdf = (4.0 * lDoth) / (D_GGX(parameters.roughness, nDoth) * nDoth);
//
//            float mipLevel = prefilteredImportanceSampling(ipdf, iblMaxMipLevel);
//
//            // we use texture() instead of textureLod() to take advantage of mipmapping
//            float3 L = decodeDataForIBL(texture(light_iblSpecular, l, mipLevel));
//
//            float D = distribution(parameters.roughness, nDoth);
//            float V = visibility(parameters.roughness, nDotv, nDotl);
//            float3  F = fresnel(parameters.f0, lDoth);
//            float3 Fr = F * (D * V * nDotl * ipdf * invNumSamples);
//
//            indirectSpecular += (Fr * L);
//        }
//    }
//
//    return indirectSpecular;
//}
//
//void isEvaluateClearCoatIBL(PixelParams pixel, float specularAO, inout float3 Fd, inout float3 Fr) {
//#if defined(MATERIAL_HAS_CLEAR_COAT)
//#if defined(MATERIAL_HAS_NORMAL) || defined(MATERIAL_HAS_CLEAR_COAT_NORMAL)
//    // We want to use the geometric normal for the clear coat layer
//    float clearCoatnDotv = clampnDotv(dot(shading_clearCoatNormal, shading_view));
//    float3 clearCoatNormal = shading_clearCoatNormal;
//#else
//    float clearCoatnDotv = shading_nDotv;
//    float3 clearCoatNormal = shading_normal;
//#endif
//    // The clear coat layer assumes an IOR of 1.5 (4% reflectance)
//    float Fc = F_Schlick(0.04, 1.0, clearCoatnDotv) * pixel.clearCoat;
//    float attenuation = 1.0 - Fc;
//    Fd *= attenuation;
//    Fr *= sq(attenuation);
//
//    PixelParams p;
//    p.perceptualRoughness = pixel.clearCoatPerceptualRoughness;
//    p.f0 = float3(0.04);
//    p.roughness = perceptualRoughnessToRoughness(p.perceptualRoughness);
//    p.anisotropy = 0.0;
//
//    float3 clearCoatLobe = isEvaluateIBL(p, clearCoatNormal, shading_view, clearCoatnDotv);
//    Fr += clearCoatLobe * (specularAO * pixel.clearCoat);
//#endif
//}
//#endif

//------------------------------------------------------------------------------
// IBL evaluation
//------------------------------------------------------------------------------

//float evaluateClothIndirectDiffuseBRDF(PixelParams pixel, float diffuseIn) {
//    // Simulate subsurface scattering with a wrap diffuse term
//    float diffuseOut = diffuseIn * Fd_Wrap(shading_nDotv, 0.5);
//    return diffuseOut;
//}

//float3x3 evaluateClearCoatIBL(PixelParams pixel, float specularAO, float3 Fd_in, float3 Fr_in) {
//    // We want to use the geometric normal for the clear coat layer
//    float clearCoatnDotv = clampnDotv(dot(shading_clearCoatNormal, shading_view));
//    float3 clearCoatR = reflect(-shading_view, shading_clearCoatNormal);
//    // The clear coat layer assumes an IOR of 1.5 (4% reflectance)
//    float Fc = F_Schlick(0.04, 1.0, clearCoatnDotv) * pixel.clearCoat;
//    float attenuation = 1.0 - Fc;
//    float3 Fr_out = Fr_in * sq(attenuation);
//    Fr_out += prefilteredRadiance(clearCoatR, pixel.clearCoatPerceptualRoughness) * (specularAO * Fr_out);
//    float3 Fd_out = Fd_in * attenuation;
//    return float3x3(Fd_out, Fr_out, float3(0));
//}

//float3 evaluateSubsurfaceIBL(PixelParams pixel, float3 diffuseIrradiance, float3 Fd_in) {
//    // Subsurface
//    float3 viewIndependent = diffuseIrradiance;
//    float3 viewDependent = prefilteredRadiance(-shading_view, pixel.roughness, 1.0 + pixel.thickness);
//    float attenuation = (1.0 - pixel.thickness) / (2.0 * PI);
//    float3 Fd_out = Fd_in + pixel.subsurfaceColor * (viewIndependent + viewDependent) * attenuation;
//    // Cloth or subsurface color
////    Fd *= saturate(pixel.subsurfaceColor + shading_nDotv);
//    return Fd_out;
//
//}

//float3 evaluateIBL(MaterialInputs material, PixelParams pixel, float3 color_in) {
//    // Apply transform here if we wanted to rotate the IBL
//    float3 n = shading_normal;
//    float3 r = getReflectedVector(pixel, n);
//
//    float ssao = evaluateSSAO();
//    float diffuseAO = min(material.ambientOcclusion, ssao);
//    float specularAO = computeSpecularAO(shading_nDotv, diffuseAO, pixel.roughness);
//
//    // diffuse indirect
//    float diffuseBRDF = singleBounceAO(diffuseAO);// Fd_Lambert() is baked in the SH below
//    evaluateClothIndirectDiffuseBRDF(pixel, diffuseBRDF);
//
//    float3 diffuseIrradiance = diffuseIrradiance(n);
//    float3 Fd = pixel.diffuseColor * diffuseIrradiance * diffuseBRDF;
//
//    // specular indirect
//    float3 Fr;
//    // IBL Cubemap
//    Fr = specularDFG(pixel) * prefilteredRadiance(r, pixel.perceptualRoughness);
//    Fr *= singleBounceAO(specularAO) * pixel.energyCompensation;
//    evaluateClearCoatIBL(pixel, specularAO, Fd, Fr);
//    // IBL _IMPORTANCE_SAMPLING
////    Fr = isEvaluateIBL(pixel, shading_normal, shading_view, shading_nDotv);
////    Fr *= singleBounceAO(specularAO) * pixel.energyCompensation;
////    isEvaluateClearCoatIBL(pixel, specularAO, Fd, Fr);
//
//    evaluateSubsurfaceIBL(pixel, diffuseIrradiance, Fd, Fr);
//
//    multiBounceAO(diffuseAO, pixel.diffuseColor, Fd);
//    multiBounceSpecularAO(specularAO, pixel.f0, Fr);
//
//    // Note: iblLuminance is already premultiplied by the exposure
//    float3 color_out = color_in + (Fd + Fr) * frameUniforms.iblLuminance;
//    return color_out;
//
//}

//------------------------------------------------------------------------------
// See: https://google.github.io/filament/Filament.html#annex/importancesamplingfortheibl
// Precomputing L for image-based lighting
//------------------------------------------------------------------------------

float GDFG(float nDotv, float nDotl, float a) {
    float a2 = a * a;
    float GGXL = nDotv * sqrt((-nDotl * a2 + nDotl) * nDotl + a2);
    float GGXV = nDotl * sqrt((-nDotv * a2 + nDotv) * nDotv + a2);
    return (2 * nDotl) / (GGXV + GGXL);
}

//------------------------------------------------------------------------------
// glTF
//------------------------------------------------------------------------------

//float3 importanceSampleGGX(float2 xi, float3 N, float roughness) {
//    float a = roughness * roughness;
//    float phi = 2 * M_PI_F * xi.x;
//    float cosTheta = sqrt((1 - xi.y) / (1 + (a * a - 1) * xi.y));
//    float sinTheta = sqrt(1 - cosTheta * cosTheta);
//
//    float3 H(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta);
//
//    float3 up = fabs(N.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
//    float3 tangent = normalize(cross(up, N));
//    float3 bitangent = cross(N, tangent);
//
//    return normalize(tangent * H.x + bitangent * H.y + N * H.z);
//}

float geometrySchlickGGX(float nDotv, float roughness) {
    float a2 = roughness;
    float k = (a2 * a2) / 2.0;
    return nDotv / (nDotv * (1.0 - k) + k);
}

float geometrySmith(float nDotl, float nDotv, float roughness) {
    float ggx2 = geometrySchlickGGX(nDotv, roughness);
    float ggx1 = geometrySchlickGGX(nDotl, roughness);
    return ggx1 * ggx2;
}

// See: https://google.github.io/filament/Filament.html#annex/importancesamplingfortheibl
// Precomputing L for image-based lighting
// float2 DFG(float NoV, float a)
float2 integrateBRDF(float roughness, float nDotv) {
    float3 n(0, 0, 1);
    float3 v(sqrt(1.0 - nDotv * nDotv), 0, nDotv);
    float A = 0;
    float B = 0;

    const uint sampleCount = 1024;
    for(uint i = 0; i < sampleCount; ++i) {
        float2 u = hammersley(i, sampleCount);
//        float3 h = importanceSampleGGX(u, n, roughness);
        float3 h = importanceSamplingNdfDggx(u, n, roughness);
        float3 l = normalize(2 * dot(v, h) * h - v);
        float nDotl = saturate(l.z);
        if(nDotl > 0) {
            float nDoth = saturate(h.z);
            float vDoth = saturate(dot(v, h));
//            float G = geometrySmith(nDotl, nDotv, roughness);
            float G = GDFG(nDotl, nDotv, roughness);
            float G_Vis = G * vDoth / (nDoth * nDotv);
            float Fc = powr(1 - vDoth, 5); // Use fresnel(float3 f0, float vDoth) ?
            A += (1 - Fc) * G_Vis;
            B += Fc * G_Vis;
        }
    }

    return float2(A, B) / float(sampleCount);
}

float3 cubeDirectionFromUVAndFace(float2 uv, int face) {
    float u = uv.x;
    float v = uv.y;
    float3 dir = float3(0);
    switch (face) {
        case 0:
            dir = float3(-1,  v, -u); break; // +X
        case 1:
            dir = float3( 1,  v,  u); break; // -X
        case 2:
            dir = float3(-u, -1,  v); break; // +Y
        case 3:
            dir = float3(-u,  1, -v); break; // -Y
        case 4:
            dir = float3(-u,  v,  1); break; // +Z
        case 5:
            dir = float3( u,  v, -1); break; // -Z
    }
    
    dir = normalize(dir);
    return dir;
}


#endif /* AK_SHADERS_IBLFUNCTIONS */

