//
//  WorldLocationManager.swift
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
import CoreLocation
import CoreMotion

public class WorldLocationManager: NSObject, LocationManager, MotionManager {
    
    public static let shared = WorldLocationManager()
    
    public func startServices() {
        startLocationService()
    }
    
    public func stopServices() {
        stopLocationService()
        stopTrackingCompasDirection()
    }
    
    // MARK: - LocationManager Methods
    
    private var _clLocationManager: CLLocationManager?
    public var clLocationManager: CLLocationManager {
        if let _clLocationManager = _clLocationManager {
            return _clLocationManager
        } else {
            let aCLLocationManager = CLLocationManager()
            aCLLocationManager.delegate = self
            _clLocationManager = aCLLocationManager
            return aCLLocationManager
        }
    }
    public var localStoreManager: LocalStoreManager? {
        return DefaultLocalStoreManager.shared as LocalStoreManager
    }
    public private(set) var serviceAvailable: Bool = false
    public private(set) var serviceStarted: Bool = false
    public private(set) var lastLocation: CLLocation?
    public private(set) var mostReliableARLocation: CLLocation?
    public private(set) var lastHeadingDirection: CLLocationDirection?
    public private(set) var mostReliableARHeading: CLHeading?
    
    public func locationServicesEnabled() -> Bool {
        return CLLocationManager.locationServicesEnabled()
    }
    
    public func authorizationStatus() -> CLAuthorizationStatus {
        return CLLocationManager.authorizationStatus()
    }
    public func setServiceAvailable(_ value: Bool) {
        serviceAvailable = value
    }
    public func setServiceStarted(_ value: Bool) {
        serviceStarted = value
    }
    public func setLastLocation(_ value: CLLocation) {
        lastLocation = value
    }
    public func setMostReliableARLocation(_ value: CLLocation) {
        mostReliableARLocation = value
    }
    public func setLastLocationDirection(_ value: CLLocationDirection) {
        lastHeadingDirection = value
    }
    public func setMostReliableARHeading(_ value: CLHeading) {
        mostReliableARHeading = value
    }
    
    // MARK: - MotionManager Methods
    
    private var _cmMotionManager: CMMotionManager?
    public var cmMotionManager: CMMotionManager {
        if let _cmMotionManager = _cmMotionManager {
            return _cmMotionManager
        } else {
            let aCMMotionManager = CMMotionManager()
            _cmMotionManager = aCMMotionManager
            return aCMMotionManager
        }
    }
    
    private var _motionQueue: OperationQueue?
    public var operationQueue: OperationQueue {
        if let _motionQueue = _motionQueue {
            return _motionQueue
        } else {
            let aMotionQueue = OperationQueue()
            _motionQueue = aMotionQueue
            return aMotionQueue
        }
    }
    public var viewPort: ViewPort {
        let screenSize = DeviceManager.shared.screenSizeInPoints()
        let viewport = ViewPort(width: Double(screenSize.width), height: Double(screenSize.height))
        return viewport
    }
    
}

extension WorldLocationManager: CLLocationManagerDelegate {
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        updateLocations(locations)
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        handlerError(error)
    }
    
    public func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        didResumeUpdates()
    }
    
    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        didEnterRegion(region)
    }
    
    public  func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        didChangeAuthorizationStatus(status)
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        didUpdateHeading(newHeading)
    }
    
}
