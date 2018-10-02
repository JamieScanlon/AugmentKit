//
//  AKWorldLocation.swift
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
import simd
import CoreLocation

// MARK: - AKWorldLocation

/**
 AKWorldLocation is a protocol that ties together a position in the AR world with a locaiton in the real world. When the `ARKit` session starts up, it crates an arbitrary coordinate system where the origin is where the device was located at the time of initialization. Every device and every AR session, therefore, has it's own local coordinate system. In order to reason about how the coordinate system relates to actual locations in the real world, AugmentKit uses location services to map a point in the `ARKit` coordinate system to a latitude and longitude in the real world and stores this as a `AKWorldLocation` instance. Once a reliable `AKWorldLocation` is found, other `AKWorldLocation` objects can be derived by calculating their relative distance from the one reliable reference AKWorldLocation object.
 */
public protocol AKWorldLocation {
    /**
     A latitude in the the real world
     */
    var latitude: Double { get set }
    /**
     A longitude in the the real world
     */
    var longitude: Double { get set }
    /**
     An elevation in the the real world
     */
    var elevation: Double { get set }
    /**
     A transform, in the coodinate space of the AR eorld, which corresponds to the `latitude`, `longitude`, and `elevation`
     */
    var transform: matrix_float4x4 { get set }
}

// MARK: - WorldLocation

/**
 A standard implementaion of AKWorldLocation that provides common initializers that make it easy to derive latitude, longitude, and elevation relative to a reference locatio
 */
public struct WorldLocation: AKWorldLocation {
    /**
     A latitude in the the real world
     */
    public var latitude: Double = 0
    /**
     A longitude in the the real world
     */
    public var longitude: Double = 0
    /**
     An elevation in the the real world
     */
    public var elevation: Double = 0
    /**
     A transform, in the coodinate space of the AR world, which corresponds to the `latitude`, `longitude`, and `elevation`
     */
    public var transform: matrix_float4x4 = matrix_identity_float4x4
    
    /**
     Initialize a new structure with a `transform`, a `latitude`, `longitude`, and `elevation`
     - Parameters:
        - transform:  A transform, in the coodinate space of the AR world, which corresponds to the `latitude`, `longitude`, and `elevation`
        - latitude: A latitude in the the real world
        - longitude: A longitude in the the real world
        - elevation: An elevation in the the real world
     */
    public init(transform: matrix_float4x4 = matrix_identity_float4x4, latitude: Double = 0, longitude: Double = 0, elevation: Double = 0) {
        self.transform = transform
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
    }
    
    /**
     Initialize a new structure with a `transform` and a `referenceLocation`.
     
     This uses the `transform`, `latitude`, `longitude`, and `elevation` of the `referenceLocation` to calculate the new `AKWorldLocation`.
     
     The meters/ºlatitude and meters/ºlongitude change with lat/lng. The `referenceLocation` is used to determine these values so the further the destination is from the reference location, the less accurate the resulting calculation is. It's usually fine unless you need very accuate calculations when the locations are tens or hundreds of km away.
     
     - Parameters:
        - transform: A transform of the new location in the coodinate space of the AR world
        - referenceLocation: Another `AKWorldLocation` which contains reliable `transform`, `latitude`, `longitude`, and `elevation` properties.
     */
    public init(transform: matrix_float4x4, referenceLocation: AKWorldLocation) {
        
        self.transform = transform
        
        
        let latitudeInRadians = referenceLocation.latitude.degreesToRadians()
        let metersPerDegreeLatitude =  111132.92 - 559.82 * cos(2 * latitudeInRadians) + 1.175 * cos(4 * latitudeInRadians) - 0.0023 * cos(6 * latitudeInRadians)
        let metersPerDegreeLongitude = 11412.84 * cos(latitudeInRadians) - 93.5 * cos(3 * latitudeInRadians) + 118 * cos(5 * latitudeInRadians)
        
        let Δz = transform.columns.3.z - referenceLocation.transform.columns.3.z
        let Δx = transform.columns.3.x - referenceLocation.transform.columns.3.x
        let Δy = transform.columns.3.y - referenceLocation.transform.columns.3.y
        
        self.latitude = Double(Δz) / metersPerDegreeLatitude
        self.longitude = Double(Δx) / metersPerDegreeLongitude
        self.elevation = Double(Δy)
        
    }
    
    /**
     Initializes a new structure with a `latitude`, `longitude`, and `elevation` and a `referenceLocation`.
     
     This uses the `transform`, `latitude`, `longitude`, and `elevation` of the `referenceLocation` to calculate the new `AKWorldLocation`.
     
     - Parameters:
        - latitude: A latitude of the new location in the the real world
        - longitude: A longitude of the new location in the the real world
        - elevation: An elevation of the new location in the the real world
        - referenceLocation: Another `AKWorldLocation` which contains reliable `transform`, `latitude`, `longitude`, and `elevation` properties.
     */
    public init(latitude: Double, longitude: Double, elevation: Double = 0, referenceLocation: AKWorldLocation) {
        
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
        
        let Δy = elevation - referenceLocation.elevation
        let latSign: Double = {
            if latitude < referenceLocation.latitude {
                return 1
            } else {
                return -1
            }
        }()
        let lngSign: Double = {
            if longitude < referenceLocation.longitude {
                return -1
            } else {
                return 1
            }
        }()
        
        let clLocation1 = CLLocation(latitude: referenceLocation.latitude, longitude: referenceLocation.longitude)
        let ΔzLocation = CLLocation(latitude: latitude, longitude: referenceLocation.longitude)
        let ΔxLocation = CLLocation(latitude: referenceLocation.latitude, longitude: longitude)
        let Δz = latSign * clLocation1.distance(from: ΔzLocation)
        let Δx = lngSign * clLocation1.distance(from: ΔxLocation)
        
        self.transform = referenceLocation.transform.translate(x: Float(Δx), y: Float(Δy), z: Float(Δz))
        
    }
    
}

// MARK: - WorldLocation

/**
 An implementation of `AKWorldLocation` that sets the y (vertical) position of an existing locaiton equal to the estimated ground of the world. This is useful when placing objects in the AR world that rest on the ground.
 In order to to get the y value of the estimated ground, a reference to and `AKWorld` object is required.
 */
public struct GroundFixedWorldLocation: AKWorldLocation {
    /**
     Latitude
     */
    public var latitude: Double = 0
    /**
     Longitude
     */
    public var longitude: Double = 0
    /**
     Elevation
     */
    public var elevation: Double = 0
    /**
     A weak reference to the `AKWorld`
     */
    public weak var world: AKWorld?
    
    /**
     A transform in the coodinate space of the AR world. The provided value gets mutated so that the y value corresponds to the y value of the estimated ground layer as provided by the `world`
     */
    public var transform: matrix_float4x4 {
        get {
            var convertedTransform = originalTransform
            guard let worldGroundTransform = world?.estimatedGroundLayer.worldLocation.transform else {
                return convertedTransform
            }
            convertedTransform.columns.3.y = worldGroundTransform.columns.3.y
            return convertedTransform
        }
        set {
            originalTransform = newValue
        }
    }
    
    /**
     Initializes a new structure with a `AKWorldLocation` and a reference to a `AKWorld` object
     - Parameters:
        - worldLocation: An existing `AKWorldLocation`
        - world: A reference the the `AKWorld`
     */
    public init(worldLocation: AKWorldLocation, world: AKWorld) {
        
        self.originalTransform = worldLocation.transform
        self.world = world
        self.latitude = worldLocation.latitude
        self.longitude = worldLocation.longitude
        self.elevation = world.estimatedGroundLayer.worldLocation.elevation
        
        
    }
    
    // MARK: - Private
    
    fileprivate var originalTransform: matrix_float4x4

}
