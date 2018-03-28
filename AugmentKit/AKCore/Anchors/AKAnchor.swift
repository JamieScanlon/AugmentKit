//
//  AKAnchor.swift
//  AugmentKit2
//
//  MIT License
//
//  Copyright (c) 2017 JamieScanlon
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
}

// MARK: - AKAnchor

//  An AKAnchor is a geometrical object 'anchored' to a location. The object itself may
//  have animation but its position is esstntially fixed in space.
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
    
    mutating func setIdentifier(_ uuid: UUID)
    
}

// MARK: - AKRealAnchor

//  Represents an anchor in the AR world that is tied to an object in the real world
//  for example a detected horizontal / vertical plane wich represents a table or wall
public protocol AKRealAnchor: AKAnchor {
    
    mutating func setIdentifier(_ uuid: UUID)
    
}

// MARK: - AKTracker

//  An AKTracker is a geometrical object that tracks another moving object or position.
//  The objects position is not fixed in world space but is relative.
//  The object's geometry is defiened by the `model` property.
//  The objects position in the world is defined by the worldLocation property.
public protocol AKTracker: AKGeometricEntity {
    
    var position: AKRelativePosition { get set }
    
}

// MARK: - AKAugmentedTracker

//  Represents a tracker placed in the AR world. This tracker only exists in the AR world
//  as opposed to a real tracker like a person or a car which exists
//  in the physical world.
public protocol AKAugmentedTracker: AKTracker {
    
}

// MARK: - AKRealTracker

//  Represents a tracker in the AR world that is tied to an moving object in the real world.
//  For example a person or a car.
public protocol AKRealTracker: AKTracker {
    
}

// MARK: - AKAugmentedUserTracker

//  Represents a tracker placed in the AR world that tracks with the user (camera).
//  This can be used to place augmented objects that follow the user such as
//  heads up displays.
public protocol AKAugmentedUserTracker: AKAugmentedTracker {
    
}
