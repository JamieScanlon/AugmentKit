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
#import "../IBLFunctions.h"
#import "../Common.h"

using namespace metal;

constexpr sampler reflectiveEnvironmentSampler(address::clamp_to_edge, min_filter::nearest, mag_filter::linear, mip_filter::none);
constexpr sampler cubeSampler(coord::normalized, filter::linear, mip_filter::linear);

float3 computeIrradiance(float3 N, texturecube<float> environmentCubemap [[ texture(kTextureIndexEnvironmentMap) ]]) {
    
    float3 irradiance = float3(0.0);
    
    float3 up(0.0, 1.0, 0.0);
    float3 right = cross(up, N);
    up = cross(N, right);

    float sampleDelta = 0.025;
    float sampleCount = 0;
    for (float phi = 0.0; phi < M_PI_F * 2; phi += sampleDelta) {
        for (float theta = 0.0; theta < M_PI_F * 0.5; theta += sampleDelta) {
            // spherical to cartesian (in tangent space)
            float3 tangentSample(sin(theta) * cos(phi),  sin(theta) * sin(phi), cos(theta));
            // tangent space to world
            float3 dir = tangentSample.x * right + tangentSample.y * up + tangentSample.z * N;

            irradiance += float3(environmentCubemap.sample(cubeSampler, dir).rgb) * cos(theta) * sin(theta);
            sampleCount += 1;
        }
    }

    irradiance = M_PI_F * irradiance * (1.0 / sampleCount);
    return irradiance;
}

float3 prefilterEnvMap(float roughness, float3 R, texturecube<float> environmentCubemap [[ texture(kTextureIndexEnvironmentMap) ]]) {
    
    float3 N = R;
    float3 V = R;
    
    float3 prefilteredColor(0);
    float totalWeight = 0;
    float resolution = environmentCubemap.get_width();
    float saTexel  = 4.0 * M_PI_F / (6.0 * resolution * resolution);

    const uint sampleCount = 512;
    for(uint i = 0; i < sampleCount; ++i) {
        float2 xi = hammersley(i, sampleCount);
        float3 H = importanceSampleGGX(xi, N, roughness);
        float3 L = normalize(2 * dot(V, H) * H - V);
        float NdotL = saturate(dot(N, L));
        if(NdotL > 0) {
            float nDoth = saturate(dot(N, H));
            float HdotV = saturate(dot(H, V));
            float D   = geometrySchlickGGX(nDoth, roughness);
            float pdf = (D * nDoth / (4.0 * HdotV)) + 0.0001;
            float saSample = 1.0 / (float(sampleCount) * pdf + 0.0001);
            float mipLevel = roughness == 0.0 ? 0.0 : 0.5 * log2(saSample / saTexel);
            prefilteredColor += NdotL * float3(environmentCubemap.sample(cubeSampler, L, level(mipLevel)).rgb);
            totalWeight += NdotL;
        }
    }
    return prefilteredColor / totalWeight;
}

// BRDF Lookup
kernel void integrate_brdf(
                           texture2d<half, access::write> lookup [[ texture(kTextureIndexBDRFLookupMap) ]],
                           uint2 tpig [[thread_position_in_grid]]
                           ) {
    float nDotv = (tpig.x + 1) / float(lookup.get_width());
    float roughness = (tpig.y + 1) / float(lookup.get_height());
    float2 scaleAndBias = integrateBRDF(roughness, nDotv);
    half4 color(scaleAndBias.x, scaleAndBias.y, 0, 0);
    lookup.write(color, tpig.xy);
}

// diffuse irradiance cube map
kernel void compute_irradiance(
                               texturecube<float, access::sample> environmentCubemap [[ texture(kTextureIndexEnvironmentMap) ]],
                               texturecube<half, access::write> irradianceMap [[ texture(kTextureIndexDiffuseIBLMap) ]],
                               uint3 tpig [[thread_position_in_grid]]
                               ) {
    float cubeSize = irradianceMap.get_width();
    float2 cubeUV = ((float2(tpig.xy) / cubeSize) * 2 - 1);
    int face = tpig.z;
    float3 dir = cubeDirectionFromUVAndFace(cubeUV, face);
    dir *= float3(-1, -1, 1);
    float3 irrad = computeIrradiance(dir, environmentCubemap);
    uint2 coords = tpig.xy;
    irradianceMap.write(half4(half3(irrad), 1), coords, face);
}

// Specular cube map

kernel void compute_prefiltered_specular(
                                         texturecube<float, access::sample> environmentCubemap [[ texture(kTextureIndexEnvironmentMap) ]],
                                         texturecube<half, access::write> specularMap [[ texture(kTextureIndexSpecularIBLMap) ]],
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
    specularMap.write(half4(half3(irrad), 1), coords, face);
}
