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
// These are inspired the filament BRDF shader functions
// See: https://github.com/google/filament
//

#include <metal_stdlib>
using namespace metal;

#import "../Common.h"

#ifndef AK_SHADERS_BDRFFUNCTIONS
#define AK_SHADERS_BDRFFUNCTIONS

//------------------------------------------------------------------------------
// Specular BRDF implementations
//------------------------------------------------------------------------------

/// Walter et al. 2007, "Microfacet Models for Refraction through Rough Surfaces"
/// equivalent to the Trowbridge-Reitz distribution
float D_GGX(float roughness, float nDoth) {
    float oneMinusNDotHSquared = 1.0 - nDoth * nDoth;
    float a = nDoth * roughness;
    float k = roughness / (oneMinusNDotHSquared + a * a);
    float d = k * k * (1.0 / M_PI_F);
    return min(d, MAXFLOAT);
}

/// Burley 2012, "Physically-Based Shading at Disney"
float D_GGX_Anisotropic(float at, float ab, float tDoth, float bDoth, float nDoth) {
    float a2 = at * ab;
    float3 d = float3(ab * tDoth, at * bDoth, a2 * nDoth);
    return min(a2 * sqr(a2 / dot(d, d)) * (1.0 / M_PI_F), MAXFLOAT);
}

/// Estevez and Kulla 2017, "Production Friendly Microfacet Sheen BRDF". Used for Cloth.
float D_Charlie(float roughness, float nDoth) {
    float invAlpha  = 1.0 / roughness;
    float cos2h = nDoth * nDoth;
    float sin2h = max(1.0 - cos2h, 0.0078125); // 2^(-14/2), so sin2h^2 > 0 in fp16
    return (2.0 + invAlpha) * pow(sin2h, invAlpha * 0.5) / (2.0 * M_PI_F);
}

float V_SmithG_GGX(float roughness, float nDotl, float nDotv) {
    float roughnessAlpha = sqr(roughness * 0.5 + 0.5);
    float a² = sqr(roughnessAlpha);
    float bL = sqr(nDotl);
    float bV = sqr(nDotv);
    float GsL = 1.0 / (nDotl + sqrt(a² + bL - a² * bL));
    float GsV = 1.0 / (nDotv + sqrt(a² + bV - a² * bV));
    return GsL * GsV;
}

/// Heitz 2014, "Understanding the Masking-Shadowing Function in Microfacet-Based BRDFs"
float V_SmithGGXCorrelated(float roughness, float nDotv, float nDotl) {
    float a² = sqr(roughness);
    // TODO: lambdaV can be pre-computed for all the lights, it should be moved out of this function
    float lambdaV = nDotl * sqrt((nDotv - a² * nDotv) * nDotv + a²);
    float lambdaL = nDotv * sqrt((nDotl - a² * nDotl) * nDotl + a²);
    float v = 0.5 / (lambdaV + lambdaL);
    // a2=0 => v = 1 / 4*nDotl*nDotv   => min=1/4, max=+inf
    // a2=1 => v = 1 / 2*(nDotl+nDotv) => min=1/4, max=+inf
    // clamp to the maximum value representable
    return min(v, MAXFLOAT);
}

/// Hammon 2017, "PBR Diffuse Lighting for GGX+Smith Microsurfaces"
float V_SmithGGXCorrelated_Fast(float roughness, float nDotv, float nDotl) {
    float v = 0.5 / mix(2.0 * nDotl * nDotv, nDotl + nDotv, roughness);
    return min(v, MAXFLOAT);
}

/// Heitz 2014, "Understanding the Masking-Shadowing Function in Microfacet-Based BRDFs"
/// TODO: lambdaV can be pre-computed for all the lights, it should be moved out of this function
float V_SmithGGXCorrelated_Anisotropic(float at, float ab, float tDotv, float bDotv, float tDotl, float bDotl, float nDotv, float nDotl) {
    float lambdaV = nDotl * length(float3(at * tDotv, ab * bDotv, nDotv));
    float lambdaL = nDotv * length(float3(at * tDotl, ab * bDotl, nDotl));
    float v = 0.5 / (lambdaV + lambdaL);
    return min(v, MAXFLOAT);
}

/// Kelemen 2001, "A Microfacet Based Coupled Specular-Matte BRDF Model with Importance Sampling"
float V_Kelemen(float lDoth) {
    return min(0.25 / (lDoth * lDoth), MAXFLOAT);
}

/// Neubelt and Pettineo 2013, "Crafting a Next-gen Material Pipeline for The Order: 1886". Used for Cloth.
float V_Neubelt(float roughness, float nDotv, float nDotl) {
    return min(1.0 / (4.0 * (nDotl + nDotv - nDotl * nDotv)), MAXFLOAT);
}

/// Schlick 1994, "An Inexpensive BRDF Model for Physically-Based Rendering"
float3 F_Schlick3(float3 f0, float f90, float vDoth) {
    float f = pow(clamp(1.0 - vDoth, 0.0, 1.0), 5.0);
    return f + f0 * (f90 - f);
}

float F_Schlick(float f0, float f90, float vDoth) {
    return f0 + (1.0 - f0) * pow(clamp(1.0 - vDoth, 0.0, 1.0), 5.0);
}

//------------------------------------------------------------------------------
// Specular BRDF dispatch
//------------------------------------------------------------------------------

// Schlick Fresnel Approximation:
// F0 + (F90 - F0) * pow(1.0 - vDoth, 5.0)
//
// F0 is the Fresnel of the material at 0º (normal incidence)
// F0 can be approximated by a constant 0.04 (water/glass)
//
// F90 is the Fresnel of the material at 90º
// F90 can be approximated by 1.0 because Fresnel goes to 1 as the angle of incidence goes to 90º
//
float3 Fresnel(float3 f0, float vDoth) {
    float f90 = saturate(dot(f0, float3(50.0 * 0.33)));
    return F_Schlick3(f0, f90, vDoth);
}

float distribution(float roughness, float nDoth) {
    return D_GGX(roughness, nDoth);
}

float distributionAnisotropic(float at, float ab, float tDoth, float bDoth, float nDoth) {
    return D_GGX_Anisotropic(at, ab, tDoth, bDoth, nDoth);
}

float distributionClearCoat(float roughness, float nDoth) {
    return D_GGX(roughness, nDoth);
}

float distributionCloth(float roughness, float nDoth) {
    // Charlie
    return D_Charlie(roughness, nDoth);
}

float visibility(float roughness, float nDotv, float nDotl) {
    // Correct
    return V_SmithGGXCorrelated(roughness, nDotv, nDotl);
    // Fast
//    return V_SmithGGXCorrelated_Fast(roughness, nDotv, nDotl);
    // Less shiney
//    return V_SmithG_GGX(roughness, nDotv, nDotl);
}

float visibilityAnisotropic(float roughness, float at, float ab, float tDotv, float bDotv, float tDotl, float bDotl, float nDotv, float nDotl) {
    return V_SmithGGXCorrelated_Anisotropic(at, ab, tDotv, bDotv, tDotl, bDotl, nDotv, nDotl);
}

float visibilityClearCoat(float lDoth) {
    return V_Kelemen(lDoth);
}

float visibilityCloth(float roughness, float nDotv, float nDotl) {
    return V_Neubelt(roughness, nDotv, nDotl);
}

//------------------------------------------------------------------------------
// Diffuse BRDF implementations
//------------------------------------------------------------------------------

float Fd_Lambert() {
    return 1.0 / M_PI_F;
}

/// Burley 2012, "Physically-Based Shading at Disney"
float Fd_Burley(float roughness, float nDotv, float nDotl, float lDoth) {
    float f90 = 0.5 + 2.0 * roughness * lDoth * lDoth;
    float lightScatter = F_Schlick(1.0, f90, nDotl);
    float viewScatter  = F_Schlick(1.0, f90, nDotv);
    return lightScatter * viewScatter * (1.0 / M_PI_F);
}

/// Energy conserving wrap diffuse term, does *not* include the divide by pi. Used for Cloth.
float Fd_Wrap(float nDotl, float w) {
    return saturate((nDotl + w) / sqr(1.0 + w));
}

//------------------------------------------------------------------------------
// Diffuse BRDF dispatch
//------------------------------------------------------------------------------

float diffuse(float roughness, float nDotv, float nDotl, float lDoth) {
    // LAMBERT
    return Fd_Lambert();
    // BURLEY
//    return Fd_Burley(roughness, nDotv, nDotl, lDoth);
}

//------------------------------------------------------------------------------
// Index of refraction (IOR)
//------------------------------------------------------------------------------

float iorToF0(float transmittedIor, float incidentIor) {
    return sqr((transmittedIor - incidentIor) / (transmittedIor + incidentIor));
}

float f0ToIor(float f0) {
    float r = sqrt(f0);
    return (1.0 + r) / (1.0 - r);
}

float3 f0ClearCoatToSurface(float3 f0) {
    // Approximation of iorTof0(f0ToIor(f0), 1.5)
    // This assumes that the clear coat layer has an IOR of 1.5
    return saturate(f0 * (f0 * (0.941892 - 0.263008 * f0) + 0.346479) - 0.0285998);
}

#endif /* AK_SHADERS_BDRFFUNCTIONS */
