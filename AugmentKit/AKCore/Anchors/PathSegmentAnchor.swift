//
//  PathSegmentAnchor.swift
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
import ModelIO

/**
 A generic implementation of a AKPathSegmentAnchor. Instead of creating these objects directly, these objects should be created as part of creating a new `AKPath` instance.
 */
open class PathSegmentAnchor: AKPathSegmentAnchor {
    
    /**
     A type string. Always returns "PathSegmentAnchor"
     */
    public static var type: String {
        return "PathSegmentAnchor"
    }
    /**
     The location in the ARWorld.
     */
    public var worldLocation: AKWorldLocation
    /**
     The heading in the ARWorld. Defaults to `SameHeading()`
     */
    public var heading: AKHeading = SameHeading()
    /**
     The `MDLAsset` associated with the entity.
     */
    public var asset: MDLAsset
    /**
     A unique, per-instance identifier
     */
    public var identifier: UUID?
    /**
     An array of `AKEffect` objects that are applied by the renderer
     */
    public var effects: [AnyEffect<Any>]?
    /**
     Specified a perfered renderer to use when rendering this enitity. Most will use the standard PBR renderer but some entities may prefer a simpiler renderer when they are not trying to achieve the look of real-world objects. Defaults to `ShaderPreference.simple`
     */
    public var shaderPreference: ShaderPreference = .simple
    /**
     Indicates whether this geometry participates in the generation of augmented shadows. Defaults to `false`
     */
    public var generatesShadows: Bool = false
    /**
     If `true`, the current base color texture of the entity has changed since the last time it was rendered and the pixel data needs to be updated. This flag can be used to achieve dynamically updated textures for rendered objects.
     */
    public var needsColorTextureUpdate: Bool = false
    /// If `true` the underlying mesh for this geometry has changed and the renderer needs to update. This can be used to achieve dynamically generated geometries that change over time.
    public var needsMeshUpdate: Bool = false
    /**
     An `ARAnchor` that will be tracked in the AR world by `ARKit`
     */
    public var arAnchor: ARAnchor?
    /**
     A transform, in the coodinate space of the AR world, which is used to transform the path segment geometry such that it connects with the previous segment to form a line.
     */
    public fileprivate(set) var segmentTransform: matrix_float4x4
    
    /**
     Sets a new `segmentTransform` value
     - Parameters:
     - _: A `matrix_float4x4`
     */
    public func setSegmentTransform(_ newTransform: matrix_float4x4) {
        segmentTransform = newTransform
    }
    /**
     Initialize an object with an array of `AKWorldLocation`s
     - Parameters:
        - at: The location of the anchor
        - identifier: A unique, per-instance identifier
        - effects: An array of `AKEffect` objects that are applied by the renderer
     */
    public init(at location: AKWorldLocation, identifier: UUID? = nil, effects: [AnyEffect<Any>]? = nil) {
        self.asset = MDLAsset()
        self.worldLocation = location
        self.identifier = identifier
        self.effects = effects
        self.segmentTransform = location.transform
    }
    /**
     Sets a new `arAnchor`
     - Parameters:
        - _: An `ARAnchor`
     */
    public func setARAnchor(_ arAnchor: ARAnchor) {
        self.arAnchor = arAnchor
        if identifier == nil {
            identifier = arAnchor.identifier
        }
        worldLocation.transform = arAnchor.transform
    }
    
}

extension PathSegmentAnchor: CustomStringConvertible, CustomDebugStringConvertible {
    /// :nodoc:
    public var description: String {
        return debugDescription
    }
    
    /// :nodoc:
    public var debugDescription: String {
        let myDescription = "<\(PathSegmentAnchor.type): \(Unmanaged.passUnretained(self).toOpaque())> Identifier: \(identifier?.uuidString ?? "none"), World Location: \(worldLocation), Heading: \(heading), effects: \(effects?.debugDescription ?? "None")"
        return myDescription
    }
}
