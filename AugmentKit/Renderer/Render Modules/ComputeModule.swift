//
//  ComputeModule.swift
//  AugmentKit
//
//  MIT License
//
//  Copyright (c) 2019 JamieScanlon
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

import Foundation
import simd

// MARK: - ComputeModule

/// A module to perform a compute function
protocol ComputeModule: ShaderModule {
    
    //
    // Bootstrap
    //
    
    /// After this function is called, The Compute Pass Desciptors, Textures, Buffers, Compute Pipeline State Descriptors should all be set up.
    func loadPipeline(withMetalLibrary metalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider, textureBundle: Bundle, forComputePass computePass: ComputePass?) -> ThreadGroup?
    
    //
    // Per Frame Updates
    //
    
    /// Update and dispatch the command encoder. At the end of this method it is expected that `dispatchThreads` or dispatchThreadgroups` is called.
    func dispatch(withComputePass computePass: ComputePass, sharedModules: [SharedRenderModule]?)
}

/// A `ComputePass` that is part of a render pipeline and used to prepare data for subsequent draw calls
protocol PreRenderComputeModule: ComputeModule {
    
    //
    // Per Frame Updates
    //
    
    /// Update the buffer(s) data from information about the render
    func prepareToDraw(withAllEntities: [AKEntity], cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties, shadowProperties: ShadowProperties, computePass: ComputePass, renderPass: RenderPass?)
    
}

extension PreRenderComputeModule {
    
    // MARK: Util
    
    func getRGB(from colorTemperature: CGFloat) -> SIMD3<Float> {
        
        let temp = Float(colorTemperature) / 100
        
        var red: Float = 127
        var green: Float = 127
        var blue: Float = 127
        
        if temp <= 66 {
            red = 255
            green = temp
            green = 99.4708025861 * log(green) - 161.1195681661
            if temp <= 19 {
                blue = 0
            } else {
                blue = temp - 10
                blue = 138.5177312231 * log(blue) - 305.0447927307
            }
        } else {
            red = temp - 60
            red = 329.698727446 * pow(red, -0.1332047592)
            green = temp - 60
            green = 288.1221695283 * pow(green, -0.0755148492 )
            blue = 255
        }
        
        let clamped = clamp(SIMD3<Float>(red, green, blue), min: 0, max: 255)
        return SIMD3<Float>(clamped.x, clamped.y, clamped.z)
        
    }
}
