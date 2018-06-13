//
//  AKRealSurfaceAnchor.swift
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
//
//  And anchor representing a surface plane that has been detected in the real
//  world. Usually these are provided by the AR engine, not created by hand.
//

import ARKit
import Foundation
import MetalKit
import ModelIO

public protocol AKRealSurfaceAnchor: AKRealAnchor {
    var orientation: ARPlaneAnchor.Alignment { get set }
}

public struct RealSurfaceAnchor: AKRealSurfaceAnchor {
    
    public static var type: String {
        return "RealSurface"
    }
    public var orientation: ARPlaneAnchor.Alignment = .horizontal
    public var worldLocation: AKWorldLocation
    public var model: AKModel
    public var identifier: UUID?
    public var effects: [AnyEffect<Any>]?
    
    public init(at location: AKWorldLocation, withAllocator metalAllocator: MTKMeshBufferAllocator? = nil) {
        
        let mesh = MDLMesh(planeWithExtent: vector3(1, 0, 1), segments: vector2(1, 1), geometryType: .triangles, allocator: metalAllocator)
        let asset = MDLAsset(bufferAllocator: metalAllocator)
        asset.add(mesh)
        
        let mySurfaceModel = AKMDLAssetModel(asset: asset, vertexDescriptor: AKMDLAssetModel.newAnchorVertexDescriptor())
        
        self.model = mySurfaceModel
        self.worldLocation = location
        
    }
    
}

public struct GuideSurfaceAnchor: AKRealSurfaceAnchor {
    
    public static var type: String {
        return "GuideSurface"
    }
    public var orientation: ARPlaneAnchor.Alignment = .horizontal
    public var worldLocation: AKWorldLocation
    public var model: AKModel
    public var identifier: UUID?
    public var effects: [AnyEffect<Any>]?
    
    public static func createModel(inBundle bundle: Bundle, withAllocator metalAllocator: MTKMeshBufferAllocator?) -> AKModel? {
        
        if let asset = MDLAssetTools.assetFromImage(inBundle: bundle, withName: "plane_grid", extension: "png", allocator: metalAllocator) {
            let mySurfaceModel = AKMDLAssetModel(asset: asset, vertexDescriptor: AKMDLAssetModel.newAnchorVertexDescriptor())
            return mySurfaceModel
        }
        
        return nil
        
    }
    
    public init(inBundle bundle: Bundle, at location: AKWorldLocation, withAllocator metalAllocator: MTKMeshBufferAllocator? = nil) {
        
        let mesh = MDLMesh(planeWithExtent: vector3(1, 0, 1), segments: vector2(1, 1), geometryType: .triangles, allocator: metalAllocator)
        let asset = MDLAsset(bufferAllocator: metalAllocator)
        asset.add(mesh)
        
        let mySurfaceModel = GuideSurfaceAnchor.createModel(inBundle: bundle, withAllocator: metalAllocator)!
        
        self.model = mySurfaceModel
        self.worldLocation = location
        
    }
    
    public mutating func setIdentifier(_ uuid: UUID) {
        identifier = uuid
    }
    
}
