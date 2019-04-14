//
//  AKUtility.swift
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
//  A set of utility function s an extensions
//

import Foundation
import simd
import CoreLocation
import MetalKit

// MARK: - Degree / Radian conversion

public extension Int {
    /**
     Converts degrees to radians
     */
    func degreesToRadians() -> Double {
        return Double(self) * .pi / 180
    }
    /**
     Converts radians to degrees
     */
    func radiansToDegrees() -> Double {
        return Double(self) * 180 / .pi
    }
}
public extension FloatingPoint {
    /**
     Converts degrees to radians
     */
    func degreesToRadians() -> Self {
        return self * .pi / 180
    }
    /**
     Converts radians to degrees
     */
    func radiansToDegrees() -> Self {
        return self * 180 / .pi
    }
}

// MARK: - Lat/Lng calculations

/**
 A utility for doing location conversion calculations
 */
public class AKLocationUtility {
    
    // Equatorial radius
    static let eR = 63781370.0
    // Polar radius
    static let pR = 63567523.0
    // Mean earth radius in meters
    static let R = (eR + pR) / 2
    
    //  An accurate algorithm for calculating distances between to far distances
    //  https://github.com/raywenderlich/swift-algorithm-club/tree/master/HaversineDistance
    static func haversineDinstance(latitude1: Double, longitude1: Double, latitude2: Double, longitude2: Double) -> Double {
        
        let haversin = { (angle: Double) -> Double in
            return (1 - cos(angle))/2
        }
        
        let ahaversin = { (angle: Double) -> Double in
            return 2*asin(sqrt(angle))
        }
        
        // Converts from degrees to radians
        let dToR = { (angle: Double) -> Double in
            return (angle / 360) * 2 * Double.pi
        }
        
        let lat1 = dToR(latitude1)
        let lon1 = dToR(longitude1)
        let lat2 = dToR(latitude2)
        let lon2 = dToR(longitude2)
        
        return R * ahaversin(haversin(lat2 - lat1) + cos(lat1) * cos(lat2) * haversin(lon2 - lon1))
        
    }
    
    /**
     Creates a new `AKWorldLocation` from an existing `AKWorldLocation` translated by a `AKWorldDistance`
     - Parameters:
        - from: The original `AKWorldLocation`
        - translatedBy: An `AKWorldDistance` that represents the distance to translate the original `AKWorldLocation`
     - Returns: A new `AKWorldLocation` object
     */
    public static func worldLocation(from location: AKWorldLocation, translatedBy: AKWorldDistance) -> AKWorldLocation {
        
        // See: https://en.wikipedia.org/wiki/Geographic_coordinate_system
        let latitudeInRadians = location.latitude.degreesToRadians()
        let metersPerDegreeLatitude =  111132.92 - 559.82 * cos(2 * latitudeInRadians) + 1.175 * cos(4 * latitudeInRadians) - 0.0023 * cos(6 * latitudeInRadians)
        let metersPerDegreeLongitude = 11412.84 * cos(latitudeInRadians) - 93.5 * cos(3 * latitudeInRadians) + 118 * cos(5 * latitudeInRadians)
        
        let Δx = (translatedBy.metersX / metersPerDegreeLongitude).radiansToDegrees()
        let Δz = (translatedBy.metersZ / metersPerDegreeLatitude).radiansToDegrees()
        
        let transform = location.transform.translate(x: Float(translatedBy.metersX), y: Float(translatedBy.metersY), z: Float(translatedBy.metersZ))
        
        return WorldLocation(transform: transform, latitude: location.latitude + Δz, longitude: location.longitude + Δx, elevation: location.elevation + translatedBy.metersY)
        
    }
    
    // Uses the latitude, longitude, and elevation of a AKWorldLocation to calculate a transform of a new
    // AKWorldLocation using a reference location. The latitude, longitude, and elevation of the new AKWorldLocation
    // are the same as the provided AKWorldLocation, only the transform is different.
//    public static func updateWorldLocationTransform(of location: AKWorldLocation, usingReferenceLocation referenceLocation: AKWorldLocation) -> AKWorldLocation {
//
//        let Δy = location.elevation - referenceLocation.elevation
//        let latSign: Double = {
//            if location.latitude < referenceLocation.latitude {
//                return 1
//            } else {
//                return -1
//            }
//        }()
//        let lngSign: Double = {
//            if location.longitude < referenceLocation.longitude {
//                return -1
//            } else {
//                return 1
//            }
//        }()
//
//        let clLocation1 = CLLocation(latitude: referenceLocation.latitude, longitude: referenceLocation.longitude)
//        let ΔzLocation = CLLocation(latitude: location.latitude, longitude: referenceLocation.longitude)
//        let ΔxLocation = CLLocation(latitude: referenceLocation.latitude, longitude: location.longitude)
//        let Δz = latSign * clLocation1.distance(from: ΔzLocation)
//        let Δx = lngSign * clLocation1.distance(from: ΔxLocation)
//
//        let transform = referenceLocation.transform.translate(x: Float(Δx), y: Float(Δy), z: Float(Δz))
//
//        return AKWorldLocation(transform: transform, latitude: location.latitude, longitude: location.longitude, elevation: location.elevation)
//
//    }
    /**
     Calculates a distance in meters between two `AKWorldLocation` objects
     - Parameters:
        - fromLocation: The first `AKWorldLocation`
        - to: The second `AKWorldLocation`
     - Returns: A distance in meters
     */
    public static func distance(fromLocation location: AKWorldLocation, to toLocation: AKWorldLocation) -> Double {
        
        let flatDistance = simd.distance(location.transform.columns.3, toLocation.transform.columns.3)
        // If the distance is > 50km use haversine otherwise use a local approximation
        // whic assumes the earth is flat
        if flatDistance > 50000 {
            return haversineDinstance(latitude1: location.latitude, longitude1: location.longitude, latitude2: toLocation.latitude, longitude2: toLocation.longitude)
        } else {
            return Double(flatDistance)
        }
        
    }
    
    // Returns the number of degrees from due north in the range of 180 to 180
    /*
    public static func bearing(fromLocation location: AKWorldLocation, to toLocation: AKWorldLocation) -> Double {
        
        let y = sin(toLocation.longitude - location.longitude) * cos(toLocation.latitude)
        let x = cos(location.latitude) * sin(toLocation.latitude) -  sin(location.latitude) * cos(toLocation.latitude) * cos(toLocation.longitude - location.longitude)
        let bearing = atan2(y, x).radiansToDegrees()
        return bearing
        
    }
    */
}

// MARK: - Debugging Extensions

extension MDLObject {
    /// :nodoc:
    override open var description: String {
        return debugDescription
    }
    
    /// :nodoc:
    override open var debugDescription: String {
        var myDescription = "<\(type(of: self)): \(Unmanaged.passUnretained(self).toOpaque())> Name: \(name), Path:\(path), Hidden: \(hidden), Components: \(components), Transform: \(transform?.debugDescription ?? "none")"
        for childIndex in 0..<children.count {
            myDescription += "\n"
            myDescription += "    Child \(childIndex) - \(children[childIndex])"
        }
        return myDescription
    }
    
}

extension MDLAsset {
    
    /// :nodoc:
    override open var description: String {
        return debugDescription
    }
    
    /// :nodoc:
    override open var debugDescription: String {
        var myDescription = "<\(type(of: self)): \(Unmanaged.passUnretained(self).toOpaque())> URL: \(url?.absoluteString ?? "none"), Count: \(count), VertedDescriptor: \(vertexDescriptor?.debugDescription ?? "none"), Masters: \(masters)"
        for childIndex in 0..<self.count {
            myDescription += "\n"
            myDescription += "    Child \(childIndex) - \(self.object(at: childIndex))"
        }
        return myDescription
    }
    /// :nodoc:
    public func transformsDescription() -> String {
        var myDescription = "<\(type(of: self)): \(Unmanaged.passUnretained(self).toOpaque())>"
        for childIndex in 0..<self.count {
            myDescription += "\n"
            myDescription += childString(forObject: self.object(at: childIndex), withIndentLevel: 1)
        }
        return myDescription
    }
    
    fileprivate func childString(forObject object: MDLObject, withIndentLevel indentLevel: Int) -> String {
        var myDescription = String(repeating: "   | ", count: indentLevel)
        myDescription += "\(object.name) \(object.transform?.debugDescription ?? "none")"
        for childIndex in 0..<object.children.count {
            myDescription += "\n"
            myDescription += childString(forObject: object.children[childIndex], withIndentLevel: indentLevel + 1)
        }
        return myDescription
    }
    
}

extension MDLMesh {
    /// :nodoc:
    override open var description: String {
        return debugDescription
    }
    /// :nodoc:
    override open var debugDescription: String {
        var myDescription = "\(super.debugDescription), Submeshes: \(submeshes?.debugDescription ?? "none"), VertexCount: \(vertexCount), VertexDescriptor: \(vertexDescriptor), Transform: \(transform?.debugDescription ?? "none")"
        for childIndex in 0..<children.count {
            myDescription += "\n"
            myDescription += "    Child \(childIndex) - \(children[childIndex])"
        }
        return myDescription
    }
    
}

extension MDLMaterial {
    /// :nodoc:
    override open var description: String {
        return debugDescription
    }
    /// :nodoc:
    override open var debugDescription: String {
        var myDescription = "<\(type(of: self)): \(Unmanaged.passUnretained(self).toOpaque())> Name: \(name)"
        for childIndex in 0..<count {
            myDescription += "\n"
            myDescription += "    Property \(childIndex) - \(self[childIndex]?.debugDescription ?? "none")"
        }
        return myDescription
    }
    
}

extension MDLMaterialProperty {
    /// :nodoc:
    override open var description: String {
        return debugDescription
    }
    /// :nodoc:
    override open var debugDescription: String {
        var myDescription = "<MDLMaterialProperty: \(Unmanaged.passUnretained(self).toOpaque())> Name: \(name), Semantic: \(semantic) "
        switch type {
        case .none:
            myDescription += "Value: none"
        case .string:
            myDescription += "Value: \(stringValue?.debugDescription ?? "none")"
        case .URL:
            myDescription += "Value: \(urlValue?.debugDescription ?? "none")"
        case .texture:
            myDescription += "Value: \(textureSamplerValue?.debugDescription ?? "none")"
        case .color:
            myDescription += "Value: \(color?.debugDescription ?? "none")"
        case .float:
            myDescription += "Value: \(floatValue)"
        case .float2:
            myDescription += "Value: \(float2Value)"
        case .float3:
            myDescription += "Value: \(float3Value)"
        case .float4:
            myDescription += "Value: \(float4Value)"
        case .matrix44:
            myDescription += "Value: \(matrix4x4)"
        @unknown default:
            fatalError("Unhandled MDLMaterialProperty type: \(type)")
        }
        return myDescription
    }
    
}

extension MDLMaterialSemantic: CustomDebugStringConvertible, CustomStringConvertible {
    /// :nodoc:
    public var description: String {
        return debugDescription
    }
    /// :nodoc:
    public var debugDescription: String {
        var myDescription = ""
        switch self {
        case .none:
            myDescription += "none"
        case .baseColor:
            myDescription += "baseColor"
        case .subsurface:
            myDescription += "subsurface"
        case .metallic:
            myDescription += "metallic"
        case .specular:
            myDescription += "specular"
        case .specularExponent:
            myDescription += "specularExponent"
        case .specularTint:
            myDescription += "specularTint"
        case .roughness:
            myDescription += "roughness"
        case .anisotropic:
            myDescription += "anisotropic"
        case .anisotropicRotation:
            myDescription += "anisotropicRotation"
        case .sheen:
            myDescription += "sheen"
        case .sheenTint:
            myDescription += "sheenTint"
        case .clearcoat:
            myDescription += "clearcoat"
        case .clearcoatGloss:
            myDescription += "clearcoatGloss"
        case .emission:
            myDescription += "emission"
        case .bump:
            myDescription += "bump"
        case .opacity:
            myDescription += "opacity"
        case .interfaceIndexOfRefraction:
            myDescription += "interfaceIndexOfRefraction"
        case .materialIndexOfRefraction:
            myDescription += "materialIndexOfRefraction"
        case .objectSpaceNormal:
            myDescription += "objectSpaceNormal"
        case .tangentSpaceNormal:
            myDescription += "tangentSpaceNormal"
        case .displacement:
            myDescription += "displacement"
        case .displacementScale:
            myDescription += "displacementScale"
        case .ambientOcclusion:
            myDescription += "ambientOcclusion"
        case .ambientOcclusionScale:
            myDescription += "ambientOcclusionScale"
        case .userDefined:
            myDescription += "userDefined"
        @unknown default:
            fatalError("Unhandled MDLMaterialSemantic: \(self)")
        }
        return myDescription
    }
    
}

extension MDLTransformStack {
    /// :nodoc:
    override open var description: String {
        return debugDescription
    }
    /// :nodoc:
    override open var debugDescription: String {
        let myDescription = "<\(type(of: self)): \(Unmanaged.passUnretained(self).toOpaque())> Matrix: \(float4x4(atTime: 0))"
        return myDescription
    }
    
}

extension MDLTransform {
    /// :nodoc:
    override open var description: String {
        return debugDescription
    }
    /// :nodoc:
    override open var debugDescription: String {
        let myDescription = "<\(type(of: self)): \(Unmanaged.passUnretained(self).toOpaque())> Matrix @ 0s: \(matrix))"
        return myDescription
    }
    
}

extension MDLSubmesh {
    /// :nodoc:
    override open var description: String {
        return debugDescription
    }
    /// :nodoc:
    override open var debugDescription: String {
        let myDescription = "<\(type(of: self)): \(Unmanaged.passUnretained(self).toOpaque())> Name: \(name), IndexCount: \(indexCount), Material: \(material?.debugDescription ?? "none")"
        return myDescription
    }
    
}

extension MDLObjectContainer {
    /// :nodoc:
    override open var description: String {
        return debugDescription
    }
    /// :nodoc:
    override open var debugDescription: String {
        var myDescription = "<\(type(of: self)): \(Unmanaged.passUnretained(self).toOpaque())> Count: \(count)"
        for childIndex in 0..<self.count {
            myDescription += "\n"
            myDescription += "    Child \(childIndex) - \(objects[childIndex])"
        }
        return myDescription
    }
    
}

extension CGColor: CustomDebugStringConvertible, CustomStringConvertible {
    /// :nodoc:
    public var description: String {
        return debugDescription
    }
    /// :nodoc:
    public var debugDescription: String {
        if let components = self.components {
            return "\(components)"
        } else {
            return "unknown"
        }
    }
}

extension simd_float4x4: CustomStringConvertible {
    /// :nodoc:
    public var description: String {
        return debugDescription
    }
    /// :nodoc:
    public var debugDescription: String {
        var myDescription = "\n"
        myDescription += "[\(self.columns.0.x), \(self.columns.1.x), \(self.columns.2.x), \(self.columns.3.x)]"
        myDescription += "\n"
        myDescription += "[\(self.columns.0.y), \(self.columns.1.y), \(self.columns.2.y), \(self.columns.3.y)]"
        myDescription += "\n"
        myDescription += "[\(self.columns.0.z), \(self.columns.1.z), \(self.columns.2.z), \(self.columns.3.z)]"
        myDescription += "\n"
        myDescription += "[\(self.columns.0.w), \(self.columns.1.w), \(self.columns.2.w), \(self.columns.3.w)]"
        return myDescription
    }
}

