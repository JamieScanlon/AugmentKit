//
//  AKHeading.swift
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
import GLKit

// MARK: - HeadingType

/**
 Represents the type of heading
 */
public enum HeadingType {
    /**
     Headings defined relative to the AR World's axis
     */
    case absolute
    /**
     Headings defined relative to another heading or transform
     */
    case relative
}

// MARK: - HeadingValidationError

/**
 An error that represents an invalid heading state.
 */
public enum HeadingValidationError: Error {
    /**
     Two or more absolute headings cannot be combined.
     */
    case combinedAbsoluteHeadings
}

// MARK: - HeadingRotation

/**
 A representation of a 3D rotation. HeadingRotation is backed by a `simd_quatf`.
 
 Quaternions are light weight and more performant and easier to do calculations on vs. a transform of Euler angles. For this reason, quaternions are used Internally to represent rotations in AugmentKit.
 */
public struct HeadingRotation: Equatable {
    /**
     The backing quaternion representing the rotation
     */
    public var quaternion: simd_quatf
    /**
     Initialize with no rotation
     */
    init() {
        self.quaternion = simd_quatf(vector: float4(0, 0, 0, 1))
    }
    /**
     Initialize with a rotation represented by a quaternion
     */
    init(withQuaternion quaternion: simd_quatf) {
        self.quaternion = quaternion
    }
    /**
     Initialize with a rotation represented by `EulerAngles`. The `EulerAngles` will be converted into a quaternion.
     */
    init(withEulerAngles eulerAngles: EulerAngles) {
        self.quaternion = QuaternionUtilities.quaternionFromEulerAngles(eulerAngles: eulerAngles)
    }
}

// MARK: - AKHeading

/**
 An `AKHeading` represents a angular rotation in 3d space. The rotation can be absolute (a rotation relative to the global x,y,z axis), or relative (a rotation relative to a local x, y, z axis). When the `HeadingType` is set to `.absolute`, the AugmentKit render engine uses the value of `offsetRotation` to rotate the object to this orientation. When the `HeadingType` is set to `.relative`, the AugmentKit render engine combines the value of `offsetRotation` with the parent objects rotation to rotate the object to it's final orientation.
 The `updateHeading(withPosition:)` method is called once per frame to give the object an opportunity to update itself before the final rotation calculations are made.
 */
public protocol AKHeading {
    /**
     Determines how the AugmentKit render engine will interperet the value found in `offsetRotation`. When the `HeadingType` is set to `.absolute`, the AugmentKit render engine uses the value of `offsetRotation` to rotate the object to this orientation. When the `HeadingType` is set to `.relative`, the AugmentKit render engine combines the value of `offsetRotation` with the parent objects rotation to rotate the object to it's final orientation.
     */
    var type: HeadingType { get }
    /**
     The value used to calculate the objects final rotation.
     */
    var offsetRotation: HeadingRotation { get }
    /**
     AugmentKit calls this method once per frame to give the object an opportunity to update the `offsetRotation` before the final rotation calculations are made.
     - Parameters:
        - withPosition: A `AKRelativePosition` representing the device's current position
     */
    mutating func updateHeading(withPosition: AKRelativePosition)
}

// MARK: - SameHeading

/**
 A relative `AKHeading` that matches the heading of it's parent. This is the simplest relative heading and is the default heading for Real anchors which (due to the fact that they represent real world geometries) must match the heading of their parent objects.
 */
open class SameHeading: AKHeading {
    /**
     Fixed to `HeadingType.relative`
     */
    public var type: HeadingType {
        return .relative
    }
    /**
     The value used to calculate the objects final rotation.
     */
    public var offsetRotation = HeadingRotation()
    /**
     This implementation does nothing when this method is called
     */
    public func updateHeading(withPosition: AKRelativePosition) {
        // Do Nothing
    }
}

// MARK: - NorthHeading

/**
 An absolute `AKHeading` that is aligned with the AR World's axis. This is the simplest absolute heading and is the default heading for Augmented anchors.
 */
open class NorthHeading: AKHeading {
    /**
     Fixed to `HeadingType.absolute`
     */
    public var type: HeadingType {
        return .absolute
    }
    /**
     The value used to calculate the objects final rotation.
     */
    public var offsetRotation = HeadingRotation()
    /**
     This implementation does nothing when this method is called
     */
    public func updateHeading(withPosition: AKRelativePosition) {
        // Do Nothing
    }
}

// MARK: - AlwaysFacingMeHeading

/**
 An absolute `AKHeading` that rotates to face the users current position.
 */
open class AlwaysFacingMeHeading: AKHeading {
    /**
     Fixed to `HeadingType.absolute`
     */
    public var type: HeadingType {
        return .absolute
    }
    /**
     The value used to calculate the objects final rotation.
     */
    public var offsetRotation: HeadingRotation
    /**
     The `AKWorldLocation` of the object which will be rotated to face the user.
     */
    public var worldLocation: AKWorldLocation
    
    public init(withWorldLocaiton worldLocation: AKWorldLocation) {
        self.offsetRotation = HeadingRotation()
        self.worldLocation = worldLocation
    }
    
    /**
     AugmentKit calls this method once per frame to give the object an opportunity to update the `offsetRotation` before the final rotation calculations are made.
     - Parameters:
        - withPosition: A `AKRelativePosition` representing the device's current position
     */
    public func updateHeading(withPosition position: AKRelativePosition) {
        let thisTransform = worldLocation.transform
        let meTransform = position.transform
        let quaternion = thisTransform.lookAtQuaternion(position: float3(meTransform.columns.3.x, meTransform.columns.3.y, meTransform.columns.3.z))
        offsetRotation = HeadingRotation(withQuaternion: quaternion)
    }
}

// MARK: - Heading

/**
 A General use implementation of `AKHeading`.
 */
open class Heading: AKHeading {
    /**
     Determines how the AugmentKit render engine will interperet the value found in `offsetRotation`. When the `HeadingType` is set to `.absolute`, the AugmentKit render engine uses the value of `offsetRotation` to rotate the object to this orientation. When the `HeadingType` is set to `.relative`, the AugmentKit render engine combines the value of `offsetRotation` with the parent objects rotation to rotate the object to it's final orientation.
     */
    public var type: HeadingType
    /**
     The value used to calculate the objects final rotation.
     */
    public var offsetRotation: HeadingRotation
    
    /**
     Initialized the new `Heading` with a `type` and `offsetRotation`
     - Parameters:
        - withType: A `HeadingType`
        - offsetRotation: A `HeadingRotation`
     */
    public init(withType type: HeadingType, offsetRotation: HeadingRotation) {
        self.type = type
        self.offsetRotation = offsetRotation
    }
    
    /**
     This implementation does nothing when this method is called
     */
    public func updateHeading(withPosition: AKRelativePosition) {
        // Do Nothing
    }
    
    /**
     Adds all offsets and returns a new heading. If all of the headings are relative, the new heading will be relative. If one of the headings is absolute, than the new heading will be absolute. If there is more than one absolute heading, this function will throw an error.
     - Parameters:
        - byCombining: An array of `Heading` objects whos rotation will be combined into the new `Heading`
     
     - Throws: A `HeadingValidationError.combinedAbsoluteHeadings` error when to or mor of the provided `Heading` objects are have type `HeadingType.absolute` since it does not make sense to combine absolute headings.
     
     - Returns: a new `Heading` object or nil if no `Heading` objects were passed in
     */
    public static func heading(byCombining headings: [Heading]) throws -> Heading? {
        
        var type = HeadingType.relative
        var offsetQ: simd_quatf?
        for heading in headings {
            if type == .absolute && heading.type == .absolute {
                throw HeadingValidationError.combinedAbsoluteHeadings
            } else if heading.type == .absolute {
                type = .absolute
            }
            if let anOffsetQ = offsetQ {
                offsetQ = anOffsetQ * heading.offsetRotation.quaternion
            } else {
                offsetQ = heading.offsetRotation.quaternion
            }
        }
        
        if let offsetQ = offsetQ {
            return Heading(withType: type, offsetRotation: HeadingRotation(withQuaternion: offsetQ))
        } else {
            return nil
        }
        
    }
    
}

// MARK: - WorldHeading

/**
 An absolute `AKHeading` where the heading can be initialized relative to due north or facing a `AKWorldLocation`
 */
open class WorldHeading: AKHeading {
    
    /**
     Used to describe how the heading should function. `WorldHeading` can be used to face in a direction described as due north offset by a number of degrees (in radians), or to face at a specific location described by a `AKWorldLocation` object
     */
    public enum WorldHeadingType {
        /**
         Describes a `WorldHeading` that is due north offset by a number of degrees (in radians). The offset degrees value is provided as an Associated Value
         */
        case north(_ offsetDegrees: Double)
        /**
         Describes a `WorldHeading` that is faces a specific location described by a `AKWorldLocation` object. The values for the `AKWorldLocation` of this object and the `AKWorldLocation` of the object to face are provided by two associated values
         - parameter: This objects `AKWorldLocation`
         - parameter: The other objects `AKWorldLocation` which this object will face
         */
        case lookAt(_ this: AKWorldLocation, _ that: AKWorldLocation)
    }
    
    /**
     The `WorldHeadingType` of this object
     */
    public var worldHeadingType: WorldHeadingType {
        didSet {
            needsUpdate = true
        }
    }
    /**
     Fixed to `HeadingType.absolute`
     */
    public var type: HeadingType {
        return .absolute
    }
    /**
     The value used to calculate the objects final rotation.
     */
    public var offsetRotation: HeadingRotation
    
    /**
     Initializes a new `WorldHeading` object with a `AKWorld` and a `WorldHeadingType`
     - Parameters:
        - withWorld: The `AKWorld` object
        - worldHeadingType: The `WorldHeadingType` object
     
     */
    public init(withWorld world: AKWorld, worldHeadingType: WorldHeadingType) {
        self.world = world
        self.worldHeadingType = worldHeadingType
        self.offsetRotation = HeadingRotation()
    }
    
    /**
     AugmentKit calls this method once per frame to give the object an opportunity to update the `offsetRotation` before the final rotation calculations are made.
     - Parameters:
        - withPosition: A `AKRelativePosition` representing the device's current position
     */
    public func updateHeading(withPosition position: AKRelativePosition) {
        
        guard needsUpdate else {
            return
        }
        
        if let world = world {
            switch worldHeadingType {
            case .north(let offsetDegrees):
                if let referenceWorldLocation = world.referenceWorldLocation {
                    let referenceQuaternion = referenceWorldLocation.transform.quaternion()
                    offsetRotation = HeadingRotation(withQuaternion: referenceQuaternion * simd_quatf(angle: Float(offsetDegrees), axis: float3(0, 1, 0)))
                }
            case .lookAt(let thisWorldLocation, let thatWorldLocation):
                let thisTransform = thisWorldLocation.transform
                let thatTransform = thatWorldLocation.transform
                let quaternion = thisTransform.lookAtQuaternion(position: float3(thatTransform.columns.3.x, thatTransform.columns.3.y, thatTransform.columns.3.z))
                offsetRotation = HeadingRotation(withQuaternion: quaternion)
            }
        }
        
    }
    
    fileprivate weak var world: AKWorld?
    fileprivate var needsUpdate = true
    
}
