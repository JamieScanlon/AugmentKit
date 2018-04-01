//
//  AKArchivedModel.swift
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
import simd

// MARK: - AKArchivedModel
//  An implementation of AKModel where the model can be loaded from an
//  archived data object that was created with SerilizeUtil.serializeMDLAsset()
public class AKArchivedModel: AKModel {
    
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
    
    public init() {}
    
    public init(filePath: String) {
        
        let url = URL(fileURLWithPath: filePath)
        
        guard let aModel = SerializeUtil.unarchiveModel(withFilePath: url) else {
            return
        }
        
        self.jointRootID = aModel.jointRootID
        self.nodeNames = aModel.nodeNames
        self.texturePaths = aModel.texturePaths
        self.localTransforms = aModel.localTransforms
        self.worldTransforms = aModel.worldTransforms
        self.parentIndices = aModel.parentIndices
        self.meshNodeIndices = aModel.meshNodeIndices
        self.meshSkinIndices = aModel.meshSkinIndices
        self.instanceCount = aModel.instanceCount
        self.vertexDescriptors = aModel.vertexDescriptors
        self.vertexBuffers = aModel.vertexBuffers
        self.indexBuffers = aModel.indexBuffers
        self.meshes = aModel.meshes
        self.skins = aModel.skins
        self.sampleTimes = aModel.sampleTimes
        self.localTransformAnimations = aModel.localTransformAnimations
        self.worldTransformAnimations = aModel.worldTransformAnimations
        self.localTransformAnimationIndices = aModel.localTransformAnimationIndices
        self.worldTransformAnimationIndices = aModel.worldTransformAnimationIndices
        self.skeletonAnimations = aModel.skeletonAnimations
        
    }
    
}
