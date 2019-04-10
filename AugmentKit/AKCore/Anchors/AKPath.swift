//
//  AKPath.swift
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
/**
 An `AKPath` draws a path in the AR world. A path is a series of straight line segments each terminated by a special type of anchor called a `AKPathSegmentAnchor`. The geometry of a line segment is an elongated cylinder. The `lineThickness` property represents the diameter of the cross section.
 */
public protocol AKPath: AKAugmentedAnchor {
    /**
     Thickness measured in meters
     */
    var lineThickness: Double { get }
    /**
     An array of `AKPathSegmentAnchor` that represent the starting and ending points for the line segments. A path must have at least two `AKPathSegmentAnchor` in the `segmentPoints` array. All segments in a path are connected such that the ending point of one segment is the starting point for the next. Therefor an array of three `AKPathSegmentAnchor` instances represents a path with two line segments
     */
    var segmentPoints: [AKPathSegmentAnchor] { get }
    /**
     This methods calculates the position, scale, and rotation of each path segment anchor so that it connects to the next and previous anchors.
     - Parameters:
     - withRenderSphere: An `AKSphere`. If provided, the calculated segment transforms will fall within the sphere provided
     */
    func updateSegmentTransforms(withRenderSphere: AKSphere?)
}
