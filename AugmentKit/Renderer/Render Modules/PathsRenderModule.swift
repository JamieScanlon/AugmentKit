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
    var isInitialized: Bool = false
    var sharedModuleIdentifiers: [String]? = [SharedBuffersRenderModule.identifier]
    var renderDistance: Double = 500
    var errors = [AKError]()
    
    // The number of path instances to render
    private(set) var pathSegmentInstanceCount: Int = 0
    
    // The UUID's of the anchors in the ARFrame.anchors array which mark the path.
    // Indexed by path
    private(set) var anchorIdentifiers = [Int: [UUID]]()
    
    func initializeBuffers(withDevice aDevice: MTLDevice, maxInFlightBuffers: Int) {
        
        device = aDevice
        
        // Calculate our uniform buffer sizes. We allocate Constants.maxBuffersInFlight instances for uniform
        // storage in a single buffer. This allows us to update uniforms in a ring (i.e. triple
        // buffer the uniforms) so that the GPU reads from one slot in the ring wil the CPU writes
        // to another. Path uniforms should be specified with a max instance count for instancing.
        // Also uniform storage must be aligned (to 256 bytes) to meet the requirements to be an
        // argument in the constant address space of our shading functions.
        let pathUniformBufferSize = Constants.alignedPathSegmentInstanceUniformsSize * maxInFlightBuffers
        let materialUniformBufferSize = RenderModuleConstants.alignedMaterialSize * maxInFlightBuffers
        let effectsUniformBufferSize = Constants.alignedEffectsUniformSize * maxInFlightBuffers
        
        // Create and allocate our uniform buffer objects. Indicate shared storage so that both the
        // CPU can access the buffer
        pathUniformBuffer = device?.makeBuffer(length: pathUniformBufferSize, options: .storageModeShared)
        pathUniformBuffer?.label = "PathUniformBuffer"
        
        materialUniformBuffer = device?.makeBuffer(length: materialUniformBufferSize, options: .storageModeShared)
        materialUniformBuffer?.label = "MaterialUniformBuffer"
        
        effectsUniformBuffer = device?.makeBuffer(length: effectsUniformBufferSize, options: .storageModeShared)
        effectsUniformBuffer?.label = "EffectsUniformBuffer"
        
    }
    
    func loadAssets(forGeometricEntities: [AKGeometricEntity], fromModelProvider: ModelProvider?, textureLoader: MTKTextureLoader, completion: (() -> Void)) {
        
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
        let mesh = MDLMesh.newCylinder(withHeight: 1, radii: vector2(0.05, 0.05), radialSegments: 6, verticalSegments: 1, geometryType: .triangles, inwardNormals: false, allocator: metalAllocator)
        let scatteringFunction = MDLScatteringFunction()
        let material = MDLMaterial(name: "baseMaterial", scatteringFunction: scatteringFunction)
        // TODO: Get color from the renderer as passed from the users setup
        let colorProperty = MDLMaterialProperty(name: "pathColor", semantic: .baseColor, float3: float3(255/255, 255/255, 255/255))
        material.setProperty(colorProperty)
        
        for submesh in mesh.submeshes!  {
            if let submesh = submesh as? MDLSubmesh {
                submesh.material = material
            }
        }
       
        let asset = MDLAsset(bufferAllocator: metalAllocator)
        asset.add(mesh)
        
        pathSegmentAsset = asset
    
        completion()
        
    }
    
    func loadPipeline(withMetalLibrary metalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider, textureBundle: Bundle) {
        
        guard let device = device else {
            print("Serious Error - device not found")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeDeviceNotFound, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return
        }
        
        guard let pointVertexShader = metalLibrary.makeFunction(name: "pathVertexShader") else {
            print("Serious Error - failed to create the pathVertexShader function")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeShaderInitializationFailed, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return
        }
        
        guard let pointFragmentShader = metalLibrary.makeFunction(name: "pathFragmentShader") else {
            print("Serious Error - failed to create the pathFragmentShader function")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeShaderInitializationFailed, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return
        }
        
        guard let pathSegmentAsset = pathSegmentAsset else {
            print("Serious Error - pathSegmentAsset not found")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeModelNotFound, userInfo: nil)
            let newError = AKError.warning(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return
        }
        
        pathMeshGPUData = ModelIOTools.meshGPUData(from: pathSegmentAsset, device: device, textureBundle: textureBundle, vertexDescriptor: MetalUtilities.createStandardVertexDescriptor())
        
        guard let pathMeshGPUData = pathMeshGPUData else {
            print("Serious Error - ERROR: No meshGPUData for target found when trying to load the pipeline.")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeIntermediateMeshDataNotFound, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return
        }
        
        if pathMeshGPUData.drawData.count > 1 {
            print("WARNING: More than one mesh was found. Currently only one mesh per anchor is supported.")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeModelNotSupported, userInfo: nil)
            let newError = AKError.warning(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
        }
        
        let myVertexDescriptor = pathMeshGPUData.vertexDescriptors.first
        
        guard let pathVertexDescriptor = myVertexDescriptor else {
            print("Serious Error - Failed to create a MetalKit vertex descriptor from ModelIO.")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeInvalidMeshData, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return
        }
        
        for (_, _) in pathMeshGPUData.drawData.enumerated() {
            let pathPipelineStateDescriptor = MTLRenderPipelineDescriptor()
            pathPipelineStateDescriptor.vertexDescriptor = pathVertexDescriptor
            pathPipelineStateDescriptor.vertexFunction = pointVertexShader
            pathPipelineStateDescriptor.fragmentFunction = pointFragmentShader
            pathPipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
            pathPipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = true
            pathPipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            pathPipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            pathPipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
            pathPipelineStateDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
            pathPipelineStateDescriptor.sampleCount = renderDestination.sampleCount
            
            do {
                try pathPipelineStates.append(device.makeRenderPipelineState(descriptor: pathPipelineStateDescriptor))
            } catch let error {
                print("Failed to create pipeline state, error \(error)")
                let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: error))))
                recordNewError(newError)
            }
        }
        
        let pathDepthStateDescriptor = MTLDepthStencilDescriptor()
        pathDepthStateDescriptor.depthCompareFunction = .less
        pathDepthStateDescriptor.isDepthWriteEnabled = true
        pathDepthState = device.makeDepthStencilState(descriptor: pathDepthStateDescriptor)
        
        isInitialized = true
        
    }
    
    //
    // Per Frame Updates
    //
    
    func updateBufferState(withBufferIndex bufferIndex: Int) {
        
        pathUniformBufferOffset = Constants.alignedPathSegmentInstanceUniformsSize * bufferIndex
        materialUniformBufferOffset = RenderModuleConstants.alignedMaterialSize * bufferIndex
        effectsUniformBufferOffset = Constants.alignedEffectsUniformSize * bufferIndex
        
        pathUniformBufferAddress = pathUniformBuffer?.contents().advanced(by: pathUniformBufferOffset)
        materialUniformBufferAddress = materialUniformBuffer?.contents().advanced(by: materialUniformBufferOffset)
        effectsUniformBufferAddress = effectsUniformBuffer?.contents().advanced(by: effectsUniformBufferOffset)
        
    }
    
    func updateBuffers(withAugmentedAnchors anchors: [AKAugmentedAnchor], cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties) {
        // Do Nothing
    }
    
    func updateBuffers(withRealAnchors: [AKRealAnchor], cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties) {
        // Do Nothing
    }
    
    func updateBuffers(withTrackers: [AKAugmentedTracker], targets: [AKTarget], cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties) {
        // Do Nothing
    }
    
    func updateBuffers(withPaths paths: [AKPath], cameraProperties theCameraProperties: CameraProperties, environmentProperties: EnvironmentProperties) {
        
        // Update the anchor uniform buffer with transforms of the current frame's anchors
        pathSegmentInstanceCount = 0
        anchorIdentifiers = [:]
        
        for path in paths {
            
            var lastAnchor: AKAugmentedAnchor?
            var uuids = [UUID]()
            
            for anchor in path.segmentPoints {
                
                guard let myLastAnchor = lastAnchor else {
                    lastAnchor = anchor
                    continue
                }
                
                //
                // Update the Instance uniform
                //
                
                // Clip the paths to the render sphere
                let p0 = float3(myLastAnchor.worldLocation.transform.columns.3.x, myLastAnchor.worldLocation.transform.columns.3.y, myLastAnchor.worldLocation.transform.columns.3.z)
                let p1 = float3(anchor.worldLocation.transform.columns.3.x, anchor.worldLocation.transform.columns.3.y, anchor.worldLocation.transform.columns.3.z)
                let sphereIntersection = renderShpereIntersectionOfPath(withPoint0: p0, point1: p1, cameraProperties: theCameraProperties)
                guard sphereIntersection.isInside else {
                    lastAnchor = anchor
                    continue
                }
                
                pathSegmentInstanceCount += 1
                
                if pathSegmentInstanceCount > Constants.maxPathSegmentInstanceCount {
                    pathSegmentInstanceCount = Constants.maxPathSegmentInstanceCount
                    break
                }
                
                if let identifier = anchor.identifier {
                    uuids.append(identifier)
                }
                
                let lastAnchorPosition = sphereIntersection.point0
                let anchorPosition = sphereIntersection.point1
                
                
                // Ignore all rotation within anchor.worldLocation.transform.
                // When dealing with paths, the anchors are considered points in space so rotation has no meaning.
                var modelMatrix = matrix_identity_float4x4.translate(x: anchorPosition.x, y: anchorPosition.y, z: anchorPosition.z)
                
                // Flip Z axis to convert geometry from right handed to left handed
                var coordinateSpaceTransform = matrix_identity_float4x4
                coordinateSpaceTransform.columns.2.z = -1.0
                
                // Rotate and scale coordinateSpaceTransform so that it is oriented from
                // myLastAnchor to anchor
                
                // Do all calculations with doubles and convert them to floats a the end.
                // This reduces floating point rounding errors especially when calculating
                // andgles of rotation
                
                let finalPosition = double3(0, 0, 0)
                let initialPosition = double3(Double(lastAnchorPosition.x - anchorPosition.x), Double(lastAnchorPosition.y - anchorPosition.y), Double(lastAnchorPosition.z - anchorPosition.z))
                
                // The following was taken from: http://www.thjsmith.com/40/cylinder-between-two-points-opengl-c
                // Default cylinder direction (up)
                let defaultLineDirection = double3(0,1,0)
                // Get diff between two points you want cylinder along
                let delta = (finalPosition - initialPosition)
                // Get CROSS product (the axis of rotation)
                let t = cross(defaultLineDirection , normalize(delta))
                
                // Get the magnitude of the vector
                let magDelta = length(delta)
                // Get angle (radians)
                let angle = acos(dot(defaultLineDirection, delta) / magDelta)
                
                // The cylinder created by MDLMesh extends from (0, -0.5, 0) to (0, 0.5, 0). Translate it so that it is
                // midway between the two points
                let middle = -delta / 2
                coordinateSpaceTransform = coordinateSpaceTransform.translate(x: Float(middle.x), y: Float(middle.y), z: Float(-middle.z))
                if angle == Double.pi {
                    coordinateSpaceTransform = coordinateSpaceTransform.rotate(radians: Float(angle), x: 0, y: 0, z: 1)
                } else if Float(angle) > 0 {
                    coordinateSpaceTransform = coordinateSpaceTransform.rotate(radians: Float(angle), x: Float(t.x), y: Float(t.y), z: Float(-t.z))
                }
                coordinateSpaceTransform = coordinateSpaceTransform.scale(x: 1, y: Float(magDelta), z: 1)
                
                // Create the final transform matrix
                modelMatrix = modelMatrix * coordinateSpaceTransform
                
                // Paths use the same uniform struct as anchors
                let pathSegmentIndex = pathSegmentInstanceCount - 1
                let pathUniforms = pathUniformBufferAddress?.assumingMemoryBound(to: AnchorInstanceUniforms.self).advanced(by: pathSegmentIndex)
                pathUniforms?.pointee.modelMatrix = modelMatrix
                
                //
                // Update the Effects uniform
                //
                
                let effectsUniforms = effectsUniformBufferAddress?.assumingMemoryBound(to: AnchorEffectsUniforms.self).advanced(by: pathSegmentIndex)
                effectsUniforms?.pointee.alpha = 1 // TODO: Implement
                effectsUniforms?.pointee.glow = 0 // TODO: Implement
                effectsUniforms?.pointee.tint = float3(1,0.25,0.25) // TODO: Implement
                
                lastAnchor = anchor
                
            }
            
            if pathSegmentInstanceCount > 0 && pathSegmentInstanceCount < Constants.maxPathSegmentInstanceCount {
                anchorIdentifiers[pathSegmentInstanceCount - 1] = uuids
            }
            
        }
        
    }
    
    func draw(withRenderEncoder renderEncoder: MTLRenderCommandEncoder, sharedModules: [SharedRenderModule]?) {
        
        guard pathSegmentInstanceCount > 0 else {
            return
        }
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("Draw Paths")
        
        // Set render command encoder state
        renderEncoder.setCullMode(.back)
        
        guard let meshGPUData = pathMeshGPUData else {
            print("Error: meshGPUData not available a draw time. Aborting")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeIntermediateMeshDataNotAvailable, userInfo: nil)
            let newError = AKError.recoverableError(.renderPipelineError(.drawAborted(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return
        }
        
        if let sharedBuffer = sharedModules?.first(where: {$0.moduleIdentifier == SharedBuffersRenderModule.identifier}) {
            
            renderEncoder.pushDebugGroup("Draw Shared Uniforms")
            
            renderEncoder.setVertexBuffer(sharedBuffer.sharedUniformBuffer, offset: sharedBuffer.sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
            renderEncoder.setFragmentBuffer(sharedBuffer.sharedUniformBuffer, offset: sharedBuffer.sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
            
            renderEncoder.popDebugGroup()
            
        }
        
        if let effectsBuffer = effectsUniformBuffer {
            
            renderEncoder.pushDebugGroup("Draw Effects Uniforms")
            renderEncoder.setFragmentBuffer(effectsBuffer, offset: effectsUniformBufferOffset, index: Int(kBufferIndexAnchorEffectsUniforms.rawValue))
            renderEncoder.popDebugGroup()
            
        }
        
        for (drawDataIdx, drawData) in meshGPUData.drawData.enumerated() {
            
            if drawDataIdx < pathPipelineStates.count {
                renderEncoder.setRenderPipelineState(pathPipelineStates[drawDataIdx])
                renderEncoder.setDepthStencilState(pathDepthState)
                
                // Set any buffers fed into our render pipeline
                renderEncoder.setVertexBuffer(pathUniformBuffer, offset: pathUniformBufferOffset, index: Int(kBufferIndexAnchorInstanceUniforms.rawValue))
                
                var mutableDrawData = drawData
                mutableDrawData.instCount = pathSegmentInstanceCount
                
                // Set the mesh's vertex data buffers
                encode(meshGPUData: meshGPUData, fromDrawData: mutableDrawData, with: renderEncoder)
                
            }
            
        }
        
        renderEncoder.popDebugGroup()
        
    }
    
    func frameEncodingComplete() {
        //
    }
    
    //
    // Util
    //
    
    func recordNewError(_ akError: AKError) {
        errors.append(akError)
    }
    
    // MARK: - Private
    
    private var device: MTLDevice?
    private var textureLoader: MTKTextureLoader?
    private var pathSegmentAsset: MDLAsset?
    private var pathUniformBuffer: MTLBuffer?
    private var materialUniformBuffer: MTLBuffer?
    private var effectsUniformBuffer: MTLBuffer?
    private var pathPipelineStates = [MTLRenderPipelineState]() // Store multiple states
    private var pathDepthState: MTLDepthStencilState?
    
    // MetalKit meshes containing vertex data and index buffer for our geometry
    private var pathMeshGPUData: MeshGPUData?
    
    // Offset within pathUniformBuffer to set for the current frame
    private var pathUniformBufferOffset: Int = 0
    
    // Offset within materialUniformBuffer to set for the current frame
    private var materialUniformBufferOffset: Int = 0
    
    // Offset within effectsUniformBuffer to set for the current frame
    private var effectsUniformBufferOffset: Int = 0
    
    // Addresses to write path uniforms to each frame
    private var pathUniformBufferAddress: UnsafeMutableRawPointer?
    
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
        pathsVertexDescriptor.attributes[0].format = .float3 // 12 bytes
        pathsVertexDescriptor.attributes[0].offset = 0
        pathsVertexDescriptor.attributes[0].bufferIndex = Int(kBufferIndexMeshPositions.rawValue)
        
        // -------- Buffer 1 --------
        
        // Texture coordinates
        pathsVertexDescriptor.attributes[1].format = .float2 // 8 bytes
        pathsVertexDescriptor.attributes[1].offset = 0
        pathsVertexDescriptor.attributes[1].bufferIndex = Int(kBufferIndexMeshGenerics.rawValue)
        
        // Normals
        pathsVertexDescriptor.attributes[2].format = .float3 // 12 bytes
        pathsVertexDescriptor.attributes[2].offset = 8
        pathsVertexDescriptor.attributes[2].bufferIndex = Int(kBufferIndexMeshGenerics.rawValue)
        
        // Color
        pathsVertexDescriptor.attributes[5].format = .float3 // 12 bytes
        pathsVertexDescriptor.attributes[5].offset = 20
        pathsVertexDescriptor.attributes[5].bufferIndex = Int(kBufferIndexMeshGenerics.rawValue)
        
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
    
}
