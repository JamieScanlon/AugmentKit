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

public protocol ModelProvider {
    func registerAsset(_ asset: MDLAsset, forObjectType type: String, identifier: UUID?)
    func unregisterAsset(forObjectType type: String, identifier: UUID?)
    func loadAsset(forObjectType type: String, identifier: UUID?, completion: (MDLAsset?) -> Void)
}

public class AKModelProvider: ModelProvider {
    
    static let sharedInstance = AKModelProvider()
    
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
    
    public func unregisterAsset(forObjectType type: String, identifier: UUID?) {
        if let identifier = identifier {
            assetsByIdentifier[identifier] = nil
        } else {
            assetsByType[type] = nil
        }
    }
    
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
