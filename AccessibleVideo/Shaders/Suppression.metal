//
//  Suprpession.metal
//  AccessibleVideo
//
//  Created by Jamie Scanlon on 5/15/16.
//  Copyright © 2016 Tenth Letter Made LLC. All rights reserved.
//

#include <metal_stdlib>
#include "Common.metal"

using namespace metal;

fragment half4 suppression_directional_nonmaximum(FILTER_SHADER_ARGS_FRAME_ONLY)
{

    half3 currentGradientAndDirection = currentFrame.sample(bilinear, inFrag.m_TexCoord).rgb;
    int2 gradientDirection = (int2(currentGradientAndDirection.gb * 2) - 1) * int2(currentFrame.get_width(), currentFrame.get_height());
    
    half firstSampledGradientMagnitude = currentFrame.sample(bilinear, inFrag.m_TexCoord, gradientDirection).r;
    half secondSampledGradientMagnitude = currentFrame.sample(bilinear, inFrag.m_TexCoord, -gradientDirection).r;
    
    half multiplier = step(firstSampledGradientMagnitude, currentGradientAndDirection.r);
    multiplier = multiplier * step(secondSampledGradientMagnitude, currentGradientAndDirection.r);
    
    half highThreshold = HIGH_THRESHOLD;
    half lowThreshold = LOW_THRESHOLD;
    
    half thresholdCompliance = smoothstep(lowThreshold, highThreshold, currentGradientAndDirection.r);
    multiplier = multiplier * thresholdCompliance;
    
    return half4(multiplier, multiplier, multiplier, 1.0);
    
    /*
     vec3 currentGradientAndDirection = texture2D(inputImageTexture, textureCoordinate).rgb;
     vec2 gradientDirection = ((currentGradientAndDirection.gb * 2.0) - 1.0) * vec2(texelWidth, texelHeight);
     
     float firstSampledGradientMagnitude = texture2D(inputImageTexture, textureCoordinate + gradientDirection).r;
     float secondSampledGradientMagnitude = texture2D(inputImageTexture, textureCoordinate - gradientDirection).r;
     
     float multiplier = step(firstSampledGradientMagnitude, currentGradientAndDirection.r);
     multiplier = multiplier * step(secondSampledGradientMagnitude, currentGradientAndDirection.r);
     
     float thresholdCompliance = smoothstep(lowerThreshold, upperThreshold, currentGradientAndDirection.r);
     multiplier = multiplier * thresholdCompliance;
     
     gl_FragColor = vec4(multiplier, multiplier, multiplier, 1.0);
     */
    
}

fragment half4 suppression_threshold_nonmaximum(FILTER_SHADER_ARGS_FRAME_ONLY)
{
    
    half m11 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(-1,+1)).r; // Bottom Left
    half m12 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(0,+1)).r; // Bottom
    half m13 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(+1,+1)).r; // Bottom Right
    half m21 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(-1,0)).r; // Left
    half m23 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(+1,0)).r; // Right
    half m31 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(-1,-1)).r; // Top Left
    half m32 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(0,-1)).r; // Top
    half m33 = currentFrame.sample(bilinear, inFrag.m_TexCoord,int2(+1,-1)).r; // Top Right
    
    half4 centerColor = currentFrame.sample(bilinear, inFrag.m_TexCoord);
    
    // Use a tiebreaker for pixels to the left and immediately above this one
    half multiplier = 1.0 - step(centerColor.r, m32);
    multiplier = multiplier * (1.0 - step(centerColor.r, m31));
    multiplier = multiplier * (1.0 - step(centerColor.r, m21));
    multiplier = multiplier * (1.0 - step(centerColor.r, m11));
    
    half maxValue = max(centerColor.r, m12);
    maxValue = max(maxValue, m13);
    maxValue = max(maxValue, m23);
    maxValue = max(maxValue, m33);
    
    half finalValue = centerColor.r * step(maxValue, centerColor.r) * multiplier;
    finalValue = step(LOW_THRESHOLD, finalValue);
    
    return half4(finalValue, finalValue, finalValue, 1.0);
    
    /*
     lowp float bottomColor = texture2D(inputImageTexture, bottomTextureCoordinate).r;
     lowp float bottomLeftColor = texture2D(inputImageTexture, bottomLeftTextureCoordinate).r;
     lowp float bottomRightColor = texture2D(inputImageTexture, bottomRightTextureCoordinate).r;
     lowp vec4 centerColor = texture2D(inputImageTexture, textureCoordinate);
     lowp float leftColor = texture2D(inputImageTexture, leftTextureCoordinate).r;
     lowp float rightColor = texture2D(inputImageTexture, rightTextureCoordinate).r;
     lowp float topColor = texture2D(inputImageTexture, topTextureCoordinate).r;
     lowp float topRightColor = texture2D(inputImageTexture, topRightTextureCoordinate).r;
     lowp float topLeftColor = texture2D(inputImageTexture, topLeftTextureCoordinate).r;
     
     // Use a tiebreaker for pixels to the left and immediately above this one
     lowp float multiplier = 1.0 - step(centerColor.r, topColor);
     multiplier = multiplier * (1.0 - step(centerColor.r, topLeftColor));
     multiplier = multiplier * (1.0 - step(centerColor.r, leftColor));
     multiplier = multiplier * (1.0 - step(centerColor.r, bottomLeftColor));
     
     lowp float maxValue = max(centerColor.r, bottomColor);
     maxValue = max(maxValue, bottomRightColor);
     maxValue = max(maxValue, rightColor);
     maxValue = max(maxValue, topRightColor);
     
     lowp float finalValue = centerColor.r * step(maxValue, centerColor.r) * multiplier;
     finalValue = step(threshold, finalValue);
     
     gl_FragColor = vec4(finalValue, finalValue, finalValue, 1.0);
     */

}