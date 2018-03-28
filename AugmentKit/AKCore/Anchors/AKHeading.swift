//
//  AKHeading.swift
//  AugmentKit
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
import GLKit

public enum HeadingType {
    case fixed
    case relative
}

public struct HeadingRotation: Equatable {
    public var x: Double = 0
    public var y: Double = 0
    public var z: Double = 0
    
    public static func ==(lhs: HeadingRotation, rhs: HeadingRotation) -> Bool {
        return lhs.x == rhs.x && lhs.y == rhs.y && lhs.z == rhs.z
    }
}

public protocol AKHeading {
    var type: HeadingType { get }
    var offsetRoation: HeadingRotation { get }
    func updateHeading(withPosition: AKRelativePosition)
}

extension AKHeading {
    public static func headingFrom(fromQuaternion quaternion: GLKQuaternion) -> HeadingRotation {
        let eulerAngles = QuaternionUtilities.quaternionToEulerAngle(quaternion: quaternion)
        let rotation = HeadingRotation(x: Double(eulerAngles.pitch), y: Double(eulerAngles.yaw), z: Double(eulerAngles.roll))
        return rotation
    }
}

public class Heading: AKHeading {
    
    public enum ValidationError: Error {
        case combinedFixedheadings
    }
    
    public var type: HeadingType
    public var offsetRoation: HeadingRotation
    
    public init(withType type: HeadingType, offsetRoation: HeadingRotation) {
        self.type = type
        self.offsetRoation = offsetRoation
    }
    
    public func updateHeading(withPosition: AKRelativePosition) {
        // Do Nothing
    }
    
    //  Adds all offsets and returns a new heading. If all of the headings are relative,
    //  the new heading will be relative. If one of the headings is fixed, than the new
    //  heading will be fixed. If there is more than one fixed heading, this function will
    //  throw an error.
    public static func heading(byCombining headings: [Heading]) throws -> Heading {
        
        var type = HeadingType.relative
        var offsetX: Double = 0
        var offsetY: Double = 0
        var offsetZ: Double = 0
        for heading in headings {
            if type == .fixed && heading.type == .fixed {
                throw ValidationError.combinedFixedheadings
            } else if heading.type == .fixed {
                type = .fixed
            }
            offsetX += heading.offsetRoation.x
            offsetY += heading.offsetRoation.y
            offsetZ += heading.offsetRoation.z
        }
        
        return Heading(withType: type, offsetRoation: HeadingRotation(x: offsetX, y: offsetY, z: offsetZ))
        
    }
    
}

// MARK: - WorldHeading

public class WorldHeading: AKHeading {
    
    public enum WorldHeadingType {
        case north
//        case lookAt
    }
    
    public var worldHeadingType: WorldHeadingType
    public var type: HeadingType
    public var offsetRoation: HeadingRotation
    
    public init(withWorld world: AKWorld, worldHeadingType: WorldHeadingType) {
        self.world = world
        self.worldHeadingType = worldHeadingType
        self.type = .fixed
        self.offsetRoation = HeadingRotation()
    }
    
    public func updateHeading(withPosition position: AKRelativePosition) {
        if let world = world {
            switch worldHeadingType {
            case .north:
                if let referenceWorldLocation = world.referenceWorldLocation {
                    let referenceQuaternion = referenceWorldLocation.transform.quaternion()
                    offsetRoation = WorldHeading.headingFrom(fromQuaternion: referenceQuaternion)
                }
            }
        }
    }
    
    fileprivate weak var world: AKWorld?
    
}
