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
    /**
     A Notification issued when the location delegate has detected a location change
     */
    public static let locationDelegateUpdateLocationNotification = Notification.Name("com.tenthlettermade.augmentKit.notificaiton.LocationDelegateUpdateLocation")
    /**
     A Notification issued when the location delegate has entered a region
     */
    public static let locationDelegateNearObjectNotification = Notification.Name("com.tenthlettermade.notificaiton.augmentKit.LocationDelegateNearObjectNotification")
    /**
     A Notification issued when the location delegate has a more accuate location available
     */
    public static let locationDelegateMoreReliableARLocationNotification = Notification.Name("com.tenthlettermade.augmentKit.notificaiton.LocationDelegateMoreReliableARLocation")
    /**
     A Notification issued when the location delegate has a more accuate heading available
     */
    public static let locationDelegateMoreReliableARHeadingNotification = Notification.Name("com.tenthlettermade.augmentKit.notificaiton.LocationDelegateMoreReliableARHeading")
}

// MARK: - LocationManager

/**
 Describes ab object responsible for aquiring and monitoring the users location.
 */
public protocol LocationManager {
    /**
     The backing `CLLocationManager`
     */
    var clLocationManager: CLLocationManager { get }
    /**
     A `LocalStoreManager` that is used to store user location state locally
     */
    var localStoreManager: LocalStoreManager? { get }
    /**
     Returns `true` if location services are available
     */
    var serviceAvailable: Bool { get }
    /**
     Returns `true` if location services have started
     */
    var serviceStarted: Bool { get }
    /**
     The last recorded location
     */
    var lastLocation: CLLocation? { get }
    /**
     The last recorded heading
     */
    var lastHeadingDirection: CLLocationDirection? { get }
    
    /**
     Provides the CLLocation with the highest accuracy. This gets updated With the most recent location if the most recent location has at least as much accuracy as the last reading.
     */
    var mostReliableARLocation: CLLocation? { get }
    
    /**
     Provides the CLHeading with the highest accuracy. This gets updated with the most recent location if the most recent location has at least as much accuracy as the last reading.
     */
    var mostReliableARHeading: CLHeading? { get }
    
    /**
     This should return the CLLocationManager.locationServicesEnabled()
     */
    func locationServicesEnabled() -> Bool
    /**
     This should return the CLLocationManager.authorizationStatus()
     */
    func authorizationStatus() -> CLAuthorizationStatus
    /**
     Change the `serviceAvailable` state
     */
    func setServiceAvailable(_ value: Bool)
    /**
     Change the `serviceStarted` state
     */
    func setServiceStarted(_ value: Bool)
    /**
     Change the `lastLocation` value
     */
    func setLastLocation(_ value: CLLocation)
    /**
     Change the `mostReliableARLocation` value
     */
    func setMostReliableARLocation(_ value: CLLocation)
    /**
     Change the `lastHeadingDirection` value
     */
    func setLastLocationDirection(_ value: CLLocationDirection)
    /**
     Change the `mostReliableARHeading` value
     */
    func setMostReliableARHeading(_ value: CLHeading)
    
}

public extension LocationManager {
    
    /**
     Starts location services
     */
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
    
    /**
     Stops location services
     */
    public func stopLocationService() {
        
        clLocationManager.stopUpdatingLocation()
        clLocationManager.stopMonitoringSignificantLocationChanges()
        setServiceStarted(false)
        
    }
    /**
     - Returns: `true` if location services are available
     */
    public func isLocationServiceAvailable() -> Bool {
        return serviceAvailable
    }
    /**
     - Returns: `true` if location services are started
     */
    public func isServiceStarted() -> Bool {
        return serviceStarted
    }
    /**
     - Returns: `true` if location services have been authorized
     */
    public func hasGivenAutorization() -> Bool {
        return  (authorizationStatus() == .authorizedAlways || authorizationStatus() == .authorizedWhenInUse)
    }
    
    func stopMonitoringRegions() {
        
        setupCLLocationManager()
        
        for region in clLocationManager.monitoredRegions {
            clLocationManager.stopMonitoring(for: region)
        }
        
    }
    /**
     Request Always On authoirization with the system
     */
    public func requestAlwaysAuthorization() {
        clLocationManager.requestAlwaysAuthorization()
    }
    /**
     Request When In Use authoirization with the system
     */
    public func requestInUseAuthorization() {
        clLocationManager.requestWhenInUseAuthorization()
    }
    /**
     - Returns: The most recent recorded location
     */
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
    
    /**
     Updated the locations.
     Call this in the `locationManager(_:,didUpdateLocations:)` method of the `CLLocationManagerDelegate`
     - Parameters:
        - _: New Locations
     */
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
    /**
     Handles and error.
     Call this in the `locationManager(_:,didFailWithError:)` method of the `CLLocationManagerDelegate`
     - Parameters:
        - _: Error
     */
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
    
    /**
     Gets called when location tracking resumes
     Call this in the `locationManagerDidResumeLocationUpdates(_:)` method of the `CLLocationManagerDelegate`
     */
    func didResumeUpdates() {
        if let lastLocation = lastLocation {
            NotificationCenter.default.post(Notification(name: .locationDelegateUpdateLocationNotification, object: self, userInfo: ["location": lastLocation]))
        }
    }
    
    /**
     Called when entering a region
     Call this in the `locationManager(_:,didEnterRegion:)` method of the `CLLocationManagerDelegate`
     - Parameters:
        - _: Region
     */
    func didEnterRegion(_ region: CLRegion) {
        setupCLLocationManager()
        NotificationCenter.default.post(Notification(name: .locationDelegateNearObjectNotification, object:self, userInfo:["identifier" : region.identifier]))
        clLocationManager.stopMonitoring(for: region)
    }
    
    /**
     Called when authorization status changes
     Call this in the `locationManager(_:,didChangeAuthorization:)` method of the `CLLocationManagerDelegate`
     - Parameters:
        - _: Status
     */
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
    
    /**
     Called when the heading updates
     Call this in the `locationManager(_:,didUpdateHeading:)` method of the `CLLocationManagerDelegate`
     - Parameters:
        - _: New heading
     */
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

