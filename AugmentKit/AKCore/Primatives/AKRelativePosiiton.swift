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
//  A data structure that represents a position relative to another reference
//  position in world space.
public class AKRelativePosition {
    
    public var parentPosition: AKRelativePosition?
    public var heading: AKHeading? {
        didSet {
            _headingHasChanged = true
        }
    }
    public private(set) var referenceTransform: matrix_float4x4 = matrix_identity_float4x4
    //  If using heading, the matrix provided should NOT contain any rotation
    public var transform: matrix_float4x4 = matrix_identity_float4x4 {
        didSet {
            _transformHasChanged = true
        }
    }
    public var transformHasChanged: Bool {
        return _transformHasChanged || (parentPosition?.transformHasChanged == true)
    }
    
    public init(withTransform transform: matrix_float4x4, relativeTo parentPosition: AKRelativePosition? = nil) {
        self.transform = transform
        self.parentPosition = parentPosition
        updateTransforms()
    }
    
    public func updateTransforms() {
        if let parentPosition = parentPosition, parentPosition.transformHasChanged == true {
            parentPosition.updateTransforms()
            referenceTransform = parentPosition.referenceTransform * parentPosition.transform
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
                    newTransform = newTransform * float4x4(
                        float4(transform.columns.0.x, 0, 0, 0),
                        float4(0, transform.columns.1.y, 0, 0),
                        float4(0, 0, transform.columns.2.z, 0),
                        float4(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z, 1)
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
