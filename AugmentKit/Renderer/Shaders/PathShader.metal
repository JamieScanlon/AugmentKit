//
//  PathShader.metal
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
//  Shader that renders paths.
//

#include <metal_stdlib>
using namespace metal;

// Include header shared between this Metal shader code and C code executing Metal API commands
#import "../ShaderTypes.h"

struct PathVertexIn {
    float4 position [[attribute(kVertexAttributePosition)]];
};

struct PathFragmentInOut {
    float4 position [[position]];
    float4 color;
    ushort iid;
    int drawCallIndex;
    int drawCallGroupIndex;
    float3 shadowCoord;
};

vertex PathFragmentInOut pathVertexShader(PathVertexIn in [[stage_in]],
                                          device PrecalculatedParameters *arguments [[ buffer(kBufferIndexPrecalculationOutputBuffer) ]],
                                          constant int &drawCallIndex [[ buffer(kBufferIndexDrawCallIndex) ]],
                                          constant int &drawCallGroupIndex [[ buffer(kBufferIndexDrawCallGroupIndex) ]],
                                          uint vid [[vertex_id]],
                                          ushort iid [[instance_id]]
                                          ){
    
    PathFragmentInOut out;
    
    // Make position a float4 to perform 4x4 matrix math on it
    float4 position = in.position;
    int argumentBufferIndex = drawCallIndex;
    
    float4x4 modelViewProjectionMatrix = arguments[argumentBufferIndex].modelViewProjectionMatrix;
    
    out.position = modelViewProjectionMatrix * position;
    
    out.iid = iid;
    out.drawCallIndex = drawCallIndex;
    out.drawCallGroupIndex = drawCallGroupIndex;
    
    // Shadow Coord
    out.shadowCoord = (arguments[argumentBufferIndex].shadowMVPTransformMatrix * out.position).xyz;

    
    return out;
    
}

fragment float4 pathFragmentShader( PathFragmentInOut in [[stage_in]],
                                    constant MaterialUniforms &materialUniforms [[ buffer(kBufferIndexMaterialUniforms) ]],
                                    constant AnchorEffectsUniforms *anchorEffectsUniforms [[ buffer(kBufferIndexAnchorEffectsUniforms) ]]
                                   ){
    
    int argumentBufferIndex = in.drawCallIndex;
    float4 intermediate_color = materialUniforms.baseColor;
    
    // Apply effects
    float4 final_color = float4(intermediate_color.rgb * anchorEffectsUniforms[argumentBufferIndex].tint, intermediate_color.a * anchorEffectsUniforms[argumentBufferIndex].alpha);
    
    return final_color;
    
}
