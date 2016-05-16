//
//  WeakPixelInclusion.metal
//  AccessibleVideo
//
//  Created by Jamie Scanlon on 5/15/16.
//  Copyright © 2016 Luke Groeninger. All rights reserved.
//

#include <metal_stdlib>
#include "Common.metal"
using namespace metal;

fragment half4 weak_pixel_inclusion(FILTER_SHADER_ARGS_FRAME_ONLY)
{

    half m11 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(-1,+1)).r; // Bottom Left
    half m12 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(0,+1)).r; // Bottom
    half m13 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(+1,+1)).r; // Bottom Right
    half m21 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(-1,0)).r; // Left
    half m22 = currentFrame.sample(bilinear, inFrag.m_TexCoord).r; // Center
    half m23 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(+1,0)).r; // Right
    half m31 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(-1,-1)).r; // Top Left
    half m32 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(0,-1)).r; // Top
    half m33 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(+1,-1)).r; // Top Right
    
    half pixelIntensitySum = m11 + m33 + m31 + m13 + m21 + m23 + m12 + m32 + m22;
    half sumTest = step(half(1.5), pixelIntensitySum);
    half pixelTest = step(half(0.01), m22);
    
    return half4(half3(sumTest * pixelTest), 1.0);
    
    /*
     float bottomLeftIntensity = texture2D(inputImageTexture, bottomLeftTextureCoordinate).r;
     float topRightIntensity = texture2D(inputImageTexture, topRightTextureCoordinate).r;
     float topLeftIntensity = texture2D(inputImageTexture, topLeftTextureCoordinate).r;
     float bottomRightIntensity = texture2D(inputImageTexture, bottomRightTextureCoordinate).r;
     float leftIntensity = texture2D(inputImageTexture, leftTextureCoordinate).r;
     float rightIntensity = texture2D(inputImageTexture, rightTextureCoordinate).r;
     float bottomIntensity = texture2D(inputImageTexture, bottomTextureCoordinate).r;
     float topIntensity = texture2D(inputImageTexture, topTextureCoordinate).r;
     float centerIntensity = texture2D(inputImageTexture, textureCoordinate).r;
     
     float pixelIntensitySum = bottomLeftIntensity + topRightIntensity + topLeftIntensity + bottomRightIntensity + leftIntensity + rightIntensity + bottomIntensity + topIntensity + centerIntensity;
     float sumTest = step(1.5, pixelIntensitySum);
     float pixelTest = step(0.01, centerIntensity);
     
     gl_FragColor = vec4(vec3(sumTest * pixelTest), 1.0);
     */
}