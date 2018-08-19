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
//
//  A generic implementation of AKPath that renders a path using the world locations
//  as endpoints for the path segments.
//

import ARKit
import Foundation

public class PathAnchor: AKPath {
    
    public static var type: String {
        return "PathAnchor"
    }
    public var worldLocation: AKWorldLocation
    public var asset: MDLAsset
    public var identifier: UUID?
    public var effects: [AnyEffect<Any>]?
    public var shaderPreference: ShaderPreference = .simple
    public var lineThickness: Double = 0.1 // Default to 10cm line thickness
    public var segmentPoints: [AKPathSegmentAnchor]
    public var arAnchor: ARAnchor?
    
    public init(withWorldLocaitons locations: [AKWorldLocation]) {
        self.asset = MDLAsset()
        self.worldLocation = locations[0]
        self.segmentPoints = locations.map {
            return PathSegmentAnchor(at: $0)
        }
    }
    
    public func setIdentifier(_ identifier: UUID) {
        self.identifier = identifier
    }
    
    public func setARAnchor(_ arAnchor: ARAnchor) {
        self.arAnchor = arAnchor
        if identifier == nil {
            identifier = arAnchor.identifier
        }
        worldLocation.transform = arAnchor.transform
    }
    
}

