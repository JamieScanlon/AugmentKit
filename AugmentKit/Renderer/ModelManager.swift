//
//  ModelManager.swift
//  AugmentKit
//
//  Created by Marvin Scanlon on 6/6/20.
//  Copyright © 2020 TenthLetterMade. All rights reserved.
//

import Foundation
import MetalKit
import ModelIO

struct ModelManagerOptions: OptionSet {
    let rawValue: Int
    static let loaded = ModelManagerOptions(rawValue: 1 << 0)
    static let cached = ModelManagerOptions(rawValue: 1 << 1)
    
    static let cachedOrLoaded: ModelManagerOptions = [.loaded, .cached]
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

/// A central repository fo `MeshGPUData` objects. Acts as a loader and a cache
class ModelManager {
    
    var device: MTLDevice
    var vertexDescriptor: MDLVertexDescriptor?
    var frameRate: Double = 60
    var textureBundle: Bundle? = nil
    
    init(device: MTLDevice, vertexDescriptor: MDLVertexDescriptor? = nil, textureBundle: Bundle? = nil, frameRate: Double = 60) {
        self.device = device
        self.vertexDescriptor = vertexDescriptor
        self.textureBundle = textureBundle
        self.frameRate = frameRate
        self.workQueue = DispatchQueue(label: "com.tenthlettermade.augmentkit.queue.modelmanaer", qos: .default)
    }
    
    func meshGPUData(for asset: MDLAsset, options: ModelManagerOptions = .cachedOrLoaded, cacheKey: String? = nil, shaderPreference: ShaderPreference = .pbr, completion: ((_ data: MeshGPUData?, _ key: String?) -> Void)? = nil) {
        
        workQueue.async { [unowned self] in
            
            self.workGroup.wait()
            self.workGroup.enter()
            
            if options == .cached {
                guard completion != nil else {
                    self.workGroup.leave()
                    return
                }
            }
            
            let key: String = {
                if let cacheKey = cacheKey {
                    return cacheKey
                } else if let aKey = asset.url?.absoluteString {
                    return aKey
                } else {
                    return UUID().uuidString
                }
            }()
            
            if let completion = completion, let cachedData = self.backingCache[key], options.contains(.cached) {
                // Cache hit
                print("Cache hit for key \(key)")
                completion(cachedData, key)
                self.workGroup.leave()
                return
            }
            
            print("Cache miss for key \(key)")
            
            guard options.contains(.loaded) else {
                // Cache miss with no .loaded option
                completion?(nil, nil)
                self.workGroup.leave()
                return
            }
            
            // Cache miss with .loaded option
            // Load and parse the asset and populate the cache
            ModelIOTools.meshGPUData(from: asset, device: self.device, vertexDescriptor: self.vertexDescriptor, frameRate: self.frameRate, shaderPreference: shaderPreference, loadTextures: true, textureBundle: self.textureBundle) { (meshGPUData) in
                DispatchQueue.main.async { [weak self] in
                    print("Chaching with key \(key)")
                    self?.backingCache[key] = meshGPUData
                    completion?(meshGPUData, key)
                    self?.workGroup.leave()
                }
            }
        }
    }
    
    func clearCache(asset: MDLAsset? = nil, cacheKey: String? = nil) {
        
        workQueue.async { [unowned self] in
            
            self.workGroup.wait()
            self.workGroup.enter()
            
            let key: String? = {
                if let cacheKey = cacheKey {
                    return cacheKey
                } else if let aKey = asset?.url?.absoluteString {
                    return aKey
                } else {
                    return nil
                }
            }()
            
            if let key = key {
                self.backingCache[key] = nil
            }
            
            self.workGroup.leave()
        }
    }
    
    // MARK: - Private
    
    private var backingCache = [String: MeshGPUData]()
    private var workGroup = DispatchGroup()
    private let workQueue: DispatchQueue
}
