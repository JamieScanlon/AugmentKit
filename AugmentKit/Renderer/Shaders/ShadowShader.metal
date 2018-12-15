//
//  ShadowShader.metal
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

#include <metal_stdlib>
using namespace metal;

// Include header shared between this Metal shader code and C code executing Metal API commands
#import "../ShaderTypes.h"

struct ShadowVertex {
    float3 position [[attribute(kVertexAttributePosition)]];
};

struct ShadowOutput {
    float4 position [[position]];
};

vertex ShadowOutput shadowVertexShader( ShadowVertex in [[stage_in]],
                                       constant SharedUniforms &sharedUniforms [[ buffer(kBufferIndexSharedUniforms) ]],
                                       constant AnchorInstanceUniforms *anchorInstanceUniforms [[ buffer(kBufferIndexAnchorInstanceUniforms) ]],
                                       constant AnchorEffectsUniforms *anchorEffectsUniforms [[ buffer(kBufferIndexAnchorEffectsUniforms) ]],
                                       constant EnvironmentUniforms *environmentUniforms [[ buffer(kBufferIndexEnvironmentUniforms) ]],
                                       uint vid [[ vertex_id ]],
                                       ushort iid [[instance_id]]
                                       ){
    
    ShadowOutput out;
    
    // Make position a float4 to perform 4x4 matrix math on it
    float4 position = float4(in.position, 1.0);
    
    // Get the anchor model's orientation in world space
    float4x4 modelMatrix = anchorInstanceUniforms[iid].modelMatrix;
    
    // Apply effects that affect geometry
    float4x4 scaleMatrix = anchorEffectsUniforms[iid].scale;
    modelMatrix = modelMatrix * scaleMatrix;
    
    // Transform the model's orientation from world space to camera space.
//    float4x4 modelViewMatrix = sharedUniforms.viewMatrix * modelMatrix;
//
//    // Calculate the position of our vertex in clip space and output for clipping and rasterization
//    position = sharedUniforms.projectionMatrix * modelViewMatrix * position;
    position = modelMatrix * position;
    
    EnvironmentUniforms uniforms = environmentUniforms[iid];
    float4x4 directionalLightMVP = uniforms.directionalLightMVP;
    // Add vertex pos to fairy position and project to clip-space
    out.position = directionalLightMVP * position;
    
    return out;
}
