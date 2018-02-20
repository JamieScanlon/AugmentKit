//
//  PathShader.metal
//  AugmentKit
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
//  Shader that renders paths.
//

#include <metal_stdlib>
using namespace metal;

// Include header shared between this Metal shader code and C code executing Metal API commands
#import "../ShaderTypes.h"

struct PathVertexIn {
    float4 position [[attribute(kVertexAttributePosition)]];
    float4 color [[attribute(kVertexAttributeColor)]];
    //float glow [[attribute(kVertexAttributeGlow)]];
};

struct PathFragmentInOut {
    float4 position [[position]];
    float4 color;
    float glow;
};

vertex PathFragmentInOut pathVertexShader(PathVertexIn in [[stage_in]],
                                          constant SharedUniforms &sharedUniforms [[ buffer(kBufferIndexSharedUniforms) ]],
                                          constant AnchorInstanceUniforms *anchorInstanceUniforms [[ buffer(kBufferIndexAnchorInstanceUniforms) ]],
                                          uint vid [[vertex_id]],
                                          ushort iid [[instance_id]]
                                          ){
    
    PathFragmentInOut out;
    
    // Make position a float4 to perform 4x4 matrix math on it
    float4 position = in.position;
    
    // Get the anchor model's orientation in world space
    float4x4 modelMatrix = anchorInstanceUniforms[iid].modelMatrix;
    
    // Transform the model's orientation from world space to camera space.
    float4x4 modelViewMatrix = sharedUniforms.viewMatrix * modelMatrix;
    
    // Calculate the position of our vertex in clip space and output for clipping and rasterization
    out.position = sharedUniforms.projectionMatrix * modelViewMatrix * position;
    
    out.color = in.color;
    
    return out;
    
}

fragment float4 pathFragmentShader(PathFragmentInOut in [[stage_in]]) {
    
//    float radiusFromPointCenter = distance(float2(0.5f), pointCoord);
//    if (radiusFromPointCenter > 0.5) {
//        discard_fragment();
//    }
//
//    float intensity = (1.0 - (radiusFromPointCenter * 2.0));
//
//    return float4(in.color.r * intensity, in.color.g * intensity, in.color.b * intensity, in.color.w * intensity);
 
    return in.color;
}
