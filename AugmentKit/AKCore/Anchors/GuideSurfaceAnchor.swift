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

/**
 An anchor used for debugging which displays a guide image as the texture for real surfaces detected by `ARKit`
 */
public class GuideSurfaceAnchor: AKRealSurfaceAnchor {
    
    /**
     A type string. Always returns "GuideSurface"
     */
    public static var type: String {
        return "GuideSurface"
    }
    /**
     The orientation of the surface. Either horizontal or vertical. Defaulets to `ARPlaneAnchor.Alignment.horizontal`
     */
    public var orientation: ARPlaneAnchor.Alignment = .horizontal
    /**
     The location in the ARWorld
     */
    public var worldLocation: AKWorldLocation
    /**
     The heading in the ARWorld. Defaults to `SameHeading()`
     */
    public var heading: AKHeading = SameHeading()
    /**
     The `MDLAsset` associated with the entity.
     */
    public var asset: MDLAsset
    /**
     A unique, per-instance identifier
     */
    public var identifier: UUID?
    /**
     An array of `AKEffect` objects that are applied by the renderer
     */
    public var effects: [AnyEffect<Any>]?
    /**
     Specified a perfered renderer to use when rendering this enitity. Most will use the standard PBR renderer but some entities may prefer a simpiler renderer when they are not trying to achieve the look of real-world objects. Defaults to `ShaderPreference.simple`
     */
    public var shaderPreference: ShaderPreference = .simple
    /**
     An `ARAnchor` that will be tracked in the AR world by `ARKit`
     */
    public var arAnchor: ARAnchor?
    /**
     Creates a plane asset from a png in the bundle named "plane_grid". The plane geometry is created using the `MTKMeshBufferAllocator`
     - Parameters:
        - inBundle: The `Bundle` where the plane_grid.png asset is located
        - withAllocator: A `MTKMeshBufferAllocator` with wich to create the plane geometry
     */
    public static func createModelAsset(inBundle bundle: Bundle, withAllocator metalAllocator: MTKMeshBufferAllocator?) -> MDLAsset? {
        
        if let asset = MDLAssetTools.assetFromImage(inBundle: bundle, withName: "plane_grid", extension: "png", allocator: metalAllocator) {
            return asset
        }
        
        return nil
        
    }
    /**
     Initialize a new object with an a image called plane_grid.png located in the bundle and allocated using the `MTKMeshBufferAllocator`
     - Parameters:.
        - bundle: The `Bundle` where the plane_grid.png asset is located
        - withAllocator: A `MTKMeshBufferAllocator` with wich to create the plane geometry
     */
    public init(inBundle bundle: Bundle, at location: AKWorldLocation, withAllocator metalAllocator: MTKMeshBufferAllocator? = nil) {
        
        let mySurfaceModelAsset = GuideSurfaceAnchor.createModelAsset(inBundle: bundle, withAllocator: metalAllocator)!
        
        self.asset = mySurfaceModelAsset
        self.worldLocation = location
        
    }
    /**
     Set the identifier for this instance
     - Parameters:
        - _: A UUID
     */
    public func setIdentifier(_ identifier: UUID) {
        self.identifier = identifier
    }
    /**
     Sets a new `arAnchor`
     - Parameters:
        - _: An `ARAnchor`
     */
    public func setARAnchor(_ arAnchor: ARAnchor) {
        self.arAnchor = arAnchor
        if identifier == nil {
            identifier = arAnchor.identifier
        }
        worldLocation.transform = arAnchor.transform
    }
    
}
