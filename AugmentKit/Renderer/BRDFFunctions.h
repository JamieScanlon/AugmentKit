//
//  BRDFFunctions.h
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


#ifndef BRDFFunctions_h
#define BRDFFunctions_h

#include <simd/simd.h>

vector_float3 fresnel(vector_float3 f0, float lDoth);
float distribution(float roughness, float nDoth);
float distributionAnisotropic(float at, float ab, float tDoth, float bDoth, float nDoth);
float distributionClearCoat(float roughness, float nDoth);
float distributionCloth(float roughness, float nDoth);
float visibility(float roughness, float nDotv, float nDotl);
float visibilityAnisotropic(float roughness, float at, float ab, float tDotv, float bDotv, float tDotl, float bDotl, float nDotv, float nDotl);
float visibilityClearCoat(float lDoth);
float visibilityCloth(float nDotv, float nDotl);

float D_GGX(float roughness, float nDoth);
float D_GGX_Anisotropic(float at, float ab, float tDoth, float bDoth, float nDoth);
float D_Ashikhmin(float roughness, float nDoth);
float D_Charlie(float roughness, float nDoth);
float V_SmithG_GGX(float roughness, float nDotv, float nDotl);
float V_SmithGGXCorrelated(float roughness, float nDotv, float nDotl);
float V_SmithGGXCorrelated_Fast(float roughness, float nDotv, float nDotl);
float V_SmithGGXCorrelated_Anisotropic(float at, float ab, float tDotv, float bDotv, float tDotl, float bDotl, float nDotv, float nDotl);
float V_Kelemen(float lDoth);
float V_Neubelt(float roughness, float nDotv, float nDotl);
vector_float3 F_Schlick3(vector_float3 f0, float f90, float vDoth);
float F_Schlick(float f0, float f90, float vDoth);

float Fd_Lambert();
float Fd_Burley(float roughness, float nDotv, float nDotl, float lDoth);
float Fd_Wrap(float nDotl, float w);

float diffuse(float roughness, float nDotv, float nDotl, float lDoth);

float iorToF0(float transmittedIor, float incidentIor);
float f0ToIor(float f0);
vector_float3 f0ClearCoatToSurface(vector_float3 f0);

#endif /* BRDFFunctions_h */
