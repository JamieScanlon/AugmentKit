//
//  RealBody.swift
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

import ARKit
import Foundation
import ModelIO
import simd

open class RealBody: AKBody {
    
    /**
     A type string.
     */
    public static var type: String {
        return "RealBody"
    }
    /**
     The `MDLAsset` associated with the entity.
     */
    public var asset: MDLAsset
    /**
     An array of `AKEffect` objects that are applied by the renderer
     */
    public var effects: [AnyEffect<Any>]?
    /**
     Specifies a perfered renderer to use when rendering this enitity. Most will use the standard PBR renderer but some entities may prefer a simpiler renderer when they are not trying to achieve the look of real-world objects.
     */
    public var shaderPreference: ShaderPreference = .pbr
    /**
     Indicates whether this geometry participates in the generation of augmented shadows. As a general guide, geometries that represent real world objects should not generate shadows because they have them already. Augmented geometries, however, should have this property enabled.
     */
    public var generatesShadows: Bool = false
    /**
     If `true`, the current base color texture of the entity has changed since the last time it was rendered and the pixel data needs to be updated. This flag can be used to achieve dynamically updated textures for rendered objects.
     */
    public var needsColorTextureUpdate: Bool = false
    
    /// If `true` the underlying mesh for this geometry has changed and the renderer needs to update. This can be used to achieve dynamically generated geometries that change over time.
    public var needsMeshUpdate: Bool = false
    /**
     A unique, per-instance identifier. Redefine the `identifier property to require a setter.
     */
    public var identifier: UUID?
    /**
     The position of the tracker. The position is relative to the objects this tracks.
     */
    public var position: AKRelativePosition
    
    /// The names of all the joints in the model. Only names matching `ARSkeleton.JointName` values will be tracked when calling `update(with: ARBodyAnchor?)`
    public var jointNames: [String] = []
    
    /// The relative joint transforms of the model.
    public var jointTransforms: [matrix_float4x4] = []
    
    /// When `true` this object has a parent `ARBodyAnchor`. If this is `false` it will not be rendered.
    public var isAnchored: Bool {
        position.parentPosition != nil
    }
    
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
    
    /// Updates the transform of the parent transform as well as updating the joint transforms. The `jointTransforms` will be overwritten with transforms provided by the `ARBodyAnchor`'s `skeleton` property. The `jointNames` array is used as a key for fetching these transforms therefor only names matching `ARSkeleton.JointName` values will be used for updating the `jointTransforms` property.
    /// - Parameter bodyAnchor: An `ARBodyAnchor` that was detected by ARKit.
    public func update(with bodyAnchor: ARBodyAnchor?) {
        
        guard let bodyAnchor = bodyAnchor else {
            position.parentPosition = nil
            return
        }
        if position.parentPosition == nil {
            position.parentPosition = AKRelativePosition(withTransform: bodyAnchor.transform)
        } else {
            position.parentPosition?.transform = bodyAnchor.transform
        }
        
        jointTransforms = jointNames.map{ bodyAnchor.skeleton.modelTransform(for: ARSkeleton.JointName(rawValue: $0)) ?? matrix_identity_float4x4 }
    }
}

extension RealBody: CustomStringConvertible, CustomDebugStringConvertible {
    
    /// :nodoc:
    public var description: String {
        return debugDescription
    }
    /// :nodoc:
    public var debugDescription: String {
        let myDescription = "<RealBody: \(Unmanaged.passUnretained(self).toOpaque())> type: \(AugmentedTracker.type), identifier: \(identifier?.debugDescription ?? "None"), position: \(position), asset: \(asset), effects: \(effects.debugDescription), shaderPreference: \(shaderPreference), generatesShadows: \(generatesShadows), needsColorTextureUpdate: \(needsColorTextureUpdate), needsMeshUpdate: \(needsMeshUpdate), jointNames: \(jointNames), jointTransforms: \(jointTransforms), isAnchored: \(isAnchored)"
        return myDescription
    }
    
}
