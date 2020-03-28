//
//  PathsRenderModule.swift
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

// TODO: Use a custom shader. The Anchor shader is best suited for rendering
// existing models, not dynamicly drawn content. Instead, create a new shader
// that lets us dynamicaly manipulate properties such as color at runtime.

import Foundation
import ARKit
import AugmentKitShader
import MetalKit

class PathsRenderModule: RenderModule {
    
    static var identifier = "PathsRenderModule"
    
    //
    // Setup
    //
    
    var moduleIdentifier: String {
        return PathsRenderModule.identifier
    }
    var renderLayer: Int {
        return 10
    }
    var state: ShaderModuleState = .uninitialized
    var sharedModuleIdentifiers: [String]? = [SharedBuffersRenderModule.identifier]
    var renderDistance: Double = 500
    var errors = [AKError]()
    
    // The number of path instances to render
    private(set) var pathSegmentInstanceCount: Int = 0
    
    // The UUID's of the anchors in the ARFrame.anchors array which mark the path.
    // Indexed by path
    private(set) var anchorIdentifiers = [Int: [UUID]]()
    
    func initializeBuffers(withDevice aDevice: MTLDevice, maxInFlightFrames: Int, maxInstances: Int) {
        
        state = .initializing
        
        device = aDevice
        
        // Calculate our uniform buffer sizes. We allocate `maxInFlightFrames` instances for uniform
        // storage in a single buffer. This allows us to update uniforms in a ring (i.e. triple
        // buffer the uniforms) so that the GPU reads from one slot in the ring wil the CPU writes
        // to another. Path uniforms should be specified with a max instance count for instancing.
        // Also uniform storage must be aligned (to 256 bytes) to meet the requirements to be an
        // argument in the constant address space of our shading functions.
        let materialUniformBufferSize = RenderModuleConstants.alignedMaterialSize * maxInFlightFrames
        let effectsUniformBufferSize = Constants.alignedEffectsUniformSize * maxInFlightFrames
        
        materialUniformBuffer = device?.makeBuffer(length: materialUniformBufferSize, options: .storageModeShared)
        materialUniformBuffer?.label = "MaterialUniformBuffer"
        
        effectsUniformBuffer = device?.makeBuffer(length: effectsUniformBufferSize, options: .storageModeShared)
        effectsUniformBuffer?.label = "EffectsUniformBuffer"
        
        geometricEntities = []
        
    }
    
    func loadAssets(forGeometricEntities theGeometricEntities: [AKGeometricEntity], fromModelProvider: ModelProvider?, textureLoader: MTKTextureLoader, completion: (() -> Void)) {
        
        guard let device = device else {
            print("Serious Error - device not found")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeDeviceNotFound, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            completion()
            return
        }
        
        // Create a MetalKit mesh buffer allocator so that ModelIO will load mesh data directly into
        // Metal buffers accessible by the GPU
        let metalAllocator = MTKMeshBufferAllocator(device: device)
        // Create a cylinder that is 10cm in diameter
        let mesh = MDLMesh.newCylinder(withHeight: 1, radii: SIMD2<Float>(0.05, 0.05), radialSegments: 6, verticalSegments: 1, geometryType: .triangles, inwardNormals: false, allocator: metalAllocator)
        let scatteringFunction = MDLScatteringFunction()
        let material = MDLMaterial(name: "AKPathSegmentAnchor - baseMaterial", scatteringFunction: scatteringFunction)
        // TODO: Get color from the renderer as passed from the users setup
        let colorProperty = MDLMaterialProperty(name: "pathColor", semantic: .baseColor, float4: SIMD4<Float>(1, 1, 1, 1))
        material.setProperty(colorProperty)
        
        for submesh in mesh.submeshes!  {
            if let submesh = submesh as? MDLSubmesh {
                submesh.material = material
            }
        }
       
        let asset = MDLAsset(bufferAllocator: metalAllocator)
        asset.add(mesh)
        
        pathSegmentAsset = asset
        
        geometricEntities.append(contentsOf: theGeometricEntities)
    
        completion()
        
    }
    
    func loadPipeline(withModuleEntities: [AKEntity], metalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider, textureBundle: Bundle, renderPass: RenderPass? = nil, numQualityLevels: Int = 1, completion: (([DrawCallGroup]) -> Void)? = nil) {
        
        guard let renderPass = renderPass else {
            print("Warning - Skipping all draw calls because the render pass is nil.")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeRenderPassNotFound, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            state = .ready
            completion?([])
            return
        }
        
        guard let device = device else {
            print("Serious Error - device not found")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeDeviceNotFound, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            state = .uninitialized
            completion?([])
            return
        }
        
        guard let pathSegmentAsset = pathSegmentAsset else {
            print("Serious Error - pathSegmentAsset not found")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeModelNotFound, userInfo: nil)
            let newError = AKError.warning(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            state = .uninitialized
            completion?([])
            return
        }
        
        DispatchQueue.global(qos: .default).async { [weak self] in
            
            var drawCallGroups = [DrawCallGroup]()
            
            guard let geometricEntities = self?.geometricEntities else {
                DispatchQueue.main.async { [weak self] in
                    self?.state = .ready
                    completion?(drawCallGroups)
                }
                return
            }
            
            let meshGPUData = ModelIOTools.meshGPUData(from: pathSegmentAsset, device: device, vertexDescriptor: RenderUtilities.createStandardVertexDescriptor(), loadTextures: renderPass.usesLighting, textureBundle: textureBundle)
            
            // Create a draw call group for every model asset. Each model asset may have multiple instances.
            for geometricEntity in geometricEntities {
                
                let uuid = geometricEntity.identifier ?? UUID()
                
                // Create a draw call group that contins all of the individual draw calls for this model
                if let drawCallGroup = self?.createDrawCallGroup(forUUID: uuid, withMetalLibrary: metalLibrary, renderDestination: renderDestination, renderPass: renderPass, meshGPUData: meshGPUData, geometricEntity: geometricEntity, numQualityLevels: numQualityLevels) {
                    drawCallGroup.moduleIdentifier = PathsRenderModule.identifier
                    drawCallGroups.append(drawCallGroup)
                }
            }
            
            // Because there must be a deterministic way to order the draw calls so the draw call groups are sorted by UUID.
            drawCallGroups.sort { $0.uuid.uuidString < $1.uuid.uuidString }
            DispatchQueue.main.async { [weak self] in
                self?.state = .ready
                completion?(drawCallGroups)
            }
        }
        
    }
    
    //
    // Per Frame Updates
    //
    
    func updateBufferState(withBufferIndex theBufferIndex: Int) {
        
        bufferIndex = theBufferIndex
        
        materialUniformBufferOffset = RenderModuleConstants.alignedMaterialSize * bufferIndex
        effectsUniformBufferOffset = Constants.alignedEffectsUniformSize * bufferIndex
        
        materialUniformBufferAddress = materialUniformBuffer?.contents().advanced(by: materialUniformBufferOffset)
        effectsUniformBufferAddress = effectsUniformBuffer?.contents().advanced(by: effectsUniformBufferOffset)
        
    }
    
    func updateBuffers(withModuleEntities moduleEntities: [AKEntity], cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties, shadowProperties: ShadowProperties, argumentBufferProperties theArgumentBufferProperties: ArgumentBufferProperties, forRenderPass renderPass: RenderPass) {
        
        argumentBufferProperties = theArgumentBufferProperties
        
        let paths: [AKPath] = moduleEntities.compactMap({
            if let anPath = $0 as? AKPath {
                return anPath
            } else {
                return nil
            }
        })
        var allSegments = [AKPathSegmentAnchor]()
        var effectsBySegmentUUID = [UUID: [AnyEffect<Any>]]()
        paths.forEach({ aPath in
            allSegments.append(contentsOf: aPath.segmentPoints)
            aPath.segmentPoints.forEach{ aSegment in
                if let uuid = aSegment.identifier {
                    if let segmentEffects = aSegment.effects {
                        effectsBySegmentUUID[uuid] = segmentEffects
                    } else {
                        effectsBySegmentUUID[uuid] = aPath.effects
                    }
                }
            }
        })
        
        // Update the anchor uniform buffer with transforms of the current frame's anchors
        pathSegmentInstanceCount = min(allSegments.count, Constants.maxPathSegmentInstanceCount)
        var meshIndex = 0
        anchorIdentifiers = [:]
        let renderSphere = AKSphere(center: AKVector(cameraProperties.position), radius: renderDistance)
        
        // update path transforms
        paths.forEach {$0.updateSegmentTransforms(withRenderSphere: renderSphere)}
        
        for drawCallGroup in renderPass.drawCallGroups {
            
            let uuid = drawCallGroup.uuid
            
            let effects = effectsBySegmentUUID[uuid]
            
            for _ in drawCallGroup.drawCalls {
                
                //
                // Update Effects uniform
                //
                
                let effectsUniforms = effectsUniformBufferAddress?.assumingMemoryBound(to: AnchorEffectsUniforms.self).advanced(by: meshIndex)
                var hasSetAlpha = false
                var hasSetGlow = false
                var hasSetTint = false
                var hasSetScale = false
                if let effects = effects {
                    let currentTime: TimeInterval = Double(cameraProperties.currentFrame) / cameraProperties.frameRate
                    for effect in effects {
                        switch effect.effectType {
                        case .alpha:
                            if let value = effect.value(forTime: currentTime) as? Float {
                                effectsUniforms?.pointee.alpha = value
                                hasSetAlpha = true
                            }
                        case .glow:
                            if let value = effect.value(forTime: currentTime) as? Float {
                                effectsUniforms?.pointee.glow = value
                                hasSetGlow = true
                            }
                        case .tint:
                            if let value = effect.value(forTime: currentTime) as? SIMD3<Float> {
                                effectsUniforms?.pointee.tint = value
                                hasSetTint = true
                            }
                        case .scale:
                            if let value = effect.value(forTime: currentTime) as? Float {
                                let scaleMatrix = matrix_identity_float4x4
                                effectsUniforms?.pointee.scale = scaleMatrix.scale(x: value, y: value, z: value)
                                hasSetScale = true
                            }
                        }
                    }
                }
                if !hasSetAlpha {
                    effectsUniforms?.pointee.alpha = 1
                }
                if !hasSetGlow {
                    effectsUniforms?.pointee.glow = 0
                }
                if !hasSetTint {
                    effectsUniforms?.pointee.tint = SIMD3<Float>(1,1,1)
                }
                if !hasSetScale {
                    effectsUniforms?.pointee.scale = matrix_identity_float4x4
                }
                
                meshIndex += 1
                
            }
            
        }
        
        pathSegmentInstanceCount = meshIndex
        
        //
        // Update the shadow map
        //
        shadowMap = shadowProperties.shadowMap
        
    }
    
    func draw(withRenderPass renderPass: RenderPass, sharedModules: [SharedRenderModule]?) {
        
        guard let renderEncoder = renderPass.renderCommandEncoder else {
            return
        }
        
        guard pathSegmentInstanceCount > 0 else {
            return
        }
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("Draw Paths")
        
        // Set render command encoder state
        renderEncoder.setCullMode(.back)
        
        if let argumentBufferProperties = argumentBufferProperties, let vertexArgumentBuffer = argumentBufferProperties.vertexArgumentBuffer {
            renderEncoder.pushDebugGroup("Argument Buffer")
            renderEncoder.setVertexBuffer(vertexArgumentBuffer, offset: argumentBufferProperties.vertexArgumentBufferOffset(forFrame: bufferIndex), index: Int(kBufferIndexPrecalculationOutputBuffer.rawValue))
            renderEncoder.popDebugGroup()
        }
        
        if let effectsBuffer = effectsUniformBuffer {
            
            renderEncoder.pushDebugGroup("Draw Effects Uniforms")
            renderEncoder.setFragmentBuffer(effectsBuffer, offset: effectsUniformBufferOffset, index: Int(kBufferIndexAnchorEffectsUniforms.rawValue))
            renderEncoder.popDebugGroup()
            
        }
        
        if let shadowMap = shadowMap, renderPass.usesShadows {
            
            renderEncoder.pushDebugGroup("Attach Shadow Buffer")
            renderEncoder.setFragmentTexture(shadowMap, index: Int(kTextureIndexShadowMap.rawValue))
            renderEncoder.popDebugGroup()
            
        }
        
        var drawCallGroupIndex: Int32 = 0
        var drawCallIndex: Int32 = 0
        
        for drawCallGroup in renderPass.drawCallGroups {
            
            guard drawCallGroup.moduleIdentifier == moduleIdentifier else {
                drawCallIndex += Int32(drawCallGroup.drawCalls.count)
                drawCallGroupIndex += 1
                continue
            }
            
            // Use the render pass filter function to skip draw call groups on an individual basis
            if let filterFunction = renderPass.drawCallGroupFilterFunction {
                guard filterFunction(drawCallGroup) else {
                    drawCallIndex += Int32(drawCallGroup.drawCalls.count)
                    drawCallGroupIndex += 1
                    continue
                }
            }
            
            for drawCall in drawCallGroup.drawCalls {
                
                guard let drawData = drawCall.drawData else {
                    drawCallIndex += 1
                    continue
                }
                
                drawCall.prepareDrawCall(withRenderPass: renderPass)
                
                if renderPass.usesGeometry {
                    // Set the offset index of the draw call into the argument buffer
                    renderEncoder.setVertexBytes(&drawCallIndex, length: MemoryLayout<Int32>.size, index: Int(kBufferIndexDrawCallIndex.rawValue))
                    // Set the offset index of the draw call group into the argument buffer
                    renderEncoder.setVertexBytes(&drawCallGroupIndex, length: MemoryLayout<Int32>.size, index: Int(kBufferIndexDrawCallGroupIndex.rawValue))
                }
                
                var mutableDrawData = drawData
                mutableDrawData.instanceCount = pathSegmentInstanceCount
                
                // Set the mesh's vertex data buffers and draw
                draw(withDrawData: mutableDrawData, with: renderEncoder, includeGeometry: renderPass.usesGeometry, includeLighting: renderPass.usesLighting)
                
                drawCallIndex += 1
                
            }
            
            drawCallGroupIndex += 1
            
        }
        
        renderEncoder.popDebugGroup()
        
    }
    
    func frameEncodingComplete(renderPasses: [RenderPass]) {
        //
    }
    
    //
    // Util
    //
    
    func recordNewError(_ akError: AKError) {
        errors.append(akError)
    }
    
    // MARK: - Private
    
    private var bufferIndex: Int = 0
    private var device: MTLDevice?
    private var textureLoader: MTKTextureLoader?
    private var geometricEntities = [AKGeometricEntity]()
    private var pathSegmentAsset: MDLAsset?
    private var materialUniformBuffer: MTLBuffer?
    private var effectsUniformBuffer: MTLBuffer?
    private var shadowMap: MTLTexture?
    private var argumentBufferProperties: ArgumentBufferProperties?
    
    // Offset within materialUniformBuffer to set for the current frame
    private var materialUniformBufferOffset: Int = 0
    
    // Offset within effectsUniformBuffer to set for the current frame
    private var effectsUniformBufferOffset: Int = 0
    
    // Addresses to write material uniforms to each frame
    private var materialUniformBufferAddress: UnsafeMutableRawPointer?
    
    // Addresses to write material uniforms to each frame
    private var effectsUniformBufferAddress: UnsafeMutableRawPointer?
    
    private enum Constants {
        static let maxPathSegmentInstanceCount = 2048
        // Paths use the same uniform struct as anchors
        static let alignedPathSegmentInstanceUniformsSize = ((MemoryLayout<AnchorInstanceUniforms>.stride * Constants.maxPathSegmentInstanceCount) & ~0xFF) + 0x100
        static let alignedEffectsUniformSize = ((MemoryLayout<AnchorEffectsUniforms>.stride * Constants.maxPathSegmentInstanceCount) & ~0xFF) + 0x100
    }
    
    // number of frames in the path animation by path index
    private var pathAnimationFrameCount = [Int]()
    
    private func createVertexDescriptor() -> MDLVertexDescriptor {
        
        // Create a vertex descriptor for our image plane vertex buffer
        let pathsVertexDescriptor = MTLVertexDescriptor()
        
        //
        // Attributes
        //
        
        // -------- Buffer 0 --------
        
        // Positions
        pathsVertexDescriptor.attributes[Int(kVertexAttributePosition.rawValue)].format = .float3 // 12 bytes
        pathsVertexDescriptor.attributes[Int(kVertexAttributePosition.rawValue)].offset = 0
        pathsVertexDescriptor.attributes[Int(kVertexAttributePosition.rawValue)].bufferIndex = Int(kBufferIndexMeshPositions.rawValue)
        
        // -------- Buffer 1 --------
        
        // Texture coordinates
        pathsVertexDescriptor.attributes[Int(kVertexAttributeTexcoord.rawValue)].format = .float2 // 8 bytes
        pathsVertexDescriptor.attributes[Int(kVertexAttributeTexcoord.rawValue)].offset = 0
        pathsVertexDescriptor.attributes[Int(kVertexAttributeTexcoord.rawValue)].bufferIndex = Int(kBufferIndexMeshGenerics.rawValue)
        
        // Normals
        pathsVertexDescriptor.attributes[Int(kVertexAttributeNormal.rawValue)].format = .float3 // 12 bytes
        pathsVertexDescriptor.attributes[Int(kVertexAttributeNormal.rawValue)].offset = 8
        pathsVertexDescriptor.attributes[Int(kVertexAttributeNormal.rawValue)].bufferIndex = Int(kBufferIndexMeshGenerics.rawValue)
        
        // Color
        pathsVertexDescriptor.attributes[Int(kVertexAttributeColor.rawValue)].format = .float3 // 12 bytes
        pathsVertexDescriptor.attributes[Int(kVertexAttributeColor.rawValue)].offset = 20
        pathsVertexDescriptor.attributes[Int(kVertexAttributeColor.rawValue)].bufferIndex = Int(kBufferIndexMeshGenerics.rawValue)
        
        //
        // Layouts
        //
        
        // Position Buffer Layout
        pathsVertexDescriptor.layouts[0].stride = 12
        pathsVertexDescriptor.layouts[0].stepRate = 1
        pathsVertexDescriptor.layouts[0].stepFunction = .perVertex
        
        // Generic Attribute Buffer Layout
        pathsVertexDescriptor.layouts[1].stride = 32
        pathsVertexDescriptor.layouts[1].stepRate = 1
        pathsVertexDescriptor.layouts[1].stepFunction = .perVertex
        
        //
        // Creata a Model IO vertexDescriptor so that we format/layout our model IO mesh vertices to
        // fit our Metal render pipeline's vertex descriptor layout
        //
        
        let vertexDescriptor = MTKModelIOVertexDescriptorFromMetal(pathsVertexDescriptor)
        
        // Indicate how each Metal vertex descriptor attribute maps to each ModelIO attribute
        (vertexDescriptor.attributes[Int(kVertexAttributePosition.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributePosition
        (vertexDescriptor.attributes[Int(kVertexAttributeTexcoord.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributeTextureCoordinate
        (vertexDescriptor.attributes[Int(kVertexAttributeNormal.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributeNormal
        (vertexDescriptor.attributes[Int(kVertexAttributeColor.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributeColor
        
        return vertexDescriptor
        
    }
    
    private func createDrawCallGroup(forUUID uuid: UUID, withMetalLibrary metalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider, renderPass: RenderPass?, meshGPUData: MeshGPUData, geometricEntity: AKGeometricEntity, numQualityLevels: Int) -> DrawCallGroup {
        
        guard let renderPass = renderPass else {
            print("Warning - Skipping all draw calls because the render pass is nil.")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeRenderPassNotFound, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return DrawCallGroup(drawCalls: [], uuid: uuid)
        }
        
        // Create a draw call group containing draw calls. Each draw call is associated with a `DrawData` object in the `MeshGPUData`
        var drawCalls = [DrawCall]()
        for drawData in meshGPUData.drawData {
            let drawCall = DrawCall(metalLibrary: metalLibrary, renderPass: renderPass, vertexFunctionName: "pathVertexShader", fragmentFunctionName: "pathFragmentShader", vertexDescriptor: meshGPUData.vertexDescriptor, drawData: drawData, numQualityLevels: numQualityLevels)
            drawCalls.append(drawCall)
        }
        
        let drawCallGroup = DrawCallGroup(drawCalls: drawCalls, uuid: uuid, generatesShadows: geometricEntity.generatesShadows)
        return drawCallGroup
        
    }
    
}
