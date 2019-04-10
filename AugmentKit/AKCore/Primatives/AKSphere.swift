//
//  AKSphere.swift
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

// MARK: - AKSphere

/**
 A three dimensional spherical object
 */
public struct AKSphere: Equatable {
    /**
     The location of the center of the sphere
     */
    public var center: AKVector
    /**
     The radius of the sphere
     */
    public var radius: Double
    
    /**
     Given a line and a sphere, returns a object that represents intersection of the two.
     - Parameters:
     - withLine: An `AKLine` object. The `point0` property represents the position of the previous `AKPathSegmentAnchor` and the `point1` property represents the position of this anchor.
     - renderSphere: An `AKSphere` object. The point in the line will be recalculated to fit within the sphere if possible.
     - Returns: A `AKSphereLineIntersection` object containing whether the line intersected with the sphere and the resulting intersection points
     */
    public func intersection(with line: AKLine) -> AKSphereLineIntersection {
        
        let point0 = line.point0.simdRepresentation()
        let point1 = line.point1.simdRepresentation()
        let center = self.center.simdRepresentation()
        let renderDistance = radius
        
        let dist0 = length(point0 - center)
        let dist1 = length(point1 - center)
        let isPoint0Inside = dist0 < renderDistance
        let isPoint1Inside = dist1 < renderDistance
        
        // If both points are inside, there is no intersection
        guard !isPoint0Inside || !isPoint1Inside else {
            let line = AKLine(point0: point0, point1: point1)
            return AKSphereLineIntersection(isInside: true, line: line)
        }
        
        let dir = normalize(point1 - point0)
        
        let q = center - point0
        let vDotQ = dot(dir, q)
        let squareDiffs = dot(q, q) - (renderDistance * renderDistance)
        let discriminant = vDotQ * vDotQ - squareDiffs
        if discriminant >= 0 {
            let root = sqrt(discriminant)
            let t0 = (vDotQ - root)
            let t1 = (vDotQ + root)
            if isPoint0Inside && !isPoint1Inside {
                let line = AKLine(point0: point0, point1: point0 + dir * t1)
                return AKSphereLineIntersection(isInside: true, line: line)
            } else if isPoint1Inside && !isPoint0Inside {
                let line = AKLine(point0: point0 + dir * t0, point1: point1)
                return AKSphereLineIntersection(isInside: true, line: line)
            } else if !isPoint1Inside && !isPoint0Inside {
                let line = AKLine(point0: point0 + dir * t0, point1: point0 + dir * t1)
                return AKSphereLineIntersection(isInside: true, line: line)
            } else {
                // Both inside. No intersections
                let line = AKLine(point0: point0, point1: point1)
                return AKSphereLineIntersection(isInside: true, line: line)
            }
        } else {
            // There are no intersections
            let line = AKLine(point0: point0, point1: point1)
            return AKSphereLineIntersection(isInside: false, line: line)
        }
    }
    
}

// MARK: - AKSphereLineIntersection

/**
 An object that represents a line that clipped by the boundaries of a sphere. There are four cases to consider when a line is clipped by a sphere.
 * 1) The line and the sphere never intersect in which case the `line` is the original line (this case includes a line that is tangent to the sphere)
 * 2) The line is completely inside the sphere in which case the `line` is the original line
 * 3) The line intersects the sphere in which case the `line` is the portion of the original line contained inside the sphere
 * 4) One of the lines points is inside the sphere and one is outside in which case the `line` is the portion of the original line contained inside the sphere. In this case one of the points of the original line will be unchanged.
 */
public struct AKSphereLineIntersection {
    /**
     This property is `true` if any point of the line intersects with the sphere (cases 2, 3, 4)
     */
    public var isInside: Bool
    /**
     The clipped line resulting from the original line being clipped by the sphere.
     */
    public var line: AKLine
}
