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
    static let locationDelegateMoreReliableARLocationNotification = Notification.Name("com.tenthlettermade.notificaiton.LocationDelegateMoreReliableARLocation")
}

// MARK: - LocationManager

protocol LocationManager {
    var clLocationManager: CLLocationManager { get }
    var localStoreManager: LocalStoreManager? { get }
    var serviceAvailable: Bool { get }
    var serviceStarted: Bool { get }
    var lastLocation: CLLocation? { get }
    var lastHeading: CLLocationDirection? { get }
    var headingAccuracy: CLLocationDegrees? { get }
    
    // Provides the CLLocation with the highest accuracy. This gets updated
    // With the most recent location if the most recent location has at least
    // as much accuracy as the last reading.
    var mostReliableARLocation: CLLocation? { get }
    
    // This should return the CLLocationManager.locationServicesEnabled()
    func locationServicesEnabled() -> Bool
    // This should return the CLLocationManager.authorizationStatus()
    func authorizationStatus() -> CLAuthorizationStatus
    func setServiceAvailable(_ value: Bool)
    func setServiceStarted(_ value: Bool)
    func setLastLocation(_ value: CLLocation)
    func setLastHeading(_ value: CLLocationDirection)
    func setHeadingAccuracy(_ value: CLLocationDegrees)
    func setMostReliableARLocation(_ value: CLLocation)
    
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
        
        //clLocationManager.startMonitoringSignificantLocationChanges()
        clLocationManager.startUpdatingLocation()
        clLocationManager.startUpdatingHeading()
        
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
        
        
//        let archivedLocationDict: [String: Any] = ["location": mostRecentLocation, "updated": Date()]
//        let archivedLocationData = NSKeyedArchiver.archivedData(withRootObject: archivedLocationDict)
//        localStoreManager?.setLastKnownLocationData(archivedLocationData)
        print("INFO: latitude \(mostRecentLocation.coordinate.latitude), longitude \(mostRecentLocation.coordinate.longitude)")
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
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        
        if newHeading.headingAccuracy >= 0 {
            setLastHeading(newHeading.trueHeading)
        } else {
            setLastHeading(newHeading.magneticHeading)
        }
        
        setHeadingAccuracy(newHeading.headingAccuracy)
        
    }
    
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        return true
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

// MARK: - Convenience extensions



public extension CLLocationCoordinate2D {
//    public func coordinateWithBearing(bearing:Double, distanceMeters:Double) -> CLLocationCoordinate2D {
//        //The numbers for earth radius may be _off_ here
//        //but this gives a reasonably accurate result..
//        //Any correction here is welcome.
//        let distRadiansLat = distanceMeters.metersToLatitude() // earth radius in meters latitude
//        let distRadiansLong = distanceMeters.metersToLongitude() // earth radius in meters longitude
//
//        let lat1 = self.latitude * Double.pi / 180
//        let lon1 = self.longitude * Double.pi / 180
//
//        let lat2 = asin(sin(lat1) * cos(distRadiansLat) + cos(lat1) * sin(distRadiansLat) * cos(bearing))
//        let lon2 = lon1 + atan2(sin(bearing) * sin(distRadiansLong) * cos(lat1), cos(distRadiansLong) - sin(lat1) * sin(lat2))
//
//        return CLLocationCoordinate2D(latitude: lat2 * 180 / Double.pi, longitude: lon2 * 180 / Double.pi)
//    }
}

