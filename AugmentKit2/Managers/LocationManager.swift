//
//  LocationManager.swift
//  AugmentKit2
//
//  Created by Jamie Scanlon on 7/4/17.
//  Copyright © 2017 TenthLetterMade. All rights reserved.
//

import Foundation
import CoreLocation

extension Notification.Name {
    static let locationDelegateUpdateLocationNotification = Notification.Name("com.tenthlettermade.notificaiton.LocationDelegateUpdateLocation")
    static let locationDelegateNearObjectNotification = Notification.Name("com.tenthlettermade.notificaiton.LocationDelegateNearObjectNotification")
}

// MARK: - LocationManager

protocol LocationManager {
    var clLocationManager: CLLocationManager { get }
    var localStoreManager: LocalStoreManager? { get }
    var serviceAvailable: Bool { get }
    var serviceStarted: Bool { get }
    var lastLocation: CLLocation? { get }
    
    // This should return the CLLocationManager.locationServicesEnabled()
    func locationServicesEnabled() -> Bool
    // This should return the CLLocationManager.authorizationStatus()
    func authorizationStatus() -> CLAuthorizationStatus
    func setServiceAvailable(_ value: Bool)
    func setServiceStarted(_ value: Bool)
    func setLastLocation(_ value: CLLocation)
    
}

extension LocationManager {
    
    func startLocationService() {
        
        if locationServicesEnabled() {
            setServiceAvailable(false)
        } else {
            setServiceAvailable(true)
        }
        
        setupCLLocationManager()
        
        // Call stopUpdatingLocation to force a new event
        // when startUpdatingLocation is called.
        stopLocationService()
        
        clLocationManager.startMonitoringSignificantLocationChanges()
        clLocationManager.startUpdatingLocation()
        
        setServiceStarted(true)
        
    }
    
    func stopLocationService() {
        
        clLocationManager.stopUpdatingLocation()
        clLocationManager.stopMonitoringSignificantLocationChanges()
        setServiceStarted(false)
        
    }
    
    func isLocationServiceAvailable() -> Bool {
        return serviceAvailable
    }
    
    func isServiceStarted() -> Bool {
        return serviceStarted
    }
    
    func hasGivenAutorization() -> Bool {
        return  (authorizationStatus() == .authorizedAlways || authorizationStatus() == .authorizedWhenInUse)
    }
    
    func stopMonitoringRegions() {
        
        setupCLLocationManager()
        
        for region in clLocationManager.monitoredRegions {
            clLocationManager.stopMonitoring(for: region)
        }
        
    }
    
    func requestAlwaysAuthorization() {
        clLocationManager.requestAlwaysAuthorization()
    }
    
    func requestInUseAuthorization() {
        clLocationManager.requestWhenInUseAuthorization()
    }
    
    func currentLocation() -> CLLocation? {
        
        guard isLocationServiceAvailable() else {
            return nil
        }
        
        var theLocation = clLocationManager.location
        
        if theLocation == nil {
            
            if let archivedLocationData = localStoreManager?.lastKnownLocationData, let archivedLocationDict = NSKeyedUnarchiver.unarchiveObject(with: archivedLocationData) as? [String: Any], let lastKnownLocation = archivedLocationDict["location"] as? CLLocation, let myUpddatedTime = archivedLocationDict["updated"] as? Date {
                // If it's less than an hour ago, ignore it.
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
        
        let distanceFromLastLocation: Double = {
            if let lastLocation = lastLocation {
                return mostRecentLocation.distance(from: lastLocation)
            } else {
                return 1000
            }
        }()
        
        setLastLocation(mostRecentLocation)
        
        let archivedLocationDict: [String: Any] = ["location": mostRecentLocation, "updated": Date()]
        let archivedLocationData = NSKeyedArchiver.archivedData(withRootObject: archivedLocationDict)
        localStoreManager?.setLastKnownLocationData(archivedLocationData)
        
        let eventDate = mostRecentLocation.timestamp
        let howRecent = eventDate.timeIntervalSinceNow
        
        // Throw away results more than 15 seconds old as they are likely to be cached.
        if fabs(howRecent) < 15 {
            
            print("INFO: latitude \(mostRecentLocation.coordinate.latitude), longitude \(mostRecentLocation.coordinate.longitude)")
            
            NotificationCenter.default.post(Notification(name: .locationDelegateUpdateLocationNotification, object: self, userInfo: ["location": mostRecentLocation]))
            
            // Stop location services once we have a fix but continue
            // monitoring for significant location changes.
            if distanceFromLastLocation < 10 {
                clLocationManager.stopUpdatingLocation()
            }
            
        }
        
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
            clLocationManager.startMonitoringSignificantLocationChanges()
            clLocationManager.startUpdatingLocation()
            setServiceAvailable(true)
        case .authorizedWhenInUse:
            clLocationManager.startMonitoringSignificantLocationChanges()
            clLocationManager.startUpdatingLocation()
            setServiceAvailable(true)
        default:
            stopLocationService()
            setServiceAvailable(false)
            setServiceStarted(false)
        }
        
    }
    
    // MARK: Private
    
    private func setupCLLocationManager() {
        
        clLocationManager.activityType = .other
        clLocationManager.desiredAccuracy = kCLLocationAccuracyBest
        
        // Set a movement threshold for new events.
        clLocationManager.distanceFilter = 400
        
        requestInUseAuthorization()
        
    }
    
}

