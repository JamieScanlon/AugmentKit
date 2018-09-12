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

//  .absolute headings are headings defined relative to the AR World's axis
//  .relative headings are headings defined relative to another heading or transform
public enum HeadingType {
    case absolute
    case relative
}

// MARK: - HeadingType

public enum HeadingValidationError: Error {
    case combinedAbsoluteHeadings
}

// MARK: - HeadingRotation

public struct HeadingRotation: Equatable {
    public var quaternion: simd_quatf
    init() {
        self.quaternion = simd_quatf(vector: float4(0, 0, 0, 0))
    }
    init(withQuaternion quaternion: simd_quatf) {
        self.quaternion = quaternion
    }
    init(withEulerAngles eulerAngles: EulerAngles) {
        // Follow the ZYX rotation order convention
        var q = simd_quatf(angle: eulerAngles.roll, axis: float3(0, 0, 1))
        q *= simd_quatf(angle: eulerAngles.yaw, axis: float3(0, 1, 0))
        q *= simd_quatf(angle: eulerAngles.pitch, axis: float3(1, 0, 0))
        self.quaternion = q
    }
}

// MARK: - AKHeading

public protocol AKHeading {
    var type: HeadingType { get }
    var offsetRotation: HeadingRotation { get }
    mutating func updateHeading(withPosition: AKRelativePosition)
}
//
//extension AKHeading {
//    public static func heading(fromQuaternion quaternion: GLKQuaternion) -> HeadingRotation {
//        let eulerAngles = QuaternionUtilities.quaternionToEulerAngle(quaternion: quaternion)
//        return heading(fromEulerAngles: eulerAngles)
//    }
//    public static func heading(fromEulerAngles eulerAngles: EulerAngles) -> HeadingRotation {
//        let rotation = HeadingRotation(withEulerAngles: eulerAngles)
//        return rotation
//    }
//}

// MARK: - SameHeading

//  A relative heading that matches the heading of it's parent. This is the simplest heading
//  and is the default heading for Real anchors which (due to the fact that they represent
//  real world geometries) must match the heading of their parent objects.
public class SameHeading: AKHeading {
    public var type: HeadingType = .relative
    public var offsetRotation = HeadingRotation()
    public func updateHeading(withPosition: AKRelativePosition) {
        // Do Nothing
    }
}

// MARK: - NorthHeading

//  An absolute heading that is aligned with the AR World's axis. This is the simplest heading
//  and is the default heading for Augmented anchors.
public class NorthHeading: AKHeading {
    public var type: HeadingType = .absolute
    public var offsetRotation = HeadingRotation()
    public func updateHeading(withPosition: AKRelativePosition) {
        // Do Nothing
    }
}

// MARK: - FacingMeHeading

public class FacingMeHeading: AKHeading {
    public var type: HeadingType
    public var offsetRotation: HeadingRotation
    public var worldLocation: AKWorldLocation
    
    public init(withWorldLocaiton worldLocation: AKWorldLocation) {
        self.type = .absolute
        self.offsetRotation = HeadingRotation()
        self.worldLocation = worldLocation
    }
    
    public func updateHeading(withPosition position: AKRelativePosition) {
        let thisTransform = worldLocation.transform
        let meTransform = position.transform
        let quaternion = thisTransform.lookAt(position: meTransform.columns.3)
        offsetRotation = HeadingRotation(withQuaternion: quaternion)
        print("offsetRotation: \(offsetRotation)")
    }
}

// MARK: - Heading

//  A General use AKHeading implementation.
public class Heading: AKHeading {
    
    public var type: HeadingType
    public var offsetRotation: HeadingRotation
    
    public init(withType type: HeadingType, offsetRotation: HeadingRotation) {
        self.type = type
        self.offsetRotation = offsetRotation
    }
    
    public func updateHeading(withPosition: AKRelativePosition) {
        // Do Nothing
    }
    
    //  Adds all offsets and returns a new heading. If all of the headings are relative,
    //  the new heading will be relative. If one of the headings is absolute, than the new
    //  heading will be absolute. If there is more than one absolute heading, this function will
    //  throw an error.
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

//  An absolute heading where the heading can be initialized relative to due north or
//  Looking at a AKWorldLocation
public class WorldHeading: AKHeading {
    
    public enum WorldHeadingType {
        case north(_ offsetDegrees: Double)
        case lookAt(_ this: AKWorldLocation, _ that: AKWorldLocation)
    }
    
    public var worldHeadingType: WorldHeadingType {
        didSet {
            needsUpdate = true
        }
    }
    public var type: HeadingType
    public var offsetRotation: HeadingRotation
    
    public init(withWorld world: AKWorld, worldHeadingType: WorldHeadingType) {
        self.world = world
        self.worldHeadingType = worldHeadingType
        self.type = .absolute
        self.offsetRotation = HeadingRotation()
    }
    
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
                let quaternion = thisTransform.lookAt(position: thatTransform.columns.3)
                print("thisTransform: \(thisTransform)")
                print("thatTransform: \(thatTransform)")
                print("quaternion: \(quaternion)")
                offsetRotation = HeadingRotation(withQuaternion: quaternion)
            }
        }
        
    }
    
    fileprivate weak var world: AKWorld?
    fileprivate var needsUpdate = true
    
}
