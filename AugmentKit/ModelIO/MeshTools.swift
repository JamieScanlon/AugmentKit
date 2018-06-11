//
//  ModelIOTools.swift
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
//  Contains utility functions for importing and exporting models
//

import UIKit
import MetalKit
import ModelIO
import AugmentKitShader

// MARK: - MDLAsset extesntions

extension MDLAsset {
    
    //  Pretty-print MDLAsset's scene graph
    public func printAsset() {
        func printSubgraph(object: MDLObject, indent: Int = 0) {
            print(String(repeating: " ", count: indent), object.name, object)

            for childIndex in 0..<object.children.count {
                printSubgraph(object: object.children[childIndex], indent: indent + 2)
            }
        }

        for childIndex in 0..<self.count {
            printSubgraph(object: self.object(at: childIndex))
        }
    }

    //  Find an MDLObject by its path from MDLAsset level
    func objectAtPath(_ path: String) -> MDLObject? {
        // pathArray[] is always ""
        let pathArray = path.components(separatedBy: "/")
        guard !pathArray.isEmpty else {
            return nil
        }

        for childIndex in 0..<self.count {
            guard let child = self[childIndex] else {
                continue
            }

            // since pathArray[0] == "" we ignore it and grab the substring if
            // the path count is greater than 2 otherwise return the child itself
            if child.name == pathArray[1] {
                if pathArray.count > 2 {
                    let startIndex = path.index(pathArray[1].endIndex, offsetBy: 3)
                    return child.atPath(String(path[startIndex...]))
                } else {
                    return child
                }
            }
        }

        return nil
    }
}

// MARK: - MDLAssetTools

//  Tools for creating ModelIO objects
public class MDLAssetTools {
    
    //  Creates a horizontal surface in the x-z plane with a material based on a base color texture file.
    //  The aspect ratio of the surface matches the aspect ratio of the base color image and the largest dimemsion
    //  is given by the scale argument (defaults to 1)
    public static func assetFromImage(withName name: String, extension fileExtension: String = "", scale: Float = 1, allocator: MDLMeshBufferAllocator? = nil) -> MDLAsset? {
        
        let fullFileName: String = {
            if !fileExtension.isEmpty {
                return "\(name).\(fileExtension)"
            } else {
                return name
            }
        }()
        
        return assetFromImage(withBaseColorFileName: fullFileName, specularFileName: nil, emissionFileName: nil, scale: scale, allocator: allocator)
        
    }
    
    //  Creates a horizontal surface in the x-z plane with a material based on base color, specular, and emmision texture files.
    //  The aspect ratio of the surface matches the aspect ratio of the base color image and the largest dimemsion
    //  is given by the scale argument (defaults to 1)
    public static func assetFromImage(withBaseColorFileName baseColorFileName: String, specularFileName: String? = nil, emissionFileName: String? = nil, scale: Float = 1, allocator: MDLMeshBufferAllocator? = nil) -> MDLAsset? {
        
        guard let baseColorFileURL = Bundle(for: MDLAssetTools.self).url(forResource: baseColorFileName, withExtension: "") else {
            print("WARNING: (MDLAssetTools) Could not find the image asset with file name: \(baseColorFileName)")
            return nil
        }
        
        let aspectRatio: Float = {
            if let image = UIImage(contentsOfFile: baseColorFileURL.path) {
                return Float(image.size.width / image.size.height)
            } else {
                return 1
            }
        }()
        let extent: vector_float3 = {
            if aspectRatio > 1 {
                return vector3(scale, 0, scale/aspectRatio)
            } else if aspectRatio < 1 {
                return vector3(aspectRatio, 0, scale)
            } else {
                return vector3(scale, 0, scale)
            }
        }()
        
        let mesh = MDLMesh(planeWithExtent: extent, segments: vector2(1, 1), geometryType: .triangles, allocator: allocator)
        let scatteringFunction = MDLScatteringFunction()
        let material = MDLMaterial(name: "baseMaterial", scatteringFunction: scatteringFunction)
        
        let textues: [MDLMaterialSemantic: URL] = {
            var myTextures = [MDLMaterialSemantic.baseColor: baseColorFileURL]
            if let specularFileName = specularFileName, let specularFileURL = Bundle(for: MDLAssetTools.self).url(forResource: specularFileName, withExtension: "") {
                myTextures[MDLMaterialSemantic.specular] = specularFileURL
            }
            if let emissionFileName = emissionFileName, let emissionFileURL = Bundle(for: MDLAssetTools.self).url(forResource: emissionFileName, withExtension: "") {
                myTextures[MDLMaterialSemantic.emission] = emissionFileURL
            }
            return myTextures
        }()
        
        setTextureProperties(material: material, textures: textues)
        
        for submesh in mesh.submeshes!  {
            if let submesh = submesh as? MDLSubmesh {
                submesh.material = material
            }
        }
        let asset = MDLAsset(bufferAllocator: allocator)
        asset.add(mesh)
        
        return asset
        
    }
    
    public static func setTextureProperties(material: MDLMaterial, textures: [MDLMaterialSemantic: URL]) {
        for (key, url) in textures {
            let value = url.lastPathComponent
            let property = MDLMaterialProperty(name:value, semantic: key, url: url)
            material.setProperty(property)
        }
    }
    
}

// MARK: - JointPathRemappable

//  Protocol for remapping joint paths (e.g. between a skeleton's complete joint list
//  and the the subset bound to a particular mesh)
protocol JointPathRemappable {
    var jointPaths: [String] { get }
}

// MARK: - ModelIOTools

//  Tools for parsing ModelIO objects
class ModelIOTools {
    
    // MARK: Encoding Mesh Data
    
    static func meshGPUData(from mdlAsset: MDLAsset, vertexDescriptor: MDLVertexDescriptor, device: MTLDevice) -> MeshGPUData {
        
        var meshGPUData = MeshGPUData()
        var jointRootID = "root"
        var texturePaths = [String]()
        var sampleTimes = [Double]()
        var localTransformAnimations = [[matrix_float4x4]]()
        var worldTransformAnimations = [[matrix_float4x4]]()
        var localTransformAnimationIndices = [Int?]()
        var worldTransformAnimationIndices = [Int?]()
        // Vertex descriptors for all of the meshes stored in the MDLAsset
        var vertexDescriptors = [MTLVertexDescriptor]()
        var vertexBuffers = [Data]()
        var indexBuffers = [Data]()
        var meshNodeIndices = [Int]()
        var meshSkinIndices = [Int?]()
        var skins = [SkinData]()
        var instanceCount = [Int]()
        var parentIndices = [Int?]()
        var skeletonAnimations = [AnimatedSkeleton]()// Transform for a node at a given index
        var localTransforms = [matrix_float4x4]()
        // Combined transform of all the parent nodes of a node at a given index
        var worldTransforms = [matrix_float4x4]()
        
        // Record all buffers and materials for an MDLMesh
        func store(_ mesh: MDLMesh, vertexDescriptor: MDLVertexDescriptor? = nil) {
            
            var drawData = DrawData()
            
            if let vertexDescriptor = vertexDescriptor {
                mesh.vertexDescriptor = vertexDescriptor
            }
            
            drawData.vbCount = getVertexBufferCount(mesh)
            drawData.vbStartIdx = vertexBuffers.count
            drawData.ibStartIdx = indexBuffers.count
            
            var materials = [MaterialUniforms]()
            if let mtlVertexDescriptor = MTKMetalVertexDescriptorFromModelIO(mesh.vertexDescriptor) {
                vertexDescriptors.append(mtlVertexDescriptor)
            }
            
            vertexBuffers += (0..<drawData.vbCount).map { vertexBufferIndex in
                let vertexBuffer = mesh.vertexBuffers[vertexBufferIndex]
                return Data(bytes: vertexBuffer.map().bytes, count: Int(vertexBuffer.length))
            }
            
            if let submeshes = mesh.submeshes {
                
                for case let submesh as MDLSubmesh in submeshes {
                    
                    var subData = DrawSubData()
                    
                    let idxBuffer = submesh.indexBuffer
                    indexBuffers.append(Data(bytes: idxBuffer.map().bytes, count: Int(idxBuffer.length)))
                    
                    subData.idxCount = submesh.indexCount
                    subData.idxType = MetalUtilities.convertToMTLIndexType(from: submesh.indexType)
                    
                    var material = MaterialUniforms()
                    if let mdlMaterial = submesh.material {
                        
                        let baseColorProperty = readMaterialProperty(from: mdlMaterial, semantic: .baseColor, withPropertyFunction: getMaterialFloat3Value)
                        let metallicProperty = readMaterialProperty(from: mdlMaterial, semantic: .metallic, withPropertyFunction: getMaterialFloatValue)
                        let roughnessProperty = readMaterialProperty(from: mdlMaterial, semantic: .roughness, withPropertyFunction: getMaterialFloatValue)
                        let ambientOcclusionProperty = readMaterialProperty(from: mdlMaterial, semantic: .ambientOcclusion, withPropertyFunction: getMaterialFloatValue)
                        let bumpProperty = readMaterialProperty(from: mdlMaterial, semantic: .bump, withPropertyFunction: getMaterialFloat3Value)
                        let emissionProperty = readMaterialProperty(from: mdlMaterial, semantic: .emission, withPropertyFunction: getMaterialFloat3Value)
                        let subsurfaceProperty = readMaterialProperty(from: mdlMaterial, semantic: .subsurface, withPropertyFunction: getMaterialFloatValue)
                        let specularProperty = readMaterialProperty(from: mdlMaterial, semantic: .specular, withPropertyFunction: getMaterialFloatValue)
                        let specularTintProperty = readMaterialProperty(from: mdlMaterial, semantic: .specularTint, withPropertyFunction: getMaterialFloatValue)
                        let anisotropicProperty = readMaterialProperty(from: mdlMaterial, semantic: .anisotropic, withPropertyFunction: getMaterialFloatValue)
                        let sheenProperty = readMaterialProperty(from: mdlMaterial, semantic: .sheen, withPropertyFunction: getMaterialFloatValue)
                        let sheenTintProperty = readMaterialProperty(from: mdlMaterial, semantic: .sheenTint, withPropertyFunction: getMaterialFloatValue)
                        let clearcoatProperty = readMaterialProperty(from: mdlMaterial, semantic: .clearcoat, withPropertyFunction: getMaterialFloatValue)
                        let clearcoatGlossProperty = readMaterialProperty(from: mdlMaterial, semantic: .clearcoatGloss, withPropertyFunction: getMaterialFloatValue)
                        let opacityProperty = readMaterialProperty(from: mdlMaterial, semantic: .opacity, withPropertyFunction: getMaterialFloatValue)
                        
                        let baseColor = baseColorProperty.uniform ?? float3(1.0, 1.0, 1.0)
                        material.baseColor = float4(baseColor.x, baseColor.y, baseColor.z, 1.0)
                        material.metalness = metallicProperty.uniform ?? 0.0
                        material.roughness = roughnessProperty.uniform ?? 1.0
                        material.ambientOcclusion = ambientOcclusionProperty.uniform ?? 1.0
                        material.irradiatedColor = emissionProperty.uniform ?? float3(1.0, 1.0, 1.0)
                        material.subsurface = subsurfaceProperty.uniform ?? 0.0
                        material.specular = specularProperty.uniform ?? 0.0
                        material.specularTint = specularTintProperty.uniform ?? 0.0
                        material.anisotropic = anisotropicProperty.uniform ?? 0.0
                        material.sheen = sheenProperty.uniform ?? 0.0
                        material.sheenTint = sheenTintProperty.uniform ?? 0.0
                        material.clearcoat = clearcoatProperty.uniform ?? 0.0
                        material.clearcoatGloss = clearcoatGlossProperty.uniform ?? 0.0
//                        material.opacity = opacityProperty.uniform ?? 1.0
                        material.opacity = 1.0
                        
                        subData.materialUniforms = material
                        
                        subData.baseColorTextureIndex = baseColorProperty.textureIndex
                        subData.metallicTextureIndex = metallicProperty.textureIndex
                        subData.normalTextureIndex = bumpProperty.textureIndex
                        subData.ambientOcclusionTextureIndex = ambientOcclusionProperty.textureIndex
                        subData.roughnessTextureIndex = roughnessProperty.textureIndex
                        subData.irradianceTextureIndex = emissionProperty.textureIndex
                        subData.subsurfaceTextureIndex = subsurfaceProperty.textureIndex
                        subData.specularTextureIndex = specularProperty.textureIndex
                        subData.specularTintTextureIndex = specularTintProperty.textureIndex
                        subData.anisotropicTextureIndex = anisotropicProperty.textureIndex
                        subData.sheenTextureIndex = sheenProperty.textureIndex
                        subData.sheenTintTextureIndex = sheenTintProperty.textureIndex
                        subData.clearcoatTextureIndex = clearcoatProperty.textureIndex
                        subData.clearcoatGlossTextureIndex = clearcoatGlossProperty.textureIndex

                    } else {
                        
                        subData.baseColorTextureIndex = nil
                        subData.normalTextureIndex = nil
                        subData.ambientOcclusionTextureIndex = nil
                        subData.roughnessTextureIndex = nil
                        subData.metallicTextureIndex = nil
                        subData.irradianceTextureIndex = nil
                        subData.subsurfaceTextureIndex = nil
                        subData.specularTextureIndex = nil
                        subData.specularTintTextureIndex = nil
                        subData.anisotropicTextureIndex = nil
                        subData.sheenTextureIndex = nil
                        subData.sheenTintTextureIndex = nil
                        subData.clearcoatTextureIndex = nil
                        subData.clearcoatGlossTextureIndex = nil
                        
                        subData.materialUniforms = MaterialUniforms()
                        
                    }
                    
                    // TODO: subData.materialBuffer
//                    MetalUtilities.convertMaterialBuffer(from: meshData.materials[subIndex], with: materialUniformBuffer, offset: materialUniformBufferOffset)
                    
                    drawData.subData.append(subData)
                    
                    materials.append(material)
                }
            }
            
            meshGPUData.drawData.append(drawData)
            
        }
        
        // Read a material's property of a particular semantic (e.g. .baseColor),
        // and return tuple of uniform value or texture index
        func readMaterialProperty<T>(from mdlMaterial: MDLMaterial, semantic: MDLMaterialSemantic, withPropertyFunction getPropertyValue: (MDLMaterialProperty) -> T) -> (uniform: T?, textureIndex: Int?) {
            var result: (uniform: T?, textureIndex: Int?) = (nil, nil)
            
            for property in mdlMaterial.properties(with: semantic) {
                switch property.type {
                case .float, .float3:
                    result.uniform = getPropertyValue(property)
                    return result
                case .string, .URL:
                    if let path = property.urlValue?.absoluteString {
                        if let index = texturePaths.index(of: path) {
                            result.textureIndex = index
                        } else {
                            let index = texturePaths.count
                            texturePaths.append(path)
                            result.textureIndex = index
                        }
                    } else if let path = property.stringValue {
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
        
        // Store skinning information if object has MDLSkinDeformerComponent
        func storeMeshSkin(for object: MDLObject) -> Bool {
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
        
        // Record a node's parent index and store its local transform
        func flattenNode(_ nodeObject: MDLObject, nodeIndex: Int, parentNodeIndex: Int?) {
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
        
        // Construct a SkeletonAnimation by time-sampling all joint transforms
        func createSkeletonAnimation(for asset: MDLAsset, rootPath: String) -> AnimatedSkeleton {
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
        
        func updateWorldTransforms() {
            
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
        
        func calculateWorldTransforms(atTime time: Double) -> [matrix_float4x4] {
            
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
        
        func getLocalTransform(atTime time: Double, index tansformIndex: Int) -> matrix_float4x4 {
            var localTransform: matrix_float4x4
            if let localTransformIndice = localTransformAnimationIndices[tansformIndex], let keyFrameIdx = ModelIOTools.lowerBoundKeyframeIndex(sampleTimes, key: time), !localTransformAnimationIndices.isEmpty {
                localTransform = localTransformAnimations[localTransformIndice][keyFrameIdx]
            } else {
                localTransform = localTransforms[tansformIndex]
            }
            
            return localTransform
        }
        
        func createMTLTexture(fromAssetPath assetPath: String, withTextureLoader textureLoader: MTKTextureLoader?) -> MTLTexture? {
            do {
                
                let textureURL: URL? = {
                    guard let aURL = URL(string: assetPath) else {
                        return nil
                    }
                    if aURL.scheme == nil {
                        // If there is no scheme, assume it's a file in the bundle.
                        let last = aURL.lastPathComponent
                        if let bundleURL = Bundle(for: Renderer.self).url(forResource: last, withExtension: nil) {
                            return bundleURL
                        } else if let bundleURL = Bundle(for: Renderer.self).url(forResource: aURL.path, withExtension: nil) {
                            return bundleURL
                        } else {
                            return aURL
                        }
                    } else {
                        return aURL
                    }
                }()
                
                guard let aURL = textureURL else {
                    return nil
                }
                
                return try textureLoader?.newTexture(URL: aURL, options: nil)
                
            } catch {
                print("Unable to loader texture with assetPath \(assetPath) with error \(error)")
//                let newError = AKError.recoverableError(.modelError(.unableToLoadTexture(AssetErrorInfo(path: assetPath, underlyingError: error))))
//                recordNewError(newError)
            }
            
            return nil
        }
        
        //
        // Animation frame times @ 60fps
        //
        
        sampleTimes = sampleTimeInterval(start: mdlAsset.startTime, end: mdlAsset.endTime, frameInterval: 1.0 / 60.0)
        
        //
        // Parse and store the mesh data
        //
        
        var masterMeshes: [MDLMesh] = []
        walkMasters(in: mdlAsset) { object in
            guard let mesh = object as? MDLMesh else { return }
            store(mesh, vertexDescriptor: vertexDescriptor)
            masterMeshes.append(mesh)
        }
        var instanceMeshIdx = [Int]()
        walkSceneGraph(in: mdlAsset) { object, currentIdx, parentIdx in
            if let mesh = object as? MDLMesh {
                meshNodeIndices.append(currentIdx)
                store(mesh, vertexDescriptor: vertexDescriptor)
                instanceMeshIdx.append(meshGPUData.drawData.count - 1)
                let hasSkin = storeMeshSkin(for: object)
                meshSkinIndices.append(hasSkin ? skins.count - 1 : nil)
            } else if let instance = object.instance, let masterIndex = ModelIOTools.findMasterIndex(masterMeshes, instance) {
                meshNodeIndices.append(currentIdx)
                instanceMeshIdx.append(masterIndex)
                let hasSkin = storeMeshSkin(for: object)
                meshSkinIndices.append(hasSkin ? skins.count - 1 : nil)
            }
            flattenNode(object, nodeIndex: currentIdx, parentNodeIndex: parentIdx)
            if let skeletonRootPath = findShortestPath(in: object.path, containing: jointRootID), skeletonRootPath == object.path {
                let animation = createSkeletonAnimation(for: mdlAsset, rootPath: skeletonRootPath)
                skeletonAnimations.append(animation)
            }
        }
        
        let (permutation, instCount) = sortedMeshIndexPermutation(instanceMeshIdx)
        meshNodeIndices = permutation.map { meshNodeIndices[$0] }
        meshSkinIndices = permutation.map { meshSkinIndices[$0] }
        instanceCount = instCount
        
        // Map the joint indices bound to a mesh to the list of all joint indices of a skeleton
        let skeletons: [String] = skeletonAnimations.compactMap {
            if $0.jointPaths.count > 0 {
                return $0.jointPaths[0]
            } else {
                return nil
            }
        }
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
        
        fixupPaths(mdlAsset, &texturePaths)
        updateWorldTransforms()
        
        // Create Vertex Buffers
        for vtxBuffer in vertexBuffers {
            vtxBuffer.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) in
                guard let aVTXBuffer = device.makeBuffer(bytes: bytes, length: vtxBuffer.count, options: .storageModeShared) else {
                    fatalError("Failed to create a buffer from the device.")
                }
                meshGPUData.vtxBuffers.append(aVTXBuffer)
            }
            
        }
        
        // Create Index Buffers
        for idxBuffer in indexBuffers {
            idxBuffer.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) in
                guard let aIDXBuffer = device.makeBuffer(bytes: bytes, length: idxBuffer.count, options: .storageModeShared) else {
                    fatalError("Failed to create a buffer from the device.")
                }
                meshGPUData.indexBuffers.append(aIDXBuffer)
            }
        }
        
        // Create Texture Buffers
        let textureLoader = MTKTextureLoader(device: device)
        for texturePath in texturePaths {
            meshGPUData.textures.append(createMTLTexture(fromAssetPath: texturePath, withTextureLoader: textureLoader))
        }
        
        return meshGPUData
        
    }

    //  Compute an index map from all elements of A.jointPaths to the corresponding paths in B.jointPaths
    static func mapJoints<A: JointPathRemappable, B: JointPathRemappable>(from src: A, to dst: B) -> [Int] {
        let dstJointPaths = dst.jointPaths
        return src.jointPaths.compactMap { srcJointPath in
            if let index = dstJointPaths.index(of: srcJointPath) {
                return index
            }
            print("Warning! animated joint \(srcJointPath) does not exist in skeleton")
            return nil
        }
    }

    //  Count the element count of the subgraph rooted at object.
    static func subGraphCount(_ object: MDLObject) -> Int {
        var elementCount: Int = 1 // counting us ...
        let childCount = object.children.count
        for childIndex in 0..<childCount {
             //... and subtree count of each child
            elementCount += subGraphCount(object.children[childIndex])
        }
        return elementCount
    }

    //  Traverse an MDLAsset's scene graph and run a closure on each element,
    //  passing on each element's flattened node index as well as its parent's index
    static func walkSceneGraph(in asset: MDLAsset, perNodeBody: (MDLObject, Int, Int?) -> Void) {
        func walkGraph(in object: MDLObject, currentIndex: inout Int, parentIndex: Int?, perNodeBody: (MDLObject, Int, Int?) -> Void) {
            perNodeBody(object, currentIndex, parentIndex)

            let ourIndex = currentIndex
            currentIndex += 1
            for childIndex in 0..<object.children.count {
                walkGraph(
                    in: object.children[childIndex],
                    currentIndex: &currentIndex,
                    parentIndex: ourIndex,
                    perNodeBody: perNodeBody
                )
            }
        }

        var currentIndex = 0
        for childIndex in 0..<asset.count {
            walkGraph(in: asset.object(at: childIndex), currentIndex: &currentIndex, parentIndex: nil, perNodeBody: perNodeBody)
        }
    }

    //  Traverse thescene graph rooted at object and run a closure on each element,
    //  passing on each element's flattened node index as well as its parent's index
    static func walkSceneGraph(rootAt object: MDLObject, perNodeBody: (MDLObject, Int, Int?) -> Void) {
        var currentIndex = 0

        func walkGraph(object: MDLObject, currentIndex: inout Int, parentIndex: Int?, perNodeBody: (MDLObject, Int, Int?) -> Void) {
            perNodeBody(object, currentIndex, parentIndex)

            let ourIndex = currentIndex
            currentIndex += 1
            for childIndex in 0..<object.children.count {
                walkGraph(
                    object: object.children[childIndex],
                    currentIndex: &currentIndex,
                    parentIndex: ourIndex,
                    perNodeBody: perNodeBody
                )
            }
        }

        walkGraph(object: object, currentIndex: &currentIndex, parentIndex: nil, perNodeBody: perNodeBody)
    }

    //  Traverse an MDLAsset's masters list and run a closure on each element.
    //  Model I/O supports instancing. These are the master objects that the instances refer to.
    static func walkMasters(in asset: MDLAsset, perNodeBody: (MDLObject) -> Void) {
        func walkGraph(in object: MDLObject, perNodeBody: (MDLObject) -> Void) {
            perNodeBody(object)

            for childIndex in 0..<object.children.count {
                walkGraph(in: object.children[childIndex], perNodeBody: perNodeBody)
            }
        }

        for childIndex in 0..<asset.masters.count {
            walkGraph(in: asset.masters[childIndex], perNodeBody: perNodeBody)
        }
    }

    //  Return the number of active vertex buffers in an MDLMesh
    static func getVertexBufferCount(_ mdlMesh: MDLMesh) -> Int {
        var vbCount = 0
        for layout in mdlMesh.vertexDescriptor.layouts {
            if let stride = (layout as? MDLVertexBufferLayout)?.stride {
                if stride == 0 {
                    return vbCount
                }
                vbCount += 1
            }
        }
        return vbCount
    }

    //  Find the index of the (first) MDLMesh in MDLAsset.masters that an MDLObject.instance points to
    static func findMasterIndex(_ masterMeshes: [MDLMesh], _ instance: MDLObject) -> Int? {
        
        //  find first MDLMesh in MDLObject hierarchy
        func findFirstMesh(_ object: MDLObject) -> MDLMesh? {
            if let object = object as? MDLMesh {
                return object
            }
            for childIndex in 0..<object.children.count {
                return findFirstMesh(object.children[childIndex])
            }
            return nil
        }

        if let mesh = findFirstMesh(instance) {
            return masterMeshes.index(of: mesh)
        }

        return nil
    }

    //  Sort all mesh instances by mesh index, and return a permutation which groups together
    //  all instances of all particular mesh
    static func sortedMeshIndexPermutation(_ instanceMeshIndices: [Int]) -> ([Int], [Int]) {
        let permutation = (0..<instanceMeshIndices.count).sorted { instanceMeshIndices[$0] < instanceMeshIndices[$1] }

        var instanceCounts: [Int] = {
            if let max = instanceMeshIndices.max() {
                return [Int](repeating: 0, count: max + 1)
            } else {
                return []
            }
        }()
        for instanceMeshIndex in instanceMeshIndices {
            instanceCounts[instanceMeshIndex] += 1
        }

        return (permutation, instanceCounts)
    }

    //  Append the asset url to all texture paths
    static func fixupPaths(_ asset: MDLAsset, _ texturePaths: inout [String]) {
        guard let assetURL = asset.url else { return }

        let assetRelativeURL = assetURL.deletingLastPathComponent()
        texturePaths = texturePaths.map { assetRelativeURL.appendingPathComponent($0).absoluteString }
    }

    //  Find the shortest subpath containing a rootIdentifier (used to find a e.g. skeleton's root path)
    static func findShortestPath(in path: String, containing rootIdentifier: String) -> String? {
        var result = ""
        let pathArray = path.components(separatedBy: "/")
        for name in pathArray {
            result += name
            if name.range(of: rootIdentifier) != nil {
                return result
            }
            result += "/"
        }
        return nil
    }

    //  Get a float3 property from an MDLMaterialProperty
    static func getMaterialFloat3Value(_ materialProperty: MDLMaterialProperty) -> float3 {
        return materialProperty.float3Value
    }

    //  Get a float property from an MDLMaterialProperty
    static func getMaterialFloatValue(_ materialProperty: MDLMaterialProperty) -> Float {
        return materialProperty.floatValue
    }

    //  Uniformly sample a time interval
    static func sampleTimeInterval(start startTime: TimeInterval, end endTime: TimeInterval,
                            frameInterval: TimeInterval) -> [TimeInterval] {
        let count = Int( (endTime - startTime) / frameInterval )
        return (0..<count).map { startTime + TimeInterval($0) * frameInterval }
    }
    
    //  Find the largest index of time stamp <= key
    static func lowerBoundKeyframeIndex(_ lhs: [Double], key: Double) -> Int? {
        guard let lhsFirst = lhs.first else {
            return nil
        }
        
        guard let lhsLast = lhs.last else {
            return nil
        }
        
        if key < lhsFirst { return 0 }
        if key > lhsLast { return lhs.count - 1 }
        
        var range = 0..<lhs.count
        
        while range.endIndex - range.startIndex > 1 {
            let midIndex = range.startIndex + (range.endIndex - range.startIndex) / 2
            
            if lhs[midIndex] == key {
                return midIndex
            } else if lhs[midIndex] < key {
                range = midIndex..<range.endIndex
            } else {
                range = range.startIndex..<midIndex
            }
        }
        return range.startIndex
    }

}
