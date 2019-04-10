//
//  AKLine.swift
//  AugmentKit
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

// MARK: - AKLine

/**
 A three dimensional line object
 */
public struct AKLine: Equatable {
    /**
     The location of the start of the line
     */
    public var point0: AKVector = AKVector(x: 0, y: 0, z: 0)
    /**
     The location of the end of the line
     */
    public var point1: AKVector = AKVector(x: 0, y: 0, z: 0)
    /**
     Initialize with two `AKVector` objects representing the starting and ending points
     */
    public init(point0: AKVector, point1: AKVector) {
        self.point0 = point0
        self.point1 = point1
    }
    /**
     Initialize with two `SIMD3<Double>` objects representing the starting and ending points
     */
    public init(point0: double3, point1: double3) {
        self.point0 = AKVector(point0)
        self.point1 = AKVector(point1)
    }
}
