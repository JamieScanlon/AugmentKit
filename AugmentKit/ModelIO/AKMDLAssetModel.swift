//
//  AKMDLAssetModel.swift
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
//  This class that impements AKModel and can parse an MDLAsset so that it is
//  suitable to be serialized to disk or to be passed directly to the renderer.
//
//  Based heavily on "From Art to Engine with Model I/O" WWDC 2017 talk.
//  https://developer.apple.com/videos/play/wwdc2017/610/
//  Sample Code: https://developer.apple.com/sample-code/wwdc/2017/ModelIO-from-MDLAsset-to-Game-Engine.zip
//

import Foundation
import AugmentKitShader
import Metal
import MetalKit
import ModelIO

// MARK: - AKMDLAssetModel

public class AKMDLAssetModel: AKModel {
    
    public var jointRootID = "root"

    public var nodeNames = [String]()
    public var texturePaths = [String]()

    // Transform for a node at a given index
    public var localTransforms = [matrix_float4x4]()
    // Combined transform of all the parent nodes of a node at a given index
    public var worldTransforms = [matrix_float4x4]()
    public var parentIndices = [Int?]()
    public var meshNodeIndices = [Int]()
    public var meshSkinIndices = [Int?]()
    public var instanceCount = [Int]()

    public var vertexDescriptors = [MDLVertexDescriptor]()
    public var vertexBuffers = [Data]()
    public var indexBuffers = [Data]()

    public var meshes = [MeshData]()
    public var skins = [SkinData]()

    public var sampleTimes = [Double]()
    public var localTransformAnimations = [[matrix_float4x4]]()
    public var worldTransformAnimations = [[matrix_float4x4]]()
    public var localTransformAnimationIndices = [Int?]()
    public var worldTransformAnimationIndices = [Int?]()

    public var skeletonAnimations = [AnimatedSkeleton]()
    
    // MARK: - Init

    public init() {}

    public init(asset: MDLAsset) {
        let vertexDescriptor = AKMDLAssetModel.newVertexDescriptor()
        sampleTimes = ModelIOTools.sampleTimeInterval(start: asset.startTime, end: asset.endTime, frameInterval: 1.0 / 60.0)
        storeAllMeshesInSceneGraph(with: asset, vertexDescriptor: vertexDescriptor)
        flattenSceneGraphHierarchy(with: asset)
        computeSkinToSkeletonMaps()
        ModelIOTools.fixupPaths(asset, &texturePaths)
        updateWorldTransforms()
    }
    
    // MARK: - Private

    // Record all buffers and materials for an MDLMesh
    private func store(_ mesh: MDLMesh, vertexDescriptor: MDLVertexDescriptor? = nil) {
        
        if let vertexDescriptor = vertexDescriptor {
            mesh.vertexDescriptor = vertexDescriptor
        }
        
        let vertexBufferCount = ModelIOTools.getVertexBufferCount(mesh)
        let vbStartIdx = vertexBuffers.count
        let ibStartIdx = indexBuffers.count
        var idxCounts = [Int]()
        var idxTypes = [MDLIndexBitDepth]()
        var materials = [Material]()

        vertexDescriptors.append(mesh.vertexDescriptor)

        vertexBuffers += (0..<vertexBufferCount).map { vertexBufferIndex in
            let vertexBuffer = mesh.vertexBuffers[vertexBufferIndex]
            return Data(bytes: vertexBuffer.map().bytes, count: Int(vertexBuffer.length))
        }

        if let submeshes = mesh.submeshes {
            for case let submesh as MDLSubmesh in submeshes {
                let idxBuffer = submesh.indexBuffer
                indexBuffers.append(Data(bytes: idxBuffer.map().bytes, count: Int(idxBuffer.length)))

                idxCounts.append(Int(submesh.indexCount))
                idxTypes.append(submesh.indexType)

                var material = Material()
                if let mdlMaterial = submesh.material {
                    material.baseColor = readMaterialProperty(mdlMaterial, .baseColor, ModelIOTools.getMaterialFloat3Value)
                    material.metallic = readMaterialProperty(mdlMaterial, .metallic, ModelIOTools.getMaterialFloatValue)
                    material.roughness = readMaterialProperty(mdlMaterial, .roughness, ModelIOTools.getMaterialFloatValue)
                    (_, material.normalMap) = readMaterialProperty(mdlMaterial, .bump, ModelIOTools.getMaterialFloat3Value)
                    (_, material.ambientOcclusionMap) = readMaterialProperty(mdlMaterial, .ambientOcclusion,
                                                                             ModelIOTools.getMaterialFloat3Value)
                }
                materials.append(material)
            }
        }

        let meshData = MeshData(vbCount: vertexBufferCount, vbStartIdx: vbStartIdx,
                                ibStartIdx: ibStartIdx, idxCounts: idxCounts,
                                idxTypes: idxTypes, materials: materials)
        meshes.append(meshData)
    }

    // Record a node's parent index and store its local transform
    private func flattenNode(_ nodeObject: MDLObject, nodeIndex: Int, parentNodeIndex: Int?) {
        nodeNames.append(nodeObject.path)
        if let transform = nodeObject.transform {
            localTransforms.append(transform.matrix)
            if transform.keyTimes.count > 1 {
                let sampledLocalTransforms = sampleTimes.map { transform.localTransform?(atTime: $0) ?? matrix_identity_float4x4 }
                localTransformAnimations.append(sampledLocalTransforms)
                localTransformAnimationIndices.append(localTransformAnimations.count - 1)
            } else {
                localTransformAnimationIndices.append(nil)
            }
        } else {
            localTransforms.append(matrix_identity_float4x4)
            localTransformAnimationIndices.append(nil)
        }

        parentIndices.append(parentNodeIndex)
    }

    // Store scene graph hierarchy's data in linear arrays
    private func flattenSceneGraphHierarchy(with asset: MDLAsset) {
        ModelIOTools.walkSceneGraph(in: asset) { object, currentIdx, parentIdx in
            self.flattenNode(object, nodeIndex: currentIdx, parentNodeIndex: parentIdx)
            if let skeletonRootPath = ModelIOTools.findShortestPath(in: object.path, containing: jointRootID), skeletonRootPath == object.path {
                let animation = createSkeletonAnimation(for: asset, rootPath: skeletonRootPath)
                skeletonAnimations.append(animation)
            }
        }
    }

    // Record all mesh data required to render a particular mesh
    private func storeAllMeshesInSceneGraph(with asset: MDLAsset, vertexDescriptor: MDLVertexDescriptor? = nil) {
        var masterMeshes: [MDLMesh] = []
        ModelIOTools.walkMasters(in: asset) { object in
            guard let mesh = object as? MDLMesh else { return }
            store(mesh, vertexDescriptor: vertexDescriptor)
            masterMeshes.append(mesh)
        }

        var instanceMeshIdx = [Int]()
        ModelIOTools.walkSceneGraph(in: asset) { object, currentIdx, _ in
            if let mesh = object as? MDLMesh {
                meshNodeIndices.append(currentIdx)
                store(mesh, vertexDescriptor: vertexDescriptor)
                instanceMeshIdx.append(meshes.count - 1)
                let hasSkin = storeMeshSkin(for: object)
                meshSkinIndices.append(hasSkin ? skins.count - 1 : nil)
            } else if let instance = object.instance, let masterIndex = ModelIOTools.findMasterIndex(masterMeshes, instance) {
                meshNodeIndices.append(currentIdx)
                instanceMeshIdx.append(masterIndex)
                let hasSkin = storeMeshSkin(for: object)
                meshSkinIndices.append(hasSkin ? skins.count - 1 : nil)
            }
        }

        let (permutation, instCount) = ModelIOTools.sortedMeshIndexPermutation(instanceMeshIdx)
        meshNodeIndices = permutation.map { meshNodeIndices[$0] }
        meshSkinIndices = permutation.map { meshSkinIndices[$0] }
        instanceCount = instCount
    }

    // Store skinning information if object has MDLSkinDeformerComponent
    private func storeMeshSkin(for object: MDLObject) -> Bool {
        guard let skinDeformer = object.componentConforming(to: MDLTransformComponent.self) as? MDLSkeleton else {
            return false
        }

        guard !skinDeformer.jointPaths.isEmpty else {
            return false
        }

        var skin = SkinData()
        // store the joint paths which tell us where the skeleton joints are
        skin.jointPaths = skinDeformer.jointPaths
        // store the joint bind transforms which give us the bind pose
        let jointBindTransforms = skinDeformer.jointBindTransforms
        skin.inverseBindTransforms = jointBindTransforms.float4x4Array.map { simd_inverse($0) }
        skins.append(skin)
        return true
    }

    // Construct a SkeletonAnimation by time-sampling all joint transforms
    private func createSkeletonAnimation(for asset: MDLAsset, rootPath: String) -> AnimatedSkeleton {
        var animation = AnimatedSkeleton()
        var jointCount = 0

        guard let object = asset.objectAtPath(rootPath) else {
            return animation
        }

        jointCount = ModelIOTools.subGraphCount(object)

        animation = AnimatedSkeleton()
        animation.keyTimes = sampleTimes
        animation.translations = [vector_float3](repeating: vector_float3(), count: sampleTimes.count * jointCount)
        animation.rotations = [simd_quatf](repeating: simd_quatf(), count: sampleTimes.count * jointCount)

        ModelIOTools.walkSceneGraph(rootAt: object) { object, jointIndex, parentIndex in
            animation.jointPaths.append(object.path)
            animation.parentIndices.append(parentIndex)

            if let xform = object.componentConforming(to: MDLTransformComponent.self) as? MDLTransformComponent {
                for timeIndex in 0..<sampleTimes.count {
                    let xM = xform.localTransform?(atTime: sampleTimes[timeIndex]) ?? matrix_identity_float4x4
                    let xR = matrix_float3x3(columns: (simd_float3(xM.columns.0.x, xM.columns.0.y, xM.columns.0.z),
                                                       simd_float3(xM.columns.1.x, xM.columns.1.y, xM.columns.1.z),
                                                       simd_float3(xM.columns.2.x, xM.columns.2.y, xM.columns.2.z)))
                    animation.rotations[timeIndex * jointCount + jointIndex] = simd_quaternion(xR)
                    animation.translations[timeIndex * jointCount + jointIndex] =
                        vector_float3(xM.columns.3.x, xM.columns.3.y, xM.columns.3.z)
                }
            }
        }

        return animation
    }

    // Map the joint indices bound to a mesh to the list of all joint indices of a skeleton
    private func computeSkinToSkeletonMaps() {
        let skeletons = skeletonAnimations.map {
            if $0.jointPaths.count > 0 {
                return $0.jointPaths[0]
            } else {
                return nil
            }
        }.flatMap({$0})
        for (skinIndex, skin) in skins.enumerated() {
            guard let boundSkeletonRoot = ModelIOTools.findShortestPath(in: skin.jointPaths[0], containing: jointRootID) else {
                continue
            }

            guard let skeletonIndex = skeletons.index(of: boundSkeletonRoot) else {
                continue
            }

            skins[skinIndex].skinToSkeletonMap = ModelIOTools.mapJoints(from: skin, to: skeletonAnimations[skeletonIndex])
            skins[skinIndex].animationIndex = skeletonIndex
        }
    }

    // Read a material's property of a particular semantic (e.g. .baseColor),
    // and return tuple of uniform value or texture index
    private func readMaterialProperty<T>(_ mdlMaterial: MDLMaterial, _ semantic: MDLMaterialSemantic,
                                 _ getPropertyValue: (MDLMaterialProperty) -> T) -> (uniform: T?, textureIndex: Int?) {
        var result: (uniform: T?, textureIndex: Int?) = (nil, nil)

        for property in mdlMaterial.properties(with: semantic) {
            switch property.type {
                case .float, .float3:
                    result.uniform = getPropertyValue(property)
                    return result
                case .string, .URL:
                    if let path = property.stringValue {
                        if let index = texturePaths.index(of: path) {
                            result.textureIndex = index
                        } else {
                            let index = texturePaths.count
                            texturePaths.append(path)
                            result.textureIndex = index
                        }
                    } else if let path = property.urlValue?.absoluteString {
                        if let index = texturePaths.index(of: path) {
                            result.textureIndex = index
                        } else {
                            let index = texturePaths.count
                            texturePaths.append(path)
                            result.textureIndex = index
                        }
                    } else {
                        result.textureIndex = nil
                    }
                default: break
            }
        }
        return result
    }
    
    private func updateWorldTransforms() {
        
        if sampleTimes.count > 0 {
            var myTransform = [[matrix_float4x4]]()
            for time in sampleTimes {
                myTransform.append(calculateWorldTransforms(atTime: time))
            }
            worldTransformAnimations = myTransform
        } else {
            worldTransforms = calculateWorldTransforms(atTime: 0)
            worldTransformAnimations = []
        }
        
    }
    
    private func calculateWorldTransforms(atTime time: Double) -> [matrix_float4x4] {
        
        let numParents = parentIndices.count
        var myTransforms = [matrix_float4x4](repeating: matrix_identity_float4x4, count: numParents)
        
        // -- traverse the scene and update the node transforms
        for (tfIdx, parentIndexOptional) in parentIndices.enumerated() {
            let localTransform = getLocalTransform(atTime: time, index: tfIdx)
            if let parentIndex = parentIndexOptional {
                let parentTransform = myTransforms[parentIndex]
                let worldMatrix = simd_mul(parentTransform, localTransform)
                myTransforms[tfIdx] = worldMatrix
                
            } else {
                myTransforms[tfIdx] = localTransform
            }
        }
        
        return myTransforms
        
    }
    
    private func getLocalTransform(atTime time: Double, index tansformIndex: Int) -> matrix_float4x4 {
        var localTransform: matrix_float4x4
        if let localTransformIndice = localTransformAnimationIndices[tansformIndex], let keyFrameIdx = ModelIOTools.lowerBoundKeyframeIndex(sampleTimes, key: time), !localTransformAnimationIndices.isEmpty {
            localTransform = localTransformAnimations[localTransformIndice][keyFrameIdx]
        } else {
            localTransform = localTransforms[tansformIndex]
        }
        
        return localTransform
    }
    
}
