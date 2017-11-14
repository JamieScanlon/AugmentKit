//
//  AKWorld.swift
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

public struct AKWorldConfiguration {
    public var usesLocation = true
    
    public init(usesLocation: Bool = true) {
        
    }
}

// A data structure that combines an absolute position (latitude, longitude, and elevation)
// with a relative postion (transform) that ties locations in the real world to locations
// in AR space.
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
    
}

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

public class AKWorld: NSObject {
    
    public let session: ARSession
    public let renderer: Renderer
    public let device: MTLDevice
    public let renderDestination: MTKView
    public var currentWorldLocation: AKWorldLocation? {
        
        guard let configuration = configuration else {
            return nil
        }
        
        if configuration.usesLocation {
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
    
    // A location that represents the origin of the AR world's reference space.
    public var referenceWorldLocation: AKWorldLocation? {
        
        guard let configuration = configuration else {
            return nil
        }
        
        if configuration.usesLocation {
            if let reliableLocation = reliableWorldLocations.first {
                // reliableLocation provides the correct translation but
                // it may need to be rotated to face due north
                let referenceWorldTransform = reliableLocation.transform.rotate(radians: Float(compassOffsetRotation), x: 0, y: 1, z: 0)
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
            let referenceWorldTransform = matrix_identity_float4x4.rotate(radians: Float(compassOffsetRotation), x: 0, y: 1, z: 0)
            return AKWorldLocation(transform: referenceWorldTransform)
        }
        
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
        self.renderer.meshProvider = self
        self.session.delegate = self
        self.renderDestination.delegate = self
        
        if configuration.usesLocation == true {
            
            // Start by getting all location updates until we have our first reliable location
            NotificationCenter.default.addObserver(self, selector: #selector(AKWorld.associateLocationWithCameraPosition(notif:)), name: .locationDelegateUpdateLocationNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(AKWorld.associateHeadingWithCameraPosition(notif:)), name: .locationDelegateMoreReliableARHeadingNotification, object: nil)
            WorldLocationManager.shared.startServices()
            
        }
        self.configuration = configuration
        
    }
    
    // Initializes an anchor's assets with the renderer. Should be called befaor begin()
    // TODO: Remove this funciton. Right now the renderer needs all MLDAssets provided up front
    // but eventually, they should be loaded as they are needed so just calling
    // add(anchor: AKAugmentedAnchor will be suffiecient.
    public func setAnchor(_ anchor: AKAnchor, forAnchorType type: String) {
        switch type {
        case AKObject.type:
            anchorAsset = anchor.mdlAsset
        default:
            return
        }
    }
    
    public func begin() {
        renderer.initialize()
        renderer.reset()
    }
    
    public func add(anchor: AKAugmentedAnchor) {
        
        // Add a new anchor to the session
        let anchor = ARAnchor(transform: anchor.worldLocation.transform)
        session.add(anchor: anchor)
        
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
        
        let newLocation = AKWorldLocation(transform: matrix_identity_float4x4, latitude: latitude, longitude: longitude, elevation: myElevation)
        return AKLocationUtility.updateWorldLocationTransform(of: newLocation, usingReferenceLocation: referenceLocation)
        
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
                NotificationCenter.default.addObserver(self, selector: #selector(AKWorld.associateHeadingWithCameraPosition(notif:)), name: .locationDelegateMoreReliableARHeadingNotification, object: nil)
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
    fileprivate var anchorAsset: MDLAsset?
    fileprivate var reliableWorldLocations = [AKWorldLocation]()
    fileprivate var reliableWorldTransformOffsetMatrix: matrix_float4x4 = matrix_identity_float4x4
    fileprivate var didRecieveFirstLocation = false
    // The Renderer produces camera positions and rotations relative to
    // a coordinate system where Z is parallel to the ground and Y is normal to the ground but
    // X may be arbitrary (depending on the initial position of the camera). This offset, if
    // applied to the currentCameraRotation of the Renderer, fixes the X axis of the
    // coodinate system to Due east (meaning that Z is due south)
    fileprivate var compassOffsetRotation: Double = 0
    
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
        
        // Update camera heading. associateHeadingWithCameraPosition may not have been called
        // after the render pipeline had a chance to initialize. Now is a good time to
        // make sure that compassOffsetRotation has been initalized.
        if compassOffsetRotation == 0, let mostReliableARHeading = WorldLocationManager.shared.mostReliableARHeading, let currentCameraHeading = renderer.currentCameraHeading {
            updateCompassOffsetRotation(withHeading: mostReliableARHeading, currentCameraHeading: currentCameraHeading)
        }
        
    }
    
    @objc private func associateHeadingWithCameraPosition(notif: NSNotification) {
        
        guard let heading = notif.userInfo?["heading"] as? CLHeading else {
            return
        }
        
        guard let currentCameraHeading = renderer.currentCameraHeading else {
            return
        }
        
        print("New reliable heading found: \(heading.trueHeading), accuracy: \(heading.headingAccuracy)")
        
        updateCompassOffsetRotation(withHeading: heading, currentCameraHeading: currentCameraHeading)
        
    }
    
    private func updateCompassOffsetRotation(withHeading heading: CLHeading, currentCameraHeading: Double) {
        
        let degreesFromNorth = heading.trueHeading.degreesToRadians()
        let offsetHeading = degreesFromNorth - currentCameraHeading
        compassOffsetRotation = offsetHeading
        
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

// MARK: - MeshProvider

extension AKWorld: MeshProvider {
    
    public func loadMesh(forType type: MeshType, completion: (MDLAsset?) -> Void) {
        
        switch type {
        case .anchor:
            if let anchorAsset = anchorAsset {
                completion(anchorAsset)
            } else {
                fatalError("Failed to find an anchor model.")
            }
        case .horizPlane:
            // Use the default guide
            completion(nil)
        case .vertPlane:
            completion(nil)
        }
        
        
        
    }
}

// MARK: - RenderDestinationProvider

extension MTKView : RenderDestinationProvider {
    
}
