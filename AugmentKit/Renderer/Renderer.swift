//
//  Renderer.swift
//  AugmentKit
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
import ARKit
import AugmentKitShader
import Metal
import MetalKit
import ModelIO

// MARK: - RenderDestinationProvider

public protocol RenderDestinationProvider {
    var currentRenderPassDescriptor: MTLRenderPassDescriptor? { get }
    var currentDrawable: CAMetalDrawable? { get }
    var colorPixelFormat: MTLPixelFormat { get set }
    var depthStencilPixelFormat: MTLPixelFormat { get set }
    var sampleCount: Int { get set }
}

// MARK: - RenderDebugLogger

public protocol RenderDebugLogger {
    func updatedAnchors(count: Int, numAnchors: Int, numPlanes: Int, numTrackingPoints: Int)
}

// MARK: - CameraProperties

public struct CameraProperties {
    var orientation: UIInterfaceOrientation
    var viewportSize: CGSize
    var viewportSizeDidChange: Bool
    var position: float3
    var currentFrame: Int
}

// MARK: - Renderer

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
    
    public var modelProvider: ModelProvider? = AKModelProvider.sharedInstance
    
    // Guides for debugging. Turning this on will show the tracking points used by
    // ARKit as well as detected surfaces. Setting this to true will
    // affect performance.
    public var showGuides = false {
        didSet {
            if showGuides {
                if renderModules.filter({$0 is TrackingPointsRenderModule}).count == 0 {
                    renderModules.append(TrackingPointsRenderModule())
                }
            } else {
                var newModules: [RenderModule] = []
                for module in renderModules {
                    if !(module is TrackingPointsRenderModule) {
                        newModules.append(module)
                    }
                }
                renderModules = newModules
            }
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
    public var currentFrameNumber: Int {
        guard worldInitiationTime > 0 && lastFrameTime > 0 else {
            return 0
        }
        
        let elapsedTime = lastFrameTime - worldInitiationTime
        let fps = 1.0/60.0
        return Int(floor(elapsedTime * fps))
    }
    
    public init(session: ARSession, metalDevice device: MTLDevice, renderDestination: RenderDestinationProvider) {
        self.session = session
        self.device = device
        self.renderDestination = renderDestination
        self.textureLoader = MTKTextureLoader(device: device)
    }
    
    // MARK: - Viewport changes
    
    public func drawRectResized(size: CGSize) {
        viewportSize = size
        viewportSizeDidChange = true
    }
    
    // MARK: - Lifecycle
    
    public func initialize() {
        
        guard state == .uninitialized else {
            return
        }
        
        loadMetal()
        
        for module in renderModules {
            if !module.isInitialized {
                hasUninitializedModules = true
                break
            }
        }
        
        initializeModules()
        
        state = .initialized
        
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
    
    // MARK: Per-frame update call
    
    public func update() {
        
        guard let commandQueue = commandQueue else {
            return
        }
        
        guard let currentFrame = session.currentFrame else {
            return
        }
        
        if worldInitiationTime == 0 {
            worldInitiationTime = Date().timeIntervalSinceReferenceDate
        }
        
        lastFrameTime = currentFrame.timestamp
        
        let surfaceAnchors = currentFrame.anchors.filter({$0 is ARPlaneAnchor}) as! [ARPlaneAnchor]
        let normalAnchors = currentFrame.anchors.filter({!($0 is ARPlaneAnchor)})
        
        // Update current camera position and heading
        //
        // From documentation:
        // This transform creates a local coordinate space for the camera that is constant
        // with respect to device orientation. In camera space, the x-axis points to the right
        // when the device is in landscapeRight orientation—that is, the x-axis always points
        // along the long axis of the device, from the front-facing camera toward the Home button.
        // The y-axis points upward (with respect to landscapeRight orientation), and the z-axis
        // points away from the device on the screen side.
        //
        // In order to orient the transform relative to world space, we take the camera transform
        // and the cameras current rotation (given by the eulerAngles) and rotate the transform
        // in the opposite direction. The result is a transform at the position of the camera
        // but oriented along the same axes as world space.
        let eulerAngles = QuaternionUtilities.EulerAngles(roll: currentFrame.camera.eulerAngles.z, pitch: currentFrame.camera.eulerAngles.x, yaw: currentFrame.camera.eulerAngles.y)
        let cameraQuaternion = QuaternionUtilities.quaternionFromEulerAngles(eulerAngles: eulerAngles)
        var positionOnlyTransform = matrix_identity_float4x4
        positionOnlyTransform = positionOnlyTransform.translate(x: currentFrame.camera.transform.columns.3.x, y: currentFrame.camera.transform.columns.3.y, z: currentFrame.camera.transform.columns.3.z)
        currentCameraPositionTransform = positionOnlyTransform
        currentCameraQuaternionRotation = cameraQuaternion
        currentCameraHeading = Double(currentFrame.camera.eulerAngles.y)
        
        // Update the lowest surface plane
        for index in 0..<surfaceAnchors.count {
            let plane = surfaceAnchors[index]
            if plane.alignment == .horizontal {
                // Keep track of the lowest horizontal plane. This can be assumed to be the ground.
                if lowestHorizPlaneAnchor != nil {
                    if plane.transform.columns.1.y < lowestHorizPlaneAnchor?.transform.columns.1.y ?? 0 {
                        lowestHorizPlaneAnchor = plane
                    }
                } else {
                    lowestHorizPlaneAnchor = plane
                }
            }
        }
        
        //
        // Initialize Modules
        //
        
        // Add surface modules for rendering if necessary
        if surfacesRenderModule == nil && showGuides && surfaceAnchors.count > 0  {
            addModule(forModuelIdentifier: SurfacesRenderModule.identifier)
        }
        
        // Add anchor modules if necessary
        if anchorsRenderModule == nil && normalAnchors.count > 0 {
            addModule(forModuelIdentifier: AnchorsRenderModule.identifier)
        }
        
        // Add tracker modules if nescessary
        if trackersRenderModule == nil && trackers.count > 0 {
            addModule(forModuelIdentifier: TrackersRenderModule.identifier)
        }
        
        // Add paths modules if nescessary
        if pathsRenderModule == nil && paths.count > 0 {
            addModule(forModuelIdentifier: PathsRenderModule.identifier)
        }
        
        initializeModules()
        
        //
        // Update positions
        //
        
//        func normalize(_ angle: Float, forMinimalRotationTo ref: Float) -> Float {
//            // Normalize angle in steps of 90 degrees such that the rotation to the other angle is minimal
//            var normalized = angle
//            while abs(normalized - ref) > Float.pi / 4 {
//                if angle > ref {
//                    normalized -= Float.pi / 2
//                } else {
//                    normalized += Float.pi / 2
//                }
//            }
//            return normalized
//        }
        
//        let aRotation: Float = {
//            // Correct y rotation of camera square
//            let tilt = abs(currentFrame.camera.eulerAngles.x)
//            let threshold1: Float = Float.pi / 2 * 0.65
//            let threshold2: Float = Float.pi / 2 * 0.75
//            let yaw = atan2f(currentFrame.camera.transform.columns.0.x, currentFrame.camera.transform.columns.1.x)
//            var angle: Float = 0
//
//            switch tilt {
//            case 0..<threshold1:
//                angle = currentFrame.camera.eulerAngles.y
//            case threshold1..<threshold2:
//                let relativeInRange = abs((tilt - threshold1) / (threshold2 - threshold1))
//                let normalizedY = normalize(currentFrame.camera.eulerAngles.y, forMinimalRotationTo: yaw)
//                angle = normalizedY * (1 - relativeInRange) + yaw * relativeInRange
//            default:
//                angle = yaw
//            }
//            return angle
//
//        }()
        
        // Calculate updates to trackers relative position
        for tracker in trackers {
            if let userTracker = tracker as? AKUserTracker {
                let cameraPositionTransform = currentCameraPositionTransform ?? matrix_identity_float4x4
                userTracker.userPosition?.transform = cameraPositionTransform
            }
            tracker.position.updateTransforms()
        }
        
        //
        // Encode Cammand Buffer
        //
        
        // Wait to ensure only kMaxBuffersInFlight are getting proccessed by any stage in the Metal
        // pipeline (App, Metal, Drivers, GPU, etc)
        let _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        // Create a new command buffer for each renderpass to the current drawable
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            
            commandBuffer.label = "RenderCommandBuffer"
            
            // Add completion hander which signal _inFlightSemaphore when Metal and the GPU has fully
            // finished proccssing the commands we're encoding this frame.  This indicates when the
            // dynamic buffers, that we're writing to this frame, will no longer be needed by Metal
            // and the GPU.
            commandBuffer.addCompletedHandler{ [weak self] commandBuffer in
                if let strongSelf = self {
                    strongSelf.inFlightSemaphore.signal()
                    for module in strongSelf.renderModules {
                        module.frameEncodingComplete()
                    }
                }
            }
            
            uniformBufferIndex = (uniformBufferIndex + 1) % Constants.maxBuffersInFlight
            
            // Update Buffer States
            for module in renderModules {
                if module.isInitialized {
                    module.updateBufferState(withBufferIndex: uniformBufferIndex)
                }
            }
            
            let cameraPosition: float3 = {
                if let currentCameraPositionTransform = currentCameraPositionTransform {
                    return float3(currentCameraPositionTransform.columns.3.x, currentCameraPositionTransform.columns.3.y, currentCameraPositionTransform.columns.3.z)
                } else {
                    return float3(0, 0, 0)
                }
            }()
            
            let cameraProperties = CameraProperties(orientation: orientation, viewportSize: viewportSize, viewportSizeDidChange: viewportSizeDidChange, position: cameraPosition, currentFrame: currentFrameNumber)
            
            // Update Buffers
            for module in renderModules {
                if module.isInitialized {
                    module.updateBuffers(withARFrame: currentFrame, cameraProperties: cameraProperties)
                    module.updateBuffers(withTrackers: trackers, cameraProperties: cameraProperties)
                    module.updateBuffers(withPaths: paths, cameraProperties: cameraProperties)
                }
            }
            
            if let renderPassDescriptor = renderDestination.currentRenderPassDescriptor, let currentDrawable = renderDestination.currentDrawable, let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                
                renderEncoder.label = "RenderEncoder"
                
                // Draw
                for module in renderModules {
                    if module.isInitialized {
                        module.draw(withRenderEncoder: renderEncoder, sharedModules: sharedModulesForModule[module.moduleIdentifier])
                    }
                }
                
                // We're done encoding commands
                renderEncoder.endEncoding()
                
                // Schedule a present once the framebuffer is complete using the current drawable
                commandBuffer.present(currentDrawable)
            }
            
            // Finalize rendering here & push the command buffer to the GPU
            commandBuffer.commit()
        }
        
        // Update viewportSizeDidChange state
        if viewportSizeDidChange {
            viewportSizeDidChange = false
        }
        
        logger?.updatedAnchors(count: currentFrame.anchors.count, numAnchors: anchorsRenderModule?.anchorInstanceCount ?? 0, numPlanes: surfacesRenderModule?.surfaceInstanceCount ?? 0, numTrackingPoints: trackingPointRenderModule?.trackingPointCount ?? 0)
        
    }
    
    // MARK: - Anchors
    
    //  Add a new AKAugmentedAnchor to the AR world
    public func add(akAnchor: AKAugmentedAnchor) {
        
        let anchorType = type(of: akAnchor).type
        
        // Resgister the AKModel with the model provider.
        modelProvider?.registerModel(akAnchor.model, forObjectType: anchorType)
        
        // Add a new anchor to the session
        let arAnchor = ARAnchor(transform: akAnchor.worldLocation.transform)
        let identifier = arAnchor.identifier
        var mutableAnchor = akAnchor
        mutableAnchor.setIdentiier(identifier)
        augmentedAnchors.append(mutableAnchor)
        
        // Keep track of the anchor's UUID bucketed by the AKAnchor.type
        // This will be used to associate individual anchors with AKAnchor.type's,
        // then associate AKAnchor.type's with models.
        if let uuidSet = anchorIdentifiersForType[anchorType] {
            var mutableUUIDSet = uuidSet
            mutableUUIDSet.insert(identifier)
            anchorIdentifiersForType[anchorType] = mutableUUIDSet
        } else {
            let uuidSet = Set([identifier])
            anchorIdentifiersForType[anchorType] = uuidSet
        }
        
        session.add(anchor: arAnchor)
        
    }
    
    //  Add a new AKAugmentedTracker to the AR world
    public func add(akTracker: AKAugmentedTracker) {
        
        let anchorType = type(of: akTracker).type
        
        // Resgister the AKModel with the model provider.
        modelProvider?.registerModel(akTracker.model, forObjectType: anchorType)
        
        trackers.append(akTracker)
        
    }
    
    //  Add a new AKAugmentedTracker to the AR world
    public func addPath(withAnchors anchors: [AKAugmentedAnchor], identifier: UUID) {
        
        var updatedAnchors = [AKAugmentedAnchor]()
        for anchor in anchors {
            
            let anchorType = type(of: anchor).type
            
            // Resgister the AKModel with the model provider.
            modelProvider?.registerModel(anchor.model, forObjectType: anchorType)
            
            // Add a new anchor to the session
            let arAnchor = ARAnchor(transform: anchor.worldLocation.transform)
            let identifier = arAnchor.identifier
            var mutableAnchor = anchor
            mutableAnchor.setIdentiier(identifier)
            updatedAnchors.append(mutableAnchor)
            
            // Keep track of the anchor's UUID bucketed by the AKAnchor.type
            // This will be used to associate individual anchors with AKAnchor.type's,
            // then associate AKAnchor.type's with models.
            if let uuidSet = anchorIdentifiersForType[anchorType] {
                var mutableUUIDSet = uuidSet
                mutableUUIDSet.insert(identifier)
                anchorIdentifiersForType[anchorType] = mutableUUIDSet
            } else {
                let uuidSet = Set([identifier])
                anchorIdentifiersForType[anchorType] = uuidSet
            }
            
            session.add(anchor: arAnchor)
            
        }
        
        paths[identifier] = updatedAnchors
        
    }
    
    // MARK: - Private
    
    private var hasUninitializedModules = false
    private var renderDestination: RenderDestinationProvider
    private let inFlightSemaphore = DispatchSemaphore(value: Constants.maxBuffersInFlight)
    // Used to determine _uniformBufferStride each frame.
    // This is the current frame number modulo kMaxBuffersInFlight
    private var uniformBufferIndex: Int = 0
    // A Quaternion that represents the rotation of the camera relative to world space.
    private var currentCameraQuaternionRotation: GLKQuaternion?
    private var worldInitiationTime: Double = 0
    private var lastFrameTime: Double = 0
    
    // Modules
    private var renderModules: [RenderModule] = [CameraPlaneRenderModule()]
    private var sharedModulesForModule = [String: [SharedRenderModule]]()
    private var cameraRenderModule: CameraPlaneRenderModule?
    private var sharedBuffersRenderModule: SharedBuffersRenderModule?
    private var anchorsRenderModule: AnchorsRenderModule?
    private var trackersRenderModule: TrackersRenderModule?
    private var pathsRenderModule: PathsRenderModule?
    private var surfacesRenderModule: SurfacesRenderModule?
    private var trackingPointRenderModule: TrackingPointsRenderModule?
    
    // Viewport
    private var viewportSize: CGSize = CGSize()
    private var viewportSizeDidChange: Bool = false
    
    // Metal objects
    private let textureLoader: MTKTextureLoader
    private var defaultLibrary: MTLLibrary?
    private var commandQueue: MTLCommandQueue?
    
    // Keeping track of Anchors / Trackers
    private var anchorIdentifiersForType = [String: Set<UUID>]()
    private var augmentedAnchors = [AKAugmentedAnchor]()
    private var trackers = [AKAugmentedTracker]()
    private var paths = [UUID: [AKAugmentedAnchor]]()
    
    // MARK: ARKit Session Configuration
    
    private func createNewConfiguration() -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        // Setting this to .gravityAndHeading aligns the the origin of the scene to compass direction
        configuration.worldAlignment = .gravityAndHeading
        
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
        
        commandQueue = device.makeCommandQueue()
        
    }
    
    // Adds a module to the renderModules array witout being initialized.
    // initializeModules() must be called
    private func addModule(forModuelIdentifier moduleIdentifier: String) {
        
        switch moduleIdentifier {
        case CameraPlaneRenderModule.identifier:
            if cameraRenderModule == nil {
                let newCameraModule = CameraPlaneRenderModule()
                cameraRenderModule = newCameraModule
                renderModules.append(newCameraModule)
                hasUninitializedModules = true
            }
        case SharedBuffersRenderModule.identifier:
            if sharedBuffersRenderModule == nil {
                let newSharedModule = SharedBuffersRenderModule()
                sharedBuffersRenderModule = newSharedModule
                renderModules.append(newSharedModule)
                hasUninitializedModules = true
            }
        case SurfacesRenderModule.identifier:
            if surfacesRenderModule == nil {
                let newSurfacesModule = SurfacesRenderModule()
                surfacesRenderModule = newSurfacesModule
                renderModules.append(newSurfacesModule)
                hasUninitializedModules = true
            }
        case AnchorsRenderModule.identifier:
            if anchorsRenderModule == nil {
                let newAnchorsModule = AnchorsRenderModule()
                anchorsRenderModule = newAnchorsModule
                renderModules.append(newAnchorsModule)
                hasUninitializedModules = true
            }
        case TrackersRenderModule.identifier:
            if trackersRenderModule == nil {
                let newTrackersModule = TrackersRenderModule()
                trackersRenderModule = newTrackersModule
                renderModules.append(newTrackersModule)
                hasUninitializedModules = true
            }
        case PathsRenderModule.identifier:
            if pathsRenderModule == nil {
                let newPathsModule = PathsRenderModule()
                pathsRenderModule = newPathsModule
                renderModules.append(newPathsModule)
                hasUninitializedModules = true
            }
        case TrackingPointsRenderModule.identifier:
            if trackingPointRenderModule == nil {
                let newSharedModule = TrackingPointsRenderModule()
                trackingPointRenderModule = newSharedModule
                renderModules.append(newSharedModule)
                hasUninitializedModules = true
            }
        default:
            break
        }
    
    }
    
    // Updates the renderModules array with all of the required modules.
    // Also updates the sharedModulesForModule map
    private func gatherModules() {
        
        var sharedModules: [SharedRenderModule] = []
        var updatedRenderModules: [RenderModule] = []
        
        for module in renderModules {
            
            updatedRenderModules.append(module)
            
            // Make an array of all of the shared modules for later use
            if module is SharedRenderModule {
                sharedModules.append(module as! SharedRenderModule)
            } else if let sharedModuleIdentifiers = module.sharedModuleIdentifiers {
                for moduleIdentifier in sharedModuleIdentifiers {
                    if let newSharedModule = setupSharedModule(forModuleIdentifier: moduleIdentifier) {
                        sharedModules.append(newSharedModule)
                        updatedRenderModules.append(newSharedModule)
                    }
                }
            }
        }
        
        renderModules = updatedRenderModules.sorted(by: {$0.renderLayer < $1.renderLayer})
        
        // Setup the shared modules map
        for module in renderModules {
            if let sharedModuleIdentifiers = module.sharedModuleIdentifiers, sharedModuleIdentifiers.count > 0 {
                let foundSharedModules = sharedModules.filter({sharedModuleIdentifiers.contains($0.moduleIdentifier)})
                sharedModulesForModule[module.moduleIdentifier] = foundSharedModules
            }
        }
            
    }
    
    // Initializes any uninitialized modules. If a module has already been
    // initialized, the inittilization functions are _not_ called again.
    private func initializeModules() {
        
        guard hasUninitializedModules else {
            return
        }
        
        gatherModules()
        
        for module in renderModules {
            
            if !module.isInitialized {
                // Initialize the module
                module.initializeBuffers(withDevice: device, maxInFlightBuffers: Constants.maxBuffersInFlight)
                
                // Load the assets
                module.loadAssets(fromModelProvider: modelProvider, textureLoader: textureLoader, completion: { [weak self] in
                    if let defaultLibrary = self?.defaultLibrary, let renderDestination = self?.renderDestination {
                        module.loadPipeline(withMetalLibrary: defaultLibrary, renderDestination: renderDestination)
                    }
                })
            }
            
        }
        
        hasUninitializedModules = false
        
    }
    
    // MARK: Shared Modules
    
    func setupSharedModule(forModuleIdentifier moduleIdentifier: String) -> SharedRenderModule? {
        
        switch moduleIdentifier {
        case SharedBuffersRenderModule.identifier:
            if let sharedBuffersRenderModule = sharedBuffersRenderModule {
                return sharedBuffersRenderModule
            } else {
                let newSharedModule = SharedBuffersRenderModule()
                sharedBuffersRenderModule = newSharedModule
                return newSharedModule
            }
        default:
            return nil
        }
    }
    
}
