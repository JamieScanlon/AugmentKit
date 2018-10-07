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

import Foundation
import ARKit
import Metal
import MetalKit
import CoreLocation

// MARK: - AKWorldConfiguration

/**
 A configuration object used to initialize the AR world.

 The `AKWorld` manages the metal renderer, the `ARKit` engine, and the world state and is the primary way you interact with AugmentKit. When setting up the `AKWorld`, you provide a configuration object which determines things like weather Location Services are enabled and what the maximum render distance is. As well as being the primary way to add Anchors, Trackers, Targets and Paths, the `AKWorld` instance also provides state information like the current world locaiton and utility methods for determining the world location based on latitude and longitude. `AKWorld` also provides some dubuging tools like logging and being able to turn on visualizations of the surfaces and raw tracking points that ARKit is detecting.
 */
public struct AKWorldConfiguration {
    /**
     When true, AKWorld manager is able to translate postions to real work latitude and longitude. Defaults to `true`
     */
    public var usesLocation = true
    /**
     Sets the maximum distance (in meters) that will be rendred. Defaults to 500
     */
    public var renderDistance: Double = 500
    /**
     Initialize the `AKWorldConfiguration` object
     - Parameters:
        - usesLocation: When true, AKWorld manager is able to translate postions to real work latitude and longitude. Defaults to `true`.
        - renderDistance: Sets the maximum distance (in meters) that will be rendred. Defaults to 500.
     
     */
    public init(usesLocation: Bool = true, renderDistance: Double = 500) {
        
    }
}

// MARK: - AKWorldStatus

/**
 A struct representing the state of the world at an instance in time.
 */
public struct AKWorldStatus {
    
    /**
     Represents the current world initialization and ready state.
     */
    public enum Status {
        case notInitialized
        case initializing(ARKitInitializationPhase, SurfacesInitializationPhase, LocationInitializationPhase)
        case ready
        case interupted
        case error
    }
    
    /**
     Represents the initialization phase when the world is initializing
     */
    public enum ARKitInitializationPhase {
        case notStarted
        case initializingARKit
        case ready
    }
    
    /**
     Represents the state of surface detection.
     */
    public enum SurfacesInitializationPhase {
        case notStarted
        case findingSurfaces
        case ready
    }
    
    /**
     Represents the state of location services
     */
    public enum LocationInitializationPhase {
        case notStarted
        case findingLocation
        case ready
    }
    
    /**
     Represents the quality of tracking data
     */
    public enum Quality {
        case notAvailable
        case limited(ARCamera.TrackingState.Reason)
        case normal
    }
    
    /**
     The current `AKWorldStatus.Status`.
     */
    public var status = Status.notInitialized
    
    /**
     The current `AKWorldStatus.Quality`.
     */
    public var quality = Quality.notAvailable
    
    /**
     An array of `AKError` objects that have been reported so far.
     */
    public var errors = [AKError]()
    
    /**
     The point in time that this `AKWorldStatus` object describes
     */
    public var timestamp: Date
    
    /**
     Initialize a new `AKWorldStatus` object for a point in time
     - Parameters:
        - timestamp: The point in time that this `AKWorldStatus` object describes
     */
    public init(timestamp: Date) {
        self.timestamp = timestamp
    }
    
    /**
     Filters the `errors` array and returns only the serious errors.
     */
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
    
    /**
     Filters the `errors` array and returns only the warnings and recoverable errors.
     */
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

/**
 An object that adheres to the `AKWorldMonitor` protocol can receive updates when the world state changes.
 */
public protocol AKWorldMonitor {
    /**
     Called when the world status changes
     - Parameters:
        - worldStatus: The new `AKWorldStatus` object
     */
    func update(worldStatus: AKWorldStatus)
    /**
     Called when the world's render statistics changes
     - Parameters:
        - renderStats: The new `RenderStats` object
     */
    func update(renderStats: RenderStats)
}

// MARK: - AKWorld

/**
 A single class to hold all world state. It manages it's own Metal Device, Renderer, and ARSession. Initialize it with a MetalKit View which this class will render into. There should only be one of these per AR View.
 */
public class AKWorld: NSObject {
    
    // MARK: Properties
    
    /**
    The `ARSession` object asociatted with the `AKWorld`.
    */
    public let session: ARSession
    /**
     The `Renderer` object asociatted with the `AKWorld`.
     */
    public let renderer: Renderer
    /**
     The `MTLDevice` object asociatted with the `AKWorld`.
     */
    public let device: MTLDevice
    /**
     The `MTKView` to which the AR world will be rendered.
     */
    public let renderDestination: MTKView
    
    /**
     The current AKWorldLocation of the user (technically the user's device). The transform is relative to the ARKit origin which was the position of the camera when the AR session starts. This world location contains no rotation information, the heading is always aligned to the referenceWorldLocation. When usesLocation = true, the axis are rotated such that z points due south.
     */
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
    
    /**
    Same as currentWorldLocation with the rotation component of the device multiplied in
     */
    public var currentWorldLocationWithRotation: AKWorldLocation? {
        guard let translationWorldLocation = currentWorldLocation else {
            return nil
        }
        let translationMatrix = translationWorldLocation.transform
        guard let rotationTransform = renderer.currentCameraRotation else {
            return WorldLocation(transform: translationMatrix, latitude: translationWorldLocation.latitude, longitude: translationWorldLocation.longitude, elevation: translationWorldLocation.elevation)
        }
        let newTransform = translationMatrix * rotationTransform
        return WorldLocation(transform: newTransform, latitude: translationWorldLocation.latitude, longitude: translationWorldLocation.longitude, elevation: translationWorldLocation.elevation)
    }
    
    /**
    A location that represents a reliable AKWorldLocation object tying together a real world location (latitude, longitude,  and elevation) to AR world transforms. This location has a transform that is relative to origin of the AR world which was the position of the camera when the AR session starts. When usesLocation = true, the axis of the transform are rotated such that z points due south. This transform correlates to the latitude, longitude, and elevation. This reference location is the basis for calulating transforms based on new lat, lng, elev or translating a new transform to lat, lng, elevation
     */
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
    
    /**
    The current AKWorldLocation of the user's gaze, the point where a vector from the center of the device intersects the closes detected surface. The transform is relative to the ARKit origin which was the position of the camera when the AR session starts. When usesLocation = true, the axis are rotated such that z points due south.
    */
    public var currentGazeLocation: AKWorldLocation? {
        
        if configuration?.usesLocation == true {
            if let originLocation = referenceWorldLocation {
                let currentGazePosition = renderer.currentGazeTransform
                let worldDistance = AKWorldDistance(metersX: Double(currentGazePosition.columns.3.x), metersY: Double(currentGazePosition.columns.3.y), metersZ: Double(currentGazePosition.columns.3.z))
                let worldLocation = AKLocationUtility.worldLocation(from: originLocation, translatedBy: worldDistance)
                return worldLocation
            } else {
                return nil
            }
        } else {
            return WorldLocation(transform: renderer.currentGazeTransform)
        }
        
    }
    
    /**
    The lowest horizontal surface anchor which is assumed to be ground. If no horizontal surfaces have been detected, this returns a horizontal surface 3m below the current device position.
    */
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
    
    /**
     The current `AKWorldStatus`
    */
    public private(set) var worldStatus: AKWorldStatus {
        didSet {
            monitor?.update(worldStatus: worldStatus)
        }
    }
    
    /**
     If provided, the `monitor` will be called when `worldStatus` or `renderStatus` changes. The `monitor` can be used to provide feedback to the user about the state of the AR world and the state of the render pipeline.
     */
    public var monitor: AKWorldMonitor?
    
    // MARK: Lifecycle
    
    /**
     Initializes a new `AKWorld` object.
     
     - parameters:
        - renderDestination: The `MTKView` to which the AR world will be rendered.
        - configuration: The `AKWorldConfiguration` object used for configuring the world.
        - textureBundle: The `Bundle` from which the renderer will look for texture assets.
    */
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
        self.renderer.delegate = self
        self.renderDestination.delegate = self
        
        if configuration.usesLocation == true {
            
            // Start by getting all location updates until we have our first reliable location
            NotificationCenter.default.addObserver(self, selector: #selector(AKWorld.associateLocationWithCameraPosition(notif:)), name: .locationDelegateUpdateLocationNotification, object: nil)
            WorldLocationManager.shared.startServices()
            
        }
        self.configuration = configuration
        
    }
    
    /**
     Initializes AR tracking and rendering.
     */
    public func initialize() {
        var newStatus = AKWorldStatus(timestamp: Date())
        newStatus.status = .initializing(.initializingARKit, .notStarted, .notStarted)
        worldStatus = newStatus
        renderer.initialize()
    }
    
    /**
     Starts AR tracking and rendering.
     */
    public func begin() {
        renderer.run()
    }
    
    /**
     Pauses AR tracking and rendering.
     */
    public func pause() {
        renderer.pause()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: Adding and removing anchors
    
    /**
     Add a new `AKAugmentedAnchor` to the AR world.
     - Parameters:
        - anchor: The `AKAugmentedAnchor` object containing model and position information for the rendered anchor.
     */
    public func add(anchor: AKAugmentedAnchor) {
        renderer.add(akAnchor: anchor)
    }
    
    /**
     Remove an `AKAugmentedAnchor` from the AR world.
     - Parameters:
        - anchor: The `AKAugmentedAnchor` object to be removed.
     */
    public func remove(anchor: AKAugmentedAnchor) {
        renderer.remove(akAnchor: anchor)
    }
    
    /**
     Add a new `AKAugmentedTracker` to the AR world.
     - Parameters:
        - tracker: The `AKAugmentedTracker` object containing model and position information for the rendered tracker.
     */
    public func add(tracker: AKAugmentedTracker) {
        renderer.add(akTracker: tracker)
    }
    
    /**
     Remove an `AKAugmentedTracker` from the AR world.
     - Parameters:
        - tracker: The `AKAugmentedTracker` object to be removed.
     */
    public func remove(tracker: AKAugmentedTracker) {
        renderer.remove(akTracker: tracker)
    }
    
    /**
     Add a new `GazeTarget` to the AR world.
     - Parameters:
        - gazeTarget: The `GazeTarget` object containing model and position information for the rendered tracker.
     */
    public func add(gazeTarget: GazeTarget) {
        renderer.add(gazeTarget: gazeTarget)
    }
    
    /**
     Remove a `GazeTarget` from the AR world.
     - Parameters:
        - gazeTarget: The `GazeTarget` object to be removed.
     */
    public func remove(gazeTarget: GazeTarget) {
        renderer.remove(gazeTarget: gazeTarget)
    }
    
    /**
     Add a new `AKPath` to the AR world.
     - Parameters:
        - akPath: The `AKPath` object containing model and position information for the rendered tracker.
     */
    public func add(akPath: AKPath) {
        renderer.add(akPath: akPath)
    }
    
    /**
     Remove an `AKPath` from the AR world.
     - Parameters:
        - akPath: The `AKPath` object to be removed.
     */
    public func remove(akPath: AKPath) {
        renderer.remove(akPath: akPath)
    }
    
    // MARK: World Map
    
    /**
     Gets the `AKWorldMap` from the AR Session.
     
     - Parameters:
        - completion: a block that will be called with either a `AKWorldMap` or an error when the world map has been retrieved.
     
     */
    public func getWorldMap(completion: @escaping (AKWorldMap?, Error?) -> Void) {
        
        let session = renderer.session
        session.getCurrentWorldMap() { [unowned self] (worldMap, error) in
            if let arWorldMap = worldMap {
                let akWorldMap = AKWorldMap(withARWorldMap: arWorldMap, worldLocation: self.currentWorldLocation)
                completion(akWorldMap, error)
            } else {
                completion(nil, error)
            }
        }
        
    }
    
    /**
     Gets the ARWorldMap and saves it to the temporary directory, returning the URL.
     
     - Parameters:
        - completion: a block that will be called with either a `URL` or an error when the world map has been retrieved.
     */
    public func getArchivedWorldMap(completion: @escaping (URL?, Error?) -> Void) {
        
        let session = renderer.session
        session.getCurrentWorldMap() { [unowned self] (worldMap, error) in
            
            if let arWorldMap = worldMap {
                let akWorldMap = AKWorldMap(withARWorldMap: arWorldMap, worldLocation: self.currentWorldLocation)
                let url = try? self.writeWorldMapToTempDir(akWorldMap)
                completion(url, error)
            } else {
                completion(nil, error)
            }
            
        }
        
    }
    
    /**
     Resets the AR Session with the given inital world map.
     
     - Parameters:
        - worldMap: The `AKWorldMap` to restore.
     */
    public func setWorldMap(worldMap: AKWorldMap) {
        renderer.worldMap = worldMap.arWorldMap
        renderer.reset(options: [])
        if let latitude = worldMap.latitude, let longitude = worldMap.longitude, let elevation = worldMap.elevation, let transform = worldMap.transform {
            let newWorldLocation = WorldLocation(transform: transform, latitude: latitude, longitude: longitude, elevation: elevation)
            reliableWorldLocations = [newWorldLocation]
        } else {
            reliableWorldLocations = []
        }
    }
    
    /**
     Load an ARKWorldMap from a file URL.
     
     - Parameters:
        - from: The `URL` to the location of the archived `AKWorldMap` on disk. After unarchiving, `setWorldMap(worldMap:)` will be called the `AKWorldMap` object
     
     - Throws: `ARError(.invalidWorldMap)` if the object cannot be unarchived from the specified url.
     */
    public func loadWorldMap(from url: URL) throws {
        let mapData = try Data(contentsOf: url)
        guard let worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: AKWorldMap.self, from: mapData)
            else {
                throw ARError(.invalidWorldMap)
        }
        setWorldMap(worldMap: worldMap)
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
//        print("New reliable location found: \(newReliableWorldLocation.latitude)lat, \(newReliableWorldLocation.longitude)lng = \(newReliableWorldLocation.transform)")
        
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
    
    //  Save an AKWorldMap to the temp directory
    func writeWorldMapToTempDir(_ worldMap: AKWorldMap) throws -> URL {
        let fileName = "worldMap"
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
        let data = try NSKeyedArchiver.archivedData(withRootObject: worldMap, requiringSecureCoding: true)
        try data.write(to: fileURL)
        return fileURL
    }
    
}

// MARK: - World Location utility methods

extension AKWorld {
    
    /**
     Creates a new `AKWorldLocation` object at the given location in the real world. This method uses the most reliable location provided be `CoreLocation` and calculates where the provided latitude, longitude, and elevation are relative to the current position. Because of this, the accuracy of the provided `AKWorldLocation` may be low if this method is called shortly after initializing the AR world.
     
     - Parameters:
        - withLatitude: The latitude of the resulting `AKWorldLocation`
        - longitude: The longitude of the resulting `AKWorldLocation`
        - elevation: The elevation of the resulting `AKWorldLocation`
     
     - Returns: A new `AKWorldLocation` or nil if there has not been enough time to reliably establish the users current location.
     */
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
    
    /**
     Creates a new `AKWorldLocation` object at a given x, y, z offset from the current users location.
     
     - Parameters:
        - withMetersEast: Meters East to offset the new location from the users current location. Use negative values to move the offset in a Westerly direction.
        - metersUp: Meters Up to offset the new location from the users current location. Use negative values to move the offset in a Downward direction.
        - metersSouth: Meters South to offset the new location from the users current location. Use negative values to move the offset in a Northerly direction.
     
     - Returns: A new `AKWorldLocation` or nil if there has not been enough time to reliably establish the users current location.
     */
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
    
    /**
     Creates a new `AKWorldLocation` object which is offset from the current users location. The offsets are given relative to the devices current orientation.
     
     - Parameters:
        - metersToTheRight: Meters Right to offset the new location from the users current location and orientation. Use negative values to move the offset to the Left.
        - metersAbove: Meters Above to offset the new location from the users current location and orientation. Use negative values to move the offset Below.
        - metersInFront: Meters in Front to offset the new location from the users current location and orientation. Use negative values to move the offset to the Back.
     
     - Returns: A new `AKWorldLocation` or nil if there has not been enough time to reliably establish the users current location.
     */
    public func worldLocationWithDistanceFromMe(metersToTheRight metersRelX: Double = 0, metersAbove metersRelY: Double = 0, metersInFront metersRelMinusZ: Double = 0) -> AKWorldLocation? {
        
        guard let currentWorldLocation = currentWorldLocation else {
            return nil
        }
        let translationMatrix = currentWorldLocation.transform
        guard let rotation = renderer.currentCameraHeading else {
            return WorldLocation(transform: translationMatrix, latitude: currentWorldLocation.latitude, longitude: currentWorldLocation.longitude, elevation: currentWorldLocation.elevation)
        }
        let offsetX = -1 * metersRelMinusZ * sin(rotation) + metersRelX * cos(rotation)
        let offsetZ = -1 * metersRelMinusZ * cos(rotation) - metersRelX * sin(rotation)
        let translation = float4( currentWorldLocation.transform.columns.3.x + Float(offsetX),
                                  currentWorldLocation.transform.columns.3.y + Float(metersRelY),
                                  currentWorldLocation.transform.columns.3.z + Float(offsetZ),
                                  1
        )
        let transform = float4x4( currentWorldLocation.transform.columns.0,
                                  currentWorldLocation.transform.columns.1,
                                  currentWorldLocation.transform.columns.2,
                                  translation)
        return WorldLocation(transform: transform, referenceLocation: currentWorldLocation)
        
    }
    
    /**
     Creates a new `AKHeading` object which faces the current users location from the `AKWorldLocation` provided. The `AKHeading` is a fixed heading and does NOT re-orient itself as the user continues to move.
     
     - Parameters:
        - from: A `AKWorldLocation` object representing the location of the object that you want to face the user.
     
     - Returns: A new `AKHeading` or nil if there has not been enough time to reliably establish the users current location.
     */
    public func headingFacingAtMe(from worldLocation: AKWorldLocation) -> AKHeading? {
        guard let currentWorldLocation = currentWorldLocation else {
            return nil
        }
        return WorldHeading(withWorld: self, worldHeadingType: .lookAt(worldLocation, currentWorldLocation))
    }
    
}

// MARK: - MTKViewDelegate

extension AKWorld: MTKViewDelegate {
    
    // Called whenever view changes orientation or layout is changed
    /// :nodoc:
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        renderer.drawRectResized(size: size)
    }
    
    // Called whenever the view needs to render
    /// :nodoc:
    public func draw(in view: MTKView) {
        renderer.update()
    }
    
}

// MARK: - ARSessionDelegate

extension AKWorld: RenderDelegate {
    
    /// :nodoc:
    public func renderer(_ renderer: Renderer, didFailWithError error: AKError) {
        var newStatus = AKWorldStatus(timestamp: Date())
        var errors = worldStatus.errors
        errors.append(error)
        newStatus.errors = errors
        if newStatus.getSeriousErrors().count > 0 {
            newStatus.status = .error
        } else {
            newStatus.status = worldStatus.status
        }
        worldStatus = newStatus
    }
    
    /// :nodoc:
    public func rendererWasInterrupted(_ renderer: Renderer) {
        var newStatus = AKWorldStatus(timestamp: Date())
        newStatus.status = .interupted
        newStatus.errors = worldStatus.errors
        worldStatus = newStatus
    }
    
    /// :nodoc:
    public func rendererInterruptionEnded(_ renderer: Renderer) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        var newStatus = AKWorldStatus(timestamp: Date())
        newStatus.status = .interupted
        newStatus.errors = worldStatus.errors
        worldStatus = newStatus
    }
    
}

// MARK: - RenderMonitor

extension AKWorld: RenderMonitor {
    
    /// :nodoc:
    public func update(renderStats: RenderStats) {
        monitor?.update(renderStats: renderStats)
    }
    
    /// :nodoc:
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
