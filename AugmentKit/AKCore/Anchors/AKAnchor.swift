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

import Foundation
import ModelIO

// MARK: - AKAnchor

//  An AKAnchor is a geometrical object 'anchored' to a location. The object itself may
//  have animation but its position is essentially fixed in space.
//  The object's geometry is defiened by the `model` property.
//  The objects position in the world is defined by the worldLocation property.
public protocol AKAnchor: AKGeometricEntity {
    
    var worldLocation: AKWorldLocation { get set }
    
}

// MARK: - AKAugmentedAnchor

//  Represents an anchor placed in the AR world. This anchor only exists in the AR world
//  as opposed to a real anchor like a detected horizontal / vertical plane which exists
//  in the physical world.
public protocol AKAugmentedAnchor: AKAnchor {
    var effects: [AnyEffect<Any>]? { get }
}

// MARK: - AKRealAnchor

//  Represents an anchor in the AR world that is tied to an object in the real world
//  for example a detected horizontal / vertical plane wich represents a table or wall
public protocol AKRealAnchor: AKAnchor {
    
}
