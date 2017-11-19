//
//  PointShader.metal
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
//  Shaders that render points. Used primarily for rendering the tracking points
//  provided by ARKit
//
//  Reference: https://forums.developer.apple.com/thread/43570
//

//  TODO: Add the ability to include a texture sprite. This can be the start of a particle renderer or perhaps a 2D sprite rendered similar to ARSKView

#include <metal_stdlib>
using namespace metal;

// Include header shared between this Metal shader code and C code executing Metal API commands
#import "ShaderTypes.h"

#define POINT_SIZE 20.0
#define MAX_RANGE  10.0

struct PointVertexIn {
    float4 position [[attribute(kVertexAttributePosition)]];
    float4 color [[attribute(kVertexAttributeColor)]];
};

struct PointInOut {
    float4 position [[position]];
    float4 color;
    float pointSize [[point_size]]; // Required when using MTLPrimitiveType.point see: https://developer.apple.com/documentation/metal/mtlprimitivetype
    float2 pointCoord [[point_coord]];
};

vertex PointInOut pointVertexShader(PointVertexIn in [[stage_in]],
                                          constant SharedUniforms &sharedUniforms [[ buffer(kBufferIndexSharedUniforms) ]]) {

    PointInOut out;
    
    float4 position = sharedUniforms.projectionMatrix * in.position;
    float4 eyePosition = sharedUniforms.viewMatrix * in.position;
    
    out.position = position;
    float dist = distance(position, eyePosition);
    float distance = min(dist, MAX_RANGE);
    float normalizedDistance = (1.0 - (distance / MAX_RANGE));
    float size = POINT_SIZE * normalizedDistance;
    out.pointSize = size;
    
    // Change color intensity according to distance
    out.color = float4(1.0, 1.0, 1.0, 1.0);//float4(in.color.r * normalizedDistance, in.color.g * normalizedDistance, in.color.b * normalizedDistance, in.color.w * normalizedDistance);
    
    return out;
    
}

fragment float4 pointFragmentShader(PointInOut in [[stage_in]]) {
    
    float radiusFromPointCenter = distance(float2(0.5f), in.pointCoord);
    if (radiusFromPointCenter > 0.5) {
        discard_fragment();
    }
    
    float intensity = (1.0 - (radiusFromPointCenter * 2.0));
    
    return float4(in.color.r * intensity, in.color.g * intensity, in.color.b * intensity, in.color.w * intensity);
    
}
