//
//  PrecalculationComputeShader.metal
//  AugmentKit
//
//  Created by Marvin Scanlon on 1/26/19.
//  Copyright © 2019 TenthLetterMade. All rights reserved.
//

#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;

#import "../ShaderTypes.h"
#import "../Common.h"

kernel void precalculationComputeShader(constant SharedUniforms &sharedUniforms [[ buffer(kBufferIndexSharedUniforms) ]],
                                        constant AnchorInstanceUniforms *anchorInstanceUniforms [[ buffer(kBufferIndexAnchorInstanceUniforms) ]],
                                        constant AnchorEffectsUniforms *anchorEffectsUniforms [[ buffer(kBufferIndexAnchorEffectsUniforms) ]],
                                        constant EnvironmentUniforms &environmentUniforms [[ buffer(kBufferIndexEnvironmentUniforms) ]],
                                        device PrecalculatedParameters *out [[ buffer(kBufferIndexPrecalculationOutputBuffer) ]],
                                        constant uint &instanceCount [[buffer(kBufferIndexInstanceCount)]],
                                        uint2 gid [[thread_position_in_grid]],
                                        uint2 tid [[thread_position_in_threadgroup]],
                                        uint2 size [[threads_per_grid]]
                                        ){
    
    uint w = size.x;
    uint index = gid.y * w + gid.x;
    if (index >= instanceCount) {
        return;
    }
    
    // TODO: Add check for render distance
    
    int hasGeometry = anchorInstanceUniforms[index].hasGeometry;
    int hasHeading = anchorInstanceUniforms[index].hasHeading;

    float4x4 coordinateSpaceTransform = float4x4(float4(1.0, 0, 0, 0),
                                                 float4(0, 1.0, 0, 0),
                                                 float4(0, 0, -1.0, 0),
                                                 float4(0, 0, 0, 1.0));
    
    // Scaled geomentry effects
    float4x4 scale4Matrix = anchorEffectsUniforms[index].scale;

    // Apply the world transform (as defined in the imported model) if applicable
    float4x4 worldTransform = scale4Matrix * anchorInstanceUniforms[index].worldTransform;
    coordinateSpaceTransform = coordinateSpaceTransform * worldTransform;
    
    float4x4 locationTransform = anchorInstanceUniforms[index].locationTransform;

    // Update Heading
    float4x4 headingTransform = anchorInstanceUniforms[index].headingTransform;
    float headingType = float(anchorInstanceUniforms[index].headingType);
    locationTransform =  float4x4(float4(locationTransform[0][0], headingType * locationTransform[0][1], headingType * locationTransform[0][2], headingType * locationTransform[0][3]),
                                        float4(headingType * locationTransform[1][0], locationTransform[1][1], headingType * locationTransform[1][2], headingType * locationTransform[1][3]),
                                        float4(headingType * locationTransform[2][0], headingType * locationTransform[2][1], locationTransform[2][2], headingType * locationTransform[2][3]),
                                        float4(locationTransform[3][0], locationTransform[3][1], locationTransform[3][2], 1)
                                        ) * headingTransform;

    
    float4x4 modelMatrix = locationTransform * coordinateSpaceTransform;
    
    // When converting a 4x4 to a 3x3, position data is discarded
    float3x3 upperLeft = convert3(modelMatrix);
    float3x3 normalMatrix = invert3(transpose(upperLeft));

    // Transform the model's orientation from world space to camera space.
    float4x4 modelViewMatrix = sharedUniforms.viewMatrix * modelMatrix;
    float4x4 modelViewProjectionMatrix = sharedUniforms.projectionMatrix * modelViewMatrix;
    
    float4x4 shadowMVPTransformMatrix = environmentUniforms.shadowMVPTransformMatrix;
    float4x4 directionalLightMVP = environmentUniforms.directionalLightMVP;
    
    out[index].hasGeometry = hasGeometry;
    out[index].worldTransform = worldTransform;
    out[index].hasHeading = hasHeading;
    out[index].headingTransform = headingTransform;
    out[index].headingType = int(headingType);
    out[index].coordinateSpaceTransform = coordinateSpaceTransform;
    out[index].locationTransform = locationTransform;
    out[index].modelMatrix = modelMatrix;
    out[index].normalMatrix = normalMatrix;
    out[index].projectionMatrix = sharedUniforms.projectionMatrix;
    out[index].modelViewMatrix = modelViewMatrix;
    out[index].modelViewProjectionMatrix = modelViewProjectionMatrix;
    out[index].shadowMVPTransformMatrix = shadowMVPTransformMatrix;
    out[index].directionalLightMVP = directionalLightMVP;
    out[index].useDepth = sharedUniforms.useDepth;
}
