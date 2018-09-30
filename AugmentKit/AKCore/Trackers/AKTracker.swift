//
//  AKTracker.swift
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


// MARK: - AKTracker

/**
 An AKTracker is a geometrical object that tracks another moving object or position. The object's geometry is defiened by the `model` property. The object's position is not fixed in world space but is relative.
 */
public protocol AKTracker: class, AKGeometricEntity {
    /**
     The position of the tracker. The position is relative to the objects this tracks.
     */
    var position: AKRelativePosition { get set }
    /**
     Set the identifier for this instance
     - Parameters:
        - _: A UUID
     */
    func setIdentifier(_ identifier: UUID)
    
}

// MARK: - AKAugmentedTracker

/**
 Represents a tracker placed in the AR world. This tracker only exists in the AR world as opposed to a real tracker like a person or a car which exists in the physical world.
 */
public protocol AKAugmentedTracker: AKTracker {
    
}

// MARK: - AKRealTracker

/**
 Represents a tracker in the AR world that is tied to an moving object in the real world. For example a person or a car.
 */
public protocol AKRealTracker: AKTracker {
    
}
