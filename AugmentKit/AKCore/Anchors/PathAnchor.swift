//
//  PathAnchor.swift
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

import ARKit
import Foundation

/**
 A generic implementation of AKPath that renders a path using the world locations as endpoints for the path segments.
 */
public class PathAnchor: AKPath {
    /**
     A type string. Always returns "PathAnchor"
     */
    public static var type: String {
        return "PathAnchor"
    }
    /**
     The location in the ARWorld. The `worldLocation` property will be set to the locaiton of the first `AKPathSegmentAnchor` in the `segmentPoints` array
     */
//    public var worldLocation: AKWorldLocation
    /**
     The heading in the ARWorld. Defaults to `SameHeading()`
     */
//    public var heading: AKHeading = SameHeading()
    /**
     The `MDLAsset` associated with the entity.
     */
//    public var asset: MDLAsset
    /**
     A unique, per-instance identifier
     */
    public var identifier: UUID?
    /**
     An array of `AKEffect` objects that are applied by the renderer
     */
//    public var effects: [AnyEffect<Any>]? {
//        didSet {
//            segmentPoints.forEach { $0.effects = effects }
//        }
//    }
    /**
     Specified a perfered renderer to use when rendering this enitity. Most will use the standard PBR renderer but some entities may prefer a simpiler renderer when they are not trying to achieve the look of real-world objects. Defaults to `ShaderPreference.simple`
     */
//    public var shaderPreference: ShaderPreference = .simple
    /**
     Indicates whether this geometry participates in the generation of augmented shadows. Defaults to `false`
     */
//    public var generatesShadows: Bool = false
    /**
     Thickness measured in meters. Defaults to 10cm
     */
    public var lineThickness: Double = 0.1
    /**
     An array of `AKPathSegmentAnchor` that represent the starting and ending points for the line segments. A path must have at least two `AKPathSegmentAnchor` in the `segmentPoints` array. All segments in a path are connected such that the ending point of one segment is the starting point for the next. Therefor an array of three `AKPathSegmentAnchor` instances represents a path with two line segments
     */
    public var geometries: [AKGeometricEntity]
    /**
     An `ARAnchor` that will be tracked in the AR world by `ARKit`
     */
//    public var arAnchor: ARAnchor?
    /**
     Initialize an object with an array of `AKWorldLocation`s 
     - Parameters:
        - withWorldLocaitons: An array of `AKWorldLocation`s representing the locations of the `segmentPoints`
     */
    public init(withWorldLocaitons locations: [AKWorldLocation]) {
//        self.asset = MDLAsset()
//        self.worldLocation = locations[0]
        self.geometries = locations.map {
            return PathSegmentAnchor(at: $0)
        }
    }
    /**
     Sets a new `arAnchor`
     - Parameters:
        - _: An `ARAnchor`
     */
//    public func setARAnchor(_ arAnchor: ARAnchor) {
//        self.arAnchor = arAnchor
//        if identifier == nil {
//            identifier = arAnchor.identifier
//        }
//        worldLocation.transform = arAnchor.transform
//    }
    
    /**
     This methods calculates the position, scale, and rotation of each path segment anchor so that it connects to the next and previous anchors.
     - Parameters:
        - withRenderSphere: An `AKSphere`. If provided, the calculated segment transforms will fall within the sphere provided
     */
    public func updateSegmentTransforms(withRenderSphere renderSphere: AKSphere? = nil) {
        
        var lastAnchor: AKAugmentedAnchor?
        for anchor in segmentPoints {
            
            guard let myLastAnchor = lastAnchor else {
                lastAnchor = anchor
                continue
            }
            
            let line = AKLine(point0: double3(Double(myLastAnchor.worldLocation.transform.columns.3.x), Double(myLastAnchor.worldLocation.transform.columns.3.y), Double(myLastAnchor.worldLocation.transform.columns.3.z)), point1: double3(Double(anchor.worldLocation.transform.columns.3.x), Double(anchor.worldLocation.transform.columns.3.y), Double(anchor.worldLocation.transform.columns.3.z)))
            let recalculatedLine: AKLine = {
                if let renderSphere = renderSphere {
                    let intersection = renderSphere.intersection(with: line)
                    return intersection.line
                } else {
                    return line
                }
            }()
            anchor.updateSegmentTransform(withLine: recalculatedLine)
        }
    }
    
}

