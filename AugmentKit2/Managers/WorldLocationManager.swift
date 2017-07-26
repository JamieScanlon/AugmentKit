//
//  WorldLocationManager.swift
//  AugmentKit2
//
//  Created by Jamie Scanlon on 7/4/17.
//  Copyright © 2017 TenthLetterMade. All rights reserved.
//

import Foundation
import CoreLocation
import CoreMotion

class WorldLocationManager: NSObject, LocationManager, MotionManager {
    
    static let shared = WorldLocationManager()
    
    func startServices() {
        startLocationService()
        startTrackingCompasDirection()
    }
    
    func stopServices() {
        stopLocationService()
        stopTrackingCompasDirection()
    }
    
    // MARK: - LocationManager Methods
    
    private var _clLocationManager: CLLocationManager?
    var clLocationManager: CLLocationManager {
        if let _clLocationManager = _clLocationManager {
            return _clLocationManager
        } else {
            let aCLLocationManager = CLLocationManager()
            aCLLocationManager.delegate = self
            _clLocationManager = aCLLocationManager
            return aCLLocationManager
        }
    }
    var localStoreManager: LocalStoreManager? {
        return DefaultLocalStoreManager.shared as LocalStoreManager
    }
    private(set) var serviceAvailable: Bool = false
    private(set) var serviceStarted: Bool = false
    private(set) var lastLocation: CLLocation?
    
    func locationServicesEnabled() -> Bool {
        return CLLocationManager.locationServicesEnabled()
    }
    
    func authorizationStatus() -> CLAuthorizationStatus {
        return CLLocationManager.authorizationStatus()
    }
    func setServiceAvailable(_ value: Bool) {
        serviceAvailable = value
    }
    func setServiceStarted(_ value: Bool) {
        serviceStarted = value
    }
    func setLastLocation(_ value: CLLocation) {
        lastLocation = value
    }
    
    // MARK: - MotionManager Methods
    
    private var _cmMotionManager: CMMotionManager?
    var cmMotionManager: CMMotionManager {
        if let _cmMotionManager = _cmMotionManager {
            return _cmMotionManager
        } else {
            let aCMMotionManager = CMMotionManager()
            _cmMotionManager = aCMMotionManager
            return aCMMotionManager
        }
    }
    
    private var _motionQueue: OperationQueue?
    var operationQueue: OperationQueue {
        if let _motionQueue = _motionQueue {
            return _motionQueue
        } else {
            let aMotionQueue = OperationQueue()
            _motionQueue = aMotionQueue
            return aMotionQueue
        }
    }
    var viewPort: ViewPort {
        let screenSize = DeviceManager.shared.screenSizeInPoints()
        let viewport = ViewPort(width: Double(screenSize.width), height: Double(screenSize.height))
        return viewport
    }
    
}

extension WorldLocationManager: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        updateLocations(locations)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        handlerError(error)
    }
    
    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        didResumeUpdates()
    }
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        didEnterRegion(region)
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        didChangeAuthorizationStatus(status)
    }
    
}
