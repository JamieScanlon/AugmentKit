//
//  Suprpession.metal
//  AccessibleVideo
//
//  Created by Jamie Scanlon on 5/15/16.
//  Copyright © 2016 Luke Groeninger. All rights reserved.
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