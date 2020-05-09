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

import ARKit
import UIKit
import MetalKit
import ModelIO
import AugmentKitShader

// MARK: - MDLAsset extesntions

extension MDLAsset {
    
    /// Exports the `MDLAsset` to the given path as a USDZ file.
    /// - Parameter url: A url to the final file location. The file must have a `.usdz` file extension
    /// - Returns: `true` if successful, `false` otherwise
    @discardableResult
    public func exportAsUSDZ(to url: URL) -> Bool {
        
        guard url.isFileURL else {
            return false
        }
        
        guard !FileManager.default.fileExists(atPath: url.path), url.pathExtension == "usdz" else {
            return false
        }

        // NOTE: At the time this was written, USDZ export is not supported.
        if MDLAsset.canExportFileExtension("usdz") {
            do {
                try export(to: url)
            } catch {
                return false
            }
            return true
        } else if MDLAsset.canExportFileExtension("usdc") {
            let tempURL = url.deletingPathExtension().appendingPathExtension("usdc")
            do {
                try export(to: tempURL)
                try FileManager.default.moveItem(at: tempURL, to: url)
            } catch {
                return false
            }
            return true
        }
        return false
    }
}

// MARK: - MDLAssetTools

/**
 Tools for creating ModelIO's `MDLAsset` objects
 */
open class MDLAssetTools {
    
    /**
     Creates an `MDLAsset` object from a `ModelIO` compatable model file. The method loads a file at the given URL and uses the specified `MTKMeshBufferAllocator` to create the `MDLAsset`.
     - Parameters:
        - url: The `URL` of the model file
        - allocator: A `MTKMeshBufferAllocator` that will be used to create the `MDLAsset`
     - Returns: A new `MDLAsset`
     */
    public static func asset(url: URL, allocator: MTKMeshBufferAllocator? = nil) -> MDLAsset? {
        return MDLAsset(url: url, vertexDescriptor: RenderUtilities.createStandardVertexDescriptor(), bufferAllocator: allocator)
    }
    
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
        let extent: SIMD3<Float> = {
            if aspectRatio > 1 {
                return SIMD3<Float>(scale, 0, scale/aspectRatio)
            } else if aspectRatio < 1 {
                return SIMD3<Float>(aspectRatio, 0, scale)
            } else {
                return SIMD3<Float>(scale, 0, scale)
            }
        }()
        
        let mesh = MDLMesh(planeWithExtent: extent, segments: SIMD2<UInt32>(1, 1), geometryType: .triangles, allocator: allocator)
        let scatteringFunction = MDLScatteringFunction()
        let material = MDLMaterial(name: "\(baseColorFileName) baseMaterial", scatteringFunction: scatteringFunction)
        
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
    
    /// Encodes an MDLAsset from ModelIO into a MeshGPUData object which is used internally to set up the render pipeline.
    static func meshGPUData(from asset: MDLAsset, device: MTLDevice, vertexDescriptor: MDLVertexDescriptor?, frameRate: Double = 60, shaderPreference: ShaderPreference = .pbr, loadTextures: Bool = true, textureBundle: Bundle? = nil) -> MeshGPUData {
        
        // see: https://github.com/metal-by-example/modelio-materials
        
        let textureLoader: MTKTextureLoader? = {
            if loadTextures {
                return MTKTextureLoader(device: device)
            } else {
                return nil
            }
        }()
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
//        for sourceMesh in asset.childObjects(of: MDLMesh.self) as! [MDLMesh] {
//
//            // Calculate tangent information
////            sourceMesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate, normalAttributeNamed: MDLVertexAttributeNormal, tangentAttributeNamed: MDLVertexAttributeTangent)
//
//            // Set the Vertex Descriptor
//            sourceMesh.vertexDescriptor = concreteVertexDescriptor
//
//        }
        
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
//            mesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate, normalAttributeNamed: MDLVertexAttributeNormal, tangentAttributeNamed: MDLVertexAttributeTangent)
            
            // Set the Vertex Descriptor
            mesh.vertexDescriptor = concreteVertexDescriptor
            
            let drawData = store(mesh, device: device, textureBundle: textureBundle, textureLoader: textureLoader, vertexDescriptor: vertexDescriptor, baseURL: asset.url?.deletingLastPathComponent())
            masterDrawDatas.append(drawData)
            masterMeshes.append(mesh)
            
        }
        
        //
        // Find and parse skeleton animations
        // Only One MDLSkeleton is supported. If there are multiple, the firs will be used and the others ignored.
        //
        
        let baseSkeleton: SkeletonData? = createSkeleton(from: asset)
        
        walkSceneGraph(in: asset) { object, currentIndex, parentIndex in
            
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
                            return [matrix_float4x4](repeating: transform.matrix, count: sampleTimes.count)
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
//                mesh.addTangentBasis(forTextureCoordinateAttributeNamed: MDLVertexAttributeTextureCoordinate, normalAttributeNamed: MDLVertexAttributeNormal, tangentAttributeNamed: MDLVertexAttributeTangent)
                
                // Set the Vertex Descriptor
                mesh.vertexDescriptor = concreteVertexDescriptor
                
                // Create a new DrawData object from the mesh
                var drawData = store(mesh, device: device, textureBundle: textureBundle, textureLoader: textureLoader, vertexDescriptor: vertexDescriptor, baseURL: asset.url?.deletingLastPathComponent())
                
                // Update the skeleton property with any animation
                drawData.skeleton = skeletonDataAnimation(from: baseSkeleton, for: object, keyTimes: sampleTimes)
                drawData.paletteStartIndex = 0
                drawData.paletteSize = drawData.skeleton?.jointCount ?? 0
                
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
                
                // Update the skeleton property with any animation
                drawData.skeleton = skeletonDataAnimation(from: baseSkeleton, for: object, keyTimes: sampleTimes)
                
                // Update the World Transforms (calculated previously)
                if hasAnimation {
                    drawData.worldTransformAnimations = parentWorldAnimationTransformsByIndex[currentIndex] ?? []
                    print()
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
    
    /// Gererates `RawVertexBuffer` uniforms given raw vertex data.
    /// - Parameter vertices: An array of verticies
    /// - Parameter textureCoordinates: An array of texture coordinates
    /// - Parameter device: The Metal device
    /// - Returns: A new buffer contining an array of `RawVertexBuffer` structs which can be used in the `rawGeometryVertexTransform` shader
    static func rawVertexBuffer(from vertices: [SIMD3<Float>], textureCoordinates: [SIMD2<Float>], device: MTLDevice) -> MTLBuffer? {
        
        let rawVerticiesSize = vertices.count * MemoryLayout<RawVertexBuffer>.size
        var rawVerticies = [RawVertexBuffer]()
        for index in 0..<vertices.count {
            let positions = vertices[index]
            let texCoord = textureCoordinates[index]
            rawVerticies.append(RawVertexBuffer(position: positions, texCoord: texCoord, normal: SIMD3<Float>(0, 0, 0), tangent: SIMD3<Float>(0, 0, 0)))
        }
        
        guard let vertexBuffer = device.makeBuffer(bytes: &rawVerticies, length: rawVerticiesSize, options: []) else {
            return nil
        }
        return vertexBuffer
    }
    
    /// Generated index buffer data from a raw array of indexes.
    /// - Parameter indices: An array of vertex indices
    /// - Parameter device: The Metal device
    static func indexBuffer(from indices: [Int16], device: MTLDevice) -> MTLBuffer? {
        let indexDataSize = indices.count * MemoryLayout<Int16>.size
        let indexBuffer = device.makeBuffer(bytes: indices, length: indexDataSize, options: [])
        return indexBuffer
    }
    
    /// Creates a `MeshGPUData` object from raw vertiex data and the material provided. The grometry will be givent the `ShaderPreference.simple` shader preference
    /// - Parameter vertices: An array of verticies
    /// - Parameter indices: An array of vertex indices
    /// - Parameter textureCoordinates: An array of texture coordinates
    /// - Parameter device: The Metal device
    /// - Parameter material: The material that will be applied to the geometry
    /// - Parameter textureBundle: The texture bundle that will be used to load any asssets in the material
    static func meshGPUData(from vertices: [SIMD3<Float>], indices: [Int16], textureCoordinates: [SIMD2<Float>], device: MTLDevice, material: MDLMaterial? = nil, textureBundle: Bundle? = nil) -> MeshGPUData {
        
        let textureLoader = MTKTextureLoader(device: device)
        var meshGPUData = MeshGPUData()
        var drawData = DrawData()
        var submesh = DrawSubData()
        
        submesh.indexBuffer = indexBuffer(from: indices, device: device)
        submesh.indexCount = indices.count
        if let material = material {
            submesh.updateMaterialTextures(from: material, textureBundle: textureBundle, textureLoader: textureLoader)
        }
        
        let verticesSize = vertices.count * MemoryLayout<SIMD3<Float>>.size
        let verticiesBuffer = device.makeBuffer(bytes: vertices, length: verticesSize, options: [])!
        
        let textureCoordinatesSize = textureCoordinates.count * MemoryLayout<SIMD2<Float>>.size
        let textureCoordinatesBuffer = device.makeBuffer(bytes: textureCoordinates, length: textureCoordinatesSize, options: [])!
        
        drawData.vertexBuffers = [verticiesBuffer, textureCoordinatesBuffer]
        if let aRawVertexBuffer = rawVertexBuffer(from: vertices, textureCoordinates: textureCoordinates, device: device) {
            drawData.rawVertexBuffers = [aRawVertexBuffer]
        } else {
            drawData.rawVertexBuffers = []
        }
        drawData.subData = [submesh]
        
        if submesh.baseColorTexture != nil {
            drawData.hasBaseColorMap = true
        }
        if submesh.normalTexture != nil, AKCapabilities.NormalMap {
            drawData.hasNormalMap = true
        }
        if submesh.ambientOcclusionTexture != nil, AKCapabilities.AmbientOcclusionMap {
            drawData.hasAmbientOcclusionMap = true
        }
        if submesh.roughnessTexture != nil, AKCapabilities.RoughnessMap {
            drawData.hasRoughnessMap = true
        }
        if submesh.metallicTexture != nil, AKCapabilities.MetallicMap {
            drawData.hasMetallicMap = true
        }
        if submesh.emissionTexture != nil, AKCapabilities.EmissionMap {
            drawData.hasEmissionMap = true
        }
        if submesh.subsurfaceTexture != nil, AKCapabilities.SubsurfaceMap {
            drawData.hasSubsurfaceMap = true
        }
        if submesh.specularTexture != nil, AKCapabilities.SpecularMap {
            drawData.hasSpecularMap = true
        }
        if submesh.specularTintTexture != nil, AKCapabilities.SpecularTintMap {
            drawData.hasSpecularTintMap = true
        }
        if submesh.anisotropicTexture != nil, AKCapabilities.AnisotropicMap {
            drawData.hasAnisotropicMap = true
        }
        if submesh.sheenTexture != nil, AKCapabilities.SheenMap {
            drawData.hasSheenMap = true
        }
        if submesh.sheenTintTexture != nil, AKCapabilities.SheenTintMap {
            drawData.hasSheenTintMap = true
        }
        if submesh.clearcoatTexture != nil, AKCapabilities.ClearcoatMap {
            drawData.hasClearcoatMap = true
        }
        if submesh.clearcoatGlossTexture != nil, AKCapabilities.ClearcoatGlossMap {
            drawData.hasClearcoatGlossMap = true
        }
        
        meshGPUData.drawData = [drawData]
        meshGPUData.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(RenderUtilities.createStandardVertexDescriptor())
        meshGPUData.shaderPreference = .simple
        
        return meshGPUData
        
    }
    
    /// Takes an `MDLMaterial` object and returns a `MaterialProperties` object. The object may come from cache.
    /// - Parameter material: The `MDLMaterial` objet to parse
    /// - Parameter textureLoader: Used to load textures when found. if nil, uniform values will be used instead of textures.
    /// - Parameter bundle: If a relatice URL to an asset is encountered, it is assumed to be an asset within this bundle.
    /// - Parameter baseURL: If provided, all texture asset path will be assumed to be relative to this base url. This may be used id the material is part of an `MDLAsset` within an bundle. Generally the texture asset patch will be relative to the asset but in order to find the asset, we need to know where the asset is. In this case the `baseURL` would be the `URL` of the folder that contains the `MDLAsset`
    static func materialProperties(from material: MDLMaterial, textureLoader: MTKTextureLoader? = nil, bundle: Bundle? = nil, baseURL: URL? = nil, meshIdentifier: String = "") -> MaterialProperties {
        
        let meshCacheKey = meshIdentifier + material.name
        
        if let cachedProperties = MaterialCache.shared.cachedMaterial(with: meshCacheKey), textureLoader != nil, bundle != nil {
            // Only attempt to load from cache materials with textures.
            return cachedProperties
        }
        
        var allProperties = [MDLMaterialSemantic: (uniform: Any?, texture: MTLTexture?)]()
        
        // Parse all material properties
        for childIndex in 0..<material.count {
            guard let property = material[childIndex] else {
                continue
            }
            
            let propertyValue = readMaterialPropertyValue(from: property, textureLoader: textureLoader, bundle: bundle, baseURL: baseURL)
            
            // There is an existing value for this semantic. Choose one that is the best fit
            
            let existingIsTexture: Bool = {
                if allProperties[property.semantic]?.texture != nil {
                    return true
                } else {
                    return false
                }
            }()
            let newIsTexture: Bool = {
                if propertyValue?.texture != nil {
                    return true
                } else {
                    return false
                }
            }()
            
            // Rule 1: Always chooce a texture over a uniform
            if newIsTexture && !existingIsTexture {
                allProperties[property.semantic] = propertyValue
            } else if !newIsTexture && existingIsTexture {
                continue
            } else {
                
                // Rule 2: The last matching semantic wins
                switch property.semantic {
                case .baseColor:
                    if property.type == .color {
                        let newValue = propertyValue?.uniform as! CGColor
                        if newValue.numberOfComponents == 3, let companents = newValue.components {
                            allProperties[property.semantic] = (SIMD4<Float>(Float(companents[0]), Float(companents[1]), Float(companents[2]), 1), nil)
                        } else if newValue.numberOfComponents == 4, let companents = newValue.components {
                            allProperties[property.semantic] = (SIMD4<Float>(Float(companents[0]), Float(companents[1]), Float(companents[2]), Float(companents[3])), nil)
                        }
                    } else if let _ = propertyValue?.uniform as? SIMD4<Float> {
                        allProperties[property.semantic] = propertyValue
                    } else if let newValue = propertyValue?.uniform as? SIMD3<Float> {
                        allProperties[property.semantic] = (SIMD4<Float>(newValue.x, newValue.y, newValue.z, 1), nil)
                    }
                case .emission:
                    // Workaround for other properties like "ambientColor" getting (incorrectly) tagged with the .emission semantic
                    guard property.name == "emission" else {
                        break
                    }
                    if property.type == .color {
                        let newValue = propertyValue?.uniform as! CGColor
                        if newValue.numberOfComponents == 3, let companents = newValue.components {
                            allProperties[property.semantic] = (SIMD4<Float>(Float(companents[0]), Float(companents[1]), Float(companents[2]), 1), nil)
                        } else if newValue.numberOfComponents == 4, let companents = newValue.components {
                            allProperties[property.semantic] = (SIMD4<Float>(Float(companents[0]), Float(companents[1]), Float(companents[2]), Float(companents[3])), nil)
                        }
                    } else if let _ = propertyValue?.uniform as? SIMD4<Float> {
                        allProperties[property.semantic] = propertyValue
                    } else if let newValue = propertyValue?.uniform as? SIMD3<Float> {
                        allProperties[property.semantic] = (SIMD4<Float>(newValue.x, newValue.y, newValue.z, 1), nil)
                    }
                case .subsurface:
                    fallthrough
                case .metallic:
                    fallthrough
                case .specular:
                    fallthrough
                case .specularExponent:
                    fallthrough
                case .specularTint:
                    fallthrough
                case .roughness:
                    fallthrough
                case .anisotropic:
                    fallthrough
                case .anisotropicRotation:
                    fallthrough
                case .sheen:
                    fallthrough
                case .sheenTint:
                    fallthrough
                case .clearcoat:
                    fallthrough
                case .bump:
                    fallthrough
                case .clearcoatGloss:
                    fallthrough
                case .opacity:
                    fallthrough
                case .interfaceIndexOfRefraction:
                    fallthrough
                case .displacementScale:
                    fallthrough
                case .ambientOcclusionScale:
                    fallthrough
                case .materialIndexOfRefraction:
                    if let _ = propertyValue?.uniform as? Float {
                        allProperties[property.semantic] = propertyValue
                    } else if let float3Value = propertyValue?.uniform as? SIMD3<Float> {
                        let aveValue = (float3Value.x + float3Value.y + float3Value.z) / 3
                        allProperties[property.semantic] = (aveValue, nil)
                    } else if let float4Value = propertyValue?.uniform as? SIMD4<Float> {
                        let aveValue = (float4Value.x + float4Value.y + float4Value.z + float4Value.w) / 4
                        allProperties[property.semantic] = (aveValue, nil)
                    }
                case .objectSpaceNormal:
                    fallthrough
                case .tangentSpaceNormal:
                    fallthrough
                case .displacement:
                    if let _ = propertyValue?.uniform as? SIMD3<Float> {
                        allProperties[property.semantic] = propertyValue
                    } else if let float4Value = propertyValue?.uniform as? SIMD4<Float> {
                        allProperties[property.semantic] = (float4Value.xyz, nil)
                    } else if let floatValue = propertyValue?.uniform as? Float {
                        allProperties[property.semantic] = (SIMD3<Float>(repeating: floatValue), nil)
                    }
                case .ambientOcclusion:
                    // Ambient Occlusion only makes sense as a texture map. Ignore any constant uniform values
                    allProperties[property.semantic] = (Float(1), nil)
                case .userDefined:
                    fallthrough
                case .none:
                    fallthrough
                @unknown default:
                    break
                }
            }
        }
        
        let materialProperties = MaterialProperties(name: material.name, properties: allProperties)
        if textureLoader != nil, bundle != nil {
            // Only cace materials with textures
            MaterialCache.shared.cacheMaterial(materialProperties, for: meshCacheKey)
        }
        return materialProperties
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
    
    /// Record all buffers and materials for an MDLMesh
    private static func store(_ mesh: MDLMesh, device: MTLDevice, textureBundle: Bundle? = nil, textureLoader: MTKTextureLoader? = nil, vertexDescriptor: MDLVertexDescriptor? = nil, baseURL: URL? = nil) -> DrawData {
        
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
                
                if let mdlMaterial = submesh.material {
                    
                    var material = MaterialUniforms()
                    
                    let myMaterialProperties = materialProperties(from: mdlMaterial, textureLoader: textureLoader, bundle: textureBundle, baseURL: baseURL, meshIdentifier: mesh.name)
                    let allProperties = myMaterialProperties.properties
                    
                    // Encode the texture indexes corresponding to the texture maps. If a property has no texture map this value will be nil
                    subData.baseColorTexture = allProperties[.baseColor]?.texture
                    subData.metallicTexture = allProperties[.metallic]?.texture
                    subData.ambientOcclusionTexture = allProperties[.ambientOcclusion]?.texture
                    subData.roughnessTexture = allProperties[.roughness]?.texture
                    subData.normalTexture = allProperties[.tangentSpaceNormal]?.texture
                    subData.emissionTexture = allProperties[.emission]?.texture
                    subData.subsurfaceTexture = allProperties[.subsurface]?.texture
                    subData.specularTexture = allProperties[.specular]?.texture
                    subData.specularTintTexture = allProperties[.specularTint]?.texture
                    subData.anisotropicTexture = allProperties[.anisotropic]?.texture
                    subData.sheenTexture = allProperties[.sheen]?.texture
                    subData.sheenTintTexture = allProperties[.sheenTint]?.texture
                    subData.clearcoatTexture = allProperties[.clearcoat]?.texture
                    subData.clearcoatGlossTexture = allProperties[.clearcoatGloss]?.texture
                    
                    // Encode the uniform values
                    
                    // The inherent color of a surface, to be used as a modulator during shading.
                    material.baseColor = (allProperties[.baseColor]?.uniform as? SIMD4<Float>) ?? SIMD4<Float>(repeating: 1)
                    // The degree to which a material appears as a dielectric surface (lower values) or as a metal (higher values).
                    material.metalness = (allProperties[.metallic]?.uniform as? Float) ?? 0.0
                    // The degree to which a material appears smooth, affecting both diffuse and specular response.
                    material.roughness = (allProperties[.roughness]?.uniform as? Float) ?? 0.9
                    // The attenuation of ambient light due to local geometry variations on a surface.
                    material.ambientOcclusion  = (allProperties[.ambientOcclusion]?.uniform as? Float) ?? 1.0
                    // The color emitted as radiance from a material’s surface.
                    material.emissionColor = (allProperties[.emission]?.uniform as? SIMD4<Float>) ?? SIMD4<Float>(repeating: 0)
                    // The degree to which light scatters under the surface of a material.
                    material.subsurface = (allProperties[.subsurface]?.uniform as? Float) ?? 0.0
                    // The intensity of specular highlights that appear on the material’s surface.
                    material.specular = (allProperties[.specular]?.uniform as? Float) ?? 0.0
                    // The balance of color for specular highlights, between the light color (lower values) and the material’s base color (at higher values).
                    material.specularTint = (allProperties[.specularTint]?.uniform as? Float) ?? 0.0
                    // The angle at which anisotropic effects are rotated relative to the local tangent basis.
                    material.anisotropic = (allProperties[.anisotropic]?.uniform as? Float) ?? 0.0
                    // The intensity of highlights that appear only at glancing angles on a material’s surface.
                    material.sheen = (allProperties[.sheen]?.uniform as? Float) ?? 0.0
                    // The balance of color for highlights that appear only at glancing angles, between the light color (lower values) and the material’s base color (at higher values).
                    material.sheenTint = (allProperties[.sheenTint]?.uniform as? Float) ?? 0.0
                    // The intensity of a second specular highlight, similar to the gloss that results from a clear coat on an automotive finish.
                    material.clearcoat = (allProperties[.clearcoat]?.uniform as? Float) ?? 0.0
                    // The spread of a second specular highlight, similar to the gloss that results from a clear coat on an automotive finish.
                    material.clearcoatGloss = (allProperties[.clearcoatGloss]?.uniform as? Float) ?? 0.0
                    material.opacity = (allProperties[.opacity]?.uniform as? Float) ?? 1.0
//                    material.opacity = 1.0
                    subData.materialUniforms = material
                    
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
            vtxBuffer.withUnsafeBytes {
                guard let bytesPointer = $0.baseAddress, let aVTXBuffer = device.makeBuffer(bytes: bytesPointer, length: vtxBuffer.count, options: .storageModeShared) else {
                    fatalError("Failed to create a buffer from the device.")
                }
                drawData.vertexBuffers.append(aVTXBuffer)
            }
        }
        
        return drawData
        
    }
    
    /// Create a `SkeletonData` object of the provided `MDLObject` has joint transform informtaion
    /// - Parameter object: An `MDLObject`
    /// - Parameter from: A base `SkeletonData` object
    /// - Parameter keyTimes: Keyframe sample times
    /// - Returns: `SkeletonData` or `nil` if not data is found
    private static func skeletonDataAnimation(from baseSkeleton: SkeletonData?, for object: MDLObject, keyTimes: [TimeInterval]) -> SkeletonData? {
        
        guard let baseSkeleton = baseSkeleton else {
            return nil
        }
        
        // MDLAnimationBindComponent? Im not sure what this component's role is in joint anomation because, guess what, "No Overview Available"
        guard let jointAnimation = object.components.first(where: {$0 is MDLPackedJointAnimation}) as? MDLPackedJointAnimation else {
            return baseSkeleton
        }
        
        var skeleton = baseSkeleton
        var animations = [SkeletonAnimation]()
        for time in keyTimes {
            let translations = jointAnimation.translations.float3Array(atTime: time)
            let rotations = jointAnimation.rotations.floatQuaternionArray(atTime: time)
            let animation = SkeletonAnimation(keyTime: time, translations: translations, rotations: rotations)
            animations.append(animation)
        }
        
        skeleton.animations = animations
        return skeleton
    }
    
    private static func readMaterialPropertyValue(from property: MDLMaterialProperty, textureLoader: MTKTextureLoader? = nil, bundle: Bundle? = nil, baseURL: URL? = nil) -> (uniform: Any?, texture: MTLTexture?)? {
        
        var result: (uniform: Any?, texture: MTLTexture?) = (nil, nil)
        
        if let textureLoader = textureLoader, let sourceTexture = property.textureSamplerValue?.texture {
            let options: [MTKTextureLoader.Option : Any] = [ .generateMipmaps : property.semantic != .tangentSpaceNormal, .allocateMipmaps: property.semantic != .tangentSpaceNormal ]
            do {
                result.texture = try textureLoader.newTexture(texture: sourceTexture, options: options)
            } catch {
                print(error)
            }
        } else {
            switch property.type {
            case .none:
                return nil
            case .string:
                if let textureLoader = textureLoader, let bundle = bundle {
                    result.texture = createMTLTexture(fromMaterialProperty: property, inBundle: bundle, withTextureLoader: textureLoader, baseURL: baseURL)
                }
            case .URL:
                if let textureLoader = textureLoader, let bundle = bundle {
                    result.texture = createMTLTexture(fromMaterialProperty: property, inBundle: bundle, withTextureLoader: textureLoader, baseURL: baseURL)
                }
            case .texture:
                if let textureLoader = textureLoader, let sourceTexture = property.textureSamplerValue?.texture {
                    let options: [MTKTextureLoader.Option : Any] = [ .generateMipmaps : property.semantic != .tangentSpaceNormal, .allocateMipmaps: property.semantic != .tangentSpaceNormal ]
                    result.texture = try? textureLoader.newTexture(texture: sourceTexture, options: options)
                } else {
                    return nil
                }
            case .color:
                result.uniform = property.color
            case .float:
                result.uniform = property.floatValue
            case .float2:
                result.uniform = property.float2Value
            case .float3:
                result.uniform = property.float3Value
            case .float4:
                result.uniform = property.float4Value
            case .matrix44:
                result.uniform = property.matrix4x4
            @unknown default:
                return nil
            }
        }
        return result
    }
    
    private static func createMTLTexture(fromMaterialProperty property: MDLMaterialProperty, inBundle bundle: Bundle, withTextureLoader textureLoader: MTKTextureLoader, baseURL: URL? = nil) -> MTLTexture? {
            
        if let textureSampler = property.textureSamplerValue, let texture = textureSampler.texture {
            return try? textureLoader.newTexture(texture: texture)
        } else if let path = property.urlValue?.absoluteString {
            let fixedPath = fullPath(with: path, baseURL: baseURL)
            return createMTLTexture(inBundle: bundle, fromAssetPath: fixedPath, withTextureLoader: textureLoader)
        } else if let path = property.stringValue {
            let fixedPath = fullPath(with: path, baseURL: baseURL)
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

    ///  Compute an index map from all elements of A.jointPaths to the corresponding paths in B.jointPaths
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
    
    /// Construct a `SkeletonData`. This generates a base object with no animation.
    private static func createSkeleton(from asset: MDLAsset) -> SkeletonData? {
        
        guard let skeletons = asset.childObjects(of: MDLSkeleton.self) as? [MDLSkeleton] else {
            return nil
        }
        
        if skeletons.count > 1 {
            print("WARNING: Multiple MDLSkeletons were found in the MDLAsset. The first will be used but this asset may not be compatible with AugmentKit.")
        }
        
        guard let skeleton = skeletons.first else {
            return nil
        }
        
        let jointCount = skeleton.jointPaths.count
        
        var skeletonData = SkeletonData()
        skeletonData.jointPaths = skeleton.jointPaths
        skeletonData.inverseBindTransforms = skeleton.jointBindTransforms.float4x4Array.map{ $0.inverse }
        skeletonData.parentIndices = Array(repeating: nil, count: jointCount)
        for (index, path) in skeletonData.jointPaths.enumerated() {
            let components = path.components(separatedBy: "/")
            let name = components.last ?? ""
            let basePath = components.dropLast().joined(separator: "/")
            let parentIndex = skeletonData.jointPaths.firstIndex(of: basePath)
            skeletonData.parentIndices[index] = parentIndex
            skeletonData.jointNames.append(name)
        }
        
        return skeletonData
    }

    ///  Count the element count of the subgraph rooted at object.
    private static func subGraphCount(_ object: MDLObject) -> Int {
        var elementCount: Int = 1 // counting us ...
        let childCount = object.children.count
        for childIndex in 0..<childCount {
             //... and subtree count of each child
            elementCount += subGraphCount(object.children[childIndex])
        }
        return elementCount
    }

    ///  Traverse an MDLAsset's scene graph and run a closure on each element, passing on each element's flattened node index as well as its parent's index
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

    ///  Traverse thescene graph rooted at object and run a closure on each element, passing on each element's flattened node index as well as its parent's index
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

    ///  Traverse an MDLAsset's masters list and run a closure on each element. Model I/O supports instancing. These are the master objects that the instances refer to.
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

    ///  Find the index of the (first) MDLMesh in MDLAsset.masters that an MDLObject.instance points to
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
    
    private static func fullPath(with path: String, baseURL: URL? = nil) -> String {
        guard let assetURL = baseURL else {
            return path
        }
        return assetURL.appendingPathComponent(path).absoluteString
    }

    ///  Find the shortest subpath containing a rootIdentifier (used to find a e.g. skeleton's root path)
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
    
    ///  Get a float4 property from an MDLMaterialProperty
    private static func getMaterialFloat4Value(_ materialProperty: MDLMaterialProperty) -> SIMD4<Float> {
        return materialProperty.float4Value
    }

    ///  Get a `SIMD3<Float>` property from an MDLMaterialProperty
    private static func getMaterialFloat3Value(_ materialProperty: MDLMaterialProperty) -> SIMD3<Float> {
        return materialProperty.float3Value
    }

    ///  Get a float property from an MDLMaterialProperty
    private static func getMaterialFloatValue(_ materialProperty: MDLMaterialProperty) -> Float {
        return materialProperty.floatValue
    }

    ///  Uniformly sample a time interval
    private static func sampleTimeInterval(start startTime: TimeInterval, end endTime: TimeInterval,
                            frameInterval: TimeInterval) -> [TimeInterval] {
        let count = Int( (endTime - startTime) / frameInterval )
        return (0..<count).map { startTime + TimeInterval($0) * frameInterval }
    }

}

// MARK: - MaterialProperties

/// Stores a material name along with a properties dictionary where the keys are each `MDLMaterialSemantic` that's contained in the material and the values are tupels that either contain a uniform value or a `MTLTexture`. Since `MDLMaterial` objects parsed from various file formats can contain multiple values for the same semantic, generally, a texture is preferred over a uniform and the last value found is the value used.
class MaterialProperties {
    var materialName: String
    var properties = [MDLMaterialSemantic: (uniform: Any?, texture: MTLTexture?)]()
    init(name: String, properties: [MDLMaterialSemantic: (uniform: Any?, texture: MTLTexture?)] = [:]) {
        self.materialName = name
        self.properties = properties
    }
}

// MARK: - MaterialCache

class MaterialCache: NSCache<AnyObject, MaterialProperties> {
    static let shared = MaterialCache()
    
    func cachedMaterial(with name: String) -> MaterialProperties? {
        return object(forKey: name as AnyObject)
    }
    
    func cacheMaterial(_ materialProperties: MaterialProperties, for name: String) {
        setObject(materialProperties, forKey: name as AnyObject)
    }
    
}
