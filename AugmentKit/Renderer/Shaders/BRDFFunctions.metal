//
//  BRDFFunctions.metal
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
// This is an atempted port of the filament BRDF shader for Android
// See: https://github.com/google/filament
//

#include <metal_stdlib>
using namespace metal;

#import "../Common.h"

#ifndef AK_SHADERS_BDRFFUNCTIONS
#define AK_SHADERS_BDRFFUNCTIONS

// Schlick Fresnel Approximation:
// F0 + (F90 - F0) * pow(1.0 - dotProduct, 5.0)
//
// F0 is the Fresnel of the material at 0º (normal incidence)
// F0 can be approximated by a constant 0.04 (water/glass)
//
// F90 is the Fresnel of the material at 90º
// F90 can be approximated by 1.0 because Fresnel goes to 1 as the angle of incidence goes to 90º
//
float Fresnel(float F0, float F90, float dotProduct) {
    return F0 + (F90 - F0) * pow(clamp(1.0 - dotProduct, 0.0, 1.0), 5.0);
}

// dotProduct is either nDotl or nDotv
// roughness = Perceptually linear roughness
float smithG_GGX(float dotProduct, float roughness) {
    float a² = sqr(roughness);
    float b = sqr(dotProduct);
    return 1.0 / (dotProduct + sqrt(a² + b - a² * b));
}

// We are using Generalized Trowbridge-Reitz to calculate Specular D
// DGGX(h) = α² / π((n⋅h)²(α²−1)+1)²
float TrowbridgeReitzNDF(float nDoth, float roughness) {
    if (roughness >= 1.0) return 1.0 / M_PI_F;
    float a² = sqr(roughness);
    float d = sqr(nDoth) * (a² - 1) + 1;
    return a² / (M_PI_F * sqr(d));
}

// Generalized Trowbridge-Reitz, with GGX divided out
float GTR2_aniso(float nDoth, float HdotX, float HdotY, float ax, float ay) {
    return 1.0 / ( M_PI_F * ax*ay * sqr( sqr(HdotX/ax) + sqr(HdotY/ay) + nDoth * nDoth ));
}

#endif /* AK_SHADERS_BDRFFUNCTIONS */
