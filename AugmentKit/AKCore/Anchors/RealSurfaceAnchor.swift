//
//  RealSurfaceAnchor.swift
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

import ARKit
import Foundation
import MetalKit

/**
 A generic implementation of AKRealSurfaceAnchor. Renders a featureless plane geometry.
 */
open class RealSurfaceAnchor: AKRealSurfaceAnchor {
    
    /**
     A type string. Always returns "RealSurface"
     */
    public static var type: String {
        return "RealSurface"
    }
    /**
     The orientation of the surface. Either horizontal or vertical. Defaulets to `ARPlaneAnchor.Alignment.horizontal`
     */
    public var orientation: ARPlaneAnchor.Alignment = .horizontal
    /**
     The geometry that describes the shape of the plane if it not a rectangle.
     */
    public var planeGeometry: ARPlaneGeometry? {
        didSet {
            needsMeshUpdate = true
        }
    }
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
     Specified a perfered renderer to use when rendering this enitity. Most will use the standard PBR renderer but some entities may prefer a simpiler renderer when they are not trying to achieve the look of real-world objects. Defaults to `ShaderPreference.pbr`
     */
    public var shaderPreference: ShaderPreference = .pbr
    /**
     Indicates whether this geometry participates in the generation of augmented shadows. Since this is a geometry that represents a real world object, it does not generate shadows.
     */
    public var generatesShadows: Bool = false
    /**
     If `true`, the current base color texture of the entity has changed since the last time it was rendered and the pixel data needs to be updated. This flag can be used to achieve dynamically updated textures for rendered objects.
     */
    public var needsColorTextureUpdate: Bool = false
    /// If `true` the underlying mesh for this geometry has changed and the renderer needs to update. This can be used to achieve dynamically generated geometries that change over time.
    public var needsMeshUpdate: Bool = false
    /**
     An `ARAnchor` that will be tracked in the AR world by `ARKit`
     */
    public var arAnchor: ARAnchor?
    
    /**
     Initialize a new object with an `MDLAsset` and an `AKWorldLocation`
     - Parameters:.
        - at: The location of the anchor
        - withAllocator: A `MTKMeshBufferAllocator` with wich to create the plane geometry
     */
    public init(at location: AKWorldLocation, planeGeometry: ARPlaneGeometry? = nil, withAllocator metalAllocator: MTKMeshBufferAllocator? = nil) {
        self.asset = MDLAsset()
        self.worldLocation = location
        self.planeGeometry = planeGeometry
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
    
    /**
     Creates a generic plane asset with a base color (defaults to white). The plane geometry is created using the `MTKMeshBufferAllocator`
     - Parameters:
     - withAllocator: A `MTKMeshBufferAllocator` with wich to create the plane geometry
     */
    public static func createModelAsset(withName: String, allocator metalAllocator: MTKMeshBufferAllocator?, baseColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)) -> MDLAsset {
        
        let mesh = MDLMesh(planeWithExtent: SIMD3<Float>(1, 0, 1), segments: SIMD2<UInt32>(1, 1), geometryType: .triangles, allocator: metalAllocator)
        let scatteringFunction = MDLScatteringFunction()
        let material = MDLMaterial(name: "RealSurfaceAnchor - baseMaterial", scatteringFunction: scatteringFunction)
        let property = MDLMaterialProperty(name: "bsseColor", semantic: .baseColor, float4: baseColor) // Clear white
        material.setProperty(property)
        for submesh in mesh.submeshes!  {
            if let submesh = submesh as? MDLSubmesh {
                submesh.material = material
            }
        }
        let asset = MDLAsset(bufferAllocator: metalAllocator)
        asset.add(mesh)
        
        return asset
        
    }
    
}
