//
//  SurfaceShader.metal
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
#import "../Common.h"

constant bool has_base_color_map [[ function_constant(kFunctionConstantBaseColorMapIndex) ]];
constexpr sampler linearSampler (address::repeat, min_filter::linear, mag_filter::linear, mip_filter::linear);
constexpr sampler shadowSampler(coord::normalized, filter::linear, mip_filter::none, address::clamp_to_edge, compare_func::less);

struct SurfaceVertex {
    float3 position      [[attribute(kVertexAttributePosition)]];
    float2 texCoord      [[attribute(kVertexAttributeTexcoord)]];
    float3 normal        [[attribute(kVertexAttributeNormal)]];
    float3 tangent       [[attribute(kVertexAttributeTangent)]];
};

struct SurfaceVertexOutput {
    float4 position [[position]];
    float3 normal;
    float3 tangent;
    float2 texCoord [[ function_constant(has_base_color_map) ]];
    float3 shadowCoord;
    ushort iid;
};

// MARK: Vertex function
vertex SurfaceVertexOutput surfaceGeometryVertexTransform(SurfaceVertex in [[stage_in]],
                                                device PrecalculatedParameters *arguments [[ buffer(kBufferIndexPrecalculationOutputBuffer) ]],
                                                constant int &drawCallIndex [[ buffer(kBufferIndexDrawCallIndex) ]],
                                                constant int &drawCallGroupIndex [[ buffer(kBufferIndexDrawCallGroupIndex) ]],
                                                uint vid [[vertex_id]],
                                                ushort iid [[instance_id]]) {
    SurfaceVertexOutput out;
    
    // Make position a float4 to perform 4x4 matrix math on it
    float4 position = float4(in.position, 1.0);
    int argumentBufferIndex = drawCallIndex;
    
    float3x3 normalMatrix = arguments[argumentBufferIndex].normalMatrix;
    float4x4 modelMatrix = arguments[argumentBufferIndex].modelMatrix;
    float4x4 modelViewProjectionMatrix = arguments[argumentBufferIndex].modelViewProjectionMatrix;
    
    out.position = modelViewProjectionMatrix * position;
    
    // Rotate our normals to world coordinates
    out.normal = normalMatrix * in.normal;
    out.tangent = normalMatrix * in.tangent;
    
    // Texture Coord
    // Pass along the texture coordinate of our vertex such which we'll use to sample from texture's
    //   in our fragment function, if we need it
    if (has_base_color_map) {
        out.texCoord = float2(in.texCoord.x, 1.0f - in.texCoord.y);
    }
    
    // Shadow Coord
    float4x4 directionalLightMVP = arguments[argumentBufferIndex].directionalLightMVP;
    out.shadowCoord = (arguments[argumentBufferIndex].shadowMVPTransformMatrix * directionalLightMVP * modelMatrix * position).xyz;
    
    out.iid = iid;
    
    return out;
}

vertex SurfaceVertexOutput rawSurfaceGeometryVertexTransform(SurfaceVertex in [[stage_in]],
                                                             device RawVertexBuffer *vertexData [[ buffer(kBufferIndexRawVertexData) ]],
                                                             device PrecalculatedParameters *arguments [[ buffer(kBufferIndexPrecalculationOutputBuffer) ]],
                                                             constant int &drawCallIndex [[ buffer(kBufferIndexDrawCallIndex) ]],
                                                             constant int &drawCallGroupIndex [[ buffer(kBufferIndexDrawCallGroupIndex) ]],
                                                             uint vid [[vertex_id]],
                                                             ushort iid [[instance_id]]) {
    SurfaceVertexOutput out;
    
    // Make position a float4 to perform 4x4 matrix math on it
    float4 position = float4(vertexData[vid].position, 1.0);
    int argumentBufferIndex = drawCallIndex;
    
    float3x3 normalMatrix = arguments[argumentBufferIndex].normalMatrix;
    float4x4 modelMatrix = arguments[argumentBufferIndex].modelMatrix;
    float4x4 modelViewProjectionMatrix = arguments[argumentBufferIndex].modelViewProjectionMatrix;
    
    out.position = modelViewProjectionMatrix * position;
    
    // Rotate our normals to world coordinates
    out.normal = normalMatrix * vertexData[vid].normal;
    out.tangent = normalMatrix * vertexData[vid].tangent;
    
    // Texture Coord
    // Pass along the texture coordinate of our vertex such which we'll use to sample from texture's
    //   in our fragment function, if we need it
    if (has_base_color_map) {
        out.texCoord = float2(vertexData[vid].texCoord.x, 1.0f - vertexData[vid].texCoord.y);
    }
    
    // Shadow Coord
    float4x4 directionalLightMVP = arguments[argumentBufferIndex].directionalLightMVP;
    out.shadowCoord = (arguments[argumentBufferIndex].shadowMVPTransformMatrix * directionalLightMVP * modelMatrix * position).xyz;
    
    out.iid = iid;
    
    return out;
}

// MARK: A simple fragment shader that uses the base color only
fragment float4 surfaceFragmentLightingSimple(SurfaceVertexOutput in [[stage_in]],
                                                     constant MaterialUniforms &materialUniforms [[ buffer(kBufferIndexMaterialUniforms) ]],
                                                     constant EnvironmentUniforms *environmentUniforms [[ buffer(kBufferIndexEnvironmentUniforms) ]],
                                                     constant AnchorEffectsUniforms *anchorEffectsUniforms [[ buffer(kBufferIndexAnchorEffectsUniforms) ]],
                                                     texture2d<float> baseColorMap [[ texture(kTextureIndexColor), function_constant(has_base_color_map) ]],
                                                     texturecube<float> environmentCubemap [[  texture(kTextureIndexEnvironmentMap) ]],
                                                     depth2d<float> shadowMap [[ texture(kTextureIndexShadowMap) ]]
                                                     ) {
    
    float4 final_color = float4(0);
    ushort iid = in.iid;
    
    float4 baseColor = has_base_color_map ? srgbToLinear(baseColorMap.sample(linearSampler, in.texCoord.xy)) : materialUniforms.baseColor;
    
    // Draw shadows
    // Compare the depth value in the shadow map to the depth value of the fragment in the sun's.
    // frame of reference.  If the sample is occluded, it will be zero.
    float shadowSample = shadowMap.sample_compare(shadowSampler, in.shadowCoord.xy, in.shadowCoord.z);
    // Lighten shadow to account for ambient light
    float shadowContribution = shadowSample + 0.4;
    // Clamp shadow values to 1;
    shadowContribution = min(1.0, shadowContribution);
    float4 shadowColor = float4(0.0, 0.0, 0.0, 1 - shadowContribution); // Black
    
    float4 intermediateColor = baseColor + shadowColor;
    
    // Apply effects
    final_color = float4(intermediateColor.rgb * anchorEffectsUniforms[iid].tint, intermediateColor.a * anchorEffectsUniforms[iid].alpha);
    
    // FIXME: discard_fragment may have performance implications.
    // see: http://metalbyexample.com/translucency-and-transparency/
    if ( final_color.w <= 0.01f ) {
        discard_fragment();
    }
    
    return final_color;
    
}

