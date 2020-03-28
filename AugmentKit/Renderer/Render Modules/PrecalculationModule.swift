//
//  PrecalculationModule.swift
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
//

import ARKit
import AugmentKitShader
import Foundation
import MetalKit

class PrecalculationModule: PreRenderComputeModule {
    
    weak var computePass: ComputePass<PrecalculatedParameters>?
    var device: MTLDevice?
    var frameCount: Int = 1
    var moduleIdentifier: String {
        return "PrecalculationModule"
    }
    var state: ShaderModuleState = .uninitialized
    var renderLayer: Int {
        return -3
    }
    
    var errors = [AKError]()
    var renderDistance: Double = 500
    var sharedModuleIdentifiers: [String]? = [SharedBuffersRenderModule.identifier]
    
    func initializeBuffers(withDevice device: MTLDevice, maxInFlightFrames: Int, maxInstances: Int) {
        
        state = .initializing
        
        self.device = device
        frameCount = maxInFlightFrames
        instanceCount = maxInstances
        
        alignedGeometryInstanceUniformsSize = ((MemoryLayout<AnchorInstanceUniforms>.stride * instanceCount) & ~0xFF) + 0x100
        alignedEffectsUniformSize = ((MemoryLayout<AnchorEffectsUniforms>.stride * instanceCount) & ~0xFF) + 0x100
        alignedEnvironmentUniformSize = ((MemoryLayout<EnvironmentUniforms>.stride * instanceCount) & ~0xFF) + 0x100
        
        // Calculate our uniform buffer sizes. We allocate `maxInFlightFrames` instances for uniform
        // storage in a single buffer. This allows us to update uniforms in a ring (i.e. triple
        // buffer the uniforms) so that the GPU reads from one slot in the ring wil the CPU writes
        // to another. Geometry uniforms should be specified with a max instance count for instancing.
        // Also uniform storage must be aligned (to 256 bytes) to meet the requirements to be an
        // argument in the constant address space of our shading functions.
        let geometryUniformBufferSize = alignedGeometryInstanceUniformsSize * maxInFlightFrames
        let paletteBufferSize = Constants.alignedPaletteSize * Constants.maxPaletteCount * maxInFlightFrames
        let effectsUniformBufferSize = alignedEffectsUniformSize * maxInFlightFrames
        let environmentUniformBufferSize = alignedEnvironmentUniformSize * maxInFlightFrames
        
        // Create and allocate our uniform buffer objects. Indicate shared storage so that both the
        // CPU can access the buffer
        geometryUniformBuffer = device.makeBuffer(length: geometryUniformBufferSize, options: .storageModeShared)
        geometryUniformBuffer?.label = "GeometryUniformBuffer"
        
        paletteBuffer = device.makeBuffer(length: paletteBufferSize, options: [])
        paletteBuffer?.label = "PaletteBuffer"
        
        effectsUniformBuffer = device.makeBuffer(length: effectsUniformBufferSize, options: .storageModeShared)
        effectsUniformBuffer?.label = "EffectsUniformBuffer"
        
        environmentUniformBuffer = device.makeBuffer(length: environmentUniformBufferSize, options: .storageModeShared)
        environmentUniformBuffer?.label = "EnvironmentUniformBuffer"
        
    }
    
    func loadPipeline(withMetalLibrary metalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider, textureBundle: Bundle, forComputePass computePass: ComputePass<PrecalculatedParameters>?) -> ThreadGroup? {
        
        guard let computePass = computePass else {
            print("Warning (PrecalculationModule) - a ComputePass was not found. Aborting.")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeModelNotFound, userInfo: nil)
            let newError = AKError.warning(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            state = .ready
            return nil
        }
        
        self.computePass = computePass
        self.computePass?.functionName = "precalculationComputeShader"
        self.computePass?.initializeBuffers(withDevice: device)
        self.computePass?.loadPipeline(withMetalLibrary: metalLibrary, instanceCount: instanceCount, threadgroupDepth: 1)
        
        state = .ready
        return self.computePass?.threadGroup
    }
    
    func updateBufferState(withBufferIndex bufferIndex: Int) {
        
        geometryUniformBufferOffset = alignedGeometryInstanceUniformsSize * bufferIndex
        paletteBufferOffset = Constants.alignedPaletteSize * Constants.maxPaletteCount * bufferIndex
        effectsUniformBufferOffset = alignedEffectsUniformSize * bufferIndex
        environmentUniformBufferOffset = alignedEnvironmentUniformSize * bufferIndex
        
        geometryUniformBufferAddress = geometryUniformBuffer?.contents().advanced(by: geometryUniformBufferOffset)
        paletteBufferAddress = paletteBuffer?.contents().advanced(by: paletteBufferOffset)
        effectsUniformBufferAddress = effectsUniformBuffer?.contents().advanced(by: effectsUniformBufferOffset)
        environmentUniformBufferAddress = environmentUniformBuffer?.contents().advanced(by: environmentUniformBufferOffset)
        
        computePass?.updateBuffers(withFrameIndex: bufferIndex)
        
    }
    
    func prepareToDraw(withAllEntities allEntities: [AKEntity], cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties, shadowProperties: ShadowProperties, computePass: ComputePass<PrecalculatedParameters>, renderPass: RenderPass?) {
        
        var drawCallGroupOffset = 0
        var drawCallGroupIndex = 0
        
        let geometryUniforms = geometryUniformBufferAddress?.assumingMemoryBound(to: AnchorInstanceUniforms.self)
        let environmentUniforms = environmentUniformBufferAddress?.assumingMemoryBound(to: EnvironmentUniforms.self)
        let effectsUniforms = effectsUniformBufferAddress?.assumingMemoryBound(to: AnchorEffectsUniforms.self)
        
        // Get all of the AKGeometricEntity's
        var allGeometricEntities: [AKGeometricEntity] = allEntities.compactMap({
            if let geoEntity = $0 as? AKGeometricEntity {
                return geoEntity
            } else {
                return nil
            }
        })
        let allGeometricEntityGroups: [AKGeometricEntityGroup] = allEntities.compactMap({
            if let geoEntity = $0 as? AKGeometricEntityGroup {
                return geoEntity
            } else {
                return nil
            }
        })
        let groupGeometries = allGeometricEntityGroups.flatMap({$0.geometries})
        allGeometricEntities.append(contentsOf: groupGeometries)
        
        renderPass?.drawCallGroups.forEach { drawCallGroup in
            
            let uuid = drawCallGroup.uuid
            let geometricEntity = allGeometricEntities.first(where: {$0.identifier == uuid})
            var drawCallIndex = 0
            
            for drawCall in drawCallGroup.drawCalls {
                
                //
                // Environment Uniform Setup
                //
                
                if let environmentUniform = environmentUniforms?.advanced(by: drawCallGroupOffset + drawCallIndex), computePass.usesEnvironment {
                    
                    // See if this anchor is associated with an environment anchor. An environment anchor applies to a region of space which may contain several anchors. The environment anchor that has the smallest volume is assumed to be more localized and therefore be the best for for this anchor
                    var environmentTexture: MTLTexture?
                    let environmentProbes: [AREnvironmentProbeAnchor] = environmentProperties.environmentAnchorsWithReatedAnchors.compactMap{
                        if $0.value.contains(uuid) {
                            return $0.key
                        } else {
                            return nil
                        }
                    }
                    if environmentProbes.count > 1 {
                        var bestEnvironmentProbe: AREnvironmentProbeAnchor?
                        environmentProbes.forEach {
                            if let theBestEnvironmentProbe = bestEnvironmentProbe {
                                let existingVolume = AKCube(position: AKVector(x: theBestEnvironmentProbe.transform.columns.3.x, y: theBestEnvironmentProbe.transform.columns.3.y, z: theBestEnvironmentProbe.transform.columns.3.z), extent: AKVector(theBestEnvironmentProbe.extent)).volume()
                                let newVolume = AKCube(position: AKVector(x: $0.transform.columns.3.x, y: $0.transform.columns.3.y, z: $0.transform.columns.3.z), extent: AKVector($0.extent)).volume()
                                if newVolume < existingVolume {
                                    bestEnvironmentProbe = $0
                                }
                            } else {
                                bestEnvironmentProbe = $0
                            }
                        }
                        if let environmentProbeAnchor = bestEnvironmentProbe, let texture = environmentProbeAnchor.environmentTexture {
                            environmentTexture = texture
                        }
                    } else {
                        if let environmentProbeAnchor = environmentProbes.first, let texture = environmentProbeAnchor.environmentTexture {
                            environmentTexture = texture
                        }
                    }
                    
                    let environmentData: EnvironmentData = {
                        var myEnvironmentData = EnvironmentData()
                        if let texture = environmentTexture {
                            myEnvironmentData.environmentTexture = texture
                            myEnvironmentData.hasEnvironmentMap = true
                            return myEnvironmentData
                        } else {
                            myEnvironmentData.hasEnvironmentMap = false
                        }
                        return myEnvironmentData
                    }()
                    // Set up lighting for the scene using the ambient intensity if provided
                    let ambientIntensity: Float = {
                        if let lightEstimate = environmentProperties.lightEstimate {
                            return Float(lightEstimate.ambientIntensity) / 1000.0
                        } else {
                            return 1
                        }
                    }()
                    let ambientLightColor: SIMD3<Float> = {
                        if let lightEstimate = environmentProperties.lightEstimate {
                            // FIXME: Remove
                            return getRGB(from: lightEstimate.ambientColorTemperature)
                        } else {
                            return SIMD3<Float>(0.5, 0.5, 0.5)
                        }
                    }()
                    
                    environmentUniforms?.pointee.ambientLightIntensity = ambientIntensity
                    environmentUniform.pointee.ambientLightColor = ambientLightColor// * ambientIntensity
                    
                    var directionalLightDirection : SIMD3<Float> = environmentProperties.directionalLightDirection
                    directionalLightDirection = simd_normalize(directionalLightDirection)
                    environmentUniform.pointee.directionalLightDirection = directionalLightDirection
                    
                    let directionalLightColor: SIMD3<Float> = SIMD3<Float>(0.6, 0.6, 0.6)
                    environmentUniform.pointee.directionalLightColor = directionalLightColor// * ambientIntensity
                    
                    environmentUniform.pointee.directionalLightMVP = environmentProperties.directionalLightMVP
                    environmentUniform.pointee.shadowMVPTransformMatrix = shadowProperties.shadowMVPTransformMatrix
                    
                    if environmentData.hasEnvironmentMap == true {
                        environmentUniform.pointee.hasEnvironmentMap = 1
                    } else {
                        environmentUniform.pointee.hasEnvironmentMap = 0
                    }
                    
                }
                
                //
                // Effects Uniform Setup
                //
                
                if let effectsUniform = effectsUniforms?.advanced(by: drawCallGroupOffset + drawCallIndex), computePass.usesEnvironment {
                    
                    var hasSetAlpha = false
                    var hasSetGlow = false
                    var hasSetTint = false
                    var hasSetScale = false
                    if let effects = geometricEntity?.effects {
                        let currentTime: TimeInterval = Double(cameraProperties.currentFrame) / cameraProperties.frameRate
                        for effect in effects {
                            switch effect.effectType {
                            case .alpha:
                                if let value = effect.value(forTime: currentTime) as? Float {
                                    effectsUniform.pointee.alpha = value
                                    hasSetAlpha = true
                                }
                            case .glow:
                                if let value = effect.value(forTime: currentTime) as? Float {
                                    effectsUniform.pointee.glow = value
                                    hasSetGlow = true
                                }
                            case .tint:
                                if let value = effect.value(forTime: currentTime) as? SIMD3<Float> {
                                    effectsUniform.pointee.tint = value
                                    hasSetTint = true
                                }
                            case .scale:
                                if let value = effect.value(forTime: currentTime) as? Float {
                                    let scaleMatrix = matrix_identity_float4x4
                                    effectsUniform.pointee.scale = scaleMatrix.scale(x: value, y: value, z: value)
                                    hasSetScale = true
                                }
                            }
                        }
                    }
                    if !hasSetAlpha {
                        effectsUniform.pointee.alpha = 1
                    }
                    if !hasSetGlow {
                        effectsUniform.pointee.glow = 0
                    }
                    if !hasSetTint {
                        effectsUniform.pointee.tint = SIMD3<Float>(1,1,1)
                    }
                    if !hasSetScale {
                        effectsUniform.pointee.scale = matrix_identity_float4x4
                    }
                    
                }
            
                //
                // Geometry Uniform Setup
                //
                
                if let geometryUniform = geometryUniforms?.advanced(by: drawCallGroupOffset + drawCallIndex), computePass.usesGeometry {
                    
                    guard let drawData = drawCall.drawData, drawCallIndex <= instanceCount else {
                        geometryUniform.pointee.hasGeometry = 0
                        drawCallIndex += 1
                        continue
                    }
                    
                    // FIXME: - Let the compute shader do most of this
                    
                    // Apply the world transform (as defined in the imported model) if applicable
                    let worldTransform: matrix_float4x4 = {
                        if let pathSegment = geometricEntity as? AKPathSegmentAnchor {
                            // For path segments, use the segmentTransform as the worldTransform
                            return pathSegment.segmentTransform
                        } else if drawData.worldTransformAnimations.count > 0 {
                            let index = Int(cameraProperties.currentFrame % UInt(drawData.worldTransformAnimations.count))
                            return drawData.worldTransformAnimations[index]
                        } else {
                            return drawData.worldTransform
                        }
                    }()
                    
                    var hasHeading = false
                    var headingType: HeadingType = .absolute
                    var headingTransform = matrix_identity_float4x4
                    var locationTransform = matrix_identity_float4x4
                    
                    if let akAnchor = geometricEntity as? AKAnchor {
                        
                        // Update Heading
                        let myHeadingTransform = akAnchor.heading.offsetRotation.quaternion.toMatrix4()
                        
                        hasHeading = true
                        headingType = akAnchor.heading.type
                        headingTransform = myHeadingTransform
                        locationTransform = akAnchor.worldLocation.transform
                        
                    } else if let akTarget = geometricEntity as? AKTarget {
                        
                        // Apply the transform of the target relative to the reference transform
                        let targetAbsoluteTransform = akTarget.position.referenceTransform * akTarget.position.transform
                        locationTransform = targetAbsoluteTransform
                        
                    } else if let akTracker = geometricEntity as? AKTracker {
                        
                        // Apply the transform of the target relative to the reference transform
                        let trackerAbsoluteTransform = akTracker.position.referenceTransform * akTracker.position.transform
                        locationTransform = trackerAbsoluteTransform
                    }
                    
                    // Ignore anchors that are beyond the renderDistance
                    let distance = anchorDistance(withTransform: locationTransform, cameraProperties: cameraProperties)
                    guard Double(distance) < renderDistance else {
                        geometryUniform.pointee.hasGeometry = 0
                        drawCallIndex += 1
                        continue
                    }
                    
                    // Calculate LOD
                    let lodMapWeights = computeTextureWeights(for: distance)
                    
                    geometryUniform.pointee.hasGeometry = 1
                    geometryUniform.pointee.hasHeading = hasHeading ? 1 : 0
                    geometryUniform.pointee.headingType = headingType == .absolute ? 0 : 1
                    geometryUniform.pointee.headingTransform = headingTransform
                    geometryUniform.pointee.worldTransform = worldTransform
                    geometryUniform.pointee.locationTransform = locationTransform
                    geometryUniform.pointee.mapWeights = lodMapWeights
                }
                
                drawCallIndex += 1
                
            }
            
            drawCallGroupOffset += drawCallGroup.drawCalls.count
            drawCallGroupIndex += 1
            
        }
    }
    
    func dispatch(withComputePass computePass: ComputePass<PrecalculatedParameters>?, sharedModules: [SharedRenderModule]?) {
        
        guard let computePass = computePass else {
            return
        }
        
        guard let computeEncoder = computePass.computeCommandEncoder else {
            return
        }
        
        guard let threadGroup = computePass.threadGroup else {
            return
        }
        
        computeEncoder.pushDebugGroup("Dispatch Precalculation")
        
        computeEncoder.setBytes(&instanceCount, length: MemoryLayout<Int>.size, index: Int(kBufferIndexInstanceCount.rawValue))
        
        if let sharedRenderModule = sharedModules?.first(where: {$0.moduleIdentifier == SharedBuffersRenderModule.identifier}), let sharedBuffer = sharedRenderModule.sharedUniformsBuffer?.buffer, let sharedBufferOffset = sharedRenderModule.sharedUniformsBuffer?.currentBufferFrameOffset, computePass.usesSharedBuffer {
            
            computeEncoder.pushDebugGroup("Shared Uniforms")
            computeEncoder.setBuffer(sharedBuffer, offset: sharedBufferOffset, index: sharedRenderModule.sharedUniformsBuffer?.shaderAttributeIndex ?? 0)
            computeEncoder.popDebugGroup()
            
        }
        
        if let environmentUniformBuffer = environmentUniformBuffer, computePass.usesEnvironment {
            
            computeEncoder.pushDebugGroup("Environment Uniforms")
            computeEncoder.setBuffer(environmentUniformBuffer, offset: environmentUniformBufferOffset, index: Int(kBufferIndexEnvironmentUniforms.rawValue))
            computeEncoder.popDebugGroup()
            
        }
        
        if let effectsBuffer = effectsUniformBuffer, computePass.usesEffects {
            
            computeEncoder.pushDebugGroup("Effects Uniforms")
            computeEncoder.setBuffer(effectsBuffer, offset: effectsUniformBufferOffset, index: Int(kBufferIndexAnchorEffectsUniforms.rawValue))
            computeEncoder.popDebugGroup()
            
        }
        
        if computePass.usesGeometry {
            computeEncoder.pushDebugGroup("Geometry Uniforms")
            computeEncoder.setBuffer(geometryUniformBuffer, offset: geometryUniformBufferOffset, index: Int(kBufferIndexAnchorInstanceUniforms.rawValue))
            computeEncoder.popDebugGroup()
        
            computeEncoder.pushDebugGroup("Palette Uniforms")
            computeEncoder.setBuffer(paletteBuffer, offset: paletteBufferOffset, index: Int(kBufferIndexMeshPalettes.rawValue))
            computeEncoder.popDebugGroup()
        }
        
        // Output Buffer
        if let argumentOutputBuffer = computePass.outputBuffer?.buffer, let argumentOutputBufferOffset = computePass.outputBuffer?.currentBufferFrameOffset {
            computeEncoder.pushDebugGroup("Output Buffer")
            computeEncoder.setBuffer(argumentOutputBuffer, offset: argumentOutputBufferOffset, index: Int(kBufferIndexPrecalculationOutputBuffer.rawValue))
            computeEncoder.popDebugGroup()
        }
        
        computePass.prepareThreadGroup()
        
        // Requires the device supports non-uniform threadgroup sizes
        computeEncoder.dispatchThreads(MTLSize(width: threadGroup.size.width, height: threadGroup.size.height, depth: threadGroup.size.depth), threadsPerThreadgroup: MTLSize(width: threadGroup.threadsPerGroup.width, height: threadGroup.threadsPerGroup.height, depth: 1))
        
        computeEncoder.popDebugGroup()
        
    }
    
    func frameEncodingComplete(renderPasses: [RenderPass]) {
        //
    }
    
    func recordNewError(_ akError: AKError) {
        errors.append(akError)
    }
    
    // MARK: - Private
    
    fileprivate enum Constants {
        static let maxPaletteCount = 100
        static let alignedPaletteSize = ((MemoryLayout<matrix_float4x4>.stride * maxPaletteCount) & ~0xFF) + 0x100
    }
    
    fileprivate var instanceCount: Int = 0
    
    fileprivate var alignedGeometryInstanceUniformsSize: Int = 0
    fileprivate var alignedEffectsUniformSize: Int = 0
    fileprivate var alignedEnvironmentUniformSize: Int = 0
    
    fileprivate var geometryUniformBuffer: MTLBuffer?
    fileprivate var paletteBuffer: MTLBuffer?
    fileprivate var effectsUniformBuffer: MTLBuffer?
    fileprivate var environmentUniformBuffer: MTLBuffer?
    
    
    
    // Offset within geometryUniformBuffer to set for the current frame
    fileprivate var geometryUniformBufferOffset: Int = 0
    // Offset within paletteBuffer to set for the current frame
    fileprivate var paletteBufferOffset = 0
    // Offset within effectsUniformBuffer to set for the current frame
    fileprivate var effectsUniformBufferOffset: Int = 0
    // Offset within environmentUniformBuffer to set for the current frame
    fileprivate var environmentUniformBufferOffset: Int = 0
    // Addresses to write geometry uniforms to each frame
    fileprivate var geometryUniformBufferAddress: UnsafeMutableRawPointer?
    // Addresses to write palette to each frame
    fileprivate var paletteBufferAddress: UnsafeMutableRawPointer?
    // Addresses to write effects uniforms to each frame
    fileprivate var effectsUniformBufferAddress: UnsafeMutableRawPointer?
    // Addresses to write environment uniforms to each frame
    fileprivate var environmentUniformBufferAddress: UnsafeMutableRawPointer?
    
    // FIXME: Remove - put in compute shader
    fileprivate func anchorDistance(withTransform transform: matrix_float4x4, cameraProperties: CameraProperties?) -> Float {
        guard let cameraProperties = cameraProperties else {
            return 0
        }
        let point = SIMD3<Float>(transform.columns.3.x, transform.columns.3.x, transform.columns.3.z)
        return length(point - cameraProperties.position)
    }
    
    fileprivate func computeTextureWeights(for distance: Float) -> (Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float) {
        
        guard AKCapabilities.LevelOfDetail else {
            return (Float(1), Float(1), Float(1), Float(1), Float(1), Float(1), Float(1), Float(1), Float(1), Float(1), Float(1), Float(1), Float(1), Float(1))
        }
        
        let quality = RenderUtilities.getQualityLevel(for: distance)
        
        // Escape hatch for performance. If the quality is low, exit with all 0 values
        guard quality.rawValue < 2 else {
            return (Float(0), Float(0), Float(0), Float(0), Float(0), Float(0), Float(0), Float(0), Float(0), Float(0), Float(0), Float(0), Float(0), Float(0))
        }
        
        var baseMapWeight: Float = 1
        var normalMapWeight: Float = 1
        var metallicMapWeight: Float = 1
        var roughnessMapWeight: Float = 1
        var ambientOcclusionMapWeight: Float = 1
        var emissionMapWeight: Float = 1
        var subsurfaceMapWeight: Float = 1
        var specularMapWeight: Float = 1
        var specularTintMapWeight: Float = 1
        var anisotropicMapWeight: Float = 1
        var sheenMapWeight: Float = 1
        var sheenTintMapWeight: Float = 1
        var clearcoatMapWeight: Float = 1
        var clearcoatMapWeightGlossMapWeight: Float = 1
        
        let nextLevel: QualityLevel = {
            if quality == kQualityLevelHigh {
                return kQualityLevelMedium
            } else {
                return kQualityLevelLow
            }
        }()
        
        let mapWeight = getMapWeight(for: quality, distance: distance)
        
        if !RenderUtilities.hasTexture(for: kTextureIndexColor, qualityLevel: quality) {
            baseMapWeight = 0
        } else if RenderUtilities.hasTexture(for: kTextureIndexColor, qualityLevel: quality) && !RenderUtilities.hasTexture(for: kTextureIndexColor, qualityLevel: nextLevel) {
            baseMapWeight = mapWeight
        }
        
        if !RenderUtilities.hasTexture(for: kTextureIndexNormal, qualityLevel: quality) {
            normalMapWeight = 0
        } else if RenderUtilities.hasTexture(for: kTextureIndexNormal, qualityLevel: quality) && !RenderUtilities.hasTexture(for: kTextureIndexNormal, qualityLevel: nextLevel) {
            normalMapWeight = mapWeight
        }
        
        if !RenderUtilities.hasTexture(for: kTextureIndexMetallic, qualityLevel: quality) {
            metallicMapWeight = 0
        } else if RenderUtilities.hasTexture(for: kTextureIndexMetallic, qualityLevel: quality) && !RenderUtilities.hasTexture(for: kTextureIndexMetallic, qualityLevel: nextLevel) {
            metallicMapWeight = mapWeight
        }
        
        if !RenderUtilities.hasTexture(for: kTextureIndexRoughness, qualityLevel: quality) {
            roughnessMapWeight = 0
        } else if RenderUtilities.hasTexture(for: kTextureIndexRoughness, qualityLevel: quality) && !RenderUtilities.hasTexture(for: kTextureIndexRoughness, qualityLevel: nextLevel) {
            roughnessMapWeight = mapWeight
        }
        
        if !RenderUtilities.hasTexture(for: kTextureIndexAmbientOcclusion, qualityLevel: quality) {
            ambientOcclusionMapWeight = 0
        } else if RenderUtilities.hasTexture(for: kTextureIndexAmbientOcclusion, qualityLevel: quality) && !RenderUtilities.hasTexture(for: kTextureIndexAmbientOcclusion, qualityLevel: nextLevel) {
            ambientOcclusionMapWeight = mapWeight
        }
        
        if !RenderUtilities.hasTexture(for: kTextureIndexEmissionMap, qualityLevel: quality) {
            emissionMapWeight = 0
        } else if RenderUtilities.hasTexture(for: kTextureIndexEmissionMap, qualityLevel: quality) && !RenderUtilities.hasTexture(for: kTextureIndexEmissionMap, qualityLevel: nextLevel) {
            emissionMapWeight = mapWeight
        }
        
        if !RenderUtilities.hasTexture(for: kTextureIndexSubsurfaceMap, qualityLevel: quality) {
            subsurfaceMapWeight = 0
        } else if RenderUtilities.hasTexture(for: kTextureIndexSubsurfaceMap, qualityLevel: quality) && !RenderUtilities.hasTexture(for: kTextureIndexSubsurfaceMap, qualityLevel: nextLevel) {
            subsurfaceMapWeight = mapWeight
        }
        
        if !RenderUtilities.hasTexture(for: kTextureIndexSpecularMap, qualityLevel: quality) {
            specularMapWeight = 0
        } else if RenderUtilities.hasTexture(for: kTextureIndexSpecularMap, qualityLevel: quality) && !RenderUtilities.hasTexture(for: kTextureIndexSpecularMap, qualityLevel: nextLevel) {
            specularMapWeight = mapWeight
        }
        
        if !RenderUtilities.hasTexture(for: kTextureIndexSpecularTintMap, qualityLevel: quality) {
            specularTintMapWeight = 0
        } else if RenderUtilities.hasTexture(for: kTextureIndexSpecularTintMap, qualityLevel: quality) && !RenderUtilities.hasTexture(for: kTextureIndexSpecularTintMap, qualityLevel: nextLevel) {
            specularTintMapWeight = mapWeight
        }
        
        if !RenderUtilities.hasTexture(for: kTextureIndexAnisotropicMap, qualityLevel: quality) {
            anisotropicMapWeight = 0
        } else if RenderUtilities.hasTexture(for: kTextureIndexAnisotropicMap, qualityLevel: quality) && !RenderUtilities.hasTexture(for: kTextureIndexAnisotropicMap, qualityLevel: nextLevel) {
            anisotropicMapWeight = mapWeight
        }
        
        if !RenderUtilities.hasTexture(for: kTextureIndexSheenMap, qualityLevel: quality) {
            sheenMapWeight = 0
        } else if RenderUtilities.hasTexture(for: kTextureIndexSheenMap, qualityLevel: quality) && !RenderUtilities.hasTexture(for: kTextureIndexSheenMap, qualityLevel: nextLevel) {
            sheenMapWeight = mapWeight
        }
        
        if !RenderUtilities.hasTexture(for: kTextureIndexSheenTintMap, qualityLevel: quality) {
            sheenTintMapWeight = 0
        } else if RenderUtilities.hasTexture(for: kTextureIndexSheenTintMap, qualityLevel: quality) && !RenderUtilities.hasTexture(for: kTextureIndexSheenTintMap, qualityLevel: nextLevel) {
            sheenTintMapWeight = mapWeight
        }
        
        if !RenderUtilities.hasTexture(for: kTextureIndexClearcoatMap, qualityLevel: quality) {
            clearcoatMapWeight = 0
        } else if RenderUtilities.hasTexture(for: kTextureIndexClearcoatMap, qualityLevel: quality) && !RenderUtilities.hasTexture(for: kTextureIndexClearcoatMap, qualityLevel: nextLevel) {
            clearcoatMapWeight = mapWeight
        }
        
        if !RenderUtilities.hasTexture(for: kTextureIndexClearcoatGlossMap, qualityLevel: quality) {
            clearcoatMapWeightGlossMapWeight = 0
        } else if RenderUtilities.hasTexture(for: kTextureIndexClearcoatGlossMap, qualityLevel: quality) && !RenderUtilities.hasTexture(for: kTextureIndexClearcoatGlossMap, qualityLevel: nextLevel) {
            clearcoatMapWeightGlossMapWeight = mapWeight
        }
        
        return (baseMapWeight, normalMapWeight, metallicMapWeight, roughnessMapWeight, ambientOcclusionMapWeight, emissionMapWeight, subsurfaceMapWeight, specularMapWeight, specularTintMapWeight, anisotropicMapWeight, sheenMapWeight, sheenTintMapWeight, clearcoatMapWeight, clearcoatMapWeightGlossMapWeight)
    }
    
    fileprivate func getMapWeight(for level: QualityLevel, distance: Float) -> Float {
        
        guard AKCapabilities.LevelOfDetail else {
            return 1
        }
        
        guard distance > 0 else {
            return 1
        }
        
        // In meters
        let MediumQualityDepth: Float = 15
        let LowQualityDepth: Float = 65
        let TransitionDepthAmount: Float = 50
        
        if level == kQualityLevelHigh {
            let TransitionDepth = MediumQualityDepth - TransitionDepthAmount
            if distance > TransitionDepth {
                return 1 - ((distance - TransitionDepth) / TransitionDepthAmount)
            } else {
                return 1
            }
        } else if level == kQualityLevelMedium {
            let TransitionDepth = LowQualityDepth - TransitionDepthAmount
            if distance > TransitionDepth {
                return 1 - ((distance - TransitionDepth) / TransitionDepthAmount)
            } else {
                return 1
            }
        } else {
            return 0
        }
        
    }
    
}
