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

// MARK: - Degree / Radian conversion

public extension Int {
    func degreesToRadians() -> Double {
        return Double(self) * .pi / 180
    }
    func radiansToDegrees() -> Double {
        return Double(self) * 180 / .pi
    }
}
public extension FloatingPoint {
    func degreesToRadians() -> Self {
        return self * .pi / 180
    }
    func radiansToDegrees() -> Self {
        return self * 180 / .pi
    }
}

// MARK: - Lat/Lng calculations

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
    
    public static func worldLocation(from location: AKWorldLocation, translatedBy: AKWorldDistance) -> AKWorldLocation {
        
        // See: https://en.wikipedia.org/wiki/Geographic_coordinate_system
        let latitudeInRadians = location.latitude.degreesToRadians()
        let metersPerDegreeLatitude =  111132.92 - 559.82 * cos(2 * latitudeInRadians) + 1.175 * cos(4 * latitudeInRadians) - 0.0023 * cos(6 * latitudeInRadians)
        let metersPerDegreeLongitude = 11412.84 * cos(latitudeInRadians) - 93.5 * cos(3 * latitudeInRadians) + 118 * cos(5 * latitudeInRadians)
        
        let Δx = (translatedBy.metersX / metersPerDegreeLongitude).radiansToDegrees()
        let Δz = (translatedBy.metersZ / metersPerDegreeLatitude).radiansToDegrees()
        
        let transform = location.transform.translate(x: Float(translatedBy.metersX), y: Float(translatedBy.metersY), z: Float(translatedBy.metersZ))
        
        return AKWorldLocation(transform: transform, latitude: location.latitude + Δz, longitude: location.longitude + Δx, elevation: location.elevation + translatedBy.metersY)
        
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
