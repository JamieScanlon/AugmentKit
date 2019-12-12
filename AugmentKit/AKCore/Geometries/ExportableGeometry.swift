//
//  ExportableGeometry.swift
//  AugmentKit
//
//  MIT License
//
//  Copyright (c) 2019 JamieScanlon
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
import Metal
import MetalKit
import ModelIO

// MARK: - ExportableGeometry

/// A `ExportableGeometry` is a tool for creating `MDLAsset` objects with basic geometries.  A `ExportableGeometry` can not be rendered in the AR world by itself. Use `ExportableGeometry` to quickly create simple geometries for `AKGeometricEntity`.
public protocol ExportableGeometry {
    /// The `MTKMeshBufferAllocator` that will be used to create the `MDLAsset`
    var allocator: MTKMeshBufferAllocator { get }
    /// Export a geometry as a `MDLAsset` which can be use with a `AKGeometricEntity` and rendered in a
    var asset: MDLAsset { get }
}

// MARK: - PlaneGeometry

public struct PlaneGeometry: ExportableGeometry {
    
    public var allocator: MTKMeshBufferAllocator
    public var asset: MDLAsset {
        
        let mesh = MDLMesh.newPlane(withDimensions: SIMD2<Float>(width, height), segments: SIMD2<UInt32>(widthSegments, heightSegments), geometryType: .triangles, allocator: allocator)
        let scatteringFunction = MDLScatteringFunction()
        let material = MDLMaterial(name: "baseMaterial", scatteringFunction: scatteringFunction)
         
        var red: CGFloat = 1
        var green: CGFloat = 1
        var blue: CGFloat = 1
        var alpha: CGFloat = 1
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let colorProperty = MDLMaterialProperty(name: "planeColor", semantic: .baseColor, float4: SIMD4<Float>(Float(red), Float(green), Float(blue), Float(alpha)))
        material.setProperty(colorProperty)

        for submesh in mesh.submeshes!  {
            if let submesh = submesh as? MDLSubmesh {
                submesh.material = material
            }
        }

        let asset = MDLAsset(bufferAllocator: allocator)
        asset.add(mesh)
        return asset
    }
    public var width: Float = 0.5
    public var height: Float = 0.5
    public var color: UIColor = .white
    
    public init(with device: MTLDevice, width: Float = 0.5, height: Float = 0.5, color: UIColor = .white) {
        self.allocator = MTKMeshBufferAllocator(device: device)
        self.width = width
        self.height = height
        self.color = color
    }
    
    public init(with allocator: MTKMeshBufferAllocator, width: Float = 0.5, height: Float = 0.5, color: UIColor = .white) {
        self.allocator = allocator
        self.width = width
        self.height = height
        self.color = color
    }
    
    // MARK: - Private
    
    private var widthSegments: UInt32 {
        max(1, UInt32(width))
    }
    private var heightSegments: UInt32 {
        max(1, UInt32(height))
    }
}

// MARK: - BoxGeometry

public struct BoxGeometry: ExportableGeometry {
    
    public var allocator: MTKMeshBufferAllocator
    public var asset: MDLAsset {

        let mesh = MDLMesh.newBox(withDimensions: SIMD3<Float>(width, height, depth), segments: SIMD3<UInt32>(widthSegments, heightSegments, depthSegments), geometryType: .triangles, inwardNormals: false, allocator: allocator)
        let scatteringFunction = MDLScatteringFunction()
        let material = MDLMaterial(name: "baseMaterial", scatteringFunction: scatteringFunction)
         
        var red: CGFloat = 1
        var green: CGFloat = 1
        var blue: CGFloat = 1
        var alpha: CGFloat = 1
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let colorProperty = MDLMaterialProperty(name: "boxColor", semantic: .baseColor, float4: SIMD4<Float>(Float(red), Float(green), Float(blue), Float(alpha)))
        material.setProperty(colorProperty)

        for submesh in mesh.submeshes!  {
            if let submesh = submesh as? MDLSubmesh {
                submesh.material = material
            }
        }

        let asset = MDLAsset(bufferAllocator: allocator)
        asset.add(mesh)
        return asset
    }
    public var width: Float = 0.5
    public var height: Float = 0.5
    public var depth: Float = 0.5
    public var color: UIColor = .white
    
    public init(with device: MTLDevice, width: Float = 0.5, height: Float = 0.5, depth: Float = 0.5, color: UIColor = .white) {
        self.allocator = MTKMeshBufferAllocator(device: device)
        self.width = width
        self.height = height
        self.depth = depth
        self.color = color
    }
    
    public init(with allocator: MTKMeshBufferAllocator, width: Float = 0.5, height: Float = 0.5, depth: Float = 0.5, color: UIColor = .white) {
        self.allocator = allocator
        self.width = width
        self.height = height
        self.depth = depth
        self.color = color
    }
    
    // MARK: - Private
    
    private var widthSegments: UInt32 {
        max(1, UInt32(width))
    }
    private var heightSegments: UInt32 {
        max(1, UInt32(height))
    }
    private var depthSegments: UInt32 {
        max(1, UInt32(depth))
    }
}

// MARK: - ShpereGeometry

public struct ShpereGeometry: ExportableGeometry {
    
    public var allocator: MTKMeshBufferAllocator
    public var asset: MDLAsset {

        let mesh = MDLMesh.newEllipsoid(withRadii: SIMD3<Float>(radius, radius, radius), radialSegments: segments, verticalSegments: segments, geometryType: .triangles, inwardNormals: false, hemisphere: false, allocator: allocator)
        let scatteringFunction = MDLScatteringFunction()
        let material = MDLMaterial(name: "baseMaterial", scatteringFunction: scatteringFunction)
         
        var red: CGFloat = 1
        var green: CGFloat = 1
        var blue: CGFloat = 1
        var alpha: CGFloat = 1
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let colorProperty = MDLMaterialProperty(name: "sphereColor", semantic: .baseColor, float4: SIMD4<Float>(Float(red), Float(green), Float(blue), Float(alpha)))
        material.setProperty(colorProperty)

        for submesh in mesh.submeshes!  {
            if let submesh = submesh as? MDLSubmesh {
                submesh.material = material
            }
        }

        let asset = MDLAsset(bufferAllocator: allocator)
        asset.add(mesh)
        return asset
    }
    public var radius: Float = 0.25
    public var color: UIColor = .white
    
    public init(with device: MTLDevice, radius: Float = 0.25, color: UIColor = .white) {
        self.allocator = MTKMeshBufferAllocator(device: device)
        self.radius = radius
        self.color = color
    }
    
    public init(with allocator: MTKMeshBufferAllocator, radius: Float = 0.25, color: UIColor = .white) {
        self.allocator = allocator
        self.radius = radius
        self.color = color
    }
    
    // MARK: - Private
    
    private var segments: Int {
        max(4, Int(120 * radius))
    }
}

// MARK: - CylinderGeometry

public struct CylinderGeometry: ExportableGeometry {
    
    public var allocator: MTKMeshBufferAllocator
    public var asset: MDLAsset {

        let mesh = MDLMesh.newCylinder(withHeight: height, radii: SIMD2<Float>(radius, radius), radialSegments: radialSegments, verticalSegments: verticalSegments, geometryType: .triangles, inwardNormals: false, allocator: allocator)
        let scatteringFunction = MDLScatteringFunction()
        let material = MDLMaterial(name: "baseMaterial", scatteringFunction: scatteringFunction)
         
        var red: CGFloat = 1
        var green: CGFloat = 1
        var blue: CGFloat = 1
        var alpha: CGFloat = 1
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let colorProperty = MDLMaterialProperty(name: "cylinderColor", semantic: .baseColor, float4: SIMD4<Float>(Float(red), Float(green), Float(blue), Float(alpha)))
        material.setProperty(colorProperty)

        for submesh in mesh.submeshes!  {
            if let submesh = submesh as? MDLSubmesh {
                submesh.material = material
            }
        }

        let asset = MDLAsset(bufferAllocator: allocator)
        asset.add(mesh)
        return asset
    }
    public var height: Float = 1
    public var radius: Float = 0.25
    public var color: UIColor = .white
    
    public init(with device: MTLDevice, height: Float = 1, radius: Float = 0.25, color: UIColor = .white) {
        self.allocator = MTKMeshBufferAllocator(device: device)
        self.height = height
        self.radius = radius
        self.color = color
    }
    
    public init(with allocator: MTKMeshBufferAllocator, height: Float = 1, radius: Float = 0.25, color: UIColor = .white) {
        self.allocator = allocator
        self.height = height
        self.radius = radius
        self.color = color
    }
    
    // MARK: - Private
    
    private var radialSegments: Int {
        max(4, Int(120 * radius))
    }
    private var verticalSegments: Int {
        max(1, Int(height))
    }
}

// MARK: - ConeGeometry

public struct ConeGeometry: ExportableGeometry {
    
    public var allocator: MTKMeshBufferAllocator
    public var asset: MDLAsset {

        let mesh = MDLMesh.newEllipticalCone(withHeight: height, radii: SIMD2<Float>(radius, radius), radialSegments: radialSegments, verticalSegments: verticalSegments, geometryType: .triangles, inwardNormals: false, allocator: allocator)
        let scatteringFunction = MDLScatteringFunction()
        let material = MDLMaterial(name: "baseMaterial", scatteringFunction: scatteringFunction)
         
        var red: CGFloat = 1
        var green: CGFloat = 1
        var blue: CGFloat = 1
        var alpha: CGFloat = 1
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let colorProperty = MDLMaterialProperty(name: "cylinderColor", semantic: .baseColor, float4: SIMD4<Float>(Float(red), Float(green), Float(blue), Float(alpha)))
        material.setProperty(colorProperty)

        for submesh in mesh.submeshes!  {
            if let submesh = submesh as? MDLSubmesh {
                submesh.material = material
            }
        }

        let asset = MDLAsset(bufferAllocator: allocator)
        asset.add(mesh)
        return asset
    }
    public var height: Float = 1
    public var radius: Float = 0.25
    public var color: UIColor = .white
    
    public init(with device: MTLDevice, height: Float = 1, radius: Float = 0.25, color: UIColor = .white) {
        self.allocator = MTKMeshBufferAllocator(device: device)
        self.height = height
        self.radius = radius
        self.color = color
    }
    
    public init(with allocator: MTKMeshBufferAllocator, height: Float = 1, radius: Float = 0.25, color: UIColor = .white) {
        self.allocator = allocator
        self.height = height
        self.radius = radius
        self.color = color
    }
    
    // MARK: - Private
    
    private var radialSegments: Int {
        max(4, Int(120 * radius))
    }
    private var verticalSegments: Int {
        max(1, Int(height))
    }
}

// MARK: - CapsuleGeometry

public struct CapsuleGeometry: ExportableGeometry {
    
    public var allocator: MTKMeshBufferAllocator
    public var asset: MDLAsset {

        let mesh = MDLMesh.newCapsule(withHeight: height, radii: SIMD2<Float>(radius, radius), radialSegments: radialSegments, verticalSegments: verticalSegments, hemisphereSegments: radialSegments, geometryType: .triangles, inwardNormals: false, allocator: allocator)
        let scatteringFunction = MDLScatteringFunction()
        let material = MDLMaterial(name: "baseMaterial", scatteringFunction: scatteringFunction)
         
        var red: CGFloat = 1
        var green: CGFloat = 1
        var blue: CGFloat = 1
        var alpha: CGFloat = 1
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let colorProperty = MDLMaterialProperty(name: "cylinderColor", semantic: .baseColor, float4: SIMD4<Float>(Float(red), Float(green), Float(blue), Float(alpha)))
        material.setProperty(colorProperty)

        for submesh in mesh.submeshes!  {
            if let submesh = submesh as? MDLSubmesh {
                submesh.material = material
            }
        }

        let asset = MDLAsset(bufferAllocator: allocator)
        asset.add(mesh)
        return asset
    }
    public var height: Float = 1
    public var radius: Float = 0.25
    public var color: UIColor = .white
    
    public init(with device: MTLDevice, height: Float = 1, radius: Float = 0.25, color: UIColor = .white) {
        self.allocator = MTKMeshBufferAllocator(device: device)
        self.height = height
        self.radius = radius
        self.color = color
    }
    
    public init(with allocator: MTKMeshBufferAllocator, height: Float = 1, radius: Float = 0.25, color: UIColor = .white) {
        self.allocator = allocator
        self.height = height
        self.radius = radius
        self.color = color
    }
    
    // MARK: - Private
    
    private var radialSegments: Int {
        max(4, Int(120 * radius))
    }
    private var verticalSegments: Int {
        max(1, Int(height))
    }
}
