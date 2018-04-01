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
//
//  An AR anchor that represents a beginning or end of a path segment. Tow or more of
//  these can be used to create a path in the AR world. These anchors have an empty
//  model so they cannot be rendered by themselves.
//

import Foundation
import ModelIO

protocol AKPathSegmentAnchor: AKAugmentedAnchor {
    
}

public struct PathSegmentAnchor: AKPathSegmentAnchor {
    
    public static var type: String {
        return "pathSegmentAnchor"
    }
    public var worldLocation: AKWorldLocation
    public var model: AKModel
    public var identifier: UUID?
    
    public init(at location: AKWorldLocation) {
        self.model = AKSimpleModel()
        self.worldLocation = location
    }
    
    public mutating func setIdentifier(_ uuid: UUID) {
        identifier = uuid
    }
    
}

