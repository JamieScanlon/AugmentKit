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

    /**
     Find an MDLObject by its path from MDLAsset level
     - Parameters:
        - _: the path
     - Returns: and `MDLObject` if found
     */
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

/**
 Tools for creating ModelIO's `MDLAsset` objects
 */
public class MDLAssetTools {
    /**
     Creates an `MDLAsset` object from a `ModelIO` compatable model file. The method looks for a file with the specified name in the specified bundle and uses the specified `MTKMeshBufferAllocator` to create the `MDLAsset`.
     - Parameters:
        - named: The specified name of the file
        - inBundle: The `Bundle` where the asset can be found
        - allocator: A `MTKMeshBufferAllocator` that will be used to create the `MDLAsset`
     - Returns: A new `MDLAsset`
     */
    public static func asset(named: String, inBundle bundle: Bundle, allocator: MTKMeshBufferAllocator? = nil) -> MDLAsset? {
        
        guard let fileURL = bundle.url(forResource: named, withExtension: "") else {
            print("WARNING: (MDLAssetTools) Could not find the asset named: \(named)")
            return nil
        }
        
        return MDLAsset(url: fileURL, vertexDescriptor: RenderUtilities.createStandardVertexDescriptor(), bufferAllocator: allocator)
        
    }
    
    /**
     Creates a horizontal surface in the x-z plane with a material based on a base color image texture file. The aspect ratio of the surface matches the aspect ratio of the base color image and the largest dimemsion is given by the scale argument (defaults to 1)
     - Parameters:
        - inBundle: The `Bundle` where the asset can be found
        - withName: The specified name of the image file
        - extension: The image file's extension
        - scale: The scale at which to render the image, 1 represinting 1 meter
        - allocator: A `MTKMeshBufferAllocator` that will be used to create the `MDLAsset`
     - Returns: A new `MDLAsset`
     */
    public static func assetFromImage(inBundle bundle: Bundle, withName name: String, extension fileExtension: String = "", scale: Float = 1, allocator: MTKMeshBufferAllocator? = nil) -> MDLAsset? {
        
        let fullFileName: String = {
            if !fileExtension.isEmpty {
                return "\(name).\(fileExtension)"
            } else {
                return name
            }
        }()
        
        return assetFromImage(inBundle: bundle, withBaseColorFileName: fullFileName, specularFileName: nil, emissionFileName: nil, scale: scale, allocator: allocator)
        
    }
    
    /**
     Creates a horizontal surface in the x-z plane with a material based on base color, specular, and emmision image texture files.  The aspect ratio of the surface matches the aspect ratio of the base color image and the largest dimemsion is given by the scale argument (defaults to 1)
     - Parameters:
        - inBundle: The `Bundle` where the asset can be found
        - withBaseColorFileName: The specified name of the base color image texture file
        - specularFileName: The specified name of the specular image texture file
        - emissionFileName: The specified name of the emission image texture file
        - scale: The scale at which to render the image, 1 represinting 1 meter
        - allocator: A `MTKMeshBufferAllocator` that will be used to create the `MDLAsset`
     - Returns: A new `MDLAsset`
     */
    public static func assetFromImage(inBundle bundle: Bundle, withBaseColorFileName baseColorFileName: String, specularFileName: String? = nil, emissionFileName: String? = nil, scale: Float = 1, allocator: MTKMeshBufferAllocator? = nil) -> MDLAsset? {
        
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
    /**
     Sets texture properties on a provided `MDLMaterial`
     - Parameters:
        - material: a `MDLMaterial` to modify.
        - textures: a dictionary of dectures where the keys are the `MDLMaterialSemantic` and the value is a `URL` to the texture file.
     */
    public static func setTextureProperties(material: MDLMaterial, textures: [MDLMaterialSemantic: URL]) {
        for (key, url) in textures {
            let value = url.lastPathComponent
            let property = MDLMaterialProperty(name:value, semantic: key, url: url)
            material.setProperty(property)
        }
    }
    
}

// MARK: - JointPathRemappable

/**
 Protocol for remapping joint paths (e.g. between a skeleton's complete joint list and the the subset bound to a particular mesh)
 */
protocol JointPathRemappable {
    var jointPaths: [String] { get }
}

// MARK: - ModelIOTools

/**
 Tools for parsing ModelIO objects
 */
class ModelIOTools {
    
    // MARK: Encoding Mesh Data
    
    // Encodes an MDLAsset from ModelIO into a MeshGPUData object which is used internally to set up the render pipeline.
    static func meshGPUData(from asset: MDLAsset, device: MTLDevice, textureBundle: Bundle, vertexDescriptor: MDLVertexDescriptor?, frameRate: Double = 60, shaderPreference: ShaderPreference = .pbr) -> MeshGPUData {
        
        // see: https://github.com/metal-by-example/modelio-materials
        
        let textureLoader = MTKTextureLoader(device: device)
        var meshGPUData = MeshGPUData()
        var parentWorldTransformsByIndex = [Int: matrix_float4x4]()
        var parentWorldAnimationTransformsByIndex = [Int: [matrix_float4x4]]()
        
        // Vertex Descriptor that will be used by the render pipeline. If none was provided
        // a standard one is created which is a Vertiex Descriptor compatible with AnchorShaders.metal
        let concreteVertexDescriptor: MDLVertexDescriptor = {
            if let vertexDescriptor = vertexDescriptor {
                return vertexDescriptor
            } else {
                return RenderUtilities.createStandardVertexDescriptor()
            }
        }()
        
        // The loadTextures() method iterates all of the materials in the asset and, if
        // they are strings or URLs, loads their associated image data. The material
        // property will then report its type as `.texture` and will have an `MDLTextureSampler`
        // object as its `textureSamplerValue` property.
        asset.loadTextures()
        
        // Find the root meshes
        for sourceMesh in asset.childObjects(of: MDLMesh.self) as! [MDLMesh] {
            
            // Calculate tangent information
            sourceMesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate, normalAttributeNamed: MDLVertexAttributeNormal, tangentAttributeNamed: MDLVertexAttributeTangent)
            
            // Set the Vertex Descriptor
            sourceMesh.vertexDescriptor = concreteVertexDescriptor
            
        }
        
        //
        // Animation frame times @ 60fps
        //
        
        let sampleTimes = sampleTimeInterval(start: asset.startTime, end: asset.endTime, frameInterval: 1.0 / frameRate)
        let hasAnimation = sampleTimes.count > 0
        
        //
        // Parse and store the mesh data
        //
        
        var masterMeshes: [MDLMesh] = []
        var masterDrawDatas: [DrawData] = []
        walkMasters(in: asset) { object in
            
            guard let mesh = object as? MDLMesh else {
                return
            }
            
            // Calculate tangent information
            mesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate, normalAttributeNamed: MDLVertexAttributeNormal, tangentAttributeNamed: MDLVertexAttributeTangent)
            
            // Set the Vertex Descriptor
            mesh.vertexDescriptor = concreteVertexDescriptor
            
            let drawData = store(mesh, from: asset, device: device, textureBundle: textureBundle, textureLoader: textureLoader, vertexDescriptor: vertexDescriptor)
            masterDrawDatas.append(drawData)
            masterMeshes.append(mesh)
            
        }
        
        var skinIndex = 0
        
        walkSceneGraph(in: asset) { object, currentIndex, parentIndex in
            
            //
            // Calculate Skeleton Animations
            //
            
            let skeletonAnimation: AnimatedSkeleton? = {
                // TODO: This skeleleton animation stuff needs more work. It is in a non-fuctional state right now
                let jointRootID = "root" // FIXME: This is hardcoded to 'root' but it should be dynamic
                if let skeletonRootPath = findShortestPath(in: object.path, containing: jointRootID), skeletonRootPath == object.path {
                    return createSkeletonAnimation(for: asset, rootPath: skeletonRootPath, sampleTimes: sampleTimes)
                } else {
                    return nil
                }
            }()
            
            //
            // Calculate the World Transform / World Transform Animations for each node
            //
            
            if hasAnimation {
                
                // Get the local transform for this node
                let myLocalTransformAnimations: [matrix_float4x4] = {
                    if let transform = object.transform {
                        if transform.keyTimes.count > 1 {
                            return sampleTimes.map { transform.localTransform?(atTime: $0) ?? matrix_identity_float4x4 }
                        } else {
                            return [matrix_float4x4](repeating: matrix_identity_float4x4, count: sampleTimes.count)
                        }
                    } else {
                        return [matrix_float4x4](repeating: matrix_identity_float4x4, count: sampleTimes.count)
                    }
                }()
                
                // Get the world transform for this node
                let myWorldTransformAnimations: [matrix_float4x4] = {
                    if let parentIndex = parentIndex, let parentAnimationTransforms = parentWorldAnimationTransformsByIndex[parentIndex] {
                        // If this node has a parent, calculate the world transform by multiplying the parent world transform and the local transform
                        let myTransformAnimations: [matrix_float4x4] = (0..<min(parentAnimationTransforms.count, myLocalTransformAnimations.count)).map { index in
                            let parentTransformAtIndex = parentAnimationTransforms[index]
                            let localTransformAtIndex = myLocalTransformAnimations[index]
                            return parentTransformAtIndex * localTransformAtIndex
                        }
                        return myTransformAnimations
                    } else {
                        // If this node has no parent, the world transform is the local transform
                        return myLocalTransformAnimations
                    }
                }()
                
                parentWorldAnimationTransformsByIndex[currentIndex] = myWorldTransformAnimations
                
            } else {
                
                // Get the local transform for this node
                let myLocalTransform: matrix_float4x4 = {
                    if let transform = object.transform, !transform.matrix.isZero() {
                        return transform.matrix
                    } else {
                        return matrix_identity_float4x4
                    }
                }()
                
                // Get the local transform for this node
                let myWorldTransform: matrix_float4x4 = {
                    if let parentIndex = parentIndex, let parentTransform = parentWorldTransformsByIndex[parentIndex] {
                        // If this node has a parent, calculate the world transform by multiplying the parent world transform and the local transform
                        return parentTransform * myLocalTransform
                    } else {
                        // If this node has no parent, the world transform is the local transform
                        return myLocalTransform
                    }
                }()
                
                parentWorldTransformsByIndex[currentIndex] = myWorldTransform
                
            }
            
            //
            // Create DrawData Objects for each MDLMesh found
            //
            
            if let mesh = object as? MDLMesh {
                
                // Calculate tangent information
                mesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate, normalAttributeNamed: MDLVertexAttributeNormal, tangentAttributeNamed: MDLVertexAttributeTangent)
                
                // Set the Vertex Descriptor
                mesh.vertexDescriptor = concreteVertexDescriptor
                
                // Create a new DrawData object from the mesh
                var drawData = store(mesh, from: asset, device: device, textureBundle: textureBundle, textureLoader: textureLoader, vertexDescriptor: vertexDescriptor)
                
                // Update the skin properties
                if let skin = storeMeshSkin(for: object) {
                    var mutableSkin = skin
                    if let skeletonAnimation = skeletonAnimation {
                        mutableSkin.skinToSkeletonMap = ModelIOTools.mapJoints(from: skin, to: skeletonAnimation)
                        mutableSkin.animationIndex = skinIndex
                        drawData.skeletonAnimations.append(skeletonAnimation)
                    }
                    drawData.skins.append(mutableSkin)
                    skinIndex += 1
                }
                
                // Update the World Transforms (calculated previously)
                if hasAnimation {
                    drawData.worldTransformAnimations = parentWorldAnimationTransformsByIndex[currentIndex] ?? []
                } else {
                    drawData.worldTransform = parentWorldTransformsByIndex[currentIndex] ?? matrix_identity_float4x4
                }
                
                // Add the new DrawData object to meshGPUData
                meshGPUData.drawData.append(drawData)
                
            } else if let instance = object.instance, let masterIndex = findMasterIndex(masterMeshes, instance) {
                
                // Get a copy of the DrawData object from the array of master DrawData objects
                var drawData = masterDrawDatas[masterIndex]
                
                // Update the skin properties
                if let skin = storeMeshSkin(for: object) {
                    var mutableSkin = skin
                    if let skeletonAnimation = skeletonAnimation {
                        mutableSkin.skinToSkeletonMap = ModelIOTools.mapJoints(from: skin, to: skeletonAnimation)
                        mutableSkin.animationIndex = skinIndex
                        drawData.skeletonAnimations.append(skeletonAnimation)
                    }
                    drawData.skins.append(skin)
                    
                }
                
                // Update the World Transforms (calculated previously)
                if hasAnimation {
                    drawData.worldTransformAnimations = parentWorldAnimationTransformsByIndex[currentIndex] ?? []
                } else {
                    drawData.worldTransform = parentWorldTransformsByIndex[currentIndex] ?? matrix_identity_float4x4
                }
                
                // Add the new DrawData object to meshGPUData
                meshGPUData.drawData.append(drawData)
                
            }
            
            
        }
        
        // Update the Vertex Descriptor
        if let vertexDescriptor = vertexDescriptor, let mtlVertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vertexDescriptor) {
            meshGPUData.vertexDescriptor = mtlVertexDescriptor
        }
        
        // Shader preference
        meshGPUData.shaderPreference = shaderPreference
        
        return meshGPUData
        
    }
    
    // MARK: - Private
    
    private struct TransformsInfo {
        var transforms = [matrix_float4x4]()
        var transformAnimations = [[matrix_float4x4]]()
        var transformAnimationIndices = [Int?]()
        mutating func combine(with: TransformsInfo) {
            transforms.append(contentsOf: with.transforms)
            transformAnimations.append(contentsOf: with.transformAnimations)
            transformAnimationIndices.append(contentsOf: with.transformAnimationIndices)
        }
    }
    
    // Record all buffers and materials for an MDLMesh
    private static func store(_ mesh: MDLMesh, from mdlAsset: MDLAsset, device: MTLDevice, textureBundle: Bundle, textureLoader: MTKTextureLoader, vertexDescriptor: MDLVertexDescriptor? = nil) -> DrawData {
        
        var drawData = DrawData()
        
        if let vertexDescriptor = vertexDescriptor {
            mesh.vertexDescriptor = vertexDescriptor
        }
        
        var vertexBuffers = [Data]()
        
        vertexBuffers = mesh.vertexBuffers.map { vertexBuffer in
            return Data(bytes: vertexBuffer.map().bytes, count: Int(vertexBuffer.length))
        }
        
        if let submeshes = mesh.submeshes {
            
            for case let submesh as MDLSubmesh in submeshes {
                
                var subData = DrawSubData()
                
                if let indexBuffer = submesh.indexBuffer as? MTKMeshBuffer {
                    subData.indexBuffer = indexBuffer.buffer
                } else {
                    guard let aIDXBuffer = device.makeBuffer(bytes: submesh.indexBuffer.map().bytes, length: submesh.indexBuffer.length, options: .storageModeShared) else {
                        fatalError("Failed to create a buffer from the device.")
                    }
                    subData.indexBuffer = aIDXBuffer
                }
                
                
                subData.indexCount = submesh.indexCount
                subData.indexType = RenderUtilities.convertToMTLIndexType(from: submesh.indexType)
                
                var material = MaterialUniforms()
                if let mdlMaterial = submesh.material {
                    
                    let baseColorProperty = readMaterialProperty(fromAsset: mdlAsset, material: mdlMaterial, semantic: .baseColor, textureLoader: textureLoader, bundle: textureBundle, withPropertyFunction: getMaterialFloat4Value)
                    let metallicProperty = readMaterialProperty(fromAsset: mdlAsset, material: mdlMaterial, semantic: .metallic, textureLoader: textureLoader, bundle: textureBundle, withPropertyFunction: getMaterialFloatValue)
                    let roughnessProperty = readMaterialProperty(fromAsset: mdlAsset, material: mdlMaterial, semantic: .roughness, textureLoader: textureLoader, bundle: textureBundle, withPropertyFunction: getMaterialFloatValue)
                    let ambientOcclusionProperty = readMaterialProperty(fromAsset: mdlAsset, material: mdlMaterial, semantic: .ambientOcclusion, textureLoader: textureLoader, bundle: textureBundle, withPropertyFunction: getMaterialFloatValue)
                    let normalProperty = readMaterialProperty(fromAsset: mdlAsset, material: mdlMaterial, semantic: .tangentSpaceNormal, textureLoader: textureLoader, bundle: textureBundle, withPropertyFunction: getMaterialFloat3Value)
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
                    material.baseColor = baseColorProperty.uniform ?? float4(1.0, 1.0, 1.0, 1.0)
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
                    subData.normalTexture = normalProperty.texture
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
        
        // Create Vertex Buffers
        for vtxBuffer in vertexBuffers {
            vtxBuffer.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) in
                guard let aVTXBuffer = device.makeBuffer(bytes: bytes, length: vtxBuffer.count, options: .storageModeShared) else {
                    fatalError("Failed to create a buffer from the device.")
                }
                drawData.vertexBuffers.append(aVTXBuffer)
            }
            
        }
        
        return drawData
        
    }
    
    // Store skinning information if object has MDLSkinDeformerComponent
    private static func storeMeshSkin(for object: MDLObject) -> SkinData? {
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
    
    // Read a material's property of a particular semantic (e.g. .baseColor),
    // and return tuple of uniform value or texture index
    private static func readMaterialProperty<T>(fromAsset asset: MDLAsset, material mdlMaterial: MDLMaterial, semantic: MDLMaterialSemantic, textureLoader: MTKTextureLoader, bundle: Bundle, withPropertyFunction getPropertyValue: (MDLMaterialProperty) -> T) -> (uniform: T?, texture: MTLTexture?) {
        var result: (uniform: T?, texture: MTLTexture?) = (nil, nil)
        
        //for property in mdlMaterial.properties(with: semantic) {
        if let property = mdlMaterial.property(with: semantic) {
            if let sourceTexture = property.textureSamplerValue?.texture {
                let wantMips = property.semantic != .tangentSpaceNormal
                let options: [MTKTextureLoader.Option : Any] = [ .generateMipmaps : wantMips ]
                do {
                    result.texture = try textureLoader.newTexture(texture: sourceTexture, options: options)
                } catch {
                    print(error)
                }
            } else {
                switch property.type {
                case .float, .float3, .float4:
                    result.uniform = getPropertyValue(property)
                    return result
                case .string, .URL:
                    result.texture = createMTLTexture(fromMaterialProperty: property, asset: asset, inBundle: bundle, withTextureLoader: textureLoader)
                default: break
                }
            }
        }
        return result
    }
    
    private static func createMTLTexture(fromMaterialProperty property: MDLMaterialProperty, asset: MDLAsset, inBundle bundle: Bundle, withTextureLoader textureLoader: MTKTextureLoader) -> MTLTexture? {
            
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
    
    private static func createMTLTexture(inBundle bundle: Bundle, fromAssetPath assetPath: String, withTextureLoader textureLoader: MTKTextureLoader) -> MTLTexture? {
        
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

    //  Compute an index map from all elements of A.jointPaths to the corresponding paths in B.jointPaths
    private static func mapJoints<A: JointPathRemappable, B: JointPathRemappable>(from src: A, to dst: B) -> [Int] {
        let dstJointPaths = dst.jointPaths
        return src.jointPaths.compactMap { srcJointPath in
            if let index = dstJointPaths.firstIndex(of: srcJointPath) {
                return index
            }
            print("Warning! animated joint \(srcJointPath) does not exist in skeleton")
            return nil
        }
    }
    
    // Construct a SkeletonAnimation by time-sampling all joint transforms
    private static func createSkeletonAnimation(for asset: MDLAsset, rootPath: String, sampleTimes: [TimeInterval]) -> AnimatedSkeleton {
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

    //  Count the element count of the subgraph rooted at object.
    private static func subGraphCount(_ object: MDLObject) -> Int {
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
    private static func walkSceneGraph(in asset: MDLAsset, perNodeBody: (MDLObject, Int, Int?) -> Void) {
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
    private static func walkSceneGraph(rootAt object: MDLObject, perNodeBody: (MDLObject, Int, Int?) -> Void) {
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
    private static func walkMasters(in asset: MDLAsset, perNodeBody: (MDLObject) -> Void) {
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

    //  Find the index of the (first) MDLMesh in MDLAsset.masters that an MDLObject.instance points to
    private static func findMasterIndex(_ masterMeshes: [MDLMesh], _ instance: MDLObject) -> Int? {
        
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
            return masterMeshes.firstIndex(of: mesh)
        }

        return nil
    }
    
    private static func fixupPath(_ asset: MDLAsset, path: String) -> String {
        guard let assetURL = asset.url else {
            return path
        }
        let assetRelativeURL = assetURL.deletingLastPathComponent()
        return assetRelativeURL.appendingPathComponent(path).absoluteString
    }

    //  Find the shortest subpath containing a rootIdentifier (used to find a e.g. skeleton's root path)
    private static func findShortestPath(in path: String, containing rootIdentifier: String) -> String? {
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
    
    //  Get a float4 property from an MDLMaterialProperty
    private static func getMaterialFloat4Value(_ materialProperty: MDLMaterialProperty) -> float4 {
        return materialProperty.float4Value
    }

    //  Get a float3 property from an MDLMaterialProperty
    private static func getMaterialFloat3Value(_ materialProperty: MDLMaterialProperty) -> float3 {
        return materialProperty.float3Value
    }

    //  Get a float property from an MDLMaterialProperty
    private static func getMaterialFloatValue(_ materialProperty: MDLMaterialProperty) -> Float {
        return materialProperty.floatValue
    }

    //  Uniformly sample a time interval
    private static func sampleTimeInterval(start startTime: TimeInterval, end endTime: TimeInterval,
                            frameInterval: TimeInterval) -> [TimeInterval] {
        let count = Int( (endTime - startTime) / frameInterval )
        return (0..<count).map { startTime + TimeInterval($0) * frameInterval }
    }

}
