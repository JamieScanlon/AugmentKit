//
//  AKGazeTarget.swift
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
import ModelIO

/**
 An ARTarget object whos vector matches the rotation of the device
 */
public class GazeTarget: AKTarget {
    /**
     A direction vector relative to it's position and can be a unit vector. Matches the orientation of the device
     */
    public var vectorDirection: AKVector
    /**
     A type string. Always returns "GazeTarget"
     */
    public static var type: String {
        return "GazeTarget"
    }
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
     The position of the tracker. The position is relative to the user.
     */
    public var position: AKRelativePosition
    /**
     Initializes a new object with an `MDLAsset` and transform that represents a position relative to the current uses position.
     - Parameters:
        - withModelAsset: The `MDLAsset` associated with the entity.
        - withUserRelativeTransform: A transform used to create a `AKRelativePosition`
     */
    public init(withModelAsset asset: MDLAsset, withUserRelativeTransform relativeTransform: matrix_float4x4) {
        self.asset = asset
        let myPosition = AKRelativePosition(withTransform: relativeTransform, relativeTo: UserPosition())
        self.position = myPosition
        self.vectorDirection = AKVector(x: 0, y: 0, z: -1)
    }
    /**
     Set the identifier for this instance
     - Parameters:
        - _: A UUID
     */
    public func setIdentifier(_ identifier: UUID) {
        self.identifier = identifier
    }
    
}
