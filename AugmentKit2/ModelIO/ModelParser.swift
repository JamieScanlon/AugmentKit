/*
 ModelParser
 This class parses an MDLAsset suitable to be serialized to disk or to be passed directly to the renderer.
*/

import Foundation
import ModelIO

class ModelParser {
    let jointRootID = "root"

    var nodeNames = [String]()
    var texturePaths = [String]()

    // Transform for a node at a given index
    var localTransforms = [matrix_float4x4]()
    // Combined transform of all the parent nodes of a node at a given index
    var worldTransforms = [matrix_float4x4]()
    var parentIndices = [Int?]()
    var meshNodeIndices = [Int]()
    var meshSkinIndices = [Int?]()
    var instanceCount = [Int]()

    var vertexDescriptors = [MDLVertexDescriptor]()
    var vertexBuffers = [Data]()
    var indexBuffers = [Data]()

    var meshes = [MeshData]()
    var skins = [SkinData]()

    var sampleTimes = [Double]()
    var localTransformAnimations = [[matrix_float4x4]]()
    var worldTransformAnimations = [[matrix_float4x4]]()
    var localTransformAnimationIndices = [Int?]()
    var worldTransformAnimationIndices = [Int?]()

    var skeletonAnimations = [AnimatedSkeleton]()

    init() {}

    init(asset: MDLAsset, vertexDescriptor: MDLVertexDescriptor? = nil) {
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

        for case let submesh as MDLSubmesh in mesh.submeshes! {
            let idxBuffer = submesh.indexBuffer
            indexBuffers.append(Data(bytes: idxBuffer.map().bytes, count: Int(idxBuffer.length)))

            idxCounts.append(Int(submesh.indexCount))
            idxTypes.append(submesh.indexType)

            var material = Material()
            if let mdlMaterial = submesh.material, readMaterialProperty(mdlMaterial, .baseColor, ModelIOTools.getMaterialFloat3Value).uniform != nil {
                material.baseColor = readMaterialProperty(mdlMaterial, .baseColor, ModelIOTools.getMaterialFloat3Value)
                material.metallic = readMaterialProperty(mdlMaterial, .metallic, ModelIOTools.getMaterialFloatValue)
                material.roughness = readMaterialProperty(mdlMaterial, .roughness, ModelIOTools.getMaterialFloatValue)
                (_, material.normalMap) = readMaterialProperty(mdlMaterial, .bump, ModelIOTools.getMaterialFloat3Value)
                (_, material.ambientOcclusionMap) = readMaterialProperty(mdlMaterial, .ambientOcclusion,
                                                                         ModelIOTools.getMaterialFloat3Value)
            }
            materials.append(material)
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
                let sampledLocalTransforms = sampleTimes.map { transform.localTransform!(atTime: $0) }
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

            let skeletonRootPath = ModelIOTools.findShortestPath(in: object.path, containing: jointRootID)
            if skeletonRootPath == object.path {
                let animation = createSkeletonAnimation(for: asset, rootPath: skeletonRootPath!)
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
            } else if let instance = object.instance {
                meshNodeIndices.append(currentIdx)
                instanceMeshIdx.append(ModelIOTools.findMasterIndex(masterMeshes, instance)!)
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
                    let xM = xform.localTransform!(atTime: sampleTimes[timeIndex])
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
                    result.textureIndex = ModelIOTools.findTextureIndex(property.stringValue, &texturePaths)
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
        if !localTransformAnimationIndices.isEmpty,
            let localTransformIndice = localTransformAnimationIndices[tansformIndex] {
            let keyFrameIdx = ModelIOTools.lowerBoundKeyframeIndex(sampleTimes, key: time)!
            localTransform = localTransformAnimations[localTransformIndice][keyFrameIdx]
        } else {
            localTransform = localTransforms[tansformIndex]
        }
        
        return localTransform
    }
    
}
