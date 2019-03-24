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
                                        constant EnvironmentUniforms *environmentUniforms [[ buffer(kBufferIndexEnvironmentUniforms) ]],
                                        ushort tid [[thread_position_in_grid]]) {
    // thread_position_in_threadgroup
    // thread_index_in_threadgroup

    float4x4 coordinateSpaceTransform = float4x4(float4(1.0, 0, 0, 0),
                                                 float4(0, 1.0, 0, 0),
                                                 float4(0, 0, -1.0, 0),
                                                 float4(0, 0, 0, 1.0));

    // Apply the world transform (as defined in the imported model) if applicable
    float4x4 worldTransform = anchorInstanceUniforms[tid].worldTransform;
    coordinateSpaceTransform = coordinateSpaceTransform * worldTransform;

    // Update Heading
    float4x4 headingTransform = anchorInstanceUniforms[tid].headingTransform;
    float headingType = float(anchorInstanceUniforms[tid].headingType);
    coordinateSpaceTransform = headingTransform * float4x4(float4(coordinateSpaceTransform[0][0], headingType * coordinateSpaceTransform[0][1], headingType * coordinateSpaceTransform[0][2], headingType * coordinateSpaceTransform[0][3]),
                                        float4(headingType * coordinateSpaceTransform[1][0], coordinateSpaceTransform[1][1], headingType * coordinateSpaceTransform[1][2], headingType * coordinateSpaceTransform[1][3]),
                                        float4(headingType * coordinateSpaceTransform[2][0], headingType * coordinateSpaceTransform[2][1], coordinateSpaceTransform[2][2], headingType * coordinateSpaceTransform[2][3]),
                                        float4(coordinateSpaceTransform[3][0], coordinateSpaceTransform[3][1], coordinateSpaceTransform[3][2], 1)
                                        );

    float4x4 modelMatrix = anchorInstanceUniforms[tid].locationTransform * coordinateSpaceTransform;

    // Scaled geomentry effects
    float4x4 scale4Matrix = anchorEffectsUniforms[tid].scale;
    float3x3 scale3Matrix = float3x3(scale4Matrix[0][0], scale4Matrix[0][1], scale4Matrix[0][2], scale4Matrix[1][0], scale4Matrix[1][1], scale4Matrix[1][2], scale4Matrix[2][0], scale4Matrix[2][1], scale4Matrix[2][2]);

    // Get the anchor model's orientation in world space
//    float4x4 modelMatrix = anchorInstanceUniforms[tid].modelMatrix;
//    float3x3 normalMatrix = anchorInstanceUniforms[tid].normalMatrix;
    
    float3x3 upperLeft = float3x3(modelMatrix[0].xyz, modelMatrix[1].xyz, modelMatrix[2].xyz);
    float3x3 normalMatrix = invert3(transpose(upperLeft));
    
    float4x4 scaledModelMatrix = modelMatrix * scale4Matrix;
    float3x3 scaledNormalMatrix = normalMatrix * scale3Matrix;

    // Transform the model's orientation from world space to camera space.
    float4x4 modelViewMatrix = sharedUniforms.viewMatrix * scaledModelMatrix;

//    ushort4 jointIndex = in.jointIndices + paletteStartIndex + tid * paletteSize;
//    float4 jointWeights = in.jointWeights;
//
//    float4 weightedPalette = jointWeights[0] * palette[jointIndex[0]] +
//    jointWeights[1] * palette[jointIndex[1]] +
//    jointWeights[2] * palette[jointIndex[2]] +
//    jointWeights[3] * palette[jointIndex[3]];
    
}
