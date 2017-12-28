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

public struct ViewportProperies {
    var orientation: UIInterfaceOrientation
    var viewportSize: CGSize
    var viewportSizeDidChange: Bool
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
    
    // Guides for debugging
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
        
        initializeModules()
        
        //
        // Update positions
        //
        
        // Calculate updates to trackers relative position
        for tracker in trackers {
            if let userTracker = tracker as? AKUserTracker {
                let cameraPositionTransform = currentCameraPositionTransform ?? matrix_identity_float4x4
                userTracker.position.parentPosition?.transform = cameraPositionTransform
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
            
            let viewportProperties = ViewportProperies(orientation: orientation, viewportSize: viewportSize, viewportSizeDidChange: viewportSizeDidChange)
            
            // Update Buffers
            for module in renderModules {
                if module.isInitialized {
                    module.updateBuffers(withARFrame: currentFrame, viewportProperties: viewportProperties)
                    module.updateBuffers(withTrackers: trackers, viewportProperties: viewportProperties)
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
        
        // Update the current frame
//        currentFrameNumber += 1
        
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
        
        // Keep track of the anchor's UUID bucketed by the AKAnchor.type
        // This will be used to associate individual anchors with AKAnchor.type's,
        // then associate AKAnchor.type's with models.
        if let uuidSet = anchorIdentifiersForType[anchorType] {
            var mutableUUIDSet = uuidSet
            mutableUUIDSet.insert(arAnchor.identifier)
            anchorIdentifiersForType[anchorType] = mutableUUIDSet
        } else {
            let uuidSet = Set([arAnchor.identifier])
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
    
    // MARK: - Private
    
    private var hasUninitializedModules = false
    private var renderDestination: RenderDestinationProvider
    private let inFlightSemaphore = DispatchSemaphore(value: Constants.maxBuffersInFlight)
    // Used to determine _uniformBufferStride each frame.
    // This is the current frame number modulo kMaxBuffersInFlight
    private var uniformBufferIndex: Int = 0
    // A Quaternion that represents the rotation of the camera relative to world space.
    private var currentCameraQuaternionRotation: GLKQuaternion?
    
    // Modules
    private var renderModules: [RenderModule] = [CameraPlaneRenderModule()]
    private var sharedModulesForModule = [String: [SharedRenderModule]]()
    private var cameraRenderModule: CameraPlaneRenderModule?
    private var sharedBuffersRenderModule: SharedBuffersRenderModule?
    private var anchorsRenderModule: AnchorsRenderModule?
    private var trackersRenderModule: TrackersRenderModule?
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
    private var trackers = [AKAugmentedTracker]()
    
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
                let newSharedModule = CameraPlaneRenderModule()
                cameraRenderModule = newSharedModule
                renderModules.append(newSharedModule)
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
                let newSharedModule = SurfacesRenderModule()
                surfacesRenderModule = newSharedModule
                renderModules.append(newSharedModule)
                hasUninitializedModules = true
            }
        case AnchorsRenderModule.identifier:
            if anchorsRenderModule == nil {
                let newSharedModule = AnchorsRenderModule()
                anchorsRenderModule = newSharedModule
                renderModules.append(newSharedModule)
                hasUninitializedModules = true
            }
        case TrackersRenderModule.identifier:
            if trackersRenderModule == nil {
                let newSharedModule = TrackersRenderModule()
                trackersRenderModule = newSharedModule
                renderModules.append(newSharedModule)
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
