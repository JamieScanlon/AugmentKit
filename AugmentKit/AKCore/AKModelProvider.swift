//
//  AKModelProvider.swift
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
import ModelIO

/**
 Defines an object that is responsible for loading `MDLAsset` asset models. The AugmentKit render engine loads models as they are needed in the AR world. A `ModelProvider` implementation is responsible for loading `MDLAsset`'s when requested and caching them as needed.
 
 AugmentKit provides `AKModelProvider` as a default implementation of this protocol that caches all `MDLAsset` objects in memory. Although this is the simplest implementation, you may need to provide your own implementation of `ModelProvider` in order to provide a more economical caching strategy.
 */
public protocol ModelProvider {
    /**
     Implementations should store the `MDLAsset` and associate it with the provided `type` and `identifier` such that when `loadAsset(forObjectType:,identifier:,completion:)` is called, the appropriate `MDLAsset` can re returned.
     
     Object type and identifier are heirarchical. A type is a general anchor type. An identifier is a specific anchor instance but if a `MDLAsset` for a specific instance is not found, the `ModelProvider` should provide an `MDLAsset` matching the type. `ModelProvider` should always try to provide the a `MDLAsset` when one is requested if at all possible.
     
     - Parameters:
        - : An `MDLAsset` that should be returned
        - forObjectType: The type associated with the `MDLAsset`
        - identifier: The identifier associated with the `MDLAsset`
     */
    func registerAsset(_ asset: MDLAsset, forObjectType type: String, identifier: UUID?)
    /**
     Implementations should remove any stored `MDLAsset`s associated with the provided `type` and `identifier`
     
     - Parameters:
        - forObjectType: The type of the `MDLAsset` to be removed.
        - identifier: The identifier of the `MDLAsset` to be removed.
     */
    func unregisterAsset(forObjectType type: String, identifier: UUID?)
    /**
     When called, the `ModelProvider` implementation should load and return the `MDLAsset` most appropriate given the type and identifier. `ModelProvider` should always try to provide the a `MDLAsset` when one is requested if at all possible. If a `MDLAsset` for a specific identifier is not found, the `ModelProvider` should provide an `MDLAsset` matching the type, or a default `MDLAsset`.
     - Parameters:
        - forObjectType: The type of the `MDLAsset` to be loaded.
        - identifier: The identifier of the `MDLAsset` to be loaded.
        - completion: a block that provides the `MDLAsset` after being loaded.
     */
    func loadAsset(forObjectType type: String, identifier: UUID?, completion: (MDLAsset?) -> Void)
}

/**
 A standard implementation of `ModelProvider`. This implementation stores all registered `MDLAsset` objects in memory and returns them synchronously when `loadAsset(forObjectType:,identifier:,completion:)` is called.
 */
public class AKModelProvider: ModelProvider {
    
    /**
     Provides a singleton instance.
     */
    static let sharedInstance = AKModelProvider()
    
    /**
     This implementation stores the `MDLAsset` in memory.
     - Parameters:
        - : An `MDLAsset` that should be returned
        - forObjectType: The type associated with the `MDLAsset`
        - identifier: The identifier associated with the `MDLAsset`
     */
    public func registerAsset(_ asset: MDLAsset, forObjectType type: String, identifier: UUID?) {
        // The first model registered will also be used as the default model
        if assetsByType.isEmpty {
            assetsByType["AnyAnchor"] = asset
        }
        if assetsByType[type] == nil || identifier == nil {
            assetsByType[type] = asset
        }
        if let identifier = identifier {
            assetsByIdentifier[identifier] = asset
        }
    }
    
    /**
     Clears the stored `MDLAsset` from memory.
     - Parameters:
        - forObjectType: The type of the `MDLAsset` to be removed.
        - identifier: The identifier of the `MDLAsset` to be removed.
     */
    public func unregisterAsset(forObjectType type: String, identifier: UUID?) {
        if let identifier = identifier {
            assetsByIdentifier[identifier] = nil
        } else {
            assetsByType[type] = nil
        }
    }
    
    /**
     Provides the `MDLAsset` matching the `identifier`. If none is found or if `identifier` is not specified, it provides the `MDLAsset` matching the object type.
     - Parameters:
        - forObjectType: The type of the `MDLAsset` to be loaded.
        - identifier: The identifier of the `MDLAsset` to be loaded.
        - completion: a block that provides the `MDLAsset` after being loaded.
     */
    public func loadAsset(forObjectType type: String, identifier: UUID?, completion: (MDLAsset?) -> Void) {
        if let identifier = identifier, let anchorAsset = assetsByIdentifier[identifier] {
            completion(anchorAsset)
        } else if let anchorAsset = assetsByType[type] {
            completion(anchorAsset)
        } else {
            print("Warning - Failed to find an MDLAsset for type: \(type).")
            completion(nil)
        }
    }
    
    // MARK: - Private
    
    private var assetsByType = [String: MDLAsset]()
    private var assetsByIdentifier = [UUID: MDLAsset]()
    
}
