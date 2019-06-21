//
//  AKVector.swift
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

import Foundation
import simd

/**
 A three dimensional vector object
 */
public struct AKVector: Equatable {
    /**
     The X component
     */
    public var x: Double = 0
    /**
     The Y component
     */
    public var y: Double = 0
    /**
     The Z component
     */
    public var z: Double = 0
    
    /**
     Initialize with `x`, `y`, and `z` components
     */
    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
    
    /**
     Initialize with `x`, `y`, and `z` components
     */
    public init(x: Float, y: Float, z: Float) {
        self.x = Double(x)
        self.y = Double(y)
        self.z = Double(z)
    }
    
    /**
     Initialize with `x`, `y`, and `z` components
     */
    public init(x: Int, y: Int, z: Int) {
        self.x = Double(x)
        self.y = Double(y)
        self.z = Double(z)
    }
    
    /**
     Initialize with a `SIMD3<Float>` object
     */
    public init(_ float3: SIMD3<Float>) {
        self.x = Double(float3.x)
        self.y = Double(float3.y)
        self.z = Double(float3.z)
    }
    
    /**
     Initialize with a `SIMD3<Double>` object
     */
    public init(_ double3: SIMD3<Double>) {
        self.x = double3.x
        self.y = double3.y
        self.z = double3.z
    }
    
    /**
     Normalize the vector
     */
    public mutating func normalize() {
        let newVecor = simd.normalize(SIMD3<Double>(x, y, z))
        x = newVecor.x
        y = newVecor.y
        z = newVecor.z
    }
    /**
     Creates a normalized vector from the current vector
     */
    public func normalized() -> AKVector {
        let newVecor = simd.normalize(SIMD3<Double>(x, y, z))
        return AKVector(x: newVecor.x, y: newVecor.y, z: newVecor.z)
    }
    
    /**
     Returns a `SIMD3<Double>` representation of the vector
     */
    public func simdRepresentation() -> SIMD3<Double> {
        return SIMD3<Double>(x, y, z)
    }
    
}
