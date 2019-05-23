//
//  AKCube.swift
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

/**
 A three dimensional cube object
 */
public struct AKCube: Equatable {
    
    public var position: AKVector
    public var extent: AKVector
    
    /**
     Given a point, returns `true` if the point is inside the cube. Otherwise returns `false`.
     - Parameters:
     - point: An `AKVector` object. If the point represented by the vector is inside the cube, this function returns `true`. Otherwise returns `false`.
     - Returns: A `Bool` which, if `true`, means that the point is inside the cube.
     */
    public func contains(_ point: AKVector) -> Bool {
        let minX = position.x - extent.x
        let minY = position.y - extent.y
        let minZ = position.z - extent.z
        let maxX = position.x + extent.x
        let maxY = position.y + extent.y
        let maxZ = position.z + extent.z
        
        return ( point.x > minX && point.y > minY && point.z > minZ ) && ( point.x < maxX && point.y < maxY && point.z < maxZ )
    }
    
    /**
     Returns the volume of the cube.
     - Returns: The volume of the cube.
     */
    public func volume() -> Double {
        return extent.x * extent.y * extent.z
    }
}
