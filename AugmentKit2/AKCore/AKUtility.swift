//
//  AKUtility.swift
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
//  A set of utility function s an extensions
//

import Foundation

// MARK: - Degree / Radian conversion

extension Int {
    func degreesToRadians() -> Double {
        return Double(self) * .pi / 180
    }
    func radiansToDegrees() -> Double {
        return Double(self) * 180 / .pi
    }
}
extension FloatingPoint {
    func degreesToRadians() -> Self {
        return self * .pi / 180
    }
    func radiansToDegrees() -> Self {
        return self * 180 / .pi
    }
}

// MARK: - Lat/Lng calculations

class AKLocationUtility {
    
    static let R = 6371000.0 // Mean earth radius in meters
    
    // Distance in meters (x, z) between two locations. This calculation is accurate to less than a centemeter for short distances (< 1Km).
    // The distances are calculated at the lattitude/longitude given by atLocation. Technically it is more accurate
    // To find a latitude/longitude midway between the two points in order to do the calculation but the slight
    // sacrifce in precision is worth the increase in calculation speed.
    static func worldDistance(atLocation location: AKWorldLocation, to toLocation: AKWorldLocation) -> AKWorldDistance {
        
        // See: https://en.wikipedia.org/wiki/Geographic_coordinate_system
        let latitudeInRadians = location.latitude.degreesToRadians()
        let longideInRadians = location.longitude.degreesToRadians()
        let metersPerDegreeLatitude =  111132.92 - 559.82 * cos(2 * latitudeInRadians) + 1.175 * cos(4 * latitudeInRadians) - 0.0023 * cos(6 * latitudeInRadians)
        let metersPerDegreeLongitude = 11412.84 * cos(latitudeInRadians) - 93.5 * cos(3 * latitudeInRadians) + 118 * cos(5 * latitudeInRadians)
    
        let Δz = toLocation.latitude.degreesToRadians() - latitudeInRadians
        let Δx = toLocation.longitude.degreesToRadians() - longideInRadians
        let Δy = toLocation.elevation - location.elevation
        let z = -1 * (Δz * metersPerDegreeLatitude) // In our coordinate space, positive z is due south
        let x = Δx * metersPerDegreeLongitude
        let planarDistance = sqrt(x * x + z * z)
        let distance = sqrt(planarDistance * planarDistance + Δy * Δy)
        
        return AKWorldDistance(metersX: x, metersY: Δy, metersZ: z, distance2D: planarDistance, distance3D: distance)
        
    }
    
    // Haversine formula
    static func distance(fromLocation location: AKWorldLocation, to toLocation: AKWorldLocation) -> Double {
        
        let φ1 = location.latitude.degreesToRadians()
        let φ2 = toLocation.latitude.degreesToRadians()
        let Δφ = (toLocation.latitude - location.latitude).degreesToRadians()
        let Δλ = (toLocation.longitude - location.longitude).degreesToRadians()
        
        let a = sin(Δφ/2) * sin(Δφ/2) + cos(φ1) * cos(φ2) * sin(Δλ/2) * sin(Δλ/2)
        let c = 2 * atan2(sqrt(a), sqrt(1-a))
        
        let distance = R * c
        return distance
        
    }
    
    // Equirectangular approximation. Faster calculation but only good for for short distances.
    static func shortRangeDistance(fromLocation location: AKWorldLocation, to toLocation: AKWorldLocation) -> Double {
        
        // Pythagoras’ theorem
        let x = (toLocation.longitude - location.longitude) * cos((location.latitude + toLocation.latitude)/2)
        let y = (toLocation.latitude - location.latitude)
        let distance = sqrt(x * x + y * y) * R
        return distance
        
    }
    
    // Returns the number of degrees from due north in the range of 180 to 180
    static func bearing(fromLocation location: AKWorldLocation, to toLocation: AKWorldLocation) -> Double {
        
        let y = sin(toLocation.longitude - location.longitude) * cos(toLocation.latitude)
        let x = cos(location.latitude) * sin(toLocation.latitude) -  sin(location.latitude) * cos(toLocation.latitude) * cos(toLocation.longitude - location.longitude)
        let bearing = atan2(y, x).radiansToDegrees()
        return bearing
        
    }
    
}
