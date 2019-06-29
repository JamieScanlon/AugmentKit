//
//  CompositeShaders.metal
//  AugmentKit
//
//  Created by Marvin Scanlon on 6/24/19.
//  Copyright © 2019 TenthLetterMade. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

#import "../ShaderTypes.h"
#import "../Common.h"


typedef struct {
    float2 position;
    float2 texCoord;
} CompositeVertex;

typedef struct {
    float4 position [[position]];
    float2 texCoordCamera;
    float2 texCoordScene;
    int useDepth;
    float projection22;
    float projection23;
    float projection32;
    float projection33;
} CompositeColorInOut;

// Convert from YCbCr to rgb
float4 ycbcrToRGBTransform(float4 y, float4 CbCr) {
    const float4x4 ycbcrToRGBTransform = float4x4(
                                                  float4(+1.0000f, +1.0000f, +1.0000f, +0.0000f),
                                                  float4(+0.0000f, -0.3441f, +1.7720f, +0.0000f),
                                                  float4(+1.4020f, -0.7141f, +0.0000f, +0.0000f),
                                                  float4(-0.7010f, +0.5291f, -0.8860f, +1.0000f)
                                                  );
    
    float4 ycbcr = float4(y.r, CbCr.rg, 1.0);
    return ycbcrToRGBTransform * ycbcr;
}

// Composite the image vertex function.
vertex CompositeColorInOut compositeImageVertexTransform(constant SharedUniforms &sharedUniforms [[ buffer(kBufferIndexSharedUniforms) ]],
                                                         const device CompositeVertex* cameraVertices [[ buffer(kBufferIndexCameraVertices) ]],
                                                         const device CompositeVertex* sceneVertices [[ buffer(kBufferIndexSceneVerticies) ]],
//                                                         constant int &drawCallIndex [[ buffer(kBufferIndexDrawCallIndex) ]],
//                                                         constant int &drawCallGroupIndex [[ buffer(kBufferIndexDrawCallGroupIndex) ]],
                                                         unsigned int vid [[ vertex_id ]]) {
    CompositeColorInOut out;
//    int argumentBufferIndex = drawCallIndex;
    
    const device CompositeVertex& cv = cameraVertices[vid];
    const device CompositeVertex& sv = sceneVertices[vid];
    
    out.position = float4(cv.position, 0.0, 1.0);
    out.texCoordCamera = cv.texCoord;
    out.texCoordScene = sv.texCoord;
//    out.useDepth = arguments[argumentBufferIndex].useDepth;
//    out.projection22 = arguments[argumentBufferIndex].projectionMatrix[2][2];
//    out.projection23 = arguments[argumentBufferIndex].projectionMatrix[2][3];
//    out.projection32 = arguments[argumentBufferIndex].projectionMatrix[3][2];
//    out.projection33 = arguments[argumentBufferIndex].projectionMatrix[3][3];
    
    out.useDepth = sharedUniforms.useDepth;
    out.projection22 = sharedUniforms.projectionMatrix[2][2];
    out.projection23 = sharedUniforms.projectionMatrix[2][3];
    out.projection32 = sharedUniforms.projectionMatrix[3][2];
    out.projection33 = sharedUniforms.projectionMatrix[3][3];
    
    return out;
}

// Composite the image fragment function.
fragment half4 compositeImageFragmentShader(CompositeColorInOut in [[ stage_in ]],
                                            texture2d<float, access::sample> capturedImageTextureY [[ texture( kTextureIndexY ) ]],
                                            texture2d<float, access::sample> capturedImageTextureCbCr [[ texture( kTextureIndexCbCr ) ]],
                                            texture2d<float, access::sample> sceneColorTexture [[ texture( kTextureIndexSceneColor ) ]],
                                            depth2d<float, access::sample> sceneDepthTexture [[ texture( kTextureIndexSceneDepth ) ]],
                                            texture2d<float, access::sample> alphaTexture [[ texture( kTextureIndexAlpha ) ]],
                                            texture2d<float, access::sample> dilatedDepthTexture [[ texture( kTextureIndexDialatedDepth ) ]]
                                            )
{
    constexpr sampler colorSampler(address::clamp_to_edge, filter::linear);
//    constexpr sampler colorSampler(mip_filter::linear, mag_filter::linear, min_filter::linear);
    
    
    
    float2 cameraTexCoord = in.texCoordCamera;
    float2 sceneTexCoord = in.texCoordScene;
    
    // Sample Y and CbCr textures to get the YCbCr color at the given texture coordinate.
    float4 rgb = ycbcrToRGBTransform(capturedImageTextureY.sample(colorSampler, cameraTexCoord), capturedImageTextureCbCr.sample(colorSampler, cameraTexCoord));
    
    // Perform composition with the matting.
    half4 sceneColor = half4(sceneColorTexture.sample(colorSampler, sceneTexCoord));
    float sceneDepth = sceneDepthTexture.sample(colorSampler, sceneTexCoord);
    
    half4 cameraColor = half4(rgb);
    half alpha = half(alphaTexture.sample(colorSampler, cameraTexCoord).r);
    
    half showOccluder = 1.0;
    
    if (in.useDepth) {
        float dilatedLinearDepth = half(dilatedDepthTexture.sample(colorSampler, cameraTexCoord).r);
        
        // Project linear depth with the projection matrix.
        float dilatedDepth = clamp((in.projection22 * -dilatedLinearDepth + in.projection32) / (in.projection23 * -dilatedLinearDepth + in.projection33), 0.0, 1.0);
        
        showOccluder = (half)step(dilatedDepth, sceneDepth); // forwardZ case
    }
    
    
    half4 occluderResult = mix(sceneColor, cameraColor, alpha);
    half4 mattingResult = mix(sceneColor, occluderResult, showOccluder);
    return mattingResult;
    
}
