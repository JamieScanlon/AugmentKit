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
//  A generic implementation of a AKPathSegmentAnchor
//

import ARKit
import Foundation
import ModelIO

public class PathSegmentAnchor: AKPathSegmentAnchor {
    
    public static var type: String {
        return "PathSegmentAnchor"
    }
    public var worldLocation: AKWorldLocation
    public var heading: AKHeading = SameHeading()
    public var asset: MDLAsset
    public var identifier: UUID?
    public var effects: [AnyEffect<Any>]?
    public var shaderPreference: ShaderPreference = .simple
    public var arAnchor: ARAnchor?
    
    public init(at location: AKWorldLocation, identifier: UUID? = nil, effects: [AnyEffect<Any>]? = nil) {
        self.asset = MDLAsset()
        self.worldLocation = location
        self.identifier = identifier
        self.effects = effects
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