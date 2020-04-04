//
//  AKRelativePosiiton.swift
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

// MARK: - AKRelativePosition
/**
 A data structure that represents a position relative to another reference position in world space. This class provides functionality for recursively updating itself when a `parentPosition` is provided. Since this operation can incur a CPU cost, this must be done through a call to `updateTransforms()`. The `transformHasChanged` property can be used to determine when the current position values are stale, requiring a call to `updateTransforms()` before position values can be considered current.
 */
open class AKRelativePosition {
    
    /**
     Another `AKRelativePosition` which this object is relative to.
     */
    public var parentPosition: AKRelativePosition?
    /**
     A heading associated with this position.
     */
    public var heading: AKHeading? {
        didSet {
            _headingHasChanged = true
        }
    }
    /**
     The transform that represents the `parentPosition`'s transform. The absolute transform that this object represents can be calulated by multiplying this `referenceTransform` with the `transform` property. If `parentPosition` is not provided, this will be equal to `matrix_identity_float4x4`
     */
    public private(set) var referenceTransform: matrix_float4x4 = matrix_identity_float4x4
    /**
     The transform that this object represents. This transform is relative to the `parentPosition`'s transform if one is provided. If using `heading`, the matrix provided should **NOT** contain any rotational component.  The absolute transform that this object represents can be calulated by multiplying this `transform` with the `referenceTransform` property.
     */
    public var transform: matrix_float4x4 = matrix_identity_float4x4 {
        didSet {
            _transformHasChanged = true
        }
    }
    /**
     When `true`, `referenceTransform` and `transform` don't represent the current state. In this case `updateTransforms()` should to be called before using `referenceTransform` and `transform` for any position calculations.
     */
    public var transformHasChanged: Bool {
        return _transformHasChanged || (parentPosition?.transformHasChanged == true)
    }
    
    /**
     Initalize a new `AKRelativePosition` with a transform and a parent `AKRelativePosition`
     - Parameters:
        - withTransform: A `matrix_float4x4` representing a relative position
        - relativeTo: A parent `AKRelativePosition`. If provided, this object's transform is relative to the provided parent.
     */
    public init(withTransform transform: matrix_float4x4, relativeTo parentPosition: AKRelativePosition? = nil) {
        self.transform = transform
        self.parentPosition = parentPosition
        updateTransforms()
    }
    
    /**
     Updates the `transform` and `referenceTransform` properties to represent the current state.
     */
    public func updateTransforms() {
        if let parentPosition = parentPosition {
            if parentPosition.transformHasChanged  {
                parentPosition.updateTransforms()
            }
            referenceTransform = parentPosition.referenceTransform * matrix_identity_float4x4.translate(x: parentPosition.transform.columns.3.x, y: parentPosition.transform.columns.3.y, z: parentPosition.transform.columns.3.z)
        }
        
        if let heading = heading {
            
            var mutableHeading = heading
            let oldHeading = mutableHeading.offsetRotation
            mutableHeading.updateHeading(withPosition: self)
            if oldHeading != mutableHeading.offsetRotation {
                self.heading = mutableHeading
            }
            
            if (_transformHasChanged || _headingHasChanged) {
            
                // Heading
                var newTransform = mutableHeading.offsetRotation.quaternion.toMatrix4()
                
                if mutableHeading.type == .absolute {
                    // FIXME: This transform calculation is incorrect when headingType = .absolute. It is naive to assume that transform.columns.0.x, transform.columns.1.y, and transform.columns.2.z have no rotational components
                    newTransform = newTransform * float4x4(
                        SIMD4<Float>(transform.columns.0.x, 0, 0, 0),
                        SIMD4<Float>(0, transform.columns.1.y, 0, 0),
                        SIMD4<Float>(0, 0, transform.columns.2.z, 0),
                        SIMD4<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z, 1)
                    )
                    transform = newTransform
                } else if mutableHeading.type == .relative {
                    transform = transform * newTransform
                }
            }
            
        }
        _transformHasChanged = false
        _headingHasChanged = false
    }
    
    // MARK: Private
    
    private var _transformHasChanged = false
    private var _headingHasChanged = false
    
}

extension AKRelativePosition: CustomStringConvertible, CustomDebugStringConvertible {
    /// :nodoc:
    public var description: String {
        return debugDescription
    }
    /// :nodoc:
    public var debugDescription: String {
        let myDescription = "<KRelativePosition: \(Unmanaged.passUnretained(self).toOpaque())> transform: \(transform), referenceTransform: \(referenceTransform), parentPosition: \(parentPosition?.debugDescription ?? "None"), transformHasChanged: \(transformHasChanged)"
        return myDescription
    }
}
