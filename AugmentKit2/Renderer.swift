//
//  Renderer.swift
//  AugmentKit2
//
//  Created by Jamie Scanlon on 7/3/17.
//  Copyright © 2017 TenthLetterMade. All rights reserved.
//

import Foundation
import Metal
import MetalKit
import ARKit
import ModelIO

protocol RenderDestinationProvider {
    var currentRenderPassDescriptor: MTLRenderPassDescriptor? { get }
    var currentDrawable: CAMetalDrawable? { get }
    var colorPixelFormat: MTLPixelFormat { get set }
    var depthStencilPixelFormat: MTLPixelFormat { get set }
    var sampleCount: Int { get set }
}

protocol MeshProvider {
    func loadMesh(forType: MeshType, metalAllocator: MTKMeshBufferAllocator, completion: (MDLAsset?) -> Void)
}

enum MeshType {
    case anchor
    case horizPlane
    case vertPlane
}

class Renderer {
    
    // Debugging
    var useOldFlow = false
    
    enum Constants {
        static let maxBuffersInFlight = 3
        static let maxAnchorInstanceCount = 64
        
        // Captured Image Plane
        static let imagePlaneVertexData: [Float] = [
            -1.0, -1.0,  0.0, 1.0,
            1.0, -1.0,  1.0, 1.0,
            -1.0,  1.0,  0.0, 0.0,
            1.0,  1.0,  1.0, 0.0,
        ]
        
        // The 16 byte aligned size of our uniform structures
        static let alignedSharedUniformsSize = (MemoryLayout<SharedUniforms>.size & ~0xFF) + 0x100
        static let alignedMaterialSize = (MemoryLayout<MaterialUniforms>.stride & ~0xFF) + 0x100
        static let alignedInstanceUniformsSize = ((MemoryLayout<InstanceUniforms>.size * Constants.maxAnchorInstanceCount) & ~0xFF) + 0x100
    }
    
    let session: ARSession
    let device: MTLDevice
    var meshProvider: MeshProvider
    // Guide Meshes for debugging
    var showGuides = false {
        didSet {
            reset()
        }
    }
    
    init(session: ARSession, metalDevice device: MTLDevice, renderDestination: RenderDestinationProvider, meshProvider: MeshProvider) {
        self.session = session
        self.device = device
        self.renderDestination = renderDestination
        self.meshProvider = meshProvider
        self.textureLoader = MTKTextureLoader(device: device)
        
        if useOldFlow {
            loadMetal()
            loadAssets()
        } else {
            loadAssets()
            loadMetal()
        }
        reset()
    }
    
    func drawRectResized(size: CGSize) {
        viewportSize = size
        viewportSizeDidChange = true
    }
    
    func update() {
        
        // Wait to ensure only kMaxBuffersInFlight are getting proccessed by any stage in the Metal
        //   pipeline (App, Metal, Drivers, GPU, etc)
        let _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        // Create a new command buffer for each renderpass to the current drawable
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            commandBuffer.label = "MyCommand"
            
            // Add completion hander which signal _inFlightSemaphore when Metal and the GPU has fully
            //   finished proccssing the commands we're encoding this frame.  This indicates when the
            //   dynamic buffers, that we're writing to this frame, will no longer be needed by Metal
            //   and the GPU.
            // Retain our CVMetalTextures for the duration of the rendering cycle. The MTLTextures
            //   we use from the CVMetalTextures are not valid unless their parent CVMetalTextures
            //   are retained. Since we may release our CVMetalTexture ivars during the rendering
            //   cycle, we must retain them separately here.
            var textures = [capturedImageTextureY, capturedImageTextureCbCr]
            commandBuffer.addCompletedHandler{ [weak self] commandBuffer in
                if let strongSelf = self {
                    strongSelf.inFlightSemaphore.signal()
                }
                textures.removeAll()
            }
            
            updateBufferStates()
            updateBuffers()
            
            if let renderPassDescriptor = renderDestination.currentRenderPassDescriptor, let currentDrawable = renderDestination.currentDrawable, let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                
                renderEncoder.label = "MyRenderEncoder"
                
                drawCapturedImage(renderEncoder: renderEncoder)
                drawSharedUniforms(renderEncoder: renderEncoder)
                drawAnchors(renderEncoder: renderEncoder)
                drawGuides(renderEncoder: renderEncoder)
                
                // We're done encoding commands
                renderEncoder.endEncoding()
                
                // Schedule a present once the framebuffer is complete using the current drawable
                commandBuffer.present(currentDrawable)
            }
            
            // Finalize rendering here & push the command buffer to the GPU
            commandBuffer.commit()
        }
        
    }
    
    func run() {
        
        // Create a session configuration
        let configuration = ARWorldTrackingSessionConfiguration()
        if showGuides {
            configuration.planeDetection = .horizontal
        }
        session.run(configuration)
        
    }
    
    func pause() {
        session.pause()
    }
    
    func reset() {
        
        // Create a session configuration
        let configuration = ARWorldTrackingSessionConfiguration()
        if showGuides {
            configuration.planeDetection = .horizontal
        }
        session.run(configuration, options: [.removeExistingAnchors, .resetTracking])
        
    }
    
    // MARK: - Private
    
    private let textureLoader: MTKTextureLoader
    private let inFlightSemaphore = DispatchSemaphore(value: Constants.maxBuffersInFlight)
    private var renderDestination: RenderDestinationProvider
    private var modelParser: ModelParser?
    
    // Metal objects
    private var commandQueue: MTLCommandQueue!
    private var sharedUniformBuffer: MTLBuffer!
    private var anchorUniformBuffer: MTLBuffer!
    private var materialUniformBuffer: MTLBuffer!
    private var imagePlaneVertexBuffer: MTLBuffer!
    private var capturedImagePipelineState: MTLRenderPipelineState!
    private var capturedImageDepthState: MTLDepthStencilState!
    private var anchorPipelineState: MTLRenderPipelineState! // Old. Single state
    private var anchorPipelineStates = [MTLRenderPipelineState]() // New store multiple states
    private var anchorDepthState: MTLDepthStencilState!
    private var capturedImageTextureY: CVMetalTexture?
    private var capturedImageTextureCbCr: CVMetalTexture?
    
    // Captured image texture cache
    private var capturedImageTextureCache: CVMetalTextureCache!
    
    // Metal vertex descriptor specifying how vertices will by laid out for input into our
    //   anchor geometry render pipeline and how we'll layout our Model IO verticies
    private var geometryVertexDescriptor: MTLVertexDescriptor!
    
    // MetalKit mesh containing vertex data and index buffer for our anchor geometry
    private var anchorMesh: MTKMesh? // OLD
    private var meshGPUData: MeshGPUData? // NEW
    private var horizPlaneMesh: MTKMesh?
    private var vertPlaneMesh: MTKMesh?
    private var horizPlaneInstanceCount: Int = 0
    private var vertPlaneInstanceCount: Int = 0
    private var totalMeshTransforms = 1
    
    // Used to determine _uniformBufferStride each frame.
    //   This is the current frame number modulo kMaxBuffersInFlight
    private var uniformBufferIndex: Int = 0
    
    // Offset within _sharedUniformBuffer to set for the current frame
    private var sharedUniformBufferOffset: Int = 0
    
    // Offset within _anchorUniformBuffer to set for the current frame
    private var anchorUniformBufferOffset: Int = 0
    
    // Offset within _materialUniformBuffer to set for the current frame
    private var materialUniformBufferOffset: Int = 0
    
    // Addresses to write shared uniforms to each frame
    private var sharedUniformBufferAddress: UnsafeMutableRawPointer!
    
    // Addresses to write anchor uniforms to each frame
    private var anchorUniformBufferAddress: UnsafeMutableRawPointer!
    
    // Addresses to write anchor uniforms to each frame
    private var materialUniformBufferAddress: UnsafeMutableRawPointer!
    
    // The number of anchor instances to render
    private var anchorInstanceCount: Int = 0
    
    // The current viewport size
    private var viewportSize: CGSize = CGSize()
    
    // Flag for viewport size changes
    private var viewportSizeDidChange: Bool = false
    
    private var usesMaterials = false
    
    private func loadMetal() {
        
        //
        // Create and load our basic Metal state objects
        //
        
        // Set the default formats needed to render
        renderDestination.depthStencilPixelFormat = .depth32Float_stencil8
        renderDestination.colorPixelFormat = .bgra8Unorm
        renderDestination.sampleCount = 1
        
        // Calculate our uniform buffer sizes. We allocate Constants.maxBuffersInFlight instances for uniform
        //   storage in a single buffer. This allows us to update uniforms in a ring (i.e. triple
        //   buffer the uniforms) so that the GPU reads from one slot in the ring wil the CPU writes
        //   to another. Anchor uniforms should be specified with a max instance count for instancing.
        //   Also uniform storage must be aligned (to 256 bytes) to meet the requirements to be an
        //   argument in the constant address space of our shading functions.
        let sharedUniformBufferSize = Constants.alignedSharedUniformsSize * Constants.maxBuffersInFlight
        let anchorUniformBufferSize = Constants.alignedInstanceUniformsSize * Constants.maxBuffersInFlight * totalMeshTransforms
        let materialUniformBufferSize = Constants.alignedMaterialSize * Constants.maxBuffersInFlight
        
        // Create and allocate our uniform buffer objects. Indicate shared storage so that both the
        //   CPU can access the buffer
        sharedUniformBuffer = device.makeBuffer(length: sharedUniformBufferSize, options: .storageModeShared)
        sharedUniformBuffer.label = "SharedUniformBuffer"
        
        anchorUniformBuffer = device.makeBuffer(length: anchorUniformBufferSize, options: .storageModeShared)
        anchorUniformBuffer.label = "AnchorUniformBuffer"
        
        materialUniformBuffer = device.makeBuffer(length: materialUniformBufferSize, options: .storageModeShared)
        materialUniformBuffer.label = "MaterialUniformBuffer"
        
        // Load all the shader files with a metal file extension in the project
        let defaultLibrary = device.makeDefaultLibrary()!
        
        //
        // Image Capture Plane
        //
        
        // Create a vertex buffer with our image plane vertex data.
        let imagePlaneVertexDataCount = Constants.imagePlaneVertexData.count * MemoryLayout<Float>.size
        imagePlaneVertexBuffer = device.makeBuffer(bytes: Constants.imagePlaneVertexData, length: imagePlaneVertexDataCount, options: [])
        imagePlaneVertexBuffer.label = "ImagePlaneVertexBuffer"
        
        let capturedImageVertexFunction = defaultLibrary.makeFunction(name: "capturedImageVertexTransform")!
        let capturedImageFragmentFunction = defaultLibrary.makeFunction(name: "capturedImageFragmentShader")!
        
        // Create a vertex descriptor for our image plane vertex buffer
        let imagePlaneVertexDescriptor = MTLVertexDescriptor()
        
        // Positions.
        imagePlaneVertexDescriptor.attributes[0].format = .float2
        imagePlaneVertexDescriptor.attributes[0].offset = 0
        imagePlaneVertexDescriptor.attributes[0].bufferIndex = Int(kBufferIndexMeshPositions.rawValue)
        
        // Texture coordinates.
        imagePlaneVertexDescriptor.attributes[1].format = .float2
        imagePlaneVertexDescriptor.attributes[1].offset = 8
        imagePlaneVertexDescriptor.attributes[1].bufferIndex = Int(kBufferIndexMeshPositions.rawValue)
        
        // Buffer Layout
        imagePlaneVertexDescriptor.layouts[0].stride = 16
        imagePlaneVertexDescriptor.layouts[0].stepRate = 1
        imagePlaneVertexDescriptor.layouts[0].stepFunction = .perVertex
        
        // Create a pipeline state for rendering the captured image
        let capturedImagePipelineStateDescriptor = MTLRenderPipelineDescriptor()
        capturedImagePipelineStateDescriptor.label = "MyCapturedImagePipeline"
        capturedImagePipelineStateDescriptor.sampleCount = renderDestination.sampleCount
        capturedImagePipelineStateDescriptor.vertexFunction = capturedImageVertexFunction
        capturedImagePipelineStateDescriptor.fragmentFunction = capturedImageFragmentFunction
        capturedImagePipelineStateDescriptor.vertexDescriptor = imagePlaneVertexDescriptor
        capturedImagePipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        capturedImagePipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        capturedImagePipelineStateDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        
        do {
            try capturedImagePipelineState = device.makeRenderPipelineState(descriptor: capturedImagePipelineStateDescriptor)
        } catch let error {
            print("Failed to create captured image pipeline state, error \(error)")
            return
        }
        
        let capturedImageDepthStateDescriptor = MTLDepthStencilDescriptor()
        capturedImageDepthStateDescriptor.depthCompareFunction = .always
        capturedImageDepthStateDescriptor.isDepthWriteEnabled = false
        capturedImageDepthState = device.makeDepthStencilState(descriptor: capturedImageDepthStateDescriptor)
        
        // Create captured image texture cache
        var textureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        capturedImageTextureCache = textureCache
        
        //
        // Anchors
        //
        
        // Create a vertex descriptor for our Metal pipeline. Specifies the layout of vertices the
        //   pipeline should expect. The layout below keeps attributes used to calculate vertex shader
        //   output position separate (world position, skinning, tweening weights) separate from other
        //   attributes (texture coordinates, normals).  This generally maximizes pipeline efficiency
        
        
        if useOldFlow {
            
            // Old.
            
            let funcConstants = MetalUtilities.getFuncConstantsForDrawDataSet(meshData: nil, useMaterials: false)
            let anchorGeometryVertexFunction: MTLFunction = {
                do {
                    return try defaultLibrary.makeFunction(name: "anchorGeometryVertexTransform", constantValues: funcConstants)
                } catch let error {
                    print("Failed to create anchor vertex and fragment functions, error \(error)")
                    fatalError()
                }
            }()
            let anchorGeometryFragmentFunction: MTLFunction = {
                do {
                    return try defaultLibrary.makeFunction(name: "anchorGeometryFragmentLighting", constantValues: funcConstants)
                } catch let error {
                    print("Failed to create anchor vertex and fragment functions, error \(error)")
                    fatalError()
                }
            }()
            
            geometryVertexDescriptor = MTLVertexDescriptor()
            
            // Positions.
            geometryVertexDescriptor.attributes[0].format = .float3
            geometryVertexDescriptor.attributes[0].offset = 0
            geometryVertexDescriptor.attributes[0].bufferIndex = Int(kBufferIndexMeshPositions.rawValue)
            
            // Texture coordinates.
            geometryVertexDescriptor.attributes[1].format = .float2
            geometryVertexDescriptor.attributes[1].offset = 0
            geometryVertexDescriptor.attributes[1].bufferIndex = Int(kBufferIndexMeshGenerics.rawValue)
            
            // Normals.
            geometryVertexDescriptor.attributes[2].format = .half3
            geometryVertexDescriptor.attributes[2].offset = 8
            geometryVertexDescriptor.attributes[2].bufferIndex = Int(kBufferIndexMeshGenerics.rawValue)
            
            // TODO: JointIndices and JointWeights for Puppet animations
            
            // Position Buffer Layout
            geometryVertexDescriptor.layouts[0].stride = 12
            geometryVertexDescriptor.layouts[0].stepRate = 1
            geometryVertexDescriptor.layouts[0].stepFunction = .perVertex
            
            // Generic Attribute Buffer Layout
            geometryVertexDescriptor.layouts[1].stride = 16
            geometryVertexDescriptor.layouts[1].stepRate = 1
            geometryVertexDescriptor.layouts[1].stepFunction = .perVertex
            
            // Create a reusable pipeline state for rendering anchor geometry
            let anchorPipelineStateDescriptor = MTLRenderPipelineDescriptor()
            anchorPipelineStateDescriptor.label = "MyAnchorPipeline"
            anchorPipelineStateDescriptor.sampleCount = renderDestination.sampleCount
            anchorPipelineStateDescriptor.vertexFunction = anchorGeometryVertexFunction
            anchorPipelineStateDescriptor.fragmentFunction = anchorGeometryFragmentFunction
            anchorPipelineStateDescriptor.vertexDescriptor = geometryVertexDescriptor
            anchorPipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
            anchorPipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
            anchorPipelineStateDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
     
            do {
                try anchorPipelineState = device.makeRenderPipelineState(descriptor: anchorPipelineStateDescriptor)
            } catch let error {
                print("Failed to created anchor geometry pipeline state, error \(error)")
            }
        } else {
        
            // NEW
            
            guard let modelParser = modelParser else {
                print("Model Perser is nil.")
                fatalError()
                return
            }
            
            let anchorVertexDescriptor = createVertexDescriptor(with: modelParser.vertexDescriptors)
            
            if let meshGPUData = meshGPUData {
                for (drawIdx, drawData) in meshGPUData.drawData.enumerated() {
                    let anchorPipelineStateDescriptor = MTLRenderPipelineDescriptor()
                    do {
                        let funcConstants = MetalUtilities.getFuncConstantsForDrawDataSet(meshData: modelParser.meshes[drawIdx], useMaterials: usesMaterials)
                        let vertexName = (drawData.paletteStartIndex != nil) ? "vertex_skinned" : "vertexShader"
                        let fragFunc = try defaultLibrary.makeFunction(name: "fragmentShader",
                                                                       constantValues: funcConstants)
                        let vertFunc = try defaultLibrary.makeFunction(name: vertexName,
                                                                       constantValues: funcConstants)
                        anchorPipelineStateDescriptor.vertexDescriptor = anchorVertexDescriptor
                        anchorPipelineStateDescriptor.vertexFunction = vertFunc
                        anchorPipelineStateDescriptor.fragmentFunction = fragFunc
                        anchorPipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
                        anchorPipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
                        anchorPipelineStateDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
                        anchorPipelineStateDescriptor.sampleCount = renderDestination.sampleCount
                    } catch let error {
                        print("Failed to create pipeline state descriptor, error \(error)")
                    }
                    
                    do {
                        try anchorPipelineStates.append(device.makeRenderPipelineState(descriptor: anchorPipelineStateDescriptor))
                    } catch let error {
                        print("Failed to create pipeline state, error \(error)")
                    }
                }
            }
        }
        
        let anchorDepthStateDescriptor = MTLDepthStencilDescriptor()
        anchorDepthStateDescriptor.depthCompareFunction = .less
        anchorDepthStateDescriptor.isDepthWriteEnabled = true
        anchorDepthState = device.makeDepthStencilState(descriptor: anchorDepthStateDescriptor)
        
        //
        // Create the command queue
        //
        commandQueue = device.makeCommandQueue()
        
    }
    
    private func loadAssets() {
        
        //
        // Create and load our assets into Metal objects including meshes and textures
        //
        
        // Create a MetalKit mesh buffer allocator so that ModelIO will load mesh data directly into
        //   Metal buffers accessible by the GPU
        let metalAllocator = MTKMeshBufferAllocator(device: device)
        
        meshProvider.loadMesh(forType: .anchor, metalAllocator: metalAllocator) { [weak self] asset in
            
            guard let asset = asset else {
                fatalError("Failed to get asset from meshProvider.")
            }
            
            if useOldFlow {
                
                guard let mesh = asset.object(at: 0).children[0].children[0] as? MDLMesh else {
                    fatalError("Failed to get mesh from asset.")
                }
                
                // Creata a Model IO vertexDescriptor so that we format/layout our model IO mesh vertices to
                //   fit our Metal render pipeline's vertex descriptor layout
                let vertexDescriptor = MTKModelIOVertexDescriptorFromMetal(geometryVertexDescriptor)
                
                // Indicate how each Metal vertex descriptor attribute maps to each ModelIO attribute
                (vertexDescriptor.attributes[Int(kVertexAttributePosition.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributePosition
                (vertexDescriptor.attributes[Int(kVertexAttributeTexcoord.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributeTextureCoordinate
                (vertexDescriptor.attributes[Int(kVertexAttributeNormal.rawValue)] as! MDLVertexAttribute).name   = MDLVertexAttributeNormal
                
                // Perform the format/relayout of mesh vertices by setting the new vertex descriptor in our
                //   Model IO mesh
                mesh.vertexDescriptor = vertexDescriptor
                
                // Create a MetalKit mesh (and submeshes) backed by Metal buffers
                do {
                    try self?.anchorMesh = MTKMesh(mesh: mesh, device: device)
                } catch let error {
                    print("Error creating MetalKit mesh from MDLMesh, error \(error)")
                }
            } else {
                // Load meshes into mode parser
                modelParser = ModelParser(asset: asset)
            }
            
            // TODO: Figure out a way to load a new mesh per anchor.
            
        }
        
        meshProvider.loadMesh(forType: .horizPlane, metalAllocator: metalAllocator) { [weak self] asset in
            
            if useOldFlow {
                
                let myMesh: MDLMesh = {
                    if let asset = asset, let mesh = asset.object(at: 0).children[0].children[0] as? MDLMesh {
                        return mesh
                    } else {
                        // Use ModelIO to create a box mesh as our object
                        let mesh = MDLMesh(planeWithExtent: vector3(1, 0, 1), segments: vector2(1, 1), geometryType: .triangles, allocator: metalAllocator)
                        if let submesh = mesh.submeshes?.firstObject as? MDLSubmesh {
                            let scatteringFunction = MDLScatteringFunction()
                            submesh.material = MDLMaterial(name: "plane_grid", scatteringFunction: scatteringFunction)
                        }
                        return mesh
                    }
                }()
                
                // Creata a Model IO vertexDescriptor so that we format/layout our model IO mesh vertices to
                //   fit our Metal render pipeline's vertex descriptor layout
                let vertexDescriptor = MTKModelIOVertexDescriptorFromMetal(geometryVertexDescriptor)
                
                // Indicate how each Metal vertex descriptor attribute maps to each ModelIO attribute
                (vertexDescriptor.attributes[Int(kVertexAttributePosition.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributePosition
                (vertexDescriptor.attributes[Int(kVertexAttributeTexcoord.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributeTextureCoordinate
                (vertexDescriptor.attributes[Int(kVertexAttributeNormal.rawValue)] as! MDLVertexAttribute).name   = MDLVertexAttributeNormal
                
                // Perform the format/relayout of mesh vertices by setting the new vertex descriptor in our
                //   Model IO mesh
                myMesh.vertexDescriptor = vertexDescriptor
                
                // Create a MetalKit mesh (and submeshes) backed by Metal buffers
                do {
                    try self?.horizPlaneMesh = MTKMesh(mesh: myMesh, device: device)
                } catch let error {
                    print("Error creating MetalKit mesh from MDLMesh, error \(error)")
                }
                
            } else {
                
                guard let asset = asset else {
                    return
                }
                
                // Load meshes into mode parser
                modelParser = ModelParser(asset: asset)
                
            }
            
        }
        
        meshProvider.loadMesh(forType: .vertPlane, metalAllocator: metalAllocator) { [weak self] asset in
            
            guard let asset = asset else {
                return
            }
            
            if useOldFlow {
                
                guard let mesh = asset.object(at: 0).children[0].children[0] as? MDLMesh else {
                    fatalError("Failed to get mesh from asset.")
                }
                
                // Creata a Model IO vertexDescriptor so that we format/layout our model IO mesh vertices to
                //   fit our Metal render pipeline's vertex descriptor layout
                let vertexDescriptor = MTKModelIOVertexDescriptorFromMetal(geometryVertexDescriptor)
                
                // Indicate how each Metal vertex descriptor attribute maps to each ModelIO attribute
                (vertexDescriptor.attributes[Int(kVertexAttributePosition.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributePosition
                (vertexDescriptor.attributes[Int(kVertexAttributeTexcoord.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributeTextureCoordinate
                (vertexDescriptor.attributes[Int(kVertexAttributeNormal.rawValue)] as! MDLVertexAttribute).name   = MDLVertexAttributeNormal
                
                // Perform the format/relayout of mesh vertices by setting the new vertex descriptor in our
                //   Model IO mesh
                mesh.vertexDescriptor = vertexDescriptor
                
                // Create a MetalKit mesh (and submeshes) backed by Metal buffers
                do {
                    try self?.vertPlaneMesh = MTKMesh(mesh: mesh, device: device)
                } catch let error {
                    print("Error creating MetalKit mesh from MDLMesh, error \(error)")
                }
            } else {
                // Load meshes into mode parser
                modelParser = ModelParser(asset: asset)
            }
            
        }
        
    }
    
    private func loadMeshesFromParser() {
        
        guard let modelParser = modelParser else {
            return
        }
        
        if modelParser.meshNodeIndices.count > 1 {
            print("WARNING: More than one mesh was found. Currently only one mesh per anchor is supported.")
        }
        
        var myGPUData = MeshGPUData()
        
        for vtxBuffer in modelParser.vertexBuffers {
            vtxBuffer.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) in
                let buffer = device.makeBuffer(bytes: bytes, length: vtxBuffer.count, options: .storageModeShared)
                myGPUData.vtxBuffers.append(buffer!)
            }
            
        }
        
        for idxBuffer in modelParser.indexBuffers {
            idxBuffer.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) in
                let buffer = device.makeBuffer(bytes: bytes, length: idxBuffer.count, options: .storageModeShared)
                myGPUData.indexBuffers.append(buffer!)
            }
        }
        
        for texturePath in modelParser.texturePaths {
            myGPUData.textures.append(createMTLTexture(fromAssetPath: texturePath))
        }
        
        var instStartIdx = 0
        var paletteStartIdx = 0
        for (meshIdx, meshData) in modelParser.meshes.enumerated() {
            
            var drawData = DrawData()
            drawData.vbCount = meshData.vbCount
            drawData.vbStartIdx = meshData.vbStartIdx
            drawData.ibStartIdx = meshData.ibStartIdx
            drawData.instCount = !modelParser.instanceCount.isEmpty ? modelParser.instanceCount[meshIdx] : 1
            drawData.instBufferStartIdx = instStartIdx
            if !modelParser.meshSkinIndices.isEmpty,
                let paletteIndex = modelParser.meshSkinIndices[instStartIdx] {
                drawData.paletteSize = modelParser.skins[paletteIndex].jointPaths.count
                drawData.paletteStartIndex = paletteStartIdx
                paletteStartIdx += drawData.paletteSize * drawData.instCount
            }
            instStartIdx += drawData.instCount
            usesMaterials = (!meshData.materials.isEmpty)
            for subIndex in 0..<meshData.idxCounts.count {
                var subData = DrawSubData()
                subData.idxCount = meshData.idxCounts[subIndex]
                subData.idxType = MetalUtilities.convertToMTLIndexType(from: meshData.idxTypes[subIndex])
                subData.materialUniforms = usesMaterials ? MetalUtilities.convertToMaterialUniform(from: meshData.materials[subIndex])
                    : MaterialUniforms()
                subData.baseColorTexIdx = usesMaterials ? meshData.materials[subIndex].baseColor.1 : nil
                subData.normalTexIdx = usesMaterials ? meshData.materials[subIndex].normalMap : nil
                subData.aoTexIdx = usesMaterials ? meshData.materials[subIndex].ambientOcclusionMap : nil
                subData.roughTexIdx = usesMaterials ? meshData.materials[subIndex].roughness.1 : nil
                subData.metalTexIdx = usesMaterials ? meshData.materials[subIndex].metallic.1 : nil
                drawData.subData.append(subData)
            }
            
            myGPUData.drawData.append(drawData)
            
        }
        
        meshGPUData = myGPUData
        totalMeshTransforms = modelParser.meshNodeIndices.count
        
    }
    
    private func createMTLTexture(fromAssetPath assetPath: String) -> MTLTexture? {
        do {
            guard let textureURL = URL(string: assetPath) else { return nil }
            return try textureLoader.newTexture(withContentsOf: textureURL, options: nil)
        } catch {
            print("Unable to loader texture with assetPath \(assetPath) with error \(error)")
        }
        
        return nil
    }
    
    private func createVertexDescriptor(with vtxDesc: [MDLVertexDescriptor]) -> MTLVertexDescriptor {
        let mtlVertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vtxDesc[0])
        return mtlVertexDescriptor!
    }
    
    private func encodeMeshGPUData(with renderEncoder: MTLRenderCommandEncoder, drawData: DrawData) {
        
        guard let meshGPUData = meshGPUData else {
            return
        }
        
        // Set mesh's vertex buffers
        for vtxBufferIdx in 0..<drawData.vbCount {
            renderEncoder.setVertexBuffer(meshGPUData.vtxBuffers[drawData.vbStartIdx + vtxBufferIdx], offset: 0, index: vtxBufferIdx)
        }
        
        // Draw each submesh of our mesh
        for drawDataSubIndex in 0..<drawData.subData.count {
            
            let idxCount = Int(drawData.subData[drawDataSubIndex].idxCount)
            let idxType = drawData.subData[drawDataSubIndex].idxType
            let ibOffset = drawData.ibStartIdx
            let indexBuffer = meshGPUData.indexBuffers[ibOffset + drawDataSubIndex]
            var materialUniforms = drawData.subData[drawDataSubIndex].materialUniforms
            
            // Set textures based off material flags
            encodeTextures(with: meshGPUData, renderEncoder: renderEncoder, subData: drawData.subData[drawDataSubIndex])
            
            renderEncoder.setFragmentBytes(&materialUniforms, length: Constants.alignedMaterialSize,
                                           index: Int(kBufferIndexMaterialUniforms.rawValue))
            
            renderEncoder.drawIndexedPrimitives(type: .triangle, indexCount: idxCount, indexType: idxType,
                                                indexBuffer: indexBuffer, indexBufferOffset: 0,
                                                instanceCount: drawData.instCount)
        }
        
    }
    
    private func encodeTextures(with meshData: MeshGPUData, renderEncoder: MTLRenderCommandEncoder, subData drawSubData: DrawSubData) {
        if let baseColorTexIdx = drawSubData.baseColorTexIdx {
            renderEncoder.setFragmentTexture(meshData.textures[baseColorTexIdx],
                                             index: Int(kTextureIndexColor.rawValue))
        }
        
        if let aoTexIdx = drawSubData.aoTexIdx {
            renderEncoder.setFragmentTexture(meshData.textures[aoTexIdx],
                                             index: Int(kTextureIndexAmbientOcclusion.rawValue))
        }
        
        if let normalTexIdx = drawSubData.normalTexIdx {
            renderEncoder.setFragmentTexture(meshData.textures[normalTexIdx],
                                             index: Int(kTextureIndexNormal.rawValue))
        }
        
        if let roughTexIdx = drawSubData.roughTexIdx {
            renderEncoder.setFragmentTexture(meshData.textures[roughTexIdx],
                                             index: Int(kTextureIndexRoughness.rawValue))
        }
        
        if let metalTexIdx = drawSubData.metalTexIdx {
            renderEncoder.setFragmentTexture(meshData.textures[metalTexIdx],
                                             index: Int(kTextureIndexMetallic.rawValue))
        }
        
    }
    
    // MARK: - Render loop
    
    // MARK: Sterp 1 - Update State
    // Update the location(s) to which we'll write to in our dynamically changing Metal buffers for
    // the current frame (i.e. update our slot in the ring buffer used for the current frame)
    private func updateBufferStates() {
        
        uniformBufferIndex = (uniformBufferIndex + 1) % Constants.maxBuffersInFlight
        
        sharedUniformBufferOffset = Constants.alignedSharedUniformsSize * uniformBufferIndex
        anchorUniformBufferOffset = Constants.alignedInstanceUniformsSize * uniformBufferIndex * totalMeshTransforms
        materialUniformBufferOffset = Constants.alignedMaterialSize * uniformBufferIndex
        
        sharedUniformBufferAddress = sharedUniformBuffer.contents().advanced(by: sharedUniformBufferOffset)
        anchorUniformBufferAddress = anchorUniformBuffer.contents().advanced(by: anchorUniformBufferOffset)
        materialUniformBufferAddress = materialUniformBuffer.contents().advanced(by: materialUniformBufferOffset)
        
    }
    
    // MARK: Step 2 - Update Metal Buffers
    private func updateBuffers() {
        
        guard let currentFrame = session.currentFrame else {
            return
        }
        
        updateSharedUniforms(frame: currentFrame)
        updateAnchors(frame: currentFrame)
        updateCapturedImageTextures(frame: currentFrame)
        
        if viewportSizeDidChange {
            viewportSizeDidChange = false
            
            updateImagePlane(frame: currentFrame)
        }
    }
    
    // Update the shared uniforms of the frame
    private func updateSharedUniforms(frame: ARFrame) {
        
        let uniforms = sharedUniformBufferAddress.assumingMemoryBound(to: SharedUniforms.self)
        
        uniforms.pointee.viewMatrix = simd_inverse(frame.camera.transform)
        uniforms.pointee.projectionMatrix = frame.camera.projectionMatrix(withViewportSize: viewportSize, orientation: .landscapeRight, zNear: 0.001, zFar: 1000)
        
        // Set up lighting for the scene using the ambient intensity if provided
        var ambientIntensity: Float = 1.0
        
        if let lightEstimate = frame.lightEstimate {
            ambientIntensity = Float(lightEstimate.ambientIntensity) / 1000.0
        }
        
        let ambientLightColor: vector_float3 = vector3(0.5, 0.5, 0.5)
        uniforms.pointee.ambientLightColor = ambientLightColor * ambientIntensity
        
        var directionalLightDirection : vector_float3 = vector3(0.0, 0.0, -1.0)
        directionalLightDirection = simd_normalize(directionalLightDirection)
        uniforms.pointee.directionalLightDirection = directionalLightDirection
        
        let directionalLightColor: vector_float3 = vector3(0.6, 0.6, 0.6)
        uniforms.pointee.directionalLightColor = directionalLightColor * ambientIntensity
        
        //uniforms.pointee.materialShininess = 30
        
    }
    
    private func updateAnchors(frame: ARFrame) {
        
        // Update the anchor uniform buffer with transforms of the current frame's anchors
        anchorInstanceCount = 0
        horizPlaneInstanceCount = 0
        vertPlaneInstanceCount = 0
        
        for index in 0..<frame.anchors.count {
            let anchor = frame.anchors[index]
            if let plane = anchor as? ARPlaneAnchor {
                if plane.alignment == .horizontal {
                    horizPlaneInstanceCount += 1
                } else {
                    vertPlaneInstanceCount += 1
                }
            } else {
                anchorInstanceCount += 1
            }
            
            if anchorInstanceCount > Constants.maxAnchorInstanceCount {
                anchorInstanceCount = Constants.maxAnchorInstanceCount
                break
            }
            
            // Flip Z axis to convert geometry from right handed to left handed
            var coordinateSpaceTransform = matrix_identity_float4x4
            coordinateSpaceTransform.columns.2.z = -1.0
            
            var modelMatrix = anchor.transform * coordinateSpaceTransform
            if let plane = anchor as? ARPlaneAnchor {
                modelMatrix = modelMatrix.scale(x: plane.extent.x, y: plane.extent.y, z: plane.extent.z)
                modelMatrix = modelMatrix.translate(x: -plane.center.x/2.0, y: -plane.center.y/2.0, z: -plane.center.z/2.0)
            }

            let anchorUniforms = anchorUniformBufferAddress.assumingMemoryBound(to: InstanceUniforms.self).advanced(by: index)
            anchorUniforms.pointee.modelMatrix = modelMatrix
            
        }
    }
    
    private func updateCapturedImageTextures(frame: ARFrame) {
        // Create two textures (Y and CbCr) from the provided frame's captured image
        let pixelBuffer = frame.capturedImage
        
        if (CVPixelBufferGetPlaneCount(pixelBuffer) < 2) {
            return
        }
        
        capturedImageTextureY = createTexture(fromPixelBuffer: pixelBuffer, pixelFormat:.r8Unorm, planeIndex:0)
        capturedImageTextureCbCr = createTexture(fromPixelBuffer: pixelBuffer, pixelFormat:.rg8Unorm, planeIndex:1)
    }
    
    private func createTexture(fromPixelBuffer pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat, planeIndex: Int) -> CVMetalTexture? {
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        
        var texture: CVMetalTexture? = nil
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, capturedImageTextureCache, pixelBuffer, nil, pixelFormat, width, height, planeIndex, &texture)
        
        if status != kCVReturnSuccess {
            texture = nil
        }
        
        return texture
    }
    
    private func updateImagePlane(frame: ARFrame) {
        // Update the texture coordinates of our image plane to aspect fill the viewport
        let displayToCameraTransform = frame.displayTransform(withViewportSize: viewportSize, orientation: .landscapeRight).inverted()
        
        let vertexData = imagePlaneVertexBuffer.contents().assumingMemoryBound(to: Float.self)
        for index in 0...3 {
            let textureCoordIndex = 4 * index + 2
            let textureCoord = CGPoint(x: CGFloat(Constants.imagePlaneVertexData[textureCoordIndex]), y: CGFloat(Constants.imagePlaneVertexData[textureCoordIndex + 1]))
            let transformedCoord = textureCoord.applying(displayToCameraTransform)
            vertexData[textureCoordIndex] = Float(transformedCoord.x)
            vertexData[textureCoordIndex + 1] = Float(transformedCoord.y)
        }
    }
    
    private func drawCapturedImage(renderEncoder: MTLRenderCommandEncoder) {
        guard let textureY = capturedImageTextureY, let textureCbCr = capturedImageTextureCbCr else {
            return
        }
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("DrawCapturedImage")
        
        // Set render command encoder state
        renderEncoder.setCullMode(.none)
        renderEncoder.setRenderPipelineState(capturedImagePipelineState)
        renderEncoder.setDepthStencilState(capturedImageDepthState)
        
        // Set mesh's vertex buffers
        renderEncoder.setVertexBuffer(imagePlaneVertexBuffer, offset: 0, index: Int(kBufferIndexMeshPositions.rawValue))
        
        // Set any textures read/sampled from our render pipeline
        renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(textureY), index: Int(kTextureIndexY.rawValue))
        renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(textureCbCr), index: Int(kTextureIndexCbCr.rawValue))
        
        // Draw each submesh of our mesh
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        
        renderEncoder.popDebugGroup()
        
    }
    
    private func drawSharedUniforms(renderEncoder: MTLRenderCommandEncoder) {
        
        renderEncoder.pushDebugGroup("DrawSharedUniforms")
        
        renderEncoder.setVertexBuffer(sharedUniformBuffer, offset: sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
        renderEncoder.setFragmentBuffer(sharedUniformBuffer, offset: sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
        
        renderEncoder.popDebugGroup()
        
    }
    
    private func drawAnchors(renderEncoder: MTLRenderCommandEncoder) {
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("DrawAnchors")
        
        // Set render command encoder state
        renderEncoder.setCullMode(.back)
        
        if useOldFlow {
            
            // OLD
            
            guard let anchorMesh = anchorMesh else {
                return
            }
            
            guard anchorInstanceCount > 0 else {
                return
            }
            
            renderEncoder.setRenderPipelineState(anchorPipelineState)
            renderEncoder.setDepthStencilState(anchorDepthState)
            
            // Set any buffers fed into our render pipeline
            renderEncoder.setVertexBuffer(anchorUniformBuffer, offset: anchorUniformBufferOffset, index: Int(kBufferIndexInstanceUniforms.rawValue))
            
            // Set mesh's vertex buffers
            for bufferIndex in 0..<anchorMesh.vertexBuffers.count {
                let vertexBuffer = anchorMesh.vertexBuffers[bufferIndex]
                renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index:bufferIndex)
            }
            
            // Draw each submesh of our mesh
            for submesh in anchorMesh.submeshes {
                renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer, indexBufferOffset: submesh.indexBuffer.offset, instanceCount: anchorInstanceCount)
            }
 
        } else {
            
            // NEW.
            
            guard let meshGPUData = meshGPUData else {
                return
            }
            
            for (drawDataIdx, drawData) in meshGPUData.drawData.enumerated() {
                
                renderEncoder.setRenderPipelineState(anchorPipelineStates[drawDataIdx])
                
                var instBufferStartIdx = drawData.instBufferStartIdx
                renderEncoder.setVertexBytes(&instBufferStartIdx, length: 8, index: Int(kBufferIndexInstanceUniforms.rawValue))
                
                // Set the mesh's vertex data buffers
                encodeMeshGPUData(with: renderEncoder, drawData: drawData)
                
            }
            
        }
        
        // Common
        
        renderEncoder.popDebugGroup()
        
    }
    
    private func drawGuides(renderEncoder: MTLRenderCommandEncoder) {
        
        // TODO: Support vertical planes
        
        guard showGuides else {
            return
        }
        
        guard let horizPlaneMesh = horizPlaneMesh else {
            return
        }
        
        guard horizPlaneInstanceCount > 0 else {
            return
        }
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("DrawGuides")
        
        // Set render command encoder state
        renderEncoder.setCullMode(.back)
        renderEncoder.setRenderPipelineState(anchorPipelineState)
        renderEncoder.setDepthStencilState(anchorDepthState)
        
        // Set any buffers fed into our render pipeline
        renderEncoder.setVertexBuffer(anchorUniformBuffer, offset: anchorUniformBufferOffset, index: Int(kBufferIndexInstanceUniforms.rawValue))
        renderEncoder.setVertexBuffer(sharedUniformBuffer, offset: sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
        renderEncoder.setFragmentBuffer(sharedUniformBuffer, offset: sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
        
        // Set mesh's vertex buffers
        for bufferIndex in 0..<horizPlaneMesh.vertexBuffers.count {
            let vertexBuffer = horizPlaneMesh.vertexBuffers[bufferIndex]
            renderEncoder.setVertexBuffer(vertexBuffer.buffer, offset: vertexBuffer.offset, index:bufferIndex)
        }
        
        // Draw each submesh of our mesh
        for submesh in horizPlaneMesh.submeshes {
            renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.buffer, indexBufferOffset: submesh.indexBuffer.offset, instanceCount: horizPlaneInstanceCount)
        }
        
        renderEncoder.popDebugGroup()
        
    }
    
}
