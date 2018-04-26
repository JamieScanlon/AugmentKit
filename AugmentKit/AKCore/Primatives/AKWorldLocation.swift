//
//  AKWorldLocation.swift
//  AugmentKit
//
//  Created by Jamie Scanlon on 4/21/18.
//  Copyright © 2018 TenthLetterMade. All rights reserved.
//

import Foundation
import simd
import CoreLocation

// MARK: - AKWorldLocation

//  A data structure that combines an absolute position (latitude, longitude, and elevation)
//  with a relative postion (transform) that ties locations in the real world to locations
//  in AR space.
public protocol AKWorldLocation {
    var latitude: Double { get set }
    var longitude: Double { get set }
    var elevation: Double { get set }
    var transform: matrix_float4x4 { get set }
}

// MARK: - WorldLocation

// Standard implementation of an AKWorldLocation object
public struct WorldLocation: AKWorldLocation {
    
    public var latitude: Double = 0
    public var longitude: Double = 0
    public var elevation: Double = 0
    public var transform: matrix_float4x4 = matrix_identity_float4x4
    
    public init(transform: matrix_float4x4 = matrix_identity_float4x4, latitude: Double = 0, longitude: Double = 0, elevation: Double = 0) {
        self.transform = transform
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
    }
    
    //  When provided a reference location that has transform that corresponds to a
    //  latitude, longitude, and elevation, a new location can be created with a transform.
    //  The latitude, longitude, and elevation will be calculated based on the reference
    //  location
    public init(transform: matrix_float4x4, referenceLocation: AKWorldLocation) {
        
        self.transform = transform
        
        // The meters/ºlatitude and meters/ºlongitude change with lat/lng. The
        // reference location is used to determine these values so the further
        // the destination is from the reference location, the less accurate the
        // resulting calculation is. It's usually fine unless you need very
        // accuate calculations when the locations are tens or hundreds of km away
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
    
    //  When provided a reference location that has transform that corresponds to a
    //  latitude, longitude, and elevation, a new location can be created with a transform.
    //  The transform will be calculated based on the reference location
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

// An implementation that sets the y (vertical) position of an existing locaiton equal to the estimated ground of the world
public struct GroundFixedWorldLocation: AKWorldLocation {
    
    public var latitude: Double = 0
    public var longitude: Double = 0
    public var elevation: Double = 0
    public var world: AKWorld
    
    public var transform: matrix_float4x4 {
        get {
            var convertedTransform = originalTransform
            let worldGroundTransform = world.estimatedGroundLayer.worldLocation.transform
            convertedTransform.columns.3.y = worldGroundTransform.columns.3.y
            return convertedTransform
        }
        set {
            originalTransform = newValue
        }
    }
    
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
