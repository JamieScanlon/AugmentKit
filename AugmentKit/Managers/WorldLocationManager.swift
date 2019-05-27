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

/**
 `LocationManager` protocol implementation
 */
open class WorldLocationManager: NSObject, LocationManager {
    /**
     Singleton instance
     */
    public static let shared = WorldLocationManager()
    /**
     Starts location services
     */
    public func startServices() {
        startLocationService()
    }
    /**
     Stops location services
     */
    public func stopServices() {
        stopLocationService()
    }
    
    // MARK: - LocationManager Methods
    
    private var _clLocationManager: CLLocationManager?
    /**
     The backing `CLLocationManager`
     */
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
    /**
     A `LocalStoreManager` that is used to store user location state locally
     */
    public var localStoreManager: LocalStoreManager? {
        return DefaultLocalStoreManager.shared as LocalStoreManager
    }
    /**
     Returns `true` if location services are available
     */
    public private(set) var serviceAvailable: Bool = false
    /**
     Returns `true` if location services have started
     */
    public private(set) var serviceStarted: Bool = false
    /**
     The last recorded location
     */
    public private(set) var lastLocation: CLLocation?
    /**
     Provides the CLLocation with the highest accuracy. This gets updated With the most recent location if the most recent location has at least as much accuracy as the last reading.
     */
    public private(set) var mostReliableARLocation: CLLocation?
    /**
     The last recorded heading
     */
    public private(set) var lastHeadingDirection: CLLocationDirection?
    /**
     Provides the CLHeading with the highest accuracy. This gets updated with the most recent location if the most recent location has at least as much accuracy as the last reading.
     */
    public private(set) var mostReliableARHeading: CLHeading?
    /**
     Returns the CLLocationManager.locationServicesEnabled()
     */
    public func locationServicesEnabled() -> Bool {
        return CLLocationManager.locationServicesEnabled()
    }
    /**
     This should return the CLLocationManager.authorizationStatus()
     */
    public func authorizationStatus() -> CLAuthorizationStatus {
        return CLLocationManager.authorizationStatus()
    }
    /**
     Change the `serviceAvailable` state
     */
    public func setServiceAvailable(_ value: Bool) {
        serviceAvailable = value
    }
    /**
     Change the `serviceStarted` state
     */
    public func setServiceStarted(_ value: Bool) {
        serviceStarted = value
    }
    /**
     Change the `lastLocation` value
     */
    public func setLastLocation(_ value: CLLocation) {
        lastLocation = value
    }
    /**
     Change the `mostReliableARLocation` value
     */
    public func setMostReliableARLocation(_ value: CLLocation) {
        mostReliableARLocation = value
    }
    /**
     Change the `lastHeadingDirection` value
     */
    public func setLastLocationDirection(_ value: CLLocationDirection) {
        lastHeadingDirection = value
    }
    /**
     Change the `mostReliableARHeading` value
     */
    public func setMostReliableARHeading(_ value: CLHeading) {
        mostReliableARHeading = value
    }
    
}

extension WorldLocationManager: CLLocationManagerDelegate {
    /// :nodoc:
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        updateLocations(locations)
    }
    /// :nodoc:
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        handlerError(error)
    }
    /// :nodoc:
    public func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        didResumeUpdates()
    }
    /// :nodoc:
    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        didEnterRegion(region)
    }
    /// :nodoc:
    public  func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        didChangeAuthorizationStatus(status)
    }
    /// :nodoc:
    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        didUpdateHeading(newHeading)
    }
    
}
