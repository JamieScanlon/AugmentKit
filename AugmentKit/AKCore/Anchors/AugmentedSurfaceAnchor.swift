//
//  AugmentedSurfaceAnchor.swift
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
import simd

/**
 A generic implementation of `AKAugmentedSurfaceAnchor` that renders a `MDLTexture` on a simple plane with a given extent
 */
open class AugmentedSurfaceAnchor: AKAugmentedSurfaceAnchor {
    
    /**
     A type string. Always returns "AugmentedSurface"
     */
    public static var type: String {
        return "AugmentedSurface"
    }
    /**
     The location in the ARWorld
     */
    public var worldLocation: AKWorldLocation
    /**
     The heading in the ARWorld. Defaults to `NorthHeading()`
     */
    public var heading: AKHeading = NorthHeading()
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
     Indicates whether this geometry participates in the generation of augmented shadows. Since this is an augmented geometry, it does generate shadows.
     */
    public var generatesShadows: Bool = true
    /**
     If `true`, the current base color texture of the entity has changed since the last time it was rendered and the pixel data needs to be updated. This flag can be used to achieve dynamically updated textures for rendered objects.
     */
    public var needsColorTextureUpdate: Bool = false
    /**
     An `ARAnchor` that will be tracked in the AR world by `ARKit`
     */
    public var arAnchor: ARAnchor?
    /**
     Initialize a new object with a `MDLTexture` and an extent representing the size at a `AKWorldLocation` and AKHeading using a `MTKMeshBufferAllocator` for allocating the geometry
     - Parameters:.
        - withTexture: The `MDLTexture` containing the image texture
        - extent: The size of the geometry in meters
        - at: The location of the anchor
        - heading: The heading for the anchor
        - withAllocator: A `MTKMeshBufferAllocator` with wich to create the plane geometry
     */
    public init(withTexture texture: MDLTexture, extent: vector_float3, at location: AKWorldLocation, heading: AKHeading? = nil, withAllocator metalAllocator: MTKMeshBufferAllocator? = nil) {
        
        let mesh = MDLMesh(planeWithExtent: extent, segments: vector2(1, 1), geometryType: .triangles, allocator: metalAllocator)
        let scatteringFunction = MDLScatteringFunction()
        let material = MDLMaterial(name: "baseMaterial", scatteringFunction: scatteringFunction)
        let textureSampler = MDLTextureSampler()
        textureSampler.texture = texture
        let property = MDLMaterialProperty(name: "baseColor", semantic: MDLMaterialSemantic.baseColor, textureSampler: textureSampler)
        material.setProperty(property)
        
        for submesh in mesh.submeshes!  {
            if let submesh = submesh as? MDLSubmesh {
                submesh.material = material
            }
        }
        let asset = MDLAsset(bufferAllocator: metalAllocator)
        asset.add(mesh)
        
        self.asset = asset
        self.worldLocation = location
        if let heading = heading {
            self.heading = heading
        }
        
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

/// :nodoc:
extension AugmentedSurfaceAnchor: CustomDebugStringConvertible, CustomStringConvertible {
    
    /// :nodoc:
    public var description: String {
        return debugDescription
    }
    
    /// :nodoc:
    public var debugDescription: String {
        let myDescription = "<AugmentedSurfaceAnchor: \(Unmanaged.passUnretained(self).toOpaque())> worldLocation: \(worldLocation), identifier:\(identifier?.uuidString ?? "None"), effects: \(effects?.debugDescription ?? "None"), arAnchor: \(arAnchor?.debugDescription ?? "None"), asset: \(asset)"
        return myDescription
    }
    
}
