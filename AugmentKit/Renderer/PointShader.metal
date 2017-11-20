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

#define POINT_SIZE 10.0
#define MAX_RANGE  3.0

struct PointVertexIn {
    float4 position [[attribute(kVertexAttributePosition)]];
    float4 color [[attribute(kVertexAttributeColor)]];
};

struct PointInOut {
    float4 position [[position]];
    float4 color;
    float pointSize [[point_size]]; // Required when using MTLPrimitiveType.point see: https://developer.apple.com/documentation/metal/mtlprimitivetype
//    float2 pointCoord [[point_coord]];
};

vertex PointInOut pointVertexShader(PointVertexIn in [[stage_in]],
                                          constant SharedUniforms &sharedUniforms [[ buffer(kBufferIndexSharedUniforms) ]]) {

    PointInOut out;
    
    // Transform the point's orientation from world space to camera space.
    float4 eyePosition = sharedUniforms.viewMatrix * in.position;
    
    // Transform the point's orientation from camera (eye) space to clip (view) space.
    float4 position = sharedUniforms.projectionMatrix * eyePosition;
    
    out.position = position;
    
    // Find the distance between the point and the camera (eye)
    float dist = distance(in.position, eyePosition);
    
    // Set a max rander for rendering
    float distance = min(dist, MAX_RANGE);
    
    // Normalize the distance as a value from 0.0 (eye) to 1.0 (MAX_RANGE)
    float normalizedDistance = (1.0 - (distance / MAX_RANGE));
    
    // Use the normalized distance to scale the point. Smaller points ar further.
    float size = POINT_SIZE * normalizedDistance;
    
    out.pointSize = size;
    
    // Change color intensity according to the normalized distance. Further points are dimmer.
    out.color = float4(in.color.r * normalizedDistance, in.color.g * normalizedDistance, in.color.b * normalizedDistance, in.color.a * normalizedDistance);
    
    return out;
    
}

fragment float4 pointFragmentShader(PointInOut in [[stage_in]], float2 pointCoord [[point_coord]]) {
    
    float radiusFromPointCenter = distance(float2(0.5f), pointCoord);
    if (radiusFromPointCenter > 0.5) {
        discard_fragment();
    }
    
    float intensity = (1.0 - (radiusFromPointCenter * 2.0));
    
    return float4(in.color.r * intensity, in.color.g * intensity, in.color.b * intensity, in.color.w * intensity);
    
}
