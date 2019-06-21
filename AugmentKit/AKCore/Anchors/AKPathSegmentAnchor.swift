//
//  AKPathSegmentAnchor.swift
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
 An AR anchor that represents a beginning or end of a path segment. Two or more of these can be used to create a path in the AR world. These anchors have an empty model so they cannot be rendered by themselves, They must be used on conjunction with an `AKPath` object.
 */
public protocol AKPathSegmentAnchor: AKAugmentedAnchor {
    /**
     An array of `AKEffect` objects that are applied by the renderer. Overrides the definition in `AKGeometricEntity` to require a setter
     */
    var effects: [AnyEffect<Any>]? { get set }
    
    /**
     A transform, in the coodinate space of the AR world, which is used to transform the path segment geometry such that it connects with the previous segment to form a line. While `worldLocation.transform` represents a location (no scaling or roataional component) of the terminating point of the segment, `segmentTransform` represents a location midpoint between the terminating point for this segment and the terminating point for the previous segment. It also includes a rotatinal and scale component that rotates the segment so that it starts at the previous anchos termination point and ends at this anchors termination point. If there is only one `AKPathSegmentAnchor` in an `AKPath`, this property is undefined.
     */
    var segmentTransform: matrix_float4x4 { get }
    
    /**
     Sets a new `segmentTransform` value
     - Parameters:
     - _: A `matrix_float4x4`
     */
    func setSegmentTransform(_ newTransform: matrix_float4x4)
    
}

extension AKPathSegmentAnchor {
    
    /**
     This methods recalculates the position, scale, and rotation of a path segment anchor so that it connects the two points in the line. For the `AKLine` object, `point0` represents the position of the previous `AKPathSegmentAnchor` and `point1` represents the position of this anchor.
     - Parameters:
        - withLine: An `AKLine` obhect. The `point0` property represents the position of the previous `AKPathSegmentAnchor` and the `point1` property represents the position of this anchor.
     */
    public func updateSegmentTransform(withLine line: AKLine) {
        
        let lastAnchorPosition = line.point0.simdRepresentation()
        let anchorPosition = line.point1.simdRepresentation()
        
        var segmentTransform = matrix_identity_double4x4
        
        // Rotate and scale the segmentTransform so that it is oriented from `point0` to `point1`
        
        // Do all calculations with doubles and convert them to floats a the end.
        // This reduces floating point rounding errors especially when calculating
        // angles of rotation
        
        let finalPosition = SIMD3<Double>(0, 0, 0)
        let initialPosition = SIMD3<Double>(lastAnchorPosition.x - anchorPosition.x, lastAnchorPosition.y - anchorPosition.y, lastAnchorPosition.z - anchorPosition.z)
        
        // The following was taken from: http://www.thjsmith.com/40/cylinder-between-two-points-opengl-c
        // Default cylinder direction (up)
        let defaultLineDirection = SIMD3<Double>(0,1,0)
        // Get diff between two points you want cylinder along
        let delta = (finalPosition - initialPosition)
        // Get CROSS product (the axis of rotation)
        let t = cross(defaultLineDirection , normalize(delta))
        // Get the magnitude of the vector
        let magDelta = length(delta)
        // Get angle (radians)
        let angle = acos(dot(defaultLineDirection, delta) / magDelta)
        
        // Translate so that it is midway between the two points
        let middle = -delta / 2
        
        segmentTransform = segmentTransform.translate(x: middle.x, y: middle.y, z: -middle.z)
        if angle == Double.pi {
            segmentTransform = segmentTransform.rotate(radians: angle, x: 0, y: 0, z: 1)
        } else if Float(angle) > 0 {
            segmentTransform = segmentTransform.rotate(radians: -angle, x: t.x, y: t.y, z: -t.z)
        }
        segmentTransform = segmentTransform.scale(x: 1, y: magDelta, z: 1)
        setSegmentTransform(segmentTransform.toFloat())
    }
}
