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

// MARK: - AKWorldStatus

public struct AKWorldStatus {
    
    public enum Status {
        case notInitialized
        case initializing(ARKitInitializationPhase, SurfacesInitializationPhase, LocationInitializationPhase)
        case ready
        case interupted
        case error
    }
    
    public enum ARKitInitializationPhase {
        case notStarted
        case initializingARKit
        case ready
    }
    
    public enum SurfacesInitializationPhase {
        case notStarted
        case findingSurfaces
        case ready
    }
    
    public enum LocationInitializationPhase {
        case notStarted
        case findingLocation
        case ready
    }
    
    public enum Quality {
        case notAvailable
        case limited(ARCamera.TrackingState.Reason)
        case normal
    }
    
    public var status = Status.notInitialized
    public var quality = Quality.notAvailable
    public var errors = [AKError]()
    public var timestamp: Date
    
    public init(timestamp: Date) {
        self.timestamp = timestamp
    }
    
    public func getSeriousErrors() -> [AKError] {
        return errors.filter(){
            switch $0 {
            case .seriousError(_):
                return true
            default:
                return false
            }
        }
    }
    
    public func getRecoverableErrorsAndWarnings() -> [AKError] {
        return errors.filter(){
            switch $0 {
            case .recoverableError(_):
                return true
            case .warning(_):
                return true
            default:
                return false
            }
        }
    }
    
}

// MARK: - AKWorldMonitor

public protocol AKWorldMonitor {
    func update(worldStatus: AKWorldStatus)
    func update(renderStats: RenderStats)
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
                return WorldLocation(transform: currentCameraPosition)
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
                let referenceLocation = WorldLocation(transform: referenceWorldTransform, latitude: reliableLocation.latitude, longitude: reliableLocation.longitude, elevation: reliableLocation.elevation)
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
            return WorldLocation(transform: referenceWorldTransform)
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
        
        let worldLocation = WorldLocation(transform: groundTransform, latitude: currentLocation.coordinate.latitude, longitude: currentLocation.coordinate.longitude, elevation: currentLocation.altitude)
        let groundLayer = RealSurfaceAnchor(at: worldLocation)
        return groundLayer
        
    }
    
    public private(set) var worldStatus: AKWorldStatus {
        didSet {
            monitor?.update(worldStatus: worldStatus)
        }
    }
    public var monitor: AKWorldMonitor?
    
    public init(renderDestination: MTKView, configuration: AKWorldConfiguration = AKWorldConfiguration(), textureBundle: Bundle? = nil) {
        
        let bundle: Bundle = {
            if let textureBundle = textureBundle {
                return textureBundle
            } else {
                return Bundle.main
            }
        }()
        self.renderDestination = renderDestination
        self.session = ARSession()
        guard let aDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        self.device = aDevice
        self.renderer = Renderer(session: self.session, metalDevice: self.device, renderDestination: renderDestination, textureBundle: bundle)
        self.worldStatus = AKWorldStatus(timestamp: Date())
        super.init()
        
        // Self is fully initialized, now do additional setup
        
        NotificationCenter.default.addObserver(self, selector: #selector(AKWorld.handleRendererStateChanged(notif:)), name: .rendererStateChanged, object: self.renderer)
        NotificationCenter.default.addObserver(self, selector: #selector(AKWorld.handleSurfaceDetectionStateChanged(notif:)), name: .surfaceDetectionStateChanged, object: self.renderer)
        NotificationCenter.default.addObserver(self, selector: #selector(AKWorld.handleAbortedDueToErrors(notif:)), name: .abortedDueToErrors, object: self.renderer)
        
        self.renderDestination.device = self.device
        self.renderer.monitor = self
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
        var newStatus = AKWorldStatus(timestamp: Date())
        newStatus.status = .initializing(.initializingARKit, .notStarted, .notStarted)
        worldStatus = newStatus
        renderer.initialize()
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
    
    public func add(akPath: AKPath) {
        renderer.add(akPath: akPath)
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
        
        return WorldLocation(latitude: latitude, longitude: longitude, elevation: myElevation, referenceLocation: referenceLocation)
        
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
        
        return WorldLocation(transform: endTransform, referenceLocation: currentWorldLocation)
        
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
        
        let newReliableWorldLocation = WorldLocation(transform: currentCameraPosition, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, elevation: location.altitude)
        if reliableWorldLocations.count > 100 {
            reliableWorldLocations = Array(reliableWorldLocations.dropLast(reliableWorldLocations.count - 100))
        }
        reliableWorldLocations.insert(newReliableWorldLocation, at: 0)
        print("New reliable location found: \(newReliableWorldLocation.latitude)lat, \(newReliableWorldLocation.longitude)lng = \(newReliableWorldLocation.transform)")
        
        if !didRecieveFirstLocation {
            didRecieveFirstLocation = true
            
            var newStatus = AKWorldStatus(timestamp: Date())
            let arKitPhase: AKWorldStatus.ARKitInitializationPhase = {
                switch renderer.state {
                case .uninitialized:
                    return .notStarted
                case .initialized:
                    return .initializingARKit
                case .running:
                    return .ready
                case .paused:
                    return .ready
                }
            }()
            if arKitPhase == .ready && renderer.hasDetectedSurfaces {
                newStatus.status = .ready
            } else if renderer.hasDetectedSurfaces {
                newStatus.status = .initializing(arKitPhase, .ready, .ready)
            } else {
                newStatus.status = .initializing(arKitPhase, .findingSurfaces, .ready)
            }
            worldStatus = newStatus
            
            // Switch from receiving every location update to only receiving updates with more reliable locations.
            NotificationCenter.default.removeObserver(self, name: .locationDelegateUpdateLocationNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(AKWorld.associateLocationWithCameraPosition(notif:)), name: .locationDelegateMoreReliableARLocationNotification, object: nil)
        }
        
    }
    
    @objc private func handleRendererStateChanged(notif: NSNotification) {
        
        guard notif.name == .rendererStateChanged else {
            return
        }
        
        guard let state = notif.userInfo?["newState"] as? Renderer.RendererState else {
            return
        }
        
        switch state {
        case .uninitialized:
            let newStatus = AKWorldStatus(timestamp: Date())
            worldStatus = newStatus
        case .initialized:
            renderer.reset()
        case .running:
            var newStatus = AKWorldStatus(timestamp: Date())
            if configuration?.usesLocation == true {
                newStatus.status = .initializing(.ready, .findingSurfaces, .findingLocation)
            } else {
                newStatus.status = .initializing(.ready, .findingSurfaces, .notStarted)
            }
            worldStatus = newStatus
        case .paused:
            break
        }
        
    }
    
    @objc private func handleSurfaceDetectionStateChanged(notif: NSNotification) {
        
        guard notif.name == .surfaceDetectionStateChanged else {
            return
        }
        
        guard let state = notif.userInfo?["newState"] as? Renderer.SurfaceDetectionState else {
            return
        }
        
        switch state {
        case .noneDetected:
            var newStatus = AKWorldStatus(timestamp: Date())
            let arKitPhase: AKWorldStatus.ARKitInitializationPhase = {
                switch renderer.state {
                case .uninitialized:
                    return .notStarted
                case .initialized:
                    return .initializingARKit
                case .running:
                    return .ready
                case .paused:
                    return .ready
                }
            }()
            if didRecieveFirstLocation || configuration?.usesLocation == false {
                newStatus.status = .initializing(arKitPhase, .findingSurfaces, .ready)
            } else {
                newStatus.status = .initializing(arKitPhase, .findingSurfaces, .findingLocation)
            }
            worldStatus = newStatus
        case .detected:
            var newStatus = AKWorldStatus(timestamp: Date())
            if didRecieveFirstLocation || configuration?.usesLocation == false {
                newStatus.status = .ready
            } else {
                newStatus.status = .initializing(.ready, .ready, .findingLocation)
            }
            worldStatus = newStatus
        }
        
    }
    
    @objc private func handleAbortedDueToErrors(notif: NSNotification) {
        
        guard notif.name == .abortedDueToErrors else {
            return
        }
        
        guard let errors = notif.userInfo?["errors"] as? [AKError] else {
            return
        }
        
        var newStatus = AKWorldStatus(timestamp: Date())
        newStatus.errors.append(contentsOf: errors)
        newStatus.status = .error
        worldStatus = newStatus
        
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
        var newStatus = AKWorldStatus(timestamp: Date())
        var errors = worldStatus.errors
        let newError = AKError.recoverableError(.arkitError(UnderlyingErrorInfo(underlyingError: error)))
        errors.append(newError)
        newStatus.errors = errors
        if newStatus.getSeriousErrors().count > 0 {
            newStatus.status = .error
        } else {
            newStatus.status = worldStatus.status
        }
        worldStatus = newStatus
    }
    
    public func sessionWasInterrupted(_ session: ARSession) {
        var newStatus = AKWorldStatus(timestamp: Date())
        newStatus.status = .interupted
        newStatus.errors = worldStatus.errors
        worldStatus = newStatus
    }
    
    public func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        var newStatus = AKWorldStatus(timestamp: Date())
        newStatus.status = .interupted
        newStatus.errors = worldStatus.errors
        worldStatus = newStatus
    }
    
}

// MARK: - RenderMonitor

extension AKWorld: RenderMonitor {
    
    public func update(renderStats: RenderStats) {
        monitor?.update(renderStats: renderStats)
    }
    
    public func update(renderErrors: [AKError]) {
        var newStatus = AKWorldStatus(timestamp: Date())
        newStatus.errors = renderErrors
        if newStatus.getSeriousErrors().count > 0 {
            newStatus.status = .error
        } else {
            newStatus.status = worldStatus.status
        }
        worldStatus = newStatus
    }
    
    
}

// MARK: - RenderDestinationProvider

extension MTKView : RenderDestinationProvider {
    
}
