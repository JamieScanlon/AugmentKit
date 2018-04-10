//
//  AKWorld.swift
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
//
// A single class to hold all world state. It manades it's own Metal Device, Renderer,
// and ARSession. Initialize it with a MetalKit View which this class will render into.
// There should only be one of these per AR View.
//

import Foundation
import ARKit
import Metal
import MetalKit
import CoreLocation

// MARK: - AKWorldConfiguration

public struct AKWorldConfiguration {
    // When true, AKWorld manager is able to translate postions to real
    // work latitude and longitude. Defaults to `true`
    public var usesLocation = true
    // Sets the maximum distance (in meters) that will be rendred. Defaults to 500
    public var renderDistance: Double = 500
    public init(usesLocation: Bool = true, renderDistance: Double = 500) {
        
    }
}

// MARK: - AKWorldLocation

//  A data structure that combines an absolute position (latitude, longitude, and elevation)
//  with a relative postion (transform) that ties locations in the real world to locations
//  in AR space.
public struct AKWorldLocation {
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

// MARK: - AKWorldDistance

//  A data structure that represents the distance in meters between tow points in world space.
public struct AKWorldDistance {
    public var metersX: Double
    public var metersY: Double
    public var metersZ: Double
    public private(set) var distance2D: Double
    public private(set) var distance3D: Double
    
    public init(metersX: Double = 0, metersY: Double = 0, metersZ: Double = 0) {
        self.metersX = metersX
        self.metersY = metersY
        self.metersZ = metersZ
        let planarDistance = sqrt(metersX * metersX + metersZ * metersZ)
        self.distance2D = planarDistance
        self.distance3D = sqrt(planarDistance * planarDistance + metersY * metersY)
    }
}

// MARK: - AKWorld

public class AKWorld: NSObject {
    
    public let session: ARSession
    public let renderer: Renderer
    public let device: MTLDevice
    public let renderDestination: MTKView
    
    //  Returns the current AKWorldLocation of the user (technically the user's device).
    //  The transform is relative to the ARKit origin which was the position of the camera
    //  when the AR session starts.
    //  When usesLocation = true, the axis are rotated such that z points due south.
    public var currentWorldLocation: AKWorldLocation? {
        
        if configuration?.usesLocation == true {
            if let currentCameraPosition = renderer.currentCameraPositionTransform, let originLocation = referenceWorldLocation {
                let worldDistance = AKWorldDistance(metersX: Double(currentCameraPosition.columns.3.x), metersY: Double(currentCameraPosition.columns.3.y), metersZ: Double(currentCameraPosition.columns.3.z))
                return AKLocationUtility.worldLocation(from: originLocation, translatedBy: worldDistance)
            } else {
                return nil
            }
        } else {
            if let currentCameraPosition = renderer.currentCameraPositionTransform {
                return AKWorldLocation(transform: currentCameraPosition)
            } else {
                return nil
            }
            
        }
        
    }
    
    //  A location that represents a reliable AKWorldLocation object tying together a
    //  real world location (latitude, longitude,  and elevation) to AR world transforms.
    //  This location has a transform that is relative to origin of the AR world which
    //  was the position of the camera when the AR session starts.
    //  When usesLocation = true, the axis of the transform are rotated such that z points due south.
    //  This transform correlates to the latitude, longitude, and elevation. This reference location
    //  is the basis for calulating transforms based on new lat, lng, elev or translating a new
    //  transform to lat, lng, elev
    public var referenceWorldLocation: AKWorldLocation? {
        
        if configuration?.usesLocation == true {
            if let reliableLocation = reliableWorldLocations.first {
                // reliableLocation provides the correct translation but
                // it may need to be rotated to face due north
                let referenceWorldTransform = matrix_identity_float4x4.translate(x: reliableLocation.transform.columns.3.x, y: reliableLocation.transform.columns.3.y, z: reliableLocation.transform.columns.3.z)
                let referenceLocation = AKWorldLocation(transform: referenceWorldTransform, latitude: reliableLocation.latitude, longitude: reliableLocation.longitude, elevation: reliableLocation.elevation)
                // The distance to the origin is the opposite of its translation
                let distanceToOrigin = AKWorldDistance(metersX: Double(-referenceWorldTransform.columns.3.x), metersY: Double(-referenceWorldTransform.columns.3.y), metersZ: Double(-referenceWorldTransform.columns.3.z))
                return AKLocationUtility.worldLocation(from: referenceLocation, translatedBy: distanceToOrigin)
            } else {
                return nil
            }
        } else {
            // matrix_identity_float4x4 provides the correct translation but
            // it may need to be rotated to face due north
            let referenceWorldTransform = matrix_identity_float4x4
            return AKWorldLocation(transform: referenceWorldTransform)
        }
        
    }
    
    //  Returns the lowest horizontal surface anchor which is assumed to be ground.
    //  If no horizontal surfaces have been detected, this returns a horizontal
    //  surface 3m below the current device position.
    public var estimatedGroundLayer: AKRealSurfaceAnchor {
        
        let currentLocation: CLLocation = {
            if let aLocation = WorldLocationManager.shared.lastLocation {
                return aLocation
            } else {
                let coordinate = CLLocationCoordinate2DMake(0, 0)
                return CLLocation(coordinate: coordinate, altitude: 0, horizontalAccuracy: 0, verticalAccuracy: 0, timestamp: Date())
            }
        }()
        
        let groundTransform: matrix_float4x4 = {
            
            if let lowestPlane = renderer.lowestHorizPlaneAnchor {
                let metersToGround = Float((currentLocation.floor?.level ?? 0) * 3)
                return lowestPlane.transform.translate(x: 0, y: -metersToGround, z: 0)
            } else {
                let identity = matrix_identity_float4x4
                return identity.translate(x: 0, y: -3, z: 0)
            }
            
        }()
        
        let worldLocation = AKWorldLocation(transform: groundTransform, latitude: currentLocation.coordinate.latitude, longitude: currentLocation.coordinate.longitude, elevation: currentLocation.altitude)
        let groundLayer = RealSurfaceAnchor(at: worldLocation)
        return groundLayer
        
    }
    
    public init(renderDestination: MTKView, configuration: AKWorldConfiguration = AKWorldConfiguration()) {
        
        self.renderDestination = renderDestination
        self.session = ARSession()
        guard let aDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        self.device = aDevice
        self.renderer = Renderer(session: self.session, metalDevice: self.device, renderDestination: renderDestination)
        super.init()
        
        // Self is fully initialized, now do additional setup
        
        self.renderDestination.device = self.device
        self.renderer.drawRectResized(size: renderDestination.bounds.size)
        self.session.delegate = self
        self.renderDestination.delegate = self
        
        if configuration.usesLocation == true {
            
            // Start by getting all location updates until we have our first reliable location
            NotificationCenter.default.addObserver(self, selector: #selector(AKWorld.associateLocationWithCameraPosition(notif:)), name: .locationDelegateUpdateLocationNotification, object: nil)
            WorldLocationManager.shared.startServices()
            
        }
        self.configuration = configuration
        
    }
    
    public func begin() {
        renderer.initialize()
        renderer.reset()
    }
    
    public func add(anchor: AKAugmentedAnchor) {
        renderer.add(akAnchor: anchor)
    }
    
    public func add(tracker: AKAugmentedTracker) {
        renderer.add(akTracker: tracker)
    }
    
    public func add(gazeTarget: GazeTarget) {
        renderer.add(gazeTarget: gazeTarget)
    }
    
    public func addPath(withAnchors anchors: [AKAugmentedAnchor], identifier: UUID) {
        renderer.addPath(withAnchors: anchors, identifier: identifier)
    }
    
    public func worldLocation(withLatitude latitude: Double, longitude: Double, elevation: Double?) -> AKWorldLocation? {
        
        guard let configuration = configuration else {
            return nil
        }
        
        guard configuration.usesLocation else {
            return nil
        }
        
        guard let referenceLocation = referenceWorldLocation else {
            return nil
        }
        
        let myElevation: Double = {
            if let elevation = elevation {
                return elevation
            } else {
                return referenceLocation.elevation
            }
        }()
        
        return AKWorldLocation(latitude: latitude, longitude: longitude, elevation: myElevation, referenceLocation: referenceLocation)
        
    }
    
    //  Creates a new world location at a given x, y, z offset from the current users (devices) position.
    public func worldLocationFromCurrentLocation(withMetersEast offsetX: Double, metersUp offsetY: Double, metersSouth offsetZ: Double) -> AKWorldLocation? {
        
        guard let currentWorldLocation = currentWorldLocation else {
            return nil
        }
        
        let translation = float4( currentWorldLocation.transform.columns.3.x + Float(offsetX),
                                  currentWorldLocation.transform.columns.3.y + Float(offsetY),
                                  currentWorldLocation.transform.columns.3.z + Float(offsetZ),
                                  1
        )
        let endTransform = float4x4( currentWorldLocation.transform.columns.0,
                                     currentWorldLocation.transform.columns.1,
                                     currentWorldLocation.transform.columns.2,
                                     translation
        )
        
        return AKWorldLocation(transform: endTransform, referenceLocation: currentWorldLocation)
        
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Private

    fileprivate var configuration: AKWorldConfiguration? {
        didSet {
            if configuration?.usesLocation == true {
                didRecieveFirstLocation = false
                // Start by receiving all location updates until we have our first reliable location
                NotificationCenter.default.addObserver(self, selector: #selector(AKWorld.associateLocationWithCameraPosition(notif:)), name: .locationDelegateUpdateLocationNotification, object: nil)
                WorldLocationManager.shared.startServices()
            } else {
                WorldLocationManager.shared.stopServices()
                didRecieveFirstLocation = false
                NotificationCenter.default.removeObserver(self, name: .locationDelegateUpdateLocationNotification, object: nil)
                NotificationCenter.default.removeObserver(self, name: .locationDelegateMoreReliableARLocationNotification, object: nil)
                NotificationCenter.default.removeObserver(self, name: .locationDelegateMoreReliableARHeadingNotification, object: nil)
                
            }
        }
    }
    
    fileprivate var reliableWorldLocations = [AKWorldLocation]()
    fileprivate var reliableWorldTransformOffsetMatrix: matrix_float4x4 = matrix_identity_float4x4
    fileprivate var didRecieveFirstLocation = false
    
    @objc private func associateLocationWithCameraPosition(notif: NSNotification) {
        
        guard let location = notif.userInfo?["location"] as? CLLocation else {
            return
        }
        
        guard let currentCameraPosition = renderer.currentCameraPositionTransform else {
            return
        }
        
        let newReliableWorldLocation = AKWorldLocation(transform: currentCameraPosition, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, elevation: location.altitude)
        if reliableWorldLocations.count > 100 {
            reliableWorldLocations = Array(reliableWorldLocations.dropLast(reliableWorldLocations.count - 100))
        }
        reliableWorldLocations.insert(newReliableWorldLocation, at: 0)
        print("New reliable location found: \(newReliableWorldLocation.latitude)lat, \(newReliableWorldLocation.longitude)lng = \(newReliableWorldLocation.transform)")
        
        if !didRecieveFirstLocation {
            didRecieveFirstLocation = true
            // Switch from receiving every location update to only receiving updates with more reliable locations.
            NotificationCenter.default.removeObserver(self, name: .locationDelegateUpdateLocationNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(AKWorld.associateLocationWithCameraPosition(notif:)), name: .locationDelegateMoreReliableARLocationNotification, object: nil)
        }
        
    }
    
}

// MARK: - MTKViewDelegate

extension AKWorld: MTKViewDelegate {
    
    // Called whenever view changes orientation or layout is changed
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        renderer.drawRectResized(size: size)
    }
    
    // Called whenever the view needs to render
    public func draw(in view: MTKView) {
        renderer.update()
    }
    
}

// MARK: - ARSessionDelegate

extension AKWorld: ARSessionDelegate {
    
    public func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
    }
    
    public func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
    }
    
    public func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
    }
    
}

// MARK: - RenderDestinationProvider

extension MTKView : RenderDestinationProvider {
    
}
