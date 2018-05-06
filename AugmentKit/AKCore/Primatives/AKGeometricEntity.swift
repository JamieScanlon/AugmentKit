//
//  AKGeometricEntity.swift
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

// MARK: - AKGeometricEntity

//  An AKGeometricEntity represents a 3D geomentry existing in world space. It may
//  be a rendered augmented object like a virtual sign or piece of furniture, or it may
//  be a non-rendered reference geomentry that is used as meta information about the
//  AR world like a 2D plane might represent a table top or a wall.
//  The object's geometry is defiened by the `model` property and may
//  contain animation therefore the geomentry it does not always have to represent a rigid body.
//  AKGeometricEntity does not contain any position information so it does not mean
//  anything by itself in the context of the AKWorld. It does serve as a base protocol
//  for more meaningful Types like AKAnchor and AKTracker.
public protocol AKGeometricEntity {
    static var type: String { get }
    var model: AKModel { get }
    var identifier: UUID? { get }
    var effects: [AnyEffect<Any>]? { get }
}
