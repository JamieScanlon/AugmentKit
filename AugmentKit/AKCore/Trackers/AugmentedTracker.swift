//
//  AugmentedTracker.swift
//  AugmentKit
//
//  MIT License
//
//  Copyright (c) 2020 JamieScanlon
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
import ModelIO
import simd

/**
 A generic implementation of `AKAugmentedTracker`. An AR tracker that can be placed in the AR world. These can be created and given to the AR engine to render in the AR world.
 */
open class AugmentedTracker: AKAugmentedTracker {
    
    /**
     A type string. Always returns "UserTracker"
     */
    public static var type: String {
        return "AugmentedTracker"
    }
    /**
     A unique, per-instance identifier
     */
    public var identifier: UUID?
    /**
     The position of the tracker. The position is relative to the object it is tracking.
     */
    public var position: AKRelativePosition
    /**
     The `MDLAsset` associated with the entity.
     */
    public var asset: MDLAsset
    /**
     An array of `AKEffect` objects that are applied by the renderer
     */
    public var effects: [AnyEffect<Any>]?
    /**
     Specified a perfered renderer to use when rendering this enitity. Most will use the standard PBR renderer but some entities may prefer a simpiler renderer when they are not trying to achieve the look of real-world objects. Defaults to `ShaderPreference.pbr`
     */
    public var shaderPreference: ShaderPreference = .pbr
    /**
     Indicates whether this geometry participates in the generation of augmented shadows. Defaults to `true`.
     */
    public var generatesShadows: Bool = true
    /**
     If `true`, the current base color texture of the entity has changed since the last time it was rendered and the pixel data needs to be updated. This flag can be used to achieve dynamically updated textures for rendered objects.
     */
    public var needsColorTextureUpdate: Bool = false
    /// If `true` the underlying mesh for this geometry has changed and the renderer needs to update. This can be used to achieve dynamically generated geometries that change over time.
    public var needsMeshUpdate: Bool = false
    /**
     Initializes a new object with an `MDLAsset` and transform that represents a position relative to the object it is tracking.
     - Parameters:
     - withModelAsset: The `MDLAsset` associated with the entity.
     - withRelativeTransform: A transform used to create a `AKRelativePosition`
     */
    public init(with asset: MDLAsset, relativeTransform: matrix_float4x4, to position: AKRelativePosition) {
        self.asset = asset
        let myPosition = AKRelativePosition(withTransform: relativeTransform, relativeTo: position)
        self.position = myPosition
    }
    
}
