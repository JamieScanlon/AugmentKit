//
//  LocalStoreManager.swift
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
/**
 Defines a managers for the users local store.
 */
public protocol LocalStoreManager {
    /**
     The users last known location as a serialized `Data` object
     */
    var lastKnownLocationData: Data? { get }
    /**
     Set the users last known location as a serialized `Data` object
     - Parameters:
        - _: The new value
     */
    func setLastKnownLocationData(_ value: Data)
}
/**
 A default implementation of `LocalStoreManager` which sotores properties in memory
 */
open class DefaultLocalStoreManager: LocalStoreManager {
    /**
     A singleton instance
     */
    public static let shared = DefaultLocalStoreManager()
    /**
     The users last known location as a serialized `Data` object
     */
    public var lastKnownLocationData: Data?
    /**
     Set the users last known location as a serialized `Data` object
     - Parameters:
        - _: The new value
     */
    public func setLastKnownLocationData(_ value: Data) {
        lastKnownLocationData = value
    }
    
}
