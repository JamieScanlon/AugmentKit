//
//  LocationManager.swift
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

public extension Notification.Name {
    public static let locationDelegateUpdateLocationNotification = Notification.Name("com.tenthlettermade.notificaiton.LocationDelegateUpdateLocation")
    public static let locationDelegateNearObjectNotification = Notification.Name("com.tenthlettermade.notificaiton.LocationDelegateNearObjectNotification")
    public static let locationDelegateMoreReliableARLocationNotification = Notification.Name("com.tenthlettermade.notificaiton.LocationDelegateMoreReliableARLocation")
    public static let locationDelegateMoreReliableARHeadingNotification = Notification.Name("com.tenthlettermade.notificaiton.LocationDelegateMoreReliableARHeading")
}

// MARK: - LocationManager

public protocol LocationManager {
    var clLocationManager: CLLocationManager { get }
    var localStoreManager: LocalStoreManager? { get }
    var serviceAvailable: Bool { get }
    var serviceStarted: Bool { get }
    var lastLocation: CLLocation? { get }
    var lastHeadingDirection: CLLocationDirection? { get }
    
    // Provides the CLLocation with the highest accuracy. This gets updated
    // With the most recent location if the most recent location has at least
    // as much accuracy as the last reading.
    var mostReliableARLocation: CLLocation? { get }
    
    // Provides the CLHeading with the highest accuracy. This gets updated
    // With the most recent location if the most recent location has at least
    // as much accuracy as the last reading.
    var mostReliableARHeading: CLHeading? { get }
    
    // This should return the CLLocationManager.locationServicesEnabled()
    func locationServicesEnabled() -> Bool
    // This should return the CLLocationManager.authorizationStatus()
    func authorizationStatus() -> CLAuthorizationStatus
    func setServiceAvailable(_ value: Bool)
    func setServiceStarted(_ value: Bool)
    func setLastLocation(_ value: CLLocation)
    func setMostReliableARLocation(_ value: CLLocation)
    func setLastLocationDirection(_ value: CLLocationDirection)
    func setMostReliableARHeading(_ value: CLHeading)
    
}

public extension LocationManager {
    
    public func startLocationService() {
        
        if locationServicesEnabled() {
            setServiceAvailable(false)
        } else {
            setServiceAvailable(true)
        }
        
        setupCLLocationManager()
        
        // Call stopUpdatingLocation to force a new event
        // when startUpdatingLocation is called.
        stopLocationService()
        
        //clLocationManager.startMonitoringSignificantLocationChanges()
        clLocationManager.startUpdatingLocation()
        clLocationManager.startUpdatingHeading()
        
        setServiceStarted(true)
        
    }
    
    public func stopLocationService() {
        
        clLocationManager.stopUpdatingLocation()
        clLocationManager.stopMonitoringSignificantLocationChanges()
        setServiceStarted(false)
        
    }
    
    public func isLocationServiceAvailable() -> Bool {
        return serviceAvailable
    }
    
    public func isServiceStarted() -> Bool {
        return serviceStarted
    }
    
    public func hasGivenAutorization() -> Bool {
        return  (authorizationStatus() == .authorizedAlways || authorizationStatus() == .authorizedWhenInUse)
    }
    
    public func stopMonitoringRegions() {
        
        setupCLLocationManager()
        
        for region in clLocationManager.monitoredRegions {
            clLocationManager.stopMonitoring(for: region)
        }
        
    }
    
    public func requestAlwaysAuthorization() {
        clLocationManager.requestAlwaysAuthorization()
    }
    
    public func requestInUseAuthorization() {
        clLocationManager.requestWhenInUseAuthorization()
    }
    
    public func currentLocation() -> CLLocation? {
        
        guard isLocationServiceAvailable() else {
            return nil
        }
        
        var theLocation = clLocationManager.location
        
        if theLocation == nil {
            
            if let archivedLocationData = localStoreManager?.lastKnownLocationData, let archivedLocationDict = NSKeyedUnarchiver.unarchiveObject(with: archivedLocationData) as? [String: Any], let lastKnownLocation = archivedLocationDict["location"] as? CLLocation, let myUpddatedTime = archivedLocationDict["updated"] as? Date {
                // If it's more than an hour ago, ignore it.
                if myUpddatedTime.timeIntervalSince(Date()) < 60 * 60 {
                    theLocation = lastKnownLocation
                }
                
            }
            
        }
        
        return theLocation
        
    }
    
    // MARK: CLLocationManagerDelegate Handlers
    
    // Call this in the locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) Method
    func updateLocations(_ locations: [CLLocation]) {
        
        guard let mostRecentLocation = locations.last else {
            return
        }
        
        // Ignore results more than 15 seconds old as they are likely to be cached.
        guard fabs(mostRecentLocation.timestamp.timeIntervalSinceNow) < 15 else {
            return
        }
        
        setLastLocation(mostRecentLocation)
        
        if let mostReliableARLocation = mostReliableARLocation {
            if mostRecentLocation.horizontalAccuracy == mostReliableARLocation.horizontalAccuracy && mostRecentLocation.verticalAccuracy == mostReliableARLocation.verticalAccuracy {
                if mostRecentLocation.timestamp > mostReliableARLocation.timestamp {
                    setMostReliableARLocation(mostRecentLocation)
                }
            } else if (mostRecentLocation.horizontalAccuracy < mostReliableARLocation.horizontalAccuracy && mostRecentLocation.horizontalAccuracy > 0) || (mostRecentLocation.verticalAccuracy < mostReliableARLocation.verticalAccuracy && mostRecentLocation.verticalAccuracy > 0) {
                setMostReliableARLocation(mostRecentLocation)
                NotificationCenter.default.post(Notification(name: .locationDelegateMoreReliableARLocationNotification, object: self, userInfo: ["location": mostRecentLocation]))
            }
        } else {
            setMostReliableARLocation(mostRecentLocation)
            NotificationCenter.default.post(Notification(name: .locationDelegateMoreReliableARLocationNotification, object: self, userInfo: ["location": mostRecentLocation]))
        }
        
        NotificationCenter.default.post(Notification(name: .locationDelegateUpdateLocationNotification, object: self, userInfo: ["location": mostRecentLocation]))
        
    }
    
    // Call this in the locationManager(_ manager: CLLocationManager, didFailWithError error: Error) Method
    func handlerError(_ error: Error) {
        
        print("ERROR: \(error)")
        let code = (error as NSError).code
        
        if code == CLError.denied.rawValue {
            stopLocationService()
            setServiceAvailable(false)
            setServiceStarted(false)
        } else if code == CLError.network.rawValue {
            setServiceAvailable(false)
            setServiceStarted(false)
        } else if code == CLError.regionMonitoringDenied.rawValue {
            stopMonitoringRegions()
            setServiceAvailable(false)
            setServiceStarted(false)
        }
        
    }
    
    // Call this in the locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) Method
    func didResumeUpdates() {
        if let lastLocation = lastLocation {
            NotificationCenter.default.post(Notification(name: .locationDelegateUpdateLocationNotification, object: self, userInfo: ["location": lastLocation]))
        }
    }
    
    // Call this in the locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) Method
    func didEnterRegion(_ region: CLRegion) {
        setupCLLocationManager()
        NotificationCenter.default.post(Notification(name: .locationDelegateNearObjectNotification, object:self, userInfo:["identifier" : region.identifier]))
        clLocationManager.stopMonitoring(for: region)
    }
    
    // Call this in the locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) Method
    func didChangeAuthorizationStatus(_ status: CLAuthorizationStatus) {
        
        switch status {
        case .authorizedAlways:
            //clLocationManager.startMonitoringSignificantLocationChanges()
            clLocationManager.startUpdatingLocation()
            clLocationManager.startUpdatingHeading()
            setServiceAvailable(true)
        case .authorizedWhenInUse:
            //clLocationManager.startMonitoringSignificantLocationChanges()
            clLocationManager.startUpdatingLocation()
            clLocationManager.startUpdatingHeading()
            setServiceAvailable(true)
        default:
            stopLocationService()
            setServiceAvailable(false)
            setServiceStarted(false)
        }
        
    }
    
    // Call this in the locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) Method
    func didUpdateHeading(_ newHeading: CLHeading) {
        
        let lastHeading: CLLocationDirection = {
            if newHeading.headingAccuracy >= 0 {
                return newHeading.trueHeading
            } else {
                return newHeading.magneticHeading
            }
        }()
        
        setLastLocationDirection(lastHeading)
        
        if let mostReliableARHeading = mostReliableARHeading {
            if newHeading.headingAccuracy == mostReliableARHeading.headingAccuracy {
                if newHeading.timestamp > mostReliableARHeading.timestamp {
                    setMostReliableARHeading(newHeading)
                }
            } else if newHeading.headingAccuracy < mostReliableARHeading.headingAccuracy && newHeading.headingAccuracy > 0 {
                setMostReliableARHeading(newHeading)
                NotificationCenter.default.post(Notification(name: .locationDelegateMoreReliableARHeadingNotification, object: self, userInfo: ["heading": newHeading]))
            }
        } else {
            setMostReliableARHeading(newHeading)
            NotificationCenter.default.post(Notification(name: .locationDelegateMoreReliableARHeadingNotification, object: self, userInfo: ["heading": newHeading]))
        }
        
    }
    
    // MARK: Private
    
    private func setupCLLocationManager() {
        
        clLocationManager.activityType = .other
        clLocationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        clLocationManager.distanceFilter = kCLDistanceFilterNone
        clLocationManager.headingFilter = kCLHeadingFilterNone
        clLocationManager.pausesLocationUpdatesAutomatically = false
        
        requestInUseAuthorization()
        
    }
    
}

