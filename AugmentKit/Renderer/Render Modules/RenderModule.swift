//
//  RenderModule.swift
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
import ARKit
import AugmentKitShader
import Metal
import MetalKit

// MARK: - RenderModule protocol

protocol RenderModule {
    
    //
    // State
    //
    
    var moduleIdentifier: String { get }
    var isInitialized: Bool { get }
    // Lower layer modules are rendered first
    var renderLayer: Int { get }
    // An array of shared module identifiers that it this module will rely on in the draw phase.
    var sharedModuleIdentifiers: [String]? { get }
    var renderDistance: Double { get set }
    var errors: [AKError] { get set }
    var drawCallGroups: [RenderPass.DrawCallGroup] { get }
    
    //
    // Bootstrap
    //
    
    // Initialize the buffers that will me managed and updated in this module.
    func initializeBuffers(withDevice: MTLDevice, maxInFlightBuffers: Int)
    
    // Load the data from the Model Provider.
    func loadAssets(forGeometricEntities: [AKGeometricEntity], fromModelProvider: ModelProvider?, textureLoader: MTKTextureLoader, completion: (() -> Void))
    
    /// After this function is called, The Render Pass Desciptors, Textures, Buffers, Render Pipeline State Descriptors, and Depth Stencil Descriptors should all be set up.
    func loadPipeline(withMetalLibrary metalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider, textureBundle: Bundle)
    
    //
    // Per Frame Updates
    //
    
    // The buffer index is the index into the ring on in flight buffers
    func updateBufferState(withBufferIndex: Int)
    
    // Update the buffer data for augmented anchors
    func updateBuffers(withAugmentedAnchors: [AKAugmentedAnchor], cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties)
    
    // Update the buffer data for real anchors
    func updateBuffers(withRealAnchors: [AKRealAnchor], cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties)
    
    // Update the buffer data for trackers
    func updateBuffers(withTrackers: [AKAugmentedTracker], targets: [AKTarget], cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties)
    
    // Update the buffer data for trackers
    func updateBuffers(withPaths: [AKPath], cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties)
    
    // Update the render encoder for the draw call. At the end of this method it is expected that
    // drawPrimatives or drawIndexedPrimatives is called.
    func draw(withRenderPass renderPass: RenderPass, sharedModules: [SharedRenderModule]?)
    
    // Called when Metal and the GPU has fully finished proccssing the commands we're encoding
    // this frame. This indicates when the dynamic buffers, that we're writing to this frame,
    // will no longer be needed by Metal and the GPU. This gets called per frame.
    func frameEncodingComplete()
    
    //
    // Util
    //
    
    func recordNewError(_ akError: AKError)
    
}

// MARK: - RenderModule extensions

extension RenderModule {
    
    func draw(withDrawData drawData: DrawData, with renderEncoder: MTLRenderCommandEncoder, baseIndex: Int = 0, environmentData: EnvironmentData? = nil) {
        
        // Set mesh's vertex buffers
        for (index, vertexBuffer) in drawData.vertexBuffers.enumerated() {
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: index)
        }
        
        // Set the palette offset info
        if var paletteStartIndex = drawData.paletteStartIndex {
            renderEncoder.setVertexBytes(&paletteStartIndex, length: 8, index: Int(kBufferIndexMeshPaletteIndex.rawValue))
            var paletteSize = drawData.paletteSize
            renderEncoder.setVertexBytes(&paletteSize, length: 8, index: Int(kBufferIndexMeshPaletteSize.rawValue))
        }
        
        // Draw each submesh of our mesh
        for submeshData in drawData.subData {
            
            guard drawData.instanceCount > 0 else {
                continue
            }
            
            guard let indexBuffer = submeshData.indexBuffer else {
                continue
            }
            
            // Sets the weight of values sampled from a texture vs value from a material uniform
            // for a transition between quality levels
            //            submeshData.computeTextureWeights(for: currentQualityLevel, with: globalMapWeight)
            
            let indexCount = Int(submeshData.indexCount)
            let indexType = submeshData.indexType
            
            var materialUniforms = submeshData.materialUniforms
            
            // Set textures based off material flags
            encodeTextures(for: renderEncoder, subData: submeshData, environmentData: environmentData)
            
            renderEncoder.setFragmentBytes(&materialUniforms, length: RenderModuleConstants.alignedMaterialSize, index: Int(kBufferIndexMaterialUniforms.rawValue))
            renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount, indexType: indexType, indexBuffer: indexBuffer, indexBufferOffset: 0, instanceCount: drawData.instanceCount, baseVertex: 0, baseInstance: baseIndex)
        }
        
    }
    
    // MARK: Encoding Textures
    
    func encodeTextures(for renderEncoder: MTLRenderCommandEncoder, subData drawSubData: DrawSubData, environmentData: EnvironmentData? = nil) {
        if let baseColorTexture = drawSubData.baseColorTexture {
            renderEncoder.setFragmentTexture(baseColorTexture, index: Int(kTextureIndexColor.rawValue))
        }
        
        if let ambientOcclusionTexture = drawSubData.ambientOcclusionTexture {
            renderEncoder.setFragmentTexture(ambientOcclusionTexture, index: Int(kTextureIndexAmbientOcclusion.rawValue))
        }
        
        if let emissionTexture = drawSubData.emissionTexture {
            renderEncoder.setFragmentTexture(emissionTexture, index: Int(kTextureIndexEmissionMap.rawValue))
        }
        
        if let normalTexture = drawSubData.normalTexture {
            renderEncoder.setFragmentTexture(normalTexture, index: Int(kTextureIndexNormal.rawValue))
        }
        
        if let roughnessTexture = drawSubData.roughnessTexture {
            renderEncoder.setFragmentTexture(roughnessTexture, index: Int(kTextureIndexRoughness.rawValue))
        }
        
        if let metallicTexture = drawSubData.metallicTexture {
            renderEncoder.setFragmentTexture(metallicTexture, index: Int(kTextureIndexMetallic.rawValue))
        }
        
        if let subsurfaceTexture = drawSubData.subsurfaceTexture {
            renderEncoder.setFragmentTexture(subsurfaceTexture, index: Int(kTextureIndexSubsurfaceMap.rawValue))
        }
        
        if let specularTexture = drawSubData.specularTexture {
            renderEncoder.setFragmentTexture(specularTexture, index: Int(kTextureIndexSpecularMap.rawValue))
        }
        
        if let specularTintTexture = drawSubData.specularTintTexture {
            renderEncoder.setFragmentTexture(specularTintTexture, index: Int(kTextureIndexSpecularTintMap.rawValue))
        }
        
        if let anisotropicTexture = drawSubData.anisotropicTexture {
            renderEncoder.setFragmentTexture(anisotropicTexture, index: Int(kTextureIndexAnisotropicMap.rawValue))
        }
        
        if let sheenTexture = drawSubData.sheenTexture {
            renderEncoder.setFragmentTexture(sheenTexture, index: Int(kTextureIndexSheenMap.rawValue))
        }
        
        if let sheenTintTexture = drawSubData.sheenTintTexture {
            renderEncoder.setFragmentTexture(sheenTintTexture, index: Int(kTextureIndexSheenTintMap.rawValue))
        }
        
        if let clearcoatTexture = drawSubData.clearcoatTexture {
            renderEncoder.setFragmentTexture(clearcoatTexture, index: Int(kTextureIndexClearcoatMap.rawValue))
        }
        
        if let clearcoatGlossTexture = drawSubData.clearcoatGlossTexture {
            renderEncoder.setFragmentTexture(clearcoatGlossTexture, index: Int(kTextureIndexClearcoatGlossMap.rawValue))
        }
        
        if let environmentTexture = environmentData?.environmentTexture {
            renderEncoder.setFragmentTexture(environmentTexture, index: Int(kTextureIndexEnvironmentMap.rawValue))
        }
        
    }
    
    func createMTLTexture(inBundle bundle: Bundle, fromAssetPath assetPath: String, withTextureLoader textureLoader: MTKTextureLoader?) -> MTLTexture? {
        do {
            
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
            
            return try textureLoader?.newTexture(URL: aURL, options: nil)
            
        } catch {
            print("Unable to loader texture with assetPath \(assetPath) with error \(error)")
            let newError = AKError.recoverableError(.modelError(.unableToLoadTexture(AssetErrorInfo(path: assetPath, underlyingError: error))))
            recordNewError(newError)
        }
        
        return nil
    }
    
    // MARK: Render Distance
    
    func anchorDistance(withTransform transform: matrix_float4x4, cameraProperties: CameraProperties?) -> Float {
        guard let cameraProperties = cameraProperties else {
            return 0
        }
        let point = float3(transform.columns.3.x, transform.columns.3.x, transform.columns.3.z)
        return length(point - cameraProperties.position)
    }
    
    func renderShpereIntersectionOfPath(withPoint0 point0: float3, point1: float3, cameraProperties: CameraProperties?) -> SphereLineIntersection {
        guard let cameraProperties = cameraProperties else {
            return SphereLineIntersection(isInside: false, point0: point0, point1: point1)
        }
        
        let dist0 = length(point0 - cameraProperties.position)
        let dist1 = length(point1 - cameraProperties.position)
        let isPoint0Inside = Double(dist0) < renderDistance
        let isPoint1Inside = Double(dist1) < renderDistance
        
        // If both points are inside, there is no intersection
        guard !isPoint0Inside || !isPoint1Inside else {
            return SphereLineIntersection(isInside: true, point0: point0, point1: point1)
        }
        
        let dir = normalize(point1 - point0)
        
        let q = cameraProperties.position - point0
        let vDotQ = dot(dir, q)
        let squareDiffs = dot(q, q) - Float(renderDistance * renderDistance)
        let discriminant = vDotQ * vDotQ - squareDiffs
        if discriminant >= 0 {
            let root = sqrt(discriminant)
            let t0 = (vDotQ - root)
            let t1 = (vDotQ + root)
            if isPoint0Inside && !isPoint1Inside {
                return SphereLineIntersection(isInside: true, point0: point0, point1: point0 + dir * t1)
            } else if isPoint1Inside && !isPoint0Inside {
                return SphereLineIntersection(isInside: true, point0: point0 + dir * t0, point1: point1)
            } else if !isPoint1Inside && !isPoint0Inside {
                return SphereLineIntersection(isInside: true, point0: point0 + dir * t0, point1: point0 + dir * t1)
            } else {
                // Both inside. No intersections
                return SphereLineIntersection(isInside: true, point0: point0, point1: point1)
            }
        } else {
            // There are no intersections
            return SphereLineIntersection(isInside: false, point0: point0, point1: point1)
        }
    }
    
    // MARK: Util
    
    func getRGB(from colorTemperature: CGFloat) -> vector_float3 {
        
        let temp = Float(colorTemperature) / 100
        
        var red: Float = 127
        var green: Float = 127
        var blue: Float = 127
        
        if temp <= 66 {
            red = 255
            green = temp
            green = 99.4708025861 * log(green) - 161.1195681661
            if temp <= 19 {
                blue = 0
            } else {
                blue = temp - 10
                blue = 138.5177312231 * log(blue) - 305.0447927307
            }
        } else {
            red = temp - 60
            red = 329.698727446 * pow(red, -0.1332047592)
            green = temp - 60
            green = 288.1221695283 * pow(green, -0.0755148492 )
            blue = 255
        }
        
        let clamped = clamp(float3(red, green, blue), min: 0, max: 255)
        return vector3(clamped.x, clamped.y, clamped.z)
        
    }
    
}

// MARK: - RenderModuleConstants

enum RenderModuleConstants {
    static let alignedMaterialSize = (MemoryLayout<MaterialUniforms>.stride & ~0xFF) + 0x100
}

// MARK: - SkinningModule

protocol SkinningModule {
    
}

extension SkinningModule {
    
    //  Find the largest index of time stamp <= key
    func lowerBoundKeyframeIndex(_ lhs: [Double], key: Double) -> Int? {
        if lhs.isEmpty {
            return nil
        }
        
        if key < lhs.first! { return 0 }
        if key > lhs.last! { return lhs.count - 1 }
        
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
    
    //  Evaluate the skeleton animation at a particular time
    func evaluateAnimation(_ animation: AnimatedSkeleton, at time: Double) -> [matrix_float4x4] {
        let keyframeIndex = lowerBoundKeyframeIndex(animation.keyTimes, key: time)!
        let parentIndices = animation.parentIndices
        let animJointCount = animation.jointCount
        
        // get the joints at the specified range
        let startIndex = keyframeIndex * animJointCount
        let endIndex = startIndex + animJointCount
        
        // get the translations and rotations using the start and endindex
        let poseTranslations = [float3](animation.translations[startIndex..<endIndex])
        let poseRotations = [simd_quatf](animation.rotations[startIndex..<endIndex])
        
        var worldPose = [matrix_float4x4]()
        worldPose.reserveCapacity(parentIndices.count)
        
        // using the parent indices create the worldspace transformations and store
        for index in 0..<parentIndices.count {
            let parentIndex = parentIndices[index]
            
            var localMatrix = simd_matrix4x4(poseRotations[index])
            let translation = poseTranslations[index]
            localMatrix.columns.3 = simd_float4(translation.x, translation.y, translation.z, 1.0)
            if let index = parentIndex {
                worldPose.append(simd_mul(worldPose[index], localMatrix))
            } else {
                worldPose.append(localMatrix)
            }
        }
        
        return worldPose
    }
    
    //  Using the the skinData and a skeleton's pose in world space, compute the matrix palette
    func evaluateMatrixPalette(_ worldPose: [matrix_float4x4], _ skinData: SkinData) -> [matrix_float4x4] {
        let paletteCount = skinData.inverseBindTransforms.count
        let inverseBindTransforms = skinData.inverseBindTransforms
        
        var palette = [matrix_float4x4]()
        palette.reserveCapacity(paletteCount)
        // using the joint map create the palette for the skeleton
        for index in 0..<skinData.skinToSkeletonMap.count {
            palette.append(simd_mul(worldPose[skinData.skinToSkeletonMap[index]], inverseBindTransforms[index]))
        }
        
        return palette
    }
    
}

// MARK: - SphereLineIntersection

struct SphereLineIntersection {
    var isInside: Bool
    var point0: float3
    var point1: float3
}

// MARK: - SharedRenderModule protocol

// A shared render module is a render module responsible for setting up and updating
// shared buffers. Although it does have a draw() method, typically this method does
// not do anything. Instead, the module that uses this shared module is responsible
// for encoding the shared buffer and issuing the draw call
protocol SharedRenderModule: RenderModule {
    var sharedUniformBuffer: MTLBuffer? { get }
    var sharedUniformBufferOffset: Int { get }
    var sharedUniformBufferAddress: UnsafeMutableRawPointer? { get }
}
