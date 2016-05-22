//
//  Shaders.metal
//  AccessibleVideo
//
//  Copyright (c) 2016 Tenth Letter Made LLC. All rights reserved.
//


// Base shaders
//
// These are required for program to run
//

#include "Common.metal"

vertex VertexOut defaultVertex( VertexIn vert [[ stage_in ]], unsigned int vid [[ vertex_id ]])
{
    VertexOut outVertices;
    outVertices.m_Position = float4(vert.m_Position,0.0,1.0);
    outVertices.m_TexCoord = vert.m_TexCoord;
    return outVertices;
}

fragment half4 yuv_rgb(YUV_SHADER_ARGS)
{
    float3 yuv;
    yuv.x = lumaTex.sample(bilinear, inFrag.m_TexCoord).r;
    yuv.yz = chromaTex.sample(bilinear,inFrag.m_TexCoord).rg - float2(0.5);
    return half4(half3(colorParameters->yuvToRGB * yuv),yuv.x);
}

fragment half4 yuv_grayscale(YUV_SHADER_ARGS)
{
    return half4(lumaTex.sample(bilinear, inFrag.m_TexCoord).r);
}

constant half3 W = half3(0.2125, 0.7154, 0.0721);
fragment half4 grayscale(FILTER_SHADER_ARGS_FRAME_ONLY)
{
    half4 textureColor = currentFrame.sample(bilinear, inFrag.m_TexCoord);
    half luminance = dot(textureColor.rgb, W);
    
    return half4(half3(luminance), textureColor.a);
}

fragment half4 blit(FILTER_SHADER_ARGS_LAST_ONLY)
{
    half4 color = half4(lastStage.sample(bilinear, inFrag.m_TexCoord).rgb,1.0);
    return color;
}


fragment half4 invert(FILTER_SHADER_ARGS_LAST_ONLY)
{
    half3 inverse = half3(1.0) - lastStage.sample(bilinear, inFrag.m_TexCoord).rgb;
    return half4(inverse,1.0);
}

// Compute shader for composing two textures, base and overlay, into one by adding the colors
kernel void compose_add(texture2d<float, access::read> base [[ texture(0) ]],
                        texture2d<float, access::read> overlay [[ texture(1) ]],
                        texture2d<float, access::write> dest [[ texture(2) ]],
                        uint2 gid [[ thread_position_in_grid ]]) {
    
    float4 base_color = base.read(gid);
    float4 overlay_color = overlay.read(gid);
    float4 result_color = base_color + overlay_color;
    
    dest.write(result_color, gid);
    
}