//
//  AKAnchorSceneKitExtensions.swift
//  AugmentKit2
//
//  MIT License
//
//  Copyright (c) 2017 JamieScanlon
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
//
//  Extensions for loading a model from SceneKit so it can be used as an anchor.
//  This can be excluded if SceneKit is not being used.
//

import Foundation
import SceneKit.ModelIO
import MetalKit

extension AKAnchor {
    
    static func mdlAssetFromScene(named: String, world: AKWorld) -> MDLAsset? {
    
        guard let scene = SCNScene(named: named) else {
            return nil
        }
        
        return Self.mdlAssetFromScene(scene, world: world)
        
    }
    
    static func mdlAssetFromScene(withURL url: URL, world: AKWorld) -> MDLAsset? {
        
        do {
            let scene = try SCNScene(url: url, options: nil)
            return Self.mdlAssetFromScene(scene, world: world)
        } catch {
            return nil
        }
        
    }
    
    static func mdlAssetFromScene(_ scene: SCNScene, world: AKWorld) -> MDLAsset {
        
        // Create a MetalKit mesh buffer allocator so that ModelIO will load mesh data directly into
        //   Metal buffers accessible by the GPU
        let metalAllocator = MTKMeshBufferAllocator(device: world.device)
        
        let asset = MDLAsset(scnScene: scene, bufferAllocator: metalAllocator)
        return asset
        
    }
    
}
