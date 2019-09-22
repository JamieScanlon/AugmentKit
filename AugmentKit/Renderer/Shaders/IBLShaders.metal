//
//  IBLShaders.metal
//  AugmentKit
//
//  Created by Marvin Scanlon on 8/3/19.
//  Copyright © 2019 TenthLetterMade. All rights reserved.
//

#include <metal_stdlib>
#include <simd/simd.h>

// Include header shared between this Metal shader code and C code executing Metal API commands
#import "../ShaderTypes.h"
#import "../BRDFFunctions.h"
#import "../IBLFunctions.h"
#import "../Common.h"

using namespace metal;

constexpr sampler reflectiveEnvironmentSampler(address::clamp_to_edge, min_filter::nearest, mag_filter::linear, mip_filter::none);
constexpr sampler cubeSampler(coord::normalized, filter::linear, mip_filter::linear);

// This is the argument buffer that contains the ICB.
typedef struct ICBContainer
{
    command_buffer commandBuffer [[ id(kICBArgumentBufferIndexCommandBuffer) ]];
} ICBContainer;

float3 computeIrradiance(float3 normal, texturecube<float> environmentCubemap [[ texture(kTextureIndexEnvironmentMap) ]]) {
    
    float3 irradiance = float3(0.0);
    
    float3 up(0.0, 1.0, 0.0);
    float3 right = cross(up, normal);
    up = cross(normal, right);

    float sampleDelta = 0.025;
//    float sampleDelta = 0.5;
    float sampleCount = 0;
    for (float phi = 0.0; phi < M_PI_F * 2; phi += sampleDelta) { // 2π / 0.025 = 251.33
        float cosPhi = cos(phi);
        float sinPhi = sin(phi);
//        float sinPhi = sqrt(1.f - cosPhi * cosPhi);
        for (float theta = 0.0; theta < M_PI_F * 0.5; theta += sampleDelta) { // 0.5π / 0.025 = 62.83
            float cosTheta = cos(theta);
            float sinTheta = sin(theta);
//            float sinTheta = sqrt(1.f - cosTheta * cosTheta);
            // spherical to cartesian (in tangent space)
            float3 tangentSample(sinTheta * cosPhi,  sinTheta * sinPhi, cosTheta);
            // tangent space to world
            float3 dir = tangentSample.x * right + tangentSample.y * up + tangentSample.z * normal;
            irradiance += float3(environmentCubemap.sample(cubeSampler, dir).rgb) * cosTheta * sinTheta;
            sampleCount += 1;
        }
    }

    irradiance = M_PI_F * irradiance * (1.0 / sampleCount);
    return irradiance;
}

float3 prefilterEnvMap(float roughness, float3 R, texturecube<float> environmentCubemap [[ texture(kTextureIndexEnvironmentMap) ]]) {
    
    float3 n = R;
    float3 v = R;
    
    float3 prefilteredColor(0);
    float totalWeight = 0;
    float resolution = environmentCubemap.get_width();
    float saTexel  = 4.0 * M_PI_F / (6.0 * resolution * resolution);

    const uint sampleCount = 512;
//    const uint sampleCount = 64;
    for(uint i = 0; i < sampleCount; ++i) {
        float2 u = hammersley(i, sampleCount);
//        float3 h = importanceSampleGGX(u, n, roughness);
        float3 h = importanceSamplingNdfDggx(u, n, roughness);
        float3 l = normalize(2 * dot(v, h) * h - v);
        float nDotl = saturate(dot(n, l));
        if(nDotl > 0) {
            float nDoth = saturate(dot(n, h));
            float hDotv = saturate(dot(h, v));
            float D = geometrySchlickGGX(nDoth, roughness);
            float pdf = (D * nDoth / (4.0 * hDotv)) + 0.0001;
            float saSample = 1.0 / (float(sampleCount) * pdf + 0.0001);
            float mipLevel = roughness == 0.0 ? 0.0 : 0.5 * log2(saSample / saTexel);
            
//            float lDoth = saturate(dot(l, h));
            // PDF inverse (we must use D_GGX() here, which is used to generate samples)
//            float ipdf = (4.0 * lDoth) / (D_GGX(roughness, nDoth) * nDoth);
//            float mipLevel = prefilteredImportanceSampling(ipdf, float2(environmentCubemap.get_width(), environmentCubemap.get_height()))
            
            prefilteredColor += nDotl * float3(environmentCubemap.sample(cubeSampler, l, level(mipLevel)).rgb);
            totalWeight += nDotl;
        }
    }
    return prefilteredColor / totalWeight;
}

//
// BRDF Lookup
//
kernel void integrate_brdf(
                           texture2d<float, access::write> lookup [[ texture(kTextureIndexBDRFLookupMap) ]],
                           uint2 tpig [[thread_position_in_grid]]
                           ) {
    float nDotv = (tpig.x + 1) / float(lookup.get_width());
    float roughness = (tpig.y + 1) / float(lookup.get_height());
    float2 scaleAndBias = integrateBRDF(roughness, nDotv);
    float4 color(scaleAndBias.x, scaleAndBias.y, 0.0, 0.0);
    lookup.write(color, tpig.xy);
}

//
// diffuse irradiance cube map
//
kernel void compute_irradiance(
                               texturecube<float, access::sample> environmentCubemap [[ texture(kTextureIndexEnvironmentMap) ]],
                               texturecube<float, access::write> irradianceMap [[ texture(kTextureIndexDiffuseIBLMap) ]],
                               uint3 tpig [[thread_position_in_grid]]
                               ) {
    float cubeSize = irradianceMap.get_width();
    float2 cubeUV = ((float2(tpig.xy) / cubeSize) * 2 - 1);
    int face = tpig.z;
    float3 dir = cubeDirectionFromUVAndFace(cubeUV, face);
    dir *= float3(-1, -1, 1);
    float3 irrad = computeIrradiance(dir, environmentCubemap);
    uint2 coords = tpig.xy;
    float4 color = float4(irrad, 1.0);
    irradianceMap.write(color, coords, face);
}

kernel void computeIBLIrradianceMap(
                                    texturecube<float, access::sample> environmentCubemap [[ texture(kTextureIndexEnvironmentMap) ]],
                                    texturecube<float, access::read_write> irradianceMap [[ texture(kTextureIndexDiffuseIBLMap) ]],
                                    device ICBContainer *icbContainer [[ buffer(kBufferIndexCommandBufferContainer) ]],
                                    uint3 tpig [[thread_position_in_grid]]
                                    ) {
    float cubeSize = irradianceMap.get_width();
    float2 cubeUV = ((float2(tpig.xy) / cubeSize) * 2 - 1);
    int face = tpig.z;
    float3 dir = cubeDirectionFromUVAndFace(cubeUV, face);
    dir *= float3(-1, -1, 1);
    uint2 coords = tpig.xy;
    
    irradianceMap.write(float4(0.0), coords, face);

    float sampleDelta = 0.025;
//    float sampleDelta = 0.5;
    float sampleCount = 0;
    for (float phi = 0.0; phi < M_PI_F * 2; phi += sampleDelta) { // 2π / 0.025 = 251.33
        float cosPhi = cos(phi);
        float sinPhi = sin(phi);
//        float sinPhi = sqrt(1.f - cosPhi * cosPhi);
        for (float theta = 0.0; theta < M_PI_F * 0.5; theta += sampleDelta) { // 0.5π / 0.025 = 62.83
            float cosTheta = cos(theta);
            float sinTheta = sin(theta);
//            float sinTheta = sqrt(1.f - cosTheta * cosTheta);
            // Encode Indirect Command Buffer
            compute_command cmd(icbContainer->commandBuffer, sampleCount);
            // TODO: Add commands
            sampleCount += 1;
        }
    }
}

kernel void computeIBLIrradianceMapFragment(
                                         texturecube<float, access::sample> environmentCubemap [[ texture(kTextureIndexEnvironmentMap) ]],
                                         texturecube<float, access::read_write> irradianceMap [[ texture(kTextureIndexDiffuseIBLMap) ]],
                                         constant float3 &normal,
                                         constant uint2 &coords,
                                         constant int &face,
                                         constant float &cosPhi,
                                         constant float &sinPhi,
                                         constant float &cosTheta,
                                         constant float &sinTheta
                                         ) {
    
    float3 up(0.0, 1.0, 0.0);
    float3 right = cross(up, normal);
    up = cross(normal, right);
    int sampleCount = 15562; // 251 * 62 see above
    
    float3 irradiance = irradianceMap.read(coords, face).rgb;
    float3 tangentSample(sinTheta * cosPhi,  sinTheta * sinPhi, cosTheta);
    // tangent space to world
    float3 dir = tangentSample.x * right + tangentSample.y * up + tangentSample.z * normal;
    irradiance += float3(environmentCubemap.sample(cubeSampler, dir).rgb) * cosTheta * sinTheta;
    irradiance = M_PI_F * irradiance * (1.0 / sampleCount);
    
    float4 color = float4(irradiance, 1.0);
    irradianceMap.write(color, coords, face);
    
}

//
// Specular cube map
//
kernel void compute_prefiltered_specular(
                                         texturecube<float, access::sample> environmentCubemap [[ texture(kTextureIndexEnvironmentMap) ]],
                                         texturecube<float, access::write> specularMap [[ texture(kTextureIndexSpecularIBLMap) ]],
                                         constant float &roughness [[buffer(kBufferIndexLODRoughness)]],
                                         uint3 tpig [[thread_position_in_grid]]
                                         ) {
    float cubeSize = specularMap.get_width();
    float2 cubeUV = ((float2(tpig.xy) / cubeSize) * 2 - 1);
    int face = tpig.z;
    float3 dir = cubeDirectionFromUVAndFace(cubeUV, face);
    dir *= float3(-1, -1, 1);
    float3 irrad = prefilterEnvMap(roughness, dir, environmentCubemap);
    uint2 coords = tpig.xy;
    float4 color = float4(irrad, 1.0);
    specularMap.write(color, coords, face);
}
