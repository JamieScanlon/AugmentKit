//
//  AKAnchor.swift
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

import ARKit
import Foundation

// MARK: - AKAnchor

/**
 
 An `AKAnchor` represents an object that can be rendered into the `AKWorld` at an anchored (fixed) position. The `AKAnchor` protocol has two sub protocols, `AKAugmentedAnchor` and `AKRealAnchor` that represent augmented objects (objects that don't exist in the real world) and real objects, objects that exist both in the augmented work and the real world.
 
 An `AKAnchor` is a `AKGeometricEntity`. The object itself may have animation but its position is essentially fixed in space. The object's geometry is defiened by the `model` property. The objects position in the world is defined by the worldLocation property. The conforming object must be a class, i.e. must have reference symantics.
 

 */
public protocol AKAnchor: class, AKGeometricEntity {
    /**
     A unique, per-instance identifier. Redefine the `identifier property to require a setter.
     */
    var identifier: UUID? { get set }
    /**
     The location in the ARWorld
     */
    var worldLocation: AKWorldLocation { get set }
    /**
     The heading in the ARWorld
     */
    var heading: AKHeading { get set }
}
