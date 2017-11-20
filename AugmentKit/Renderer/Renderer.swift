//
//  Renderer.swift
//  AugmentKit2
//
//  MIT License
//
//  Copyright (c) 2017 JamieScanlon
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
import Metal
import MetalKit
import ARKit
import ModelIO
import AugmentKitShader

public protocol RenderDestinationProvider {
    var currentRenderPassDescriptor: MTLRenderPassDescriptor? { get }
    var currentDrawable: CAMetalDrawable? { get }
    var colorPixelFormat: MTLPixelFormat { get set }
    var depthStencilPixelFormat: MTLPixelFormat { get set }
    var sampleCount: Int { get set }
}

public protocol RenderDebugLogger {
    func updatedAnchors(count: Int, numAnchors: Int, numPlanes: Int, numTrackingPoints: Int)
}

public protocol MeshProvider {
    func loadMesh(forType: MeshType, completion: (MDLAsset?) -> Void)
}

public enum MeshType {
    case anchor
    case horizPlane
    case vertPlane
}

public class Renderer {
    
    // Debugging
    public var logger: RenderDebugLogger?
    
    public var orientation: UIInterfaceOrientation = .portrait {
        didSet {
            viewportSizeDidChange = true
        }
    }
    
    public enum Constants {
        static let maxBuffersInFlight = 3
        static let maxAnchorInstanceCount = 64
        static let maxTrackingPointCount = 1024
        
        // Captured Image Plane
        static let imagePlaneVertexData: [Float] = [
            -1.0, -1.0,  0.0, 1.0,
            1.0, -1.0,  1.0, 1.0,
            -1.0,  1.0,  0.0, 0.0,
            1.0,  1.0,  1.0, 0.0,
        ]
        
        // The 16 byte aligned size of our uniform structures
        static let alignedSharedUniformsSize = (MemoryLayout<SharedUniforms>.stride & ~0xFF) + 0x100
        static let alignedMaterialSize = (MemoryLayout<MaterialUniforms>.stride & ~0xFF) + 0x100
        static let alignedAnchorInstanceUniformsSize = ((MemoryLayout<AnchorInstanceUniforms>.stride * Constants.maxAnchorInstanceCount) & ~0xFF) + 0x100
        static let alignedTrackingPointDataSize = ((MemoryLayout<float3>.stride * Constants.maxTrackingPointCount) & ~0xFF) + 0x100
    }
    
    public enum RendererState {
        case uninitialized
        case initialized
        case running
        case paused
    }
    
    public private(set) var state: RendererState = .uninitialized
    public let session: ARSession
    public let device: MTLDevice
    public var meshProvider: MeshProvider?
    
    // Guide Meshes for debugging
    public var showGuides = false {
        didSet {
            reset()
        }
    }
    
    // A transform matrix that represents the position of the camera in world space.
    // There is no rotation component.
    public private(set) var currentCameraPositionTransform: matrix_float4x4?
    // A transform matrix that represents the rotation of the camera relative to world space.
    // There is no postion component.
    public var currentCameraRotation: matrix_float4x4? {
        guard let currentCameraQuaternionRotation = currentCameraQuaternionRotation else {
            return nil
        }
        return unsafeBitCast(GLKMatrix4MakeWithQuaternion(currentCameraQuaternionRotation), to: simd_float4x4.self)
    }
    public private(set) var currentCameraHeading: Double?
    public private(set) var lowestHorizPlaneAnchor: ARPlaneAnchor?
    
    public init(session: ARSession, metalDevice device: MTLDevice, renderDestination: RenderDestinationProvider, meshProvider: MeshProvider? = nil) {
        self.session = session
        self.device = device
        self.renderDestination = renderDestination
        self.textureLoader = MTKTextureLoader(device: device)
        if let provider = meshProvider {
            self.meshProvider = provider
        }
    }
    
    // MARK: Inititialization
    
    public func initialize() {
        
        guard state == .uninitialized else {
            return
        }
        
        loadMetal()
        loadAssets()
        loadMeshesFromParser()
        loadPipeline()
        
        state = .initialized
        
    }
    
    public func drawRectResized(size: CGSize) {
        viewportSize = size
        viewportSizeDidChange = true
    }
    
    // MARK: Update
    
    public func update() {
        
        guard let commandQueue = commandQueue else {
            return
        }
        
        // Wait to ensure only kMaxBuffersInFlight are getting proccessed by any stage in the Metal
        // pipeline (App, Metal, Drivers, GPU, etc)
        let _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        // Create a new command buffer for each renderpass to the current drawable
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            commandBuffer.label = "MyCommand"
            
            // Add completion hander which signal _inFlightSemaphore when Metal and the GPU has fully
            // finished proccssing the commands we're encoding this frame.  This indicates when the
            // dynamic buffers, that we're writing to this frame, will no longer be needed by Metal
            // and the GPU.
            //
            // Retain our CVMetalTextures for the duration of the rendering cycle. The MTLTextures
            // we use from the CVMetalTextures are not valid unless their parent CVMetalTextures
            // are retained. Since we may release our CVMetalTexture ivars during the rendering
            // cycle, we must retain them separately here.
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
                drawPlanes(renderEncoder: renderEncoder)
                drawTrackingPoints(renderEncoder: renderEncoder)
                
                // We're done encoding commands
                renderEncoder.endEncoding()
                
                // Schedule a present once the framebuffer is complete using the current drawable
                commandBuffer.present(currentDrawable)
            }
            
            // Finalize rendering here & push the command buffer to the GPU
            commandBuffer.commit()
        }
        
        // Update the current frame
        currentFrameNumber += 1
        
    }
    
    public func run() {
        guard state != .uninitialized else {
            return
        }
        session.run(createNewConfiguration())
        state = .running
    }
    
    public func pause() {
        guard state != .uninitialized else {
            return
        }
        session.pause()
        state = .paused
    }
    
    public func reset() {
        guard state != .uninitialized else {
            return
        }
        session.run(createNewConfiguration(), options: [.removeExistingAnchors, .resetTracking])
        state = .running
    }
    
    // MARK: - Private
    
    private let textureLoader: MTKTextureLoader
    private let inFlightSemaphore = DispatchSemaphore(value: Constants.maxBuffersInFlight)
    private var renderDestination: RenderDestinationProvider
    private var anchorModelParser: ModelParser?
    private var horizPlaneModelParser: ModelParser?
    private var vertPlaneModelParser: ModelParser?
    
    // Metal objects
    private var defaultLibrary: MTLLibrary!
    private var commandQueue: MTLCommandQueue?
    private var sharedUniformBuffer: MTLBuffer?
    private var anchorUniformBuffer: MTLBuffer?
    private var materialUniformBuffer: MTLBuffer?
    private var imagePlaneVertexBuffer: MTLBuffer?
    private var capturedImagePipelineState: MTLRenderPipelineState?
    private var capturedImageDepthState: MTLDepthStencilState?
    private var anchorPipelineStates = [MTLRenderPipelineState]() // Store multiple states
    private var anchorDepthState: MTLDepthStencilState?
    private var capturedImageTextureY: CVMetalTexture?
    private var capturedImageTextureCbCr: CVMetalTexture?
    private var trackingPointDataBuffer: MTLBuffer?
    private var trackingPointPipelineState: MTLRenderPipelineState?
    private var trackingPointDepthState: MTLDepthStencilState?
    
    // Captured image texture cache
    private var capturedImageTextureCache: CVMetalTextureCache?
    
    // Metal vertex descriptor specifying how vertices will by laid out for input into our
    // anchor geometry render pipeline and how we'll layout our Model IO verticies
    private var geometryVertexDescriptor: MTLVertexDescriptor?
    
    // MetalKit meshes containing vertex data and index buffer for our anchor geometry
    private var anchorMeshGPUData: MeshGPUData?
    private var horizPlaneMeshGPUData: MeshGPUData?
    private var vertPlaneMeshGPUData: MeshGPUData?
    private var horizPlaneInstanceCount: Int = 0
    private var vertPlaneInstanceCount: Int = 0
    private var totalMeshTransforms = 1
    
    // Used to determine _uniformBufferStride each frame.
    // This is the current frame number modulo kMaxBuffersInFlight
    private var uniformBufferIndex: Int = 0
    
    // Offset within _sharedUniformBuffer to set for the current frame
    private var sharedUniformBufferOffset: Int = 0
    
    // Offset within _anchorUniformBuffer to set for the current frame
    private var anchorUniformBufferOffset: Int = 0
    
    // Offset within _materialUniformBuffer to set for the current frame
    private var materialUniformBufferOffset: Int = 0
    
    // Offset within trackingPointDataBuffer to set for the current frame
    private var trackingPointDataBufferOffset: Int = 0
    
    // Addresses to write shared uniforms to each frame
    private var sharedUniformBufferAddress: UnsafeMutableRawPointer?
    
    // Addresses to write anchor uniforms to each frame
    private var anchorUniformBufferAddress: UnsafeMutableRawPointer?
    
    // Addresses to write anchor uniforms to each frame
    private var materialUniformBufferAddress: UnsafeMutableRawPointer?
    
    // Addresses to write anchor uniforms to each frame
    private var trackingPointDataBufferAddress: UnsafeMutableRawPointer?
    
    // The number of anchor instances to render
    private var anchorInstanceCount: Int = 0
    
    // The number of tracking points to render
    private var trackingPointCount: Int = 0
    
    // The current viewport size
    private var viewportSize: CGSize = CGSize()
    
    // Flag for viewport size changes
    private var viewportSizeDidChange: Bool = false
    
    private var usesMaterials = false
    
    // TODO: Implement anchor animation
    // Keeps track of the current frame in order to support animtaion for anchors.
    private var currentFrameNumber = 0
    
    // number of frames in the anchor animation by anchor index
    private var anchorAnimationFrameCount = [Int]()
    
    // A Quaternion that represents the rotation of the camera relative to world space.
    private var currentCameraQuaternionRotation: GLKQuaternion?
    
    // MARK: ARKit Session Configuration
    
    private func createNewConfiguration() -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        // Setting this to .gravityAndHeading aligns the the origin of the scene to compass
        // direction but it also tend to make the scene jumpy.
        // AKWorld and WorkLocationManager has the ability take heading into account when
        // creating anchors which means that we can just use the .gravity alignment
        configuration.worldAlignment = .gravity
        
        // Enable horizontal plane detection
        configuration.planeDetection = .horizontal
        
        return configuration
    }
    
    // MARK: Bootstrap
    
    private func loadMetal() {
        
        //
        // Create and load our basic Metal state objects
        //
        
        // Set the default formats needed to render
        renderDestination.depthStencilPixelFormat = .depth32Float_stencil8
        renderDestination.colorPixelFormat = .bgra8Unorm
        renderDestination.sampleCount = 1
        
        // Calculate our uniform buffer sizes. We allocate Constants.maxBuffersInFlight instances for uniform
        // storage in a single buffer. This allows us to update uniforms in a ring (i.e. triple
        // buffer the uniforms) so that the GPU reads from one slot in the ring wil the CPU writes
        // to another. Anchor uniforms should be specified with a max instance count for instancing.
        // Also uniform storage must be aligned (to 256 bytes) to meet the requirements to be an
        // argument in the constant address space of our shading functions.
        let sharedUniformBufferSize = Constants.alignedSharedUniformsSize * Constants.maxBuffersInFlight
        let anchorUniformBufferSize = Constants.alignedAnchorInstanceUniformsSize * Constants.maxBuffersInFlight
        let materialUniformBufferSize = Constants.alignedMaterialSize * Constants.maxBuffersInFlight
        let trackingPointDataBufferSize = Constants.alignedTrackingPointDataSize * Constants.maxBuffersInFlight
        
        // Create and allocate our uniform buffer objects. Indicate shared storage so that both the
        // CPU can access the buffer
        sharedUniformBuffer = device.makeBuffer(length: sharedUniformBufferSize, options: .storageModeShared)
        sharedUniformBuffer?.label = "SharedUniformBuffer"
        
        anchorUniformBuffer = device.makeBuffer(length: anchorUniformBufferSize, options: .storageModeShared)
        anchorUniformBuffer?.label = "AnchorUniformBuffer"
        
        materialUniformBuffer = device.makeBuffer(length: materialUniformBufferSize, options: .storageModeShared)
        materialUniformBuffer?.label = "MaterialUniformBuffer"
        
        trackingPointDataBuffer = device.makeBuffer(length: trackingPointDataBufferSize, options: .storageModeShared)
        trackingPointDataBuffer?.label = "TrackingPointDataBuffer"
        
        // Load the default metal library file which contains all of the compiled .metal files
        guard let libraryFile = Bundle(for: Renderer.self).path(forResource: "default", ofType: "metallib") else {
            fatalError("failed to create a default library for the device.")
        }
        
        defaultLibrary = {
            do {
                 return try device.makeLibrary(filepath: libraryFile)
            } catch {
                fatalError("failed to create a default library for the device.")
            }
        }()
        
        //
        // Image Capture Plane
        //
        
        // Create a vertex buffer with our image plane vertex data.
        let imagePlaneVertexDataCount = Constants.imagePlaneVertexData.count * MemoryLayout<Float>.size
        imagePlaneVertexBuffer = device.makeBuffer(bytes: Constants.imagePlaneVertexData, length: imagePlaneVertexDataCount, options: [])
        imagePlaneVertexBuffer?.label = "ImagePlaneVertexBuffer"
        
        guard let capturedImageVertexTransform = defaultLibrary.makeFunction(name: "capturedImageVertexTransform") else {
            fatalError("failed to create the capturedImageVertexTransform function")
        }
        guard let capturedImageFragmentShader = defaultLibrary.makeFunction(name: "capturedImageFragmentShader") else {
            fatalError("failed to create the capturedImageFragmentShader function")
        }
        let capturedImageVertexFunction = capturedImageVertexTransform
        let capturedImageFragmentFunction = capturedImageFragmentShader
        
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
            fatalError()
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
        // pipeline should expect. The layout below keeps attributes used to calculate vertex shader
        // output position separate (world position, skinning, tweening weights) separate from other
        // attributes (texture coordinates, normals).  This generally maximizes pipeline efficiency
        
        geometryVertexDescriptor = MTLVertexDescriptor()
        
        // Positions.
        geometryVertexDescriptor?.attributes[0].format = .float3
        geometryVertexDescriptor?.attributes[0].offset = 0
        geometryVertexDescriptor?.attributes[0].bufferIndex = Int(kBufferIndexMeshPositions.rawValue)
        
        // Texture coordinates.
        geometryVertexDescriptor?.attributes[1].format = .float2
        geometryVertexDescriptor?.attributes[1].offset = 0
        geometryVertexDescriptor?.attributes[1].bufferIndex = Int(kBufferIndexMeshGenerics.rawValue)
        
        // Normals.
        geometryVertexDescriptor?.attributes[2].format = .float3
        geometryVertexDescriptor?.attributes[2].offset = 8
        geometryVertexDescriptor?.attributes[2].bufferIndex = Int(kBufferIndexMeshGenerics.rawValue)
        
        // TODO: JointIndices and JointWeights for Puppet animations
        
        // Position Buffer Layout
        geometryVertexDescriptor?.layouts[0].stride = 12
        geometryVertexDescriptor?.layouts[0].stepRate = 1
        geometryVertexDescriptor?.layouts[0].stepFunction = .perVertex
        
        // Generic Attribute Buffer Layout
        geometryVertexDescriptor?.layouts[1].stride = 20
        geometryVertexDescriptor?.layouts[1].stepRate = 1
        geometryVertexDescriptor?.layouts[1].stepFunction = .perVertex
        
        //
        // Tracking Points
        //
        
        guard let pointVertexShader = defaultLibrary.makeFunction(name: "pointVertexShader") else {
            fatalError("failed to create the pointVertexShader function")
        }
        guard let pointFragmentShader = defaultLibrary.makeFunction(name: "pointFragmentShader") else {
            fatalError("failed to create the pointFragmentShader function")
        }
        
        // Create a vertex descriptor for our image plane vertex buffer
        let trackingPointVertexDescriptor = MTLVertexDescriptor()
        
        // Positions
        trackingPointVertexDescriptor.attributes[0].format = .float4
        trackingPointVertexDescriptor.attributes[0].offset = 0
        trackingPointVertexDescriptor.attributes[0].bufferIndex = Int(kBufferIndexTrackingPointData.rawValue)
        
        // Color
        trackingPointVertexDescriptor.attributes[5].format = .float4
        trackingPointVertexDescriptor.attributes[5].offset = 16
        trackingPointVertexDescriptor.attributes[5].bufferIndex = Int(kBufferIndexTrackingPointData.rawValue)
        
        // Buffer Layout
        trackingPointVertexDescriptor.layouts[Int(kBufferIndexTrackingPointData.rawValue)].stride = 32
        trackingPointVertexDescriptor.layouts[Int(kBufferIndexTrackingPointData.rawValue)].stepRate = 1
        trackingPointVertexDescriptor.layouts[Int(kBufferIndexTrackingPointData.rawValue)].stepFunction = .perVertex
        
        let trackingPointPipelineStateDescriptor = MTLRenderPipelineDescriptor()
        trackingPointPipelineStateDescriptor.label = "TrackingPointPipeline"
        trackingPointPipelineStateDescriptor.vertexFunction = pointVertexShader
        trackingPointPipelineStateDescriptor.fragmentFunction = pointFragmentShader
        trackingPointPipelineStateDescriptor.vertexDescriptor = trackingPointVertexDescriptor
        trackingPointPipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        trackingPointPipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = true
        trackingPointPipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        trackingPointPipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
        trackingPointPipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = .add
        trackingPointPipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = .add
        trackingPointPipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        trackingPointPipelineStateDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        trackingPointPipelineStateDescriptor.sampleCount = renderDestination.sampleCount
        
        do {
            try trackingPointPipelineState = device.makeRenderPipelineState(descriptor: trackingPointPipelineStateDescriptor)
        } catch let error {
            print("Failed to create tracking point pipeline state, error \(error)")
            fatalError()
        }
        
        let trackingPointDepthStateDescriptor = MTLDepthStencilDescriptor()
        trackingPointDepthStateDescriptor.depthCompareFunction = .always
        trackingPointDepthStateDescriptor.isDepthWriteEnabled = false
        trackingPointDepthState = device.makeDepthStencilState(descriptor: trackingPointDepthStateDescriptor)
        
    }
    
    private func loadPipeline() {
            
        guard let modelParser = anchorModelParser else {
            print("Model Perser is nil.")
            fatalError()
        }
        
        guard let meshGPUData = anchorMeshGPUData else {
            print("ERROR: No meshGPUData found when trying to load the pipeline.")
            fatalError()
        }
        
        let anchorVertexDescriptor = createMetalVertexDescriptor(withModelIOVertexDescriptor: modelParser.vertexDescriptors)
        
        for (drawIdx, drawData) in meshGPUData.drawData.enumerated() {
            let anchorPipelineStateDescriptor = MTLRenderPipelineDescriptor()
            do {
                let funcConstants = MetalUtilities.getFuncConstantsForDrawDataSet(meshData: modelParser.meshes[drawIdx], useMaterials: usesMaterials)
                // TODO: Implement a vertex shader with puppet animation support
//                let vertexName = (drawData.paletteStartIndex != nil) ? "vertex_skinned" : "anchorGeometryVertexTransform"
                let vertexName = "anchorGeometryVertexTransform"
                let fragFunc = try defaultLibrary.makeFunction(name: "anchorGeometryFragmentLighting",
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
        
        guard let meshProvider = meshProvider else {
            print("Serious Error - Mesh Provider not found.")
            return
        }
        
        //
        // Create and load our assets into Metal objects including meshes and textures
        //
        
        meshProvider.loadMesh(forType: .anchor) { asset in
            
            guard let asset = asset else {
                print("Serious Error - Failed to get asset from meshProvider.")
                return
            }
            
            guard let geometryVertexDescriptor = geometryVertexDescriptor else {
                print("Serious Error - Geometry Vertex Descriptor is nil.")
                return
            }
            
            // Creata a Model IO vertexDescriptor so that we format/layout our model IO mesh vertices to
            // fit our Metal render pipeline's vertex descriptor layout
            let vertexDescriptor = MTKModelIOVertexDescriptorFromMetal(geometryVertexDescriptor)
            
            // Indicate how each Metal vertex descriptor attribute maps to each ModelIO attribute
            (vertexDescriptor.attributes[Int(kVertexAttributePosition.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributePosition
            (vertexDescriptor.attributes[Int(kVertexAttributeTexcoord.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributeTextureCoordinate
            (vertexDescriptor.attributes[Int(kVertexAttributeNormal.rawValue)] as! MDLVertexAttribute).name   = MDLVertexAttributeNormal
            
            // Load meshes into mode parser
            anchorModelParser = ModelParser(asset: asset, vertexDescriptor: vertexDescriptor)
            
            // TODO: Figure out a way to load a new mesh per anchor.
            
        }
        
        meshProvider.loadMesh(forType: .horizPlane) { asset in
            
            guard let geometryVertexDescriptor = geometryVertexDescriptor else {
                print("Serious Error - Geometry Vertex Descriptor is nil.")
                return
            }
            
            // Creata a Model IO vertexDescriptor so that we format/layout our model IO mesh vertices to
            // fit our Metal render pipeline's vertex descriptor layout
            let vertexDescriptor = MTKModelIOVertexDescriptorFromMetal(geometryVertexDescriptor)
            
            // Indicate how each Metal vertex descriptor attribute maps to each ModelIO attribute
            (vertexDescriptor.attributes[Int(kVertexAttributePosition.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributePosition
            (vertexDescriptor.attributes[Int(kVertexAttributeTexcoord.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributeTextureCoordinate
            (vertexDescriptor.attributes[Int(kVertexAttributeNormal.rawValue)] as! MDLVertexAttribute).name   = MDLVertexAttributeNormal
            
            if let asset = asset {
                horizPlaneModelParser = ModelParser(asset: asset, vertexDescriptor: vertexDescriptor)
            } else {
            
                // Create a MetalKit mesh buffer allocator so that ModelIO will load mesh data directly into
                // Metal buffers accessible by the GPU
                let metalAllocator = MTKMeshBufferAllocator(device: device)
                
                let mesh = MDLMesh(planeWithExtent: vector3(1, 0, 1), segments: vector2(1, 1), geometryType: .triangles, allocator: metalAllocator)
                if let submesh = mesh.submeshes?.firstObject as? MDLSubmesh {
                    let scatteringFunction = MDLPhysicallyPlausibleScatteringFunction()
                    scatteringFunction.baseColor.textureSamplerValue = MDLTextureSampler()
                    scatteringFunction.baseColor.textureSamplerValue?.texture = MDLTexture(named: "plane_grid.png")
                    submesh.material = MDLMaterial(name: "Grid", scatteringFunction: scatteringFunction)
//                        let gridAssetURL = Bundle.main.url(forResource: "plane_grid", withExtension: ".png")
                }
                let asset = MDLAsset(bufferAllocator: metalAllocator)
                asset.add(mesh)
                horizPlaneModelParser = ModelParser(asset: asset, vertexDescriptor: vertexDescriptor)
                
            }
            
        }
        
        meshProvider.loadMesh(forType: .vertPlane) { asset in
            
            guard let asset = asset else {
                return
            }
            
            guard let geometryVertexDescriptor = geometryVertexDescriptor else {
                print("Serious Error - Geometry Vertex Descriptor is nil.")
                return
            }
            
            // Creata a Model IO vertexDescriptor so that we format/layout our model IO mesh vertices to
            // fit our Metal render pipeline's vertex descriptor layout
            let vertexDescriptor = MTKModelIOVertexDescriptorFromMetal(geometryVertexDescriptor)
            
            // Indicate how each Metal vertex descriptor attribute maps to each ModelIO attribute
            (vertexDescriptor.attributes[Int(kVertexAttributePosition.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributePosition
            (vertexDescriptor.attributes[Int(kVertexAttributeTexcoord.rawValue)] as! MDLVertexAttribute).name = MDLVertexAttributeTextureCoordinate
            (vertexDescriptor.attributes[Int(kVertexAttributeNormal.rawValue)] as! MDLVertexAttribute).name   = MDLVertexAttributeNormal
            
            // Load meshes into mode parser
            vertPlaneModelParser = ModelParser(asset: asset, vertexDescriptor: vertexDescriptor)
            
        }
        
    }
    
    private func loadMeshesFromParser() {
        
        guard let modelParser = anchorModelParser else {
            print("ERROR: Model Parser not found when attempting to load meshes.")
            fatalError()
        }
        
        if modelParser.meshNodeIndices.count > 1 {
            print("WARNING: More than one mesh was found. Currently only one mesh per anchor is supported.")
        }
        
        anchorMeshGPUData = meshData(from: modelParser)
        totalMeshTransforms = modelParser.meshNodeIndices.count
        
        if let horizPlaneModelParser = horizPlaneModelParser {
            horizPlaneMeshGPUData = meshData(from: horizPlaneModelParser)
        }
        
        if let vertPlaneModelParser = vertPlaneModelParser {
            vertPlaneMeshGPUData = meshData(from: vertPlaneModelParser)
        }
        
    }
    
    private func meshData(from aModelParser: ModelParser) -> MeshGPUData {
        
        var myGPUData = MeshGPUData()
        
        // Create Vertex Buffers
        for vtxBuffer in aModelParser.vertexBuffers {
            vtxBuffer.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) in
                guard let aVTXBuffer = device.makeBuffer(bytes: bytes, length: vtxBuffer.count, options: .storageModeShared) else {
                    fatalError("Failed to create a buffer from the device.")
                }
                myGPUData.vtxBuffers.append(aVTXBuffer)
            }
            
        }
        
        // Create Index Buffers
        for idxBuffer in aModelParser.indexBuffers {
            idxBuffer.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) in
                guard let aIDXBuffer = device.makeBuffer(bytes: bytes, length: idxBuffer.count, options: .storageModeShared) else {
                    fatalError("Failed to create a buffer from the device.")
                }
                myGPUData.indexBuffers.append(aIDXBuffer)
            }
        }
        
        // Create Texture Buffers
        for texturePath in aModelParser.texturePaths {
            myGPUData.textures.append(createMTLTexture(fromAssetPath: texturePath))
        }
        
        // Encode the data in the meshes as DrawData objects and store them in the MeshGPUData
        var instStartIdx = 0
        var paletteStartIdx = 0
        for (meshIdx, meshData) in aModelParser.meshes.enumerated() {
            
            var drawData = DrawData()
            drawData.vbCount = meshData.vbCount
            drawData.vbStartIdx = meshData.vbStartIdx
            drawData.ibStartIdx = meshData.ibStartIdx
            drawData.instCount = !aModelParser.instanceCount.isEmpty ? aModelParser.instanceCount[meshIdx] : 1
            drawData.instBufferStartIdx = instStartIdx
            if !aModelParser.meshSkinIndices.isEmpty,
                let paletteIndex = aModelParser.meshSkinIndices[instStartIdx] {
                drawData.paletteSize = aModelParser.skins[paletteIndex].jointPaths.count
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
                if usesMaterials {
                    
                    guard let materialUniformBuffer = materialUniformBuffer else {
                        print("Serious Error - Material Uniform Buffer is nil")
                        return myGPUData
                    }
                    
                    MetalUtilities.convertMaterialBuffer(from: meshData.materials[subIndex], with: materialUniformBuffer, offset: materialUniformBufferOffset)
                    subData.materialBuffer = materialUniformBuffer
                    
                }
                subData.baseColorTexIdx = usesMaterials ? meshData.materials[subIndex].baseColor.1 : nil
                subData.normalTexIdx = usesMaterials ? meshData.materials[subIndex].normalMap : nil
                subData.aoTexIdx = usesMaterials ? meshData.materials[subIndex].ambientOcclusionMap : nil
                subData.roughTexIdx = usesMaterials ? meshData.materials[subIndex].roughness.1 : nil
                subData.metalTexIdx = usesMaterials ? meshData.materials[subIndex].metallic.1 : nil
                drawData.subData.append(subData)
            }
            
            myGPUData.drawData.append(drawData)
            
        }
        
        return myGPUData
        
    }
    
    private func createMTLTexture(fromAssetPath assetPath: String) -> MTLTexture? {
        do {
            
            let textureURL: URL? = {
                guard let aURL = URL(string: assetPath) else {
                    return nil
                }
                if aURL.scheme == nil {
                    // If there is no scheme, assume it's a file in the bundle.
                    let last = aURL.lastPathComponent
                    if let bundleURL = Bundle.main.url(forResource: last, withExtension: nil) {
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
            
            return try textureLoader.newTexture(URL: aURL, options: nil)
            
        } catch {
            print("Unable to loader texture with assetPath \(assetPath) with error \(error)")
        }
        
        return nil
    }
    
    private func createMetalVertexDescriptor(withModelIOVertexDescriptor vtxDesc: [MDLVertexDescriptor]) -> MTLVertexDescriptor {
        guard let mtlVertexDescriptor = MTKMetalVertexDescriptorFromModelIO(vtxDesc[0]) else {
            fatalError("Failed to create a MetalKit vertex descriptor from ModelIO.")
        }
        return mtlVertexDescriptor
    }
    
    // MARK: - Render loop
    
    // MARK: Step 1 - Update State
    // Update the location(s) to which we'll write to in our dynamically changing Metal buffers for
    // the current frame (i.e. update our slot in the ring buffer used for the current frame)
    private func updateBufferStates() {
        
        uniformBufferIndex = (uniformBufferIndex + 1) % Constants.maxBuffersInFlight
        
        sharedUniformBufferOffset = Constants.alignedSharedUniformsSize * uniformBufferIndex
        anchorUniformBufferOffset = Constants.alignedAnchorInstanceUniformsSize * uniformBufferIndex
        materialUniformBufferOffset = Constants.alignedMaterialSize * uniformBufferIndex
        trackingPointDataBufferOffset = Constants.alignedTrackingPointDataSize * uniformBufferIndex
        
        sharedUniformBufferAddress = sharedUniformBuffer?.contents().advanced(by: sharedUniformBufferOffset)
        anchorUniformBufferAddress = anchorUniformBuffer?.contents().advanced(by: anchorUniformBufferOffset)
        materialUniformBufferAddress = materialUniformBuffer?.contents().advanced(by: materialUniformBufferOffset)
        trackingPointDataBufferAddress = trackingPointDataBuffer?.contents().advanced(by: trackingPointDataBufferOffset)
        
    }
    
    // MARK: Step 2 - Update Metal Buffers
    private func updateBuffers() {
        
        guard let currentFrame = session.currentFrame else {
            return
        }
        
        updateSharedUniforms(frame: currentFrame)
        updateAnchors(frame: currentFrame)
        updateTrackingPoints(frame: currentFrame)
        updateCapturedImageTextures(frame: currentFrame)
        
        if viewportSizeDidChange {
            viewportSizeDidChange = false
            updateImagePlane(frame: currentFrame)
        }
        
        // From documentation:
        // This transform creates a local coordinate space for the camera that is constant
        // with respect to device orientation. In camera space, the x-axis points to the right
        // when the device is in landscapeRight orientation—that is, the x-axis always points
        // along the long axis of the device, from the front-facing camera toward the Home button.
        // The y-axis points upward (with respect to landscapeRight orientation), and the z-axis
        // points away from the device on the screen side.
        //
        // In order to orient the transform relative to word space, we take the camera transform
        // and the cameras current rotation (given by the eulerAngles) and rotate the transform
        // in the opposite direction. The result is a transform at the position of the camera
        // but oriented along the same axes as world space.
        let cameraQuaternion = QuaternionUtilities.quaternionFromEulerAngles(pitch: currentFrame.camera.eulerAngles.x, roll: currentFrame.camera.eulerAngles.y, yaw: currentFrame.camera.eulerAngles.z)
        let inverseCameraRotation = GLKQuaternionInvert(cameraQuaternion)
        
        let invertedRotationMatrix = unsafeBitCast(GLKMatrix4MakeWithQuaternion(inverseCameraRotation), to: simd_float4x4.self)
        currentCameraPositionTransform = currentFrame.camera.transform * invertedRotationMatrix
        currentCameraQuaternionRotation = cameraQuaternion
        currentCameraHeading = Double(currentFrame.camera.eulerAngles.y)
        
    }
    
    // MARK: Update Uniforms
    
    // Update the shared uniforms of the frame
    private func updateSharedUniforms(frame: ARFrame) {
        
        let uniforms = sharedUniformBufferAddress?.assumingMemoryBound(to: SharedUniforms.self)
        
        uniforms?.pointee.viewMatrix = frame.camera.viewMatrix(for: orientation)
        uniforms?.pointee.projectionMatrix = frame.camera.projectionMatrix(for: orientation, viewportSize: viewportSize, zNear: 0.001, zFar: 1000)
        
        // Set up lighting for the scene using the ambient intensity if provided
        var ambientIntensity: Float = 1.0
        
        if let lightEstimate = frame.lightEstimate {
            ambientIntensity = Float(lightEstimate.ambientIntensity) / 1000.0
        }
        
        let ambientLightColor: vector_float3 = vector3(0.5, 0.5, 0.5)
        uniforms?.pointee.ambientLightColor = ambientLightColor * ambientIntensity
        
        var directionalLightDirection : vector_float3 = vector3(0.0, 0.0, -1.0)
        directionalLightDirection = simd_normalize(directionalLightDirection)
        uniforms?.pointee.directionalLightDirection = directionalLightDirection
        
        let directionalLightColor: vector_float3 = vector3(0.6, 0.6, 0.6)
        uniforms?.pointee.directionalLightColor = directionalLightColor * ambientIntensity
        
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
                    // Keep track of the lowest horizontal plane. This can be assumed to be the ground.
                    if lowestHorizPlaneAnchor != nil {
                        if plane.transform.columns.1.y < lowestHorizPlaneAnchor?.transform.columns.1.y ?? 0 {
                            lowestHorizPlaneAnchor = plane
                        }
                    } else {
                        lowestHorizPlaneAnchor = plane
                    }
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
            
            if let modelParser = anchorModelParser, !(anchor is ARPlaneAnchor) {
                
                // Apply the world transform (as defined in the imported model) if applicable
                let anchorIndex = index - horizPlaneInstanceCount - vertPlaneInstanceCount
                if let modelParserIndex = modelParserIndex(in: modelParser, fromAnchorIndex: anchorIndex), modelParserIndex < modelParser.worldTransforms.count {
                    let worldTransform = modelParser.worldTransforms[modelParserIndex]
                    coordinateSpaceTransform = simd_mul(coordinateSpaceTransform, worldTransform)
                }
                
            }
            
            var modelMatrix = anchor.transform * coordinateSpaceTransform
            if let plane = anchor as? ARPlaneAnchor {
                modelMatrix = modelMatrix.scale(x: plane.extent.x, y: plane.extent.y, z: plane.extent.z)
                modelMatrix = modelMatrix.translate(x: -plane.center.x/2.0, y: -plane.center.y/2.0, z: -plane.center.z/2.0)
            }

            let anchorUniforms = anchorUniformBufferAddress?.assumingMemoryBound(to: AnchorInstanceUniforms.self).advanced(by: index)
            anchorUniforms?.pointee.modelMatrix = modelMatrix
            
        }
        
        logger?.updatedAnchors(count: frame.anchors.count, numAnchors: anchorInstanceCount, numPlanes: horizPlaneInstanceCount, numTrackingPoints: trackingPointCount)
        
    }
    
    private func updateTrackingPoints(frame: ARFrame) {
        
        trackingPointCount = 0
        
        guard let rawFeaturePoints = frame.rawFeaturePoints else {
            return
        }
        
        for index in 0..<rawFeaturePoints.points.count {
            
            if index >= Constants.maxTrackingPointCount {
                break
            }
            
            /**
             * Memory layout of struct PointVertexIn struct:
             *  float4 position
             *  float4 color
             */
            
            let point = rawFeaturePoints.points[index]
            let trackingPointData = trackingPointDataBufferAddress?.assumingMemoryBound(to: float4.self).advanced(by: index * 2)
            trackingPointData?.pointee = vector4(point, 1.0)
            
            let colorData = trackingPointDataBufferAddress?.assumingMemoryBound(to: float4.self).advanced(by: index * 2 + 1)
            colorData?.pointee = vector4(0.5, 1.0, 1.0, 1.0) // Light blue
            
            trackingPointCount += 1
            
            if trackingPointCount > Constants.maxTrackingPointCount {
                break
            }
        }
        
    }
    
    // MARK: Update Textures
    
    private func updateCapturedImageTextures(frame: ARFrame) {
        // Create two textures (Y and CbCr) from the provided frame's captured image
        let pixelBuffer = frame.capturedImage
        
        if (CVPixelBufferGetPlaneCount(pixelBuffer) < 2) {
            return
        }
        
        capturedImageTextureY = createTexture(fromPixelBuffer: pixelBuffer, pixelFormat:.r8Unorm, planeIndex:0)
        capturedImageTextureCbCr = createTexture(fromPixelBuffer: pixelBuffer, pixelFormat:.rg8Unorm, planeIndex:1)
    }
    
    // MARK: Update background image layer
    
    private func updateImagePlane(frame: ARFrame) {
        // Update the texture coordinates of our image plane to aspect fill the viewport
        let displayToCameraTransform = frame.displayTransform(for: orientation, viewportSize: viewportSize).inverted()
        
        if let vertexData = imagePlaneVertexBuffer?.contents().assumingMemoryBound(to: Float.self) {
            for index in 0...3 {
                let textureCoordIndex = 4 * index + 2
                let textureCoord = CGPoint(x: CGFloat(Constants.imagePlaneVertexData[textureCoordIndex]), y: CGFloat(Constants.imagePlaneVertexData[textureCoordIndex + 1]))
                let transformedCoord = textureCoord.applying(displayToCameraTransform)
                vertexData[textureCoordIndex] = Float(transformedCoord.x)
                vertexData[textureCoordIndex + 1] = Float(transformedCoord.y)
            }
        }
    }
    
    // MARK: Drawing
    
    private func drawCapturedImage(renderEncoder: MTLRenderCommandEncoder) {
        
        guard let textureY = capturedImageTextureY, let textureCbCr = capturedImageTextureCbCr else {
            return
        }
        
        guard let capturedImagePipelineState = capturedImagePipelineState else {
            print("Serious Error - Captured Image Pipeline State ids nil")
            return
        }
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("Draw Captured Image")
        
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
        
        renderEncoder.pushDebugGroup("Draw Shared Uniforms")
        
        renderEncoder.setVertexBuffer(sharedUniformBuffer, offset: sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
        renderEncoder.setFragmentBuffer(sharedUniformBuffer, offset: sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
        
        renderEncoder.popDebugGroup()
        
    }
    
    private func drawAnchors(renderEncoder: MTLRenderCommandEncoder) {
        
        guard anchorInstanceCount > 0 else {
            return
        }
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("Draw Anchors")
        
        // Set render command encoder state
        renderEncoder.setCullMode(.back)
        
        guard let meshGPUData = anchorMeshGPUData else {
            print("Error: meshGPUData not available a draw time. Aborting")
            return
        }
        
        for (drawDataIdx, drawData) in meshGPUData.drawData.enumerated() {
            
            if drawDataIdx < anchorPipelineStates.count {
                renderEncoder.setRenderPipelineState(anchorPipelineStates[drawDataIdx])
                renderEncoder.setDepthStencilState(anchorDepthState)
                
                // Set any buffers fed into our render pipeline
                renderEncoder.setVertexBuffer(anchorUniformBuffer, offset: anchorUniformBufferOffset, index: Int(kBufferIndexAnchorInstanceUniforms.rawValue))
                
                var mutableDrawData = drawData
                mutableDrawData.instCount = anchorInstanceCount
                
                // Set the mesh's vertex data buffers
                encode(meshGPUData: meshGPUData, fromDrawData: mutableDrawData, with: renderEncoder)
                
            }
            
        }
        
        renderEncoder.popDebugGroup()
        
    }
    
    private func drawPlanes(renderEncoder: MTLRenderCommandEncoder) {
        
        guard horizPlaneInstanceCount > 0 else {
            return
        }
        
        // TODO: Support vertical planes
        
        guard showGuides else {
            return
        }
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("Draw Planes")
        
        // Set render command encoder state
        renderEncoder.setCullMode(.back)
        
        guard let meshGPUData = horizPlaneMeshGPUData else {
            print("Error: meshGPUData not available a draw time. Aborting")
            return
        }
        
        for (drawDataIdx, drawData) in meshGPUData.drawData.enumerated() {
            
            if drawDataIdx < anchorPipelineStates.count {
                renderEncoder.setRenderPipelineState(anchorPipelineStates[drawDataIdx])
                renderEncoder.setDepthStencilState(anchorDepthState)
                
                // Set any buffers fed into our render pipeline
                renderEncoder.setVertexBuffer(anchorUniformBuffer, offset: anchorUniformBufferOffset, index: Int(kBufferIndexAnchorInstanceUniforms.rawValue))
                renderEncoder.setVertexBuffer(sharedUniformBuffer, offset: sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
                renderEncoder.setFragmentBuffer(sharedUniformBuffer, offset: sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
                
                var mutableDrawData = drawData
                mutableDrawData.instCount = horizPlaneInstanceCount + vertPlaneInstanceCount
                
                // Set the mesh's vertex data buffers
                encode(meshGPUData: meshGPUData, fromDrawData: mutableDrawData, with: renderEncoder)
                
            }
            
        }
        
        renderEncoder.popDebugGroup()
        
    }
    
    private func drawTrackingPoints(renderEncoder: MTLRenderCommandEncoder) {
        
        guard showGuides else {
            return
        }
        
        guard let trackingPointPipelineState = trackingPointPipelineState else {
            return
        }
        
        guard trackingPointCount > 0 else {
            return
        }
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("Draw Tracking Points")
        
        renderEncoder.setRenderPipelineState(trackingPointPipelineState)
        renderEncoder.setVertexBuffer(trackingPointDataBuffer, offset: trackingPointDataBufferOffset, index: Int(kBufferIndexTrackingPointData.rawValue))
        renderEncoder.setVertexBuffer(sharedUniformBuffer, offset: sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: trackingPointCount)
        
        renderEncoder.popDebugGroup()
        
    }
    
    // MARK: Encoding from MeshGPUData
    
    private func encode(meshGPUData: MeshGPUData, fromDrawData drawData: DrawData, with renderEncoder: MTLRenderCommandEncoder) {
        
        // Set mesh's vertex buffers
        for vtxBufferIdx in 0..<drawData.vbCount {
            renderEncoder.setVertexBuffer(meshGPUData.vtxBuffers[drawData.vbStartIdx + vtxBufferIdx], offset: 0, index: vtxBufferIdx)
        }
        
        // Draw each submesh of our mesh
        for drawDataSubIndex in 0..<drawData.subData.count {
            
            let submeshData = drawData.subData[drawDataSubIndex]
            
            // Sets the weight of values sampled from a texture vs value from a material uniform
            // for a transition between quality levels
//            submeshData.computeTextureWeights(for: currentQualityLevel, with: globalMapWeight)
            
            let idxCount = Int(submeshData.idxCount)
            let idxType = submeshData.idxType
            let ibOffset = drawData.ibStartIdx
            let indexBuffer = meshGPUData.indexBuffers[ibOffset + drawDataSubIndex]
            var materialUniforms = submeshData.materialUniforms
            
            // Set textures based off material flags
            encodeTextures(with: meshGPUData, renderEncoder: renderEncoder, subData: submeshData)
            
            // Set Material
            // FIXME: Using a buffer is not working. I think the buffer is set up wrong.
//            let materialBuffer = submeshData.materialBuffer
//            if let materialBuffer = materialBuffer {
//                renderEncoder.setFragmentBuffer(materialBuffer, offset: materialUniformBufferOffset, index: Int(kBufferIndexMaterialUniforms.rawValue))
//            } else {
//                renderEncoder.setFragmentBytes(&materialUniforms, length: Constants.alignedMaterialSize, index: Int(kBufferIndexMaterialUniforms.rawValue))
//            }
            
            renderEncoder.setFragmentBytes(&materialUniforms, length: Constants.alignedMaterialSize, index: Int(kBufferIndexMaterialUniforms.rawValue))
            
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
    
    // MARK: Util
    
    private func modelParserIndex(in modelParser: ModelParser, fromAnchorIndex anchorIndex: Int) -> Int? {
        if anchorIndex < modelParser.meshNodeIndices.count, anchorIndex >= 0 {
            return modelParser.meshNodeIndices[anchorIndex]
        } else {
            return nil
        }
    }
    
    private func createTexture(fromPixelBuffer pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat, planeIndex: Int) -> CVMetalTexture? {
        
        guard let capturedImageTextureCache = capturedImageTextureCache else {
            print("Serious Error - Cptured Image Texture Cache is nil")
            return nil
        }
        
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        
        var texture: CVMetalTexture? = nil
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, capturedImageTextureCache, pixelBuffer, nil, pixelFormat, width, height, planeIndex, &texture)
        
        if status != kCVReturnSuccess {
            texture = nil
        }
        
        return texture
    }
    
}
