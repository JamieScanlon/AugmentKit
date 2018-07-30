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
    
    public static func asset(named: String, inBundle bundle: Bundle, allocator: MDLMeshBufferAllocator? = nil) -> MDLAsset? {
        
        guard let fileURL = bundle.url(forResource: named, withExtension: "") else {
            print("WARNING: (MDLAssetTools) Could not find the asset named: \(named)")
            return nil
        }
        
        return MDLAsset(url: fileURL, vertexDescriptor: MetalUtilities.createStandardVertexDescriptor(), bufferAllocator: allocator)
        
    }
    
    //  Creates a horizontal surface in the x-z plane with a material based on a base color texture file.
    //  The aspect ratio of the surface matches the aspect ratio of the base color image and the largest dimemsion
    //  is given by the scale argument (defaults to 1)
    public static func assetFromImage(inBundle bundle: Bundle, withName name: String, extension fileExtension: String = "", scale: Float = 1, allocator: MDLMeshBufferAllocator? = nil) -> MDLAsset? {
        
        let fullFileName: String = {
            if !fileExtension.isEmpty {
                return "\(name).\(fileExtension)"
            } else {
                return name
            }
        }()
        
        return assetFromImage(inBundle: bundle, withBaseColorFileName: fullFileName, specularFileName: nil, emissionFileName: nil, scale: scale, allocator: allocator)
        
    }
    
    //  Creates a horizontal surface in the x-z plane with a material based on base color, specular, and emmision texture files.
    //  The aspect ratio of the surface matches the aspect ratio of the base color image and the largest dimemsion
    //  is given by the scale argument (defaults to 1)
    public static func assetFromImage(inBundle bundle: Bundle, withBaseColorFileName baseColorFileName: String, specularFileName: String? = nil, emissionFileName: String? = nil, scale: Float = 1, allocator: MDLMeshBufferAllocator? = nil) -> MDLAsset? {
        
        guard let baseColorFileURL = bundle.url(forResource: baseColorFileName, withExtension: "") else {
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
            if let specularFileName = specularFileName, let specularFileURL = bundle.url(forResource: specularFileName, withExtension: "") {
                myTextures[MDLMaterialSemantic.specular] = specularFileURL
            }
            if let emissionFileName = emissionFileName, let emissionFileURL = bundle.url(forResource: emissionFileName, withExtension: "") {
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
    
    // Encodes an MDLAsset from ModelID into a MeshGPUData object which is used internally to set up the render pipeline.
    static func meshGPUData(from mdlAsset: MDLAsset, device: MTLDevice, textureBundle: Bundle, vertexDescriptor: MDLVertexDescriptor?) -> MeshGPUData {
        
        let textureLoader = MTKTextureLoader(device: device)
        
        var meshGPUData = MeshGPUData()
        var jointRootID = "root" // FIXME: This is hardcoded to 'root' but it should be dynamic
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
        func store(_ mesh: MDLMesh, vertexDescriptor: MDLVertexDescriptor? = nil) -> DrawData {
            
            var drawData = DrawData()
            
            if let vertexDescriptor = vertexDescriptor {
                mesh.vertexDescriptor = vertexDescriptor
            }
            
            drawData.vbCount = getVertexBufferCount(mesh)
            drawData.vbStartIdx = vertexBuffers.count
            drawData.ibStartIdx = indexBuffers.count
            
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
                        
                        let baseColorProperty = readMaterialProperty(fromAsset: mdlAsset, material: mdlMaterial, semantic: .baseColor, textureLoader: textureLoader, bundle: textureBundle, withPropertyFunction: getMaterialFloat3Value)
                        let metallicProperty = readMaterialProperty(fromAsset: mdlAsset, material: mdlMaterial, semantic: .metallic, textureLoader: textureLoader, bundle: textureBundle, withPropertyFunction: getMaterialFloatValue)
                        let roughnessProperty = readMaterialProperty(fromAsset: mdlAsset, material: mdlMaterial, semantic: .roughness, textureLoader: textureLoader, bundle: textureBundle, withPropertyFunction: getMaterialFloatValue)
                        let ambientOcclusionProperty = readMaterialProperty(fromAsset: mdlAsset, material: mdlMaterial, semantic: .ambientOcclusion, textureLoader: textureLoader, bundle: textureBundle, withPropertyFunction: getMaterialFloatValue)
                        let bumpProperty = readMaterialProperty(fromAsset: mdlAsset, material: mdlMaterial, semantic: .bump, textureLoader: textureLoader, bundle: textureBundle, withPropertyFunction: getMaterialFloat3Value)
                        let emissionProperty = readMaterialProperty(fromAsset: mdlAsset, material: mdlMaterial, semantic: .emission, textureLoader: textureLoader, bundle: textureBundle, withPropertyFunction: getMaterialFloat3Value)
                        let subsurfaceProperty = readMaterialProperty(fromAsset: mdlAsset, material: mdlMaterial, semantic: .subsurface, textureLoader: textureLoader, bundle: textureBundle, withPropertyFunction: getMaterialFloatValue)
                        let specularProperty = readMaterialProperty(fromAsset: mdlAsset, material: mdlMaterial, semantic: .specular, textureLoader: textureLoader, bundle: textureBundle, withPropertyFunction: getMaterialFloatValue)
                        let specularTintProperty = readMaterialProperty(fromAsset: mdlAsset, material: mdlMaterial, semantic: .specularTint, textureLoader: textureLoader, bundle: textureBundle, withPropertyFunction: getMaterialFloatValue)
                        let anisotropicProperty = readMaterialProperty(fromAsset: mdlAsset, material: mdlMaterial, semantic: .anisotropic, textureLoader: textureLoader, bundle: textureBundle, withPropertyFunction: getMaterialFloatValue)
                        let sheenProperty = readMaterialProperty(fromAsset: mdlAsset, material: mdlMaterial, semantic: .sheen, textureLoader: textureLoader, bundle: textureBundle, withPropertyFunction: getMaterialFloatValue)
                        let sheenTintProperty = readMaterialProperty(fromAsset: mdlAsset, material: mdlMaterial, semantic: .sheenTint, textureLoader: textureLoader, bundle: textureBundle, withPropertyFunction: getMaterialFloatValue)
                        let clearcoatProperty = readMaterialProperty(fromAsset: mdlAsset, material: mdlMaterial, semantic: .clearcoat, textureLoader: textureLoader, bundle: textureBundle, withPropertyFunction: getMaterialFloatValue)
                        let clearcoatGlossProperty = readMaterialProperty(fromAsset: mdlAsset, material: mdlMaterial, semantic: .clearcoatGloss, textureLoader: textureLoader, bundle: textureBundle, withPropertyFunction: getMaterialFloatValue)
//                        let opacityProperty = readMaterialProperty(fromAsset: mdlAsset, material: mdlMaterial, semantic: .opacity, textureLoader: textureLoader, bundle: textureBundle, withPropertyFunction: getMaterialFloatValue)
                        
                        // Encode the uniform values
                        let baseColor = baseColorProperty.uniform ?? float3(1.0, 1.0, 1.0)
                        material.baseColor = float4(baseColor.x, baseColor.y, baseColor.z, 1.0)
                        material.metalness = metallicProperty.uniform ?? 0.0
                        material.roughness = roughnessProperty.uniform ?? 1.0
                        material.ambientOcclusion = ambientOcclusionProperty.uniform ?? 1.0
                        material.emissionColor = emissionProperty.uniform ?? float3(0, 0, 0)
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
                        
                        // Encode the texture indexes corresponding to the texture maps. If a property has no texture map this value will be nil
                        subData.baseColorTexture = baseColorProperty.texture
                        subData.metallicTexture = metallicProperty.texture
                        subData.ambientOcclusionTexture = ambientOcclusionProperty.texture
                        subData.roughnessTexture = roughnessProperty.texture
                        subData.normalTexture = bumpProperty.texture
                        subData.emissionTexture = emissionProperty.texture
                        subData.subsurfaceTexture = subsurfaceProperty.texture
                        subData.specularTexture = specularProperty.texture
                        subData.specularTintTexture = specularTintProperty.texture
                        subData.anisotropicTexture = anisotropicProperty.texture
                        subData.sheenTexture = sheenProperty.texture
                        subData.sheenTintTexture = sheenTintProperty.texture
                        subData.clearcoatTexture = clearcoatProperty.texture
                        subData.clearcoatGlossTexture = clearcoatGlossProperty.texture

                    } else {
                        
                        // Default uniforms
                        subData.materialUniforms = MaterialUniforms()
                        
                    }
                    
                    if subData.baseColorTexture != nil {
                        drawData.hasBaseColorMap = true
                    }
                    if subData.normalTexture != nil {
                        drawData.hasNormalMap = true
                    }
                    if subData.ambientOcclusionTexture != nil {
                        drawData.hasAmbientOcclusionMap = true
                    }
                    if subData.roughnessTexture != nil {
                        drawData.hasRoughnessMap = true
                    }
                    if subData.metallicTexture != nil {
                        drawData.hasMetallicMap = true
                    }
                    if subData.emissionTexture != nil {
                        drawData.hasEmissionMap = true
                    }
                    if subData.subsurfaceTexture != nil {
                        drawData.hasSubsurfaceMap = true
                    }
                    if subData.specularTexture != nil {
                        drawData.hasSpecularMap = true
                    }
                    if subData.specularTintTexture != nil {
                        drawData.hasSpecularTintMap = true
                    }
                    if subData.anisotropicTexture != nil {
                        drawData.hasAnisotropicMap = true
                    }
                    if subData.sheenTexture != nil {
                        drawData.hasSheenMap = true
                    }
                    if subData.sheenTintTexture != nil {
                        drawData.hasSheenTintMap = true
                    }
                    if subData.clearcoatTexture != nil {
                        drawData.hasClearcoatMap = true
                    }
                    if subData.clearcoatGlossTexture != nil {
                        drawData.hasClearcoatGlossMap = true
                    }
                    
                    drawData.subData.append(subData)
                    
                }
            }
            
            return drawData
            
        }
        
        // Read a material's property of a particular semantic (e.g. .baseColor),
        // and return tuple of uniform value or texture index
        func readMaterialProperty<T>(fromAsset asset: MDLAsset, material mdlMaterial: MDLMaterial, semantic: MDLMaterialSemantic, textureLoader: MTKTextureLoader, bundle: Bundle, withPropertyFunction getPropertyValue: (MDLMaterialProperty) -> T) -> (uniform: T?, texture: MTLTexture?) {
            var result: (uniform: T?, texture: MTLTexture?) = (nil, nil)
            
            for property in mdlMaterial.properties(with: semantic) {
                switch property.type {
                case .float, .float3:
                    result.uniform = getPropertyValue(property)
                    return result
                case .string, .URL:
                    result.texture = createMTLTexture(fromMaterialProperty: property, asset: asset, inBundle: bundle, withTextureLoader: textureLoader)
                default: break
                }
            }
            return result
        }
        
        // Store skinning information if object has MDLSkinDeformerComponent
        func storeMeshSkin(for object: MDLObject) -> SkinData? {
            guard let skinDeformer = object.componentConforming(to: MDLTransformComponent.self) as? MDLSkeleton else {
                return nil
            }
            
            guard !skinDeformer.jointPaths.isEmpty else {
                return nil
            }
            
            var skin = SkinData()
            // store the joint paths which tell us where the skeleton joints are
            skin.jointPaths = skinDeformer.jointPaths
            // store the joint bind transforms which give us the bind pose
            let jointBindTransforms = skinDeformer.jointBindTransforms
            skin.inverseBindTransforms = jointBindTransforms.float4x4Array.map { simd_inverse($0) }
            return skin
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
                var myTransforms = [[matrix_float4x4]](repeating: [], count: meshNodeIndices.count)
                for time in sampleTimes {
                    let allModelTransformsForTime = calculateWorldTransforms(atTime: time)
                    for meshIndex in 0..<allModelTransformsForTime.count {
                        myTransforms[meshIndex].append(allModelTransformsForTime[meshIndex])
                    }
                }
                worldTransformAnimations = myTransforms
            } else {
                worldTransforms = calculateWorldTransforms(atTime: 0)
                worldTransformAnimations = []
            }
            
        }
        
        func calculateWorldTransforms(atTime time: Double) -> [matrix_float4x4] {
            
            var myTransforms = [matrix_float4x4](repeating: matrix_identity_float4x4, count: meshNodeIndices.count)
            
            for (index, meshIndex) in meshNodeIndices.enumerated() {
                
                let localTransform = getLocalTransform(atTime: time, index: meshIndex)
                let parentTransform: matrix_float4x4 = {
                    var currentIndex = meshIndex
                    var parentIndex = parentIndices[currentIndex]
                    var currentTransform = matrix_identity_float4x4
                    while parentIndex != nil {
                        let aTransform = getLocalTransform(atTime: time, index: parentIndex!)
                        currentTransform = simd_mul(currentTransform, aTransform)
                        currentIndex = parentIndex!
                        parentIndex = parentIndices[currentIndex]
                    }
                    return currentTransform
                }()
                
                let worldMatrix = simd_mul(parentTransform, localTransform)
                myTransforms[index] = worldMatrix
                
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
        
        func createMTLTexture(fromMaterialProperty property: MDLMaterialProperty, asset: MDLAsset, inBundle bundle: Bundle, withTextureLoader textureLoader: MTKTextureLoader) -> MTLTexture? {
            
            if let assetURL = mdlAsset.url, let fileName = property.stringValue, let archive = Archive(url: assetURL, accessMode: .read), let entry = archive[fileName], assetURL.absoluteString.hasSuffix(".usdz") {
                
                let tempUUID = UUID().uuidString
                guard let tempFolder = createTempDirectory(withName: tempUUID) else {
                    return nil
                }
                let tempFileURL = tempFolder.appendingPathComponent(fileName)
                
                do {
                    let _ = try archive.extract(entry, to: tempFileURL)
                } catch {
                    return nil
                }
                
                do {
                    return try textureLoader.newTexture(URL: tempFileURL, options: nil)
                } catch {
                    print("Unable to loader texture for asset \(asset.url?.description ?? "") with error \(error)")
                    //                let newError = AKError.recoverableError(.modelError(.unableToLoadTexture(AssetErrorInfo(path: assetPath, underlyingError: error))))
                    //                recordNewError(newError)
                    return nil
                }
                
            } else {
            
                if let textureSampler = property.textureSamplerValue, let texture = textureSampler.texture {
                    return try? textureLoader.newTexture(texture: texture)
                } else if let path = property.urlValue?.absoluteString {
                    let fixedPath = fixupPath(asset, path: path)
                    return createMTLTexture(inBundle: bundle, fromAssetPath: fixedPath, withTextureLoader: textureLoader)
                } else if let path = property.stringValue {
                    let fixedPath = fixupPath(asset, path: path)
                    return createMTLTexture(inBundle: bundle, fromAssetPath: fixedPath, withTextureLoader: textureLoader)
                } else {
                    return nil
                }
                
            }
            
        }
        
        func createMTLTexture(inBundle bundle: Bundle, fromAssetPath assetPath: String, withTextureLoader textureLoader: MTKTextureLoader) -> MTLTexture? {
            
            let textureURL: URL? = {
                guard let aURL = URL(string: assetPath) else {
                    return nil
                }
                if aURL.scheme == nil {
                    // If there is no scheme, assume it's a file in the bundle.
                    let last = aURL.lastPathComponent
                    if let bundleURL = bundle.url(forResource: last, withExtension: nil) {
                        return bundleURL
                    } else if let bundleURL = bundle.url(forResource: aURL.path, withExtension: nil) {
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
            
            do {
                return try textureLoader.newTexture(URL: aURL, options: nil)
            } catch {
                print("Unable to loader texture with assetPath \(assetPath) with error \(error)")
//                let newError = AKError.recoverableError(.modelError(.unableToLoadTexture(AssetErrorInfo(path: assetPath, underlyingError: error))))
//                recordNewError(newError)
            }
            
            return nil
        }
        
        func createTempDirectory(withName name: String) -> URL? {
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print(error)
                return nil
            }
            return url
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
            meshGPUData.drawData.append(store(mesh, vertexDescriptor: vertexDescriptor))
            masterMeshes.append(mesh)
        }
        
        var instanceMeshIdx = [Int]()
        walkSceneGraph(in: mdlAsset) { object, currentIdx, parentIdx in
            
            if let mesh = object as? MDLMesh {
                meshNodeIndices.append(currentIdx)
                var drawData = store(mesh, vertexDescriptor: vertexDescriptor)
                if let skin = storeMeshSkin(for: object) {
                    skins.append(skin)
                    drawData.skins.append(skin)
                    drawData.skeletonAnimations.append(AnimatedSkeleton()) // FIXME: Parse the skeleton animation
                    meshSkinIndices.append(skins.count - 1)
                } else {
                    meshSkinIndices.append(nil)
                }
                meshGPUData.drawData.append(drawData)
                instanceMeshIdx.append(meshGPUData.drawData.count - 1)
            } else if let instance = object.instance, let masterIndex = ModelIOTools.findMasterIndex(masterMeshes, instance) {
                meshNodeIndices.append(currentIdx)
                instanceMeshIdx.append(masterIndex)
                if let skin = storeMeshSkin(for: object) {
                    skins.append(skin)
                    var drawData = meshGPUData.drawData[masterIndex]
                    drawData.skins.append(skin)
                    drawData.skeletonAnimations.append(AnimatedSkeleton()) // FIXME: Parse the skeleton animation
                    meshSkinIndices.append(skins.count - 1)
                } else {
                    meshSkinIndices.append(nil)
                }
            }
            
            flattenNode(object, nodeIndex: currentIdx, parentNodeIndex: parentIdx)
            
            // TODO: This skeleleton animation stuff needs more work. It is in a non-fuctional state right now
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
            guard let boundSkeletonRoot = findShortestPath(in: skin.jointPaths[0], containing: jointRootID) else {
                continue
            }
            
            guard let skeletonIndex = skeletons.index(of: boundSkeletonRoot) else {
                continue
            }
            
            skins[skinIndex].skinToSkeletonMap = ModelIOTools.mapJoints(from: skin, to: skeletonAnimations[skeletonIndex])
            skins[skinIndex].animationIndex = skeletonIndex
        }
        
        updateWorldTransforms()
        
        // Attach world transform to the DrawData object
        for (nodeIndex, transform) in worldTransforms.enumerated() {
            meshGPUData.drawData[nodeIndex].worldTransform = transform
        }
        for (nodeIndex, transforms) in worldTransformAnimations.enumerated() {
            meshGPUData.drawData[nodeIndex].worldTransformAnimations = transforms
        }
        
        // Create Vertex Buffers
        for vtxBuffer in vertexBuffers {
            vtxBuffer.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) in
                guard let aVTXBuffer = device.makeBuffer(bytes: bytes, length: vtxBuffer.count, options: .storageModeShared) else {
                    fatalError("Failed to create a buffer from the device.")
                }
                meshGPUData.vertexBuffers.append(aVTXBuffer)
            }
            
        }
        
        // Vertex Descriptors
        meshGPUData.vertexDescriptors = vertexDescriptors
        
        // Create Index Buffers
        for idxBuffer in indexBuffers {
            idxBuffer.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) in
                guard let aIDXBuffer = device.makeBuffer(bytes: bytes, length: idxBuffer.count, options: .storageModeShared) else {
                    fatalError("Failed to create a buffer from the device.")
                }
                meshGPUData.indexBuffers.append(aIDXBuffer)
            }
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
    
    static func fixupPath(_ asset: MDLAsset, path: String) -> String {
        guard let assetURL = asset.url else {
            return path
        }
        let assetRelativeURL = assetURL.deletingLastPathComponent()
        return assetRelativeURL.appendingPathComponent(path).absoluteString
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
