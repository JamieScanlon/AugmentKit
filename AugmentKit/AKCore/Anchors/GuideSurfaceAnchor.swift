//
//  GuideSurfaceAnchor.swift
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
//  An implementation of AKRealSurfaceAnchor which renders an image named plane_grig.png
//  as the texture for a simple plane geometry. This type of anchor is mostly used for
//  visualizing the planes that ARKit detects
//

import ARKit
import Foundation
import MetalKit

public class GuideSurfaceAnchor: AKRealSurfaceAnchor {
    
    public static var type: String {
        return "GuideSurface"
    }
    public var orientation: ARPlaneAnchor.Alignment = .horizontal
    public var worldLocation: AKWorldLocation
    public var heading: AKHeading = SameHeading()
    public var asset: MDLAsset
    public var identifier: UUID?
    public var effects: [AnyEffect<Any>]?
    public var shaderPreference: ShaderPreference = .simple
    public var arAnchor: ARAnchor?
    
    public static func createModelAsset(inBundle bundle: Bundle, withAllocator metalAllocator: MTKMeshBufferAllocator?) -> MDLAsset? {
        
        if let asset = MDLAssetTools.assetFromImage(inBundle: bundle, withName: "plane_grid", extension: "png", allocator: metalAllocator) {
            return asset
        }
        
        return nil
        
    }
    
    public init(inBundle bundle: Bundle, at location: AKWorldLocation, withAllocator metalAllocator: MTKMeshBufferAllocator? = nil) {
        
        let mySurfaceModelAsset = GuideSurfaceAnchor.createModelAsset(inBundle: bundle, withAllocator: metalAllocator)!
        
        self.asset = mySurfaceModelAsset
        self.worldLocation = location
        
    }
    
    public func setIdentifier(_ identifier: UUID) {
        self.identifier = identifier
    }
    
    public func setARAnchor(_ arAnchor: ARAnchor) {
        self.arAnchor = arAnchor
        if identifier == nil {
            identifier = arAnchor.identifier
        }
        worldLocation.transform = arAnchor.transform
    }
    
}
