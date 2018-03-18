//
//  AKModel.swift
//  AugmentKit
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
//  A Protocol that defines a 3D model suitable for rendering by the Renderer class.
//

import Foundation
import AugmentKitShader
import MetalKit
import ModelIO
import simd

// MARK: - AKModel

public protocol AKModel {
    
    var jointRootID: String { get set }
    
    var nodeNames: [String] { get set }
    var texturePaths: [String] { get set }
    
    // Transform for a node at a given index
    var localTransforms: [matrix_float4x4] { get set }
    // Combined transform of all the parent nodes of a node at a given index
    var worldTransforms: [matrix_float4x4] { get set }
    var parentIndices: [Int?] { get set }
    var meshNodeIndices: [Int] { get set }
    var meshSkinIndices: [Int?] { get set }
    var instanceCount: [Int] { get set }
    
    var vertexDescriptors: [MDLVertexDescriptor] { get set }
    var vertexBuffers: [Data] { get set }
    var indexBuffers: [Data] { get set }
    
    var meshes: [MeshData] { get set }
    var skins: [SkinData] { get set }
    
    var sampleTimes: [Double] { get set }
    var localTransformAnimations: [[matrix_float4x4]] { get set }
    var worldTransformAnimations: [[matrix_float4x4]] { get set }
    var localTransformAnimationIndices: [Int?] { get set }
    var worldTransformAnimationIndices: [Int?] { get set }
    
    var skeletonAnimations: [AnimatedSkeleton] { get set }
    
}

extension AKModel {
    
    //  Create a vertex descriptor for our Metal pipeline. Specifies the layout of vertices the
    //  pipeline should expect. The layout below keeps attributes used to calculate vertex shader
    //  output position separate (world position, skinning, tweening weights) separate from other
    //  attributes (texture coordinates, normals).  This generally maximizes pipeline efficiency
    public static func newAnchorVertexDescriptor() -> MDLVertexDescriptor {
        
        let geometryVertexDescriptor = MTLVertexDescriptor()
        
        // Positions.
        geometryVertexDescriptor.attributes[0].format = .float3
        geometryVertexDescriptor.attributes[0].offset = 0
        geometryVertexDescriptor.attributes[0].bufferIndex = Int(kBufferIndexMeshPositions.rawValue)
        
        // Texture coordinates.
        geometryVertexDescriptor.attributes[1].format = .float2
        geometryVertexDescriptor.attributes[1].offset = 0
        geometryVertexDescriptor.attributes[1].bufferIndex = Int(kBufferIndexMeshGenerics.rawValue)
        
        // Normals.
        geometryVertexDescriptor.attributes[2].format = .float3
        geometryVertexDescriptor.attributes[2].offset = 8
        geometryVertexDescriptor.attributes[2].bufferIndex = Int(kBufferIndexMeshGenerics.rawValue)
        
        // TODO: JointIndices and JointWeights for Puppet animations
        
        // Position Buffer Layout
        geometryVertexDescriptor.layouts[0].stride = 12
        geometryVertexDescriptor.layouts[0].stepRate = 1
        geometryVertexDescriptor.layouts[0].stepFunction = .perVertex
        
        // Generic Attribute Buffer Layout
        geometryVertexDescriptor.layouts[1].stride = 20
        geometryVertexDescriptor.layouts[1].stepRate = 1
        geometryVertexDescriptor.layouts[1].stepFunction = .perVertex
        
        // Creata a Model IO vertexDescriptor so that we format/layout our model IO mesh vertices to
        // fit our Metal render pipeline's vertex descriptor layout
        let vertexDescriptor = MTKModelIOVertexDescriptorFromMetal(geometryVertexDescriptor)
        
        // Indicate how each Metal vertex descriptor attribute maps to each ModelIO attribute
        (vertexDescriptor.attributes[Int(kVertexAttributePosition.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributePosition
        (vertexDescriptor.attributes[Int(kVertexAttributeTexcoord.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributeTextureCoordinate
        (vertexDescriptor.attributes[Int(kVertexAttributeNormal.rawValue)] as! MDLVertexAttribute).name   = MDLVertexAttributeNormal
        
        return vertexDescriptor
        
    }
    
}

// MARK: - AKSimpleModel
//  A Basic implementation of the protocol
public class AKSimpleModel: AKModel {
    
    public var jointRootID: String = String()
    public var nodeNames: [String] = [String]()
    public var texturePaths: [String] = [String]()
    public var localTransforms: [matrix_float4x4] = [matrix_float4x4]()
    public var worldTransforms: [matrix_float4x4] = [matrix_float4x4]()
    public var parentIndices: [Int?] = [Int?]()
    public var meshNodeIndices: [Int] = [Int]()
    public var meshSkinIndices: [Int?] = [Int?]()
    public var instanceCount: [Int] = [Int]()
    public var vertexDescriptors: [MDLVertexDescriptor] = [MDLVertexDescriptor]()
    public var vertexBuffers: [Data] = [Data]()
    public var indexBuffers: [Data] = [Data]()
    public var meshes: [MeshData] = [MeshData]()
    public var skins: [SkinData] = [SkinData]()
    public var sampleTimes: [Double] = [Double]()
    public var localTransformAnimations: [[matrix_float4x4]] = [[matrix_float4x4]]()
    public var worldTransformAnimations: [[matrix_float4x4]] = [[matrix_float4x4]]()
    public var localTransformAnimationIndices: [Int?] = [Int?]()
    public var worldTransformAnimationIndices: [Int?] = [Int?]()
    public var skeletonAnimations: [AnimatedSkeleton] = [AnimatedSkeleton]()
    
}
