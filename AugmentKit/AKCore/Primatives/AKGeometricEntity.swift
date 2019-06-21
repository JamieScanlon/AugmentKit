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
import ModelIO

// MARK: - AKGeometricEntity

/**
 An `AKGeometricEntity` represents a 3D geomentry existing in world space. It may be a rendered augmented object like a virtual sign or piece of furniture, or it may be a non-rendered reference geomentry that is used as meta information about the AR world like a 2D plane might represent a table top or a wall. The object's geometry is defiened by the `model` property and may contain animation therefore the geomentry it does not always have to represent a rigid body. AKGeometricEntity does not contain any position information so it does not mean anything by itself in the context of the AKWorld. It does serve as a base protocol for more meaningful Types like `AKAnchor` and `AKTracker`.
 */
public protocol AKGeometricEntity: AKEntity {
    /**
     The `MDLAsset` associated with the entity.
     */
    var asset: MDLAsset { get }
    /**
     An array of `AKEffect` objects that are applied by the renderer
     */
    var effects: [AnyEffect<Any>]? { get }
    /**
     Specifies a perfered renderer to use when rendering this enitity. Most will use the standard PBR renderer but some entities may prefer a simpiler renderer when they are not trying to achieve the look of real-world objects.
     */
    var shaderPreference: ShaderPreference { get }
    /**
     Indicates whether this geometry participates in the generation of augmented shadows. As a general guide, geometries that represent real world objects should not generate shadows because they have them already. Augmented geometries, however, should have this property enabled.
     */
    var generatesShadows: Bool { get }
    /**
     If `true`, the current base color texture of the entity has changed since the last time it was rendered and the pixel data needs to be updated. This flag can be used to achieve dynamically updated textures for rendered objects.
     */
    var needsColorTextureUpdate: Bool { get set }
    
    /// If `true` the underlying mesh for this geometry has changed and the renderer needs to update. This can be used to achieve dynamically generated geometries that change over time.
    var needsMeshUpdate: Bool { get set }
}
