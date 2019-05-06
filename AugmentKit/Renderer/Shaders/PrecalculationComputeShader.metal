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
                                        constant float4x4 *palette [[buffer(kBufferIndexMeshPalettes)]],
                                        constant int &paletteStartIndex [[buffer(kBufferIndexMeshPaletteIndex)]],
                                        constant int &paletteSize [[buffer(kBufferIndexMeshPaletteSize)]],
                                        constant AnchorInstanceUniforms *anchorInstanceUniforms [[ buffer(kBufferIndexAnchorInstanceUniforms) ]],
                                        constant AnchorEffectsUniforms *anchorEffectsUniforms [[ buffer(kBufferIndexAnchorEffectsUniforms) ]],
                                        constant EnvironmentUniforms &environmentUniforms [[ buffer(kBufferIndexEnvironmentUniforms) ]],
                                        device PrecalculatedParameters *out [[ buffer(kBufferIndexPrecalculationOutputBuffer) ]],
                                        uint2 gid [[thread_position_in_grid]],
                                        uint2 tid [[thread_position_in_threadgroup]],
                                        uint2 size [[threads_per_grid]]
                                        ){
    // thread_position_in_threadgroup
    // thread_index_in_threadgroup
    
    uint w = size.x;
    uint index = gid.y * w + gid.x;
    
    int hasGeometry = anchorInstanceUniforms[index].hasGeometry;
    int hasHeading = anchorInstanceUniforms[index].hasHeading;

    float4x4 coordinateSpaceTransform = float4x4(float4(1.0, 0, 0, 0),
                                                 float4(0, 1.0, 0, 0),
                                                 float4(0, 0, -1.0, 0),
                                                 float4(0, 0, 0, 1.0));

    // Apply the world transform (as defined in the imported model) if applicable
    float4x4 worldTransform = anchorInstanceUniforms[index].worldTransform;
    coordinateSpaceTransform = coordinateSpaceTransform * worldTransform;

    // Update Heading
    float4x4 headingTransform = anchorInstanceUniforms[index].headingTransform;
    float headingType = float(anchorInstanceUniforms[index].headingType);
    coordinateSpaceTransform = headingTransform * float4x4(float4(coordinateSpaceTransform[0][0], headingType * coordinateSpaceTransform[0][1], headingType * coordinateSpaceTransform[0][2], headingType * coordinateSpaceTransform[0][3]),
                                        float4(headingType * coordinateSpaceTransform[1][0], coordinateSpaceTransform[1][1], headingType * coordinateSpaceTransform[1][2], headingType * coordinateSpaceTransform[1][3]),
                                        float4(headingType * coordinateSpaceTransform[2][0], headingType * coordinateSpaceTransform[2][1], coordinateSpaceTransform[2][2], headingType * coordinateSpaceTransform[2][3]),
                                        float4(coordinateSpaceTransform[3][0], coordinateSpaceTransform[3][1], coordinateSpaceTransform[3][2], 1)
                                        );

    float4x4 locationTransform = anchorInstanceUniforms[index].locationTransform;
    float4x4 modelMatrix = locationTransform * coordinateSpaceTransform;

    // Scaled geomentry effects
    float4x4 scale4Matrix = anchorEffectsUniforms[index].scale;
    float3x3 scale3Matrix = convert3(scale4Matrix);
    
    // When converting a 4x4 to a 3x3, position data is discarded
    float3x3 upperLeft = convert3(modelMatrix);
    float3x3 normalMatrix = invert3(transpose(upperLeft));
    
    float4x4 scaledModelMatrix = modelMatrix * scale4Matrix;
    float3x3 scaledNormalMatrix = normalMatrix * scale3Matrix;

    // Transform the model's orientation from world space to camera space.
    float4x4 modelViewMatrix = sharedUniforms.viewMatrix * scaledModelMatrix;
    float4x4 modelViewProjectionMatrix = sharedUniforms.projectionMatrix * modelViewMatrix;

//    float4 jointIndex = in.jointIndices + paletteStartIndex + index * paletteSize;
//    float4 jointWeights = in.jointWeights;
//
//    float4 weightedPalette = jointWeights[0] * palette[jointIndex[0]] +
//    jointWeights[1] * palette[jointIndex[1]] +
//    jointWeights[2] * palette[jointIndex[2]] +
//    jointWeights[3] * palette[jointIndex[3]];
    
    float4x4 shadowMVPTransformMatrix = environmentUniforms.shadowMVPTransformMatrix;
    
    out[index].hasGeometry = hasGeometry;
    out[index].worldTransform = worldTransform;
    out[index].hasHeading = hasHeading;
    out[index].headingTransform = headingTransform;
    out[index].headingType = int(headingType);
    out[index].coordinateSpaceTransform = coordinateSpaceTransform;
    out[index].locationTransform = locationTransform;
    out[index].modelMatrix = modelMatrix;
    out[index].scaledModelMatrix = scaledModelMatrix;
    out[index].normalMatrix = normalMatrix;
    out[index].scaledNormalMatrix = scaledNormalMatrix;
    out[index].modelViewMatrix = modelViewMatrix;
    out[index].modelViewProjectionMatrix = modelViewProjectionMatrix;
//    out[index].jointIndeces = jointIndeces;
//    out[index].jointWeights = jointWeights;
//    out[index].weightedPalette = weightedPalette;
    out[index].shadowMVPTransformMatrix = shadowMVPTransformMatrix;
    
    
}
