//
//  LocalStoreManager.swift
//  AugmentKit2
//
//  Created by Jamie Scanlon on 7/4/17.
//  Copyright © 2017 TenthLetterMade. All rights reserved.
//

import Foundation

protocol LocalStoreManager {
    var lastKnownLocationData: Data? { get }
    func setLastKnownLocationData(_ value: Data)
}

class DefaultLocalStoreManager: LocalStoreManager {
    
    static let shared = DefaultLocalStoreManager()
    
    var lastKnownLocationData: Data?
    func setLastKnownLocationData(_ value: Data) {
        lastKnownLocationData = value
    }
    
}
