//
//  LocalStoreManager.swift
//  AugmentKit2
//
//  Created by Jamie Scanlon on 7/4/17.
//  Copyright © 2017 TenthLetterMade. All rights reserved.
//

import Foundation

public protocol LocalStoreManager {
    var lastKnownLocationData: Data? { get }
    func setLastKnownLocationData(_ value: Data)
}

public class DefaultLocalStoreManager: LocalStoreManager {
    
    public static let shared = DefaultLocalStoreManager()
    
    public var lastKnownLocationData: Data?
    public func setLastKnownLocationData(_ value: Data) {
        lastKnownLocationData = value
    }
    
}
