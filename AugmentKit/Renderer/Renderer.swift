//
//  Renderer.swift
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
import ModelIO

// MARK: - Notifications

public extension Notification.Name {
    public static let rendererStateChanged = Notification.Name("com.tenthlettermade.augmentKit.notificaiton.rendererStateChanged")
    public static let surfaceDetectionStateChanged = Notification.Name("com.tenthlettermade.augmentKit.notificaiton.surfaceDetectionStateChanged")
    public static let abortedDueToErrors = Notification.Name("com.tenthlettermade.augmentKit.notificaiton.abortedDueToErrors")
}

// MARK: - RenderDestinationProvider

public protocol RenderDestinationProvider {
    var currentRenderPassDescriptor: MTLRenderPassDescriptor? { get }
    var currentDrawable: CAMetalDrawable? { get }
    var colorPixelFormat: MTLPixelFormat { get set }
    var depthStencilPixelFormat: MTLPixelFormat { get set }
    var sampleCount: Int { get set }
}

// MARK: - RenderMonitor

public struct RenderStats {
    public var arKitAnchorCount: Int
    public var numAnchors: Int
    public var numPlanes: Int
    public var numTrackingPoints: Int
    public var numTrackers: Int
    public var numTargets: Int
    public var numPathSegments: Int
}

public protocol RenderMonitor {
    func update(renderStats: RenderStats)
    func update(renderErrors: [AKError])
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
    public var monitor: RenderMonitor?
    
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
    
    public enum SurfaceDetectionState {
        case noneDetected
        case detected
    }
    
    public fileprivate(set) var state: RendererState = .uninitialized {
        didSet {
            if state != oldValue {
                NotificationCenter.default.post(Notification(name: .rendererStateChanged, object: self, userInfo: ["newValue": state, "oldValue": oldValue]))
            }
        }
    }
    public fileprivate(set) var hasDetectedSurfaces = false {
        didSet {
            if hasDetectedSurfaces != oldValue {
                NotificationCenter.default.post(Notification(name: .surfaceDetectionStateChanged, object: self, userInfo: ["newState": hasDetectedSurfaces]))
            }
        }
    }
    
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
    public fileprivate(set) var currentCameraPositionTransform: matrix_float4x4?
    // A transform matrix that represents the rotation of the camera relative to world space.
    // There is no postion component.
    public var currentCameraRotation: matrix_float4x4? {
        guard let currentCameraQuaternionRotation = currentCameraQuaternionRotation else {
            return nil
        }
        return unsafeBitCast(GLKMatrix4MakeWithQuaternion(currentCameraQuaternionRotation), to: simd_float4x4.self)
    }
    // A Quaternion that represents the rotation of the camera relative to world space.
    // There is no postion component.
    public fileprivate(set) var currentCameraQuaternionRotation: GLKQuaternion?
    public fileprivate(set) var currentCameraHeading: Double?
    public fileprivate(set) var lowestHorizPlaneAnchor: ARPlaneAnchor?
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
        hasDetectedSurfaces = false
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
        
        hasDetectedSurfaces = hasDetectedSurfaces || (lowestHorizPlaneAnchor != nil) || (surfaceAnchors.count > 0)
        
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
        let eulerAngles = EulerAngles(roll: currentFrame.camera.eulerAngles.z, pitch: currentFrame.camera.eulerAngles.x, yaw: currentFrame.camera.eulerAngles.y)
        let cameraQuaternion = QuaternionUtilities.quaternionFromEulerAngles(eulerAngles: eulerAngles)
        var positionOnlyTransform = matrix_identity_float4x4
        positionOnlyTransform = positionOnlyTransform.translate(x: currentFrame.camera.transform.columns.3.x, y: currentFrame.camera.transform.columns.3.y, z: currentFrame.camera.transform.columns.3.z)
        currentCameraPositionTransform = positionOnlyTransform
        currentCameraQuaternionRotation = cameraQuaternion
        currentCameraHeading = Double(currentFrame.camera.eulerAngles.y)
        
        //
        // Update the lowest surface plane
        //
        
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
            
            let metalAllocator = MTKMeshBufferAllocator(device: device)
            modelProvider?.registerModel(GuideSurfaceAnchor.createModel(withAllocator: metalAllocator)!, forObjectType: GuideSurfaceAnchor.type, identifier: nil)
            
            addModule(forModuelIdentifier: SurfacesRenderModule.identifier)
            
        }
        
        //
        // Add new Modules
        //
        
        // Add anchor modules if necessary
        if anchorsRenderModule == nil && normalAnchors.count > 0 {
            addModule(forModuelIdentifier: AnchorsRenderModule.identifier)
        }
        
        // Add Unanchored modules if nescessary
        if unanchoredRenderModule == nil && (trackers.count > 0 || gazeTargets.count > 0) {
            addModule(forModuelIdentifier: UnanchoredRenderModule.identifier)
        }
        
        // Add paths modules if nescessary
        if pathsRenderModule == nil && paths.count > 0 {
            addModule(forModuelIdentifier: PathsRenderModule.identifier)
        }
        
        initializeModules()
        
        //
        // Update positions
        //
        
        // Calculate updates to trackers relative position
        let cameraPositionTransform = currentCameraPositionTransform ?? matrix_identity_float4x4
        
        //
        // Update Trackers
        //
        
        let updatedTrackers: [AKAugmentedTracker] = trackers.map {
            if let userTracker = $0 as? AKAugmentedUserTracker {
                userTracker.userPosition()?.transform = cameraPositionTransform
                userTracker.position.updateTransforms()
                return userTracker
            } else {
                var mutableTracker = $0
                mutableTracker.position.updateTransforms()
                return mutableTracker
            }
        }
        
        trackers = updatedTrackers
        
        //
        // Update Gaze Targets
        //
        
        let results = currentFrame.hitTest(CGPoint(x: 0.5, y: 0.5), types: [.existingPlaneUsingGeometry, .estimatedVerticalPlane, .estimatedHorizontalPlane])
        hasDetectedSurfaces = hasDetectedSurfaces || results.count > 0
        
        if gazeTargets.count > 0 {
            
            let hitTestResult: ARHitTestResult? = {
                
                // 1. Check for a result on an existing plane using geometry.
                if let existingPlaneUsingGeometryResult = results.first(where: { $0.type == .existingPlaneUsingGeometry }) {
                    return existingPlaneUsingGeometryResult
                }
                
                // 2. Check for a result on the ground plane, assuming its dimensions are infinite.
                //    Loop through all hits against infinite existing planes and either return the
                //    nearest one (vertical planes) or return the nearest one which is within 5 cm
                //    of the object's position.
                
                let infinitePlaneResults = currentFrame.hitTest(CGPoint(x: 0.5, y: 0.5), types: .existingPlane)
                hasDetectedSurfaces = hasDetectedSurfaces || infinitePlaneResults.count > 0
                
                for infinitePlaneResult in infinitePlaneResults {
                    if let planeAnchor = infinitePlaneResult.anchor as? ARPlaneAnchor, planeAnchor.alignment == .horizontal {
                        if let lowestHorizPlaneAnchor = lowestHorizPlaneAnchor, planeAnchor.identifier == lowestHorizPlaneAnchor.identifier {
                            return infinitePlaneResult
                        }
                    }
                }
                
                // 3. As a final fallback, check for a result on estimated planes.
                let vResult = results.first(where: { $0.type == .estimatedVerticalPlane })
                let hResult = results.first(where: { $0.type == .estimatedHorizontalPlane })
                if hResult != nil && vResult != nil {
                    return hResult!.distance < vResult!.distance ? hResult! : vResult!
                } else {
                    return hResult ?? vResult
                }
                
            }()
            
            if let hitTestResult = hitTestResult {
                let updatedGazeTargets: [GazeTarget] = gazeTargets.map {
                    $0.position.parentPosition?.transform = hitTestResult.worldTransform
                    $0.position.updateTransforms()
                    return $0
                }
                gazeTargets = updatedGazeTargets
            }
            
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
                    module.updateBuffers(withTrackers: trackers, targets: gazeTargets, cameraProperties: cameraProperties)
                    module.updateBuffers(withPaths: paths, cameraProperties: cameraProperties)
                }
            }
            
            // Getting the currentDrawable from the RenderDestinationProvider should be called as
            // close as possible to presenting it with the command buffer. The currentDrawable is
            // a scarce resource and holding on to it too long may affect performance
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
        
        let errors = renderModules.flatMap {
            $0.errors
        }
        monitor?.update(renderErrors: errors)
        
        let stats = RenderStats(arKitAnchorCount: currentFrame.anchors.count, numAnchors: anchorsRenderModule?.anchorInstanceCount ?? 0, numPlanes: surfacesRenderModule?.surfaceInstanceCount ?? 0, numTrackingPoints: trackingPointRenderModule?.trackingPointCount ?? 0, numTrackers: unanchoredRenderModule?.trackerInstanceCount ?? 0, numTargets: unanchoredRenderModule?.targetInstanceCount ?? 0, numPathSegments: pathsRenderModule?.pathSegmentInstanceCount ?? 0)
        monitor?.update(renderStats: stats)
        
    }
    
    // MARK: - Adding objects for render
    
    //  Add a new AKAugmentedAnchor to the AR world
    @discardableResult
    public func add(akAnchor: AKAugmentedAnchor) -> UUID {
        
        let arAnchor = ARAnchor(transform: akAnchor.worldLocation.transform)
        let identifier = arAnchor.identifier
        
        // Create an InternalAugmentedAnchor for internal use
        let myAnchor = InternalAugmentedAnchor(withAKAugmentedAnchor: akAnchor)
        myAnchor.identifier = identifier
        augmentedAnchors.append(myAnchor)
        
        let anchorType = type(of: myAnchor).type
        
        // Resgister the AKModel with the model provider.
        modelProvider?.registerModel(myAnchor.model, forObjectType: anchorType, identifier: myAnchor.identifier)
        
        // Keep track of the anchor bucketed by the RenderModule
        // This will be used to load individual models per anchor.
        if let existingGeometries = geometriesForRenderModule[AnchorsRenderModule.identifier] {
            var mutableExistingGeometries = existingGeometries
            mutableExistingGeometries.append(myAnchor)
            geometriesForRenderModule[AnchorsRenderModule.identifier] = mutableExistingGeometries
        } else {
            geometriesForRenderModule[AnchorsRenderModule.identifier] = [myAnchor]
        }
        
        // Add a new anchor to the session
        session.add(anchor: arAnchor)
        
        return identifier
        
    }
    
    //  Add a new AKAugmentedTracker to the AR world
    @discardableResult
    public func add(akTracker: AKAugmentedTracker) -> UUID {
        
        let identifier = UUID()
        
        let myTracker: AKAugmentedTracker = {
            if let userTracker = akTracker as? UserTracker {
                // If a UserTracker instance was passed in, use that directly instead of the
                // internal type
                userTracker.identifier = identifier
                return userTracker
            } else {
                // Create an InternalAugmentedAnchor for internal use
                let aTracker = InternalAugmentedTracker(withAKAugmentedTracker: akTracker)
                aTracker.identifier = identifier
                return aTracker
            }
        }()
        
        let anchorType = type(of: myTracker).type
        
        // Resgister the AKModel with the model provider.
        modelProvider?.registerModel(myTracker.model, forObjectType: anchorType, identifier: myTracker.identifier)
        
        trackers.append(myTracker)
        
        return identifier
        
    }
    
    //  Add a new path to the AR world
    @discardableResult
    public func addPath(withAnchors anchors: [AKAugmentedAnchor]) -> UUID {
        
        let identifier = UUID()
        paths[identifier] = anchors.map() {
            
            let anchorType = type(of: $0).type
            
            // Resgister the AKModel with the model provider.
            modelProvider?.registerModel($0.model, forObjectType: anchorType, identifier: $0.identifier)
            
            
            let arAnchor = ARAnchor(transform: $0.worldLocation.transform)
            let identifier = arAnchor.identifier
            
            // Create an InternalAugmentedAnchor for internal use
            let mutableAnchor = InternalAugmentedAnchor(withAKAugmentedAnchor: $0)
            mutableAnchor.identifier = identifier
            
            // Add a new anchor to the session
            session.add(anchor: arAnchor)
            
            return mutableAnchor
            
        }
        
        return identifier
        
    }
    
    @discardableResult
    public func add(gazeTarget: GazeTarget) -> UUID {
        
        let theType = type(of: gazeTarget).type
        let identifier = UUID()
        gazeTarget.identifier = identifier
        
        // Resgister the AKModel with the model provider.
        modelProvider?.registerModel(gazeTarget.model, forObjectType: theType, identifier: gazeTarget.identifier)
        
        gazeTargets.append(gazeTarget)
        
        return identifier
        
    }
    
    // MARK: - Private
    
    fileprivate var hasUninitializedModules = false
    fileprivate var renderDestination: RenderDestinationProvider
    fileprivate let inFlightSemaphore = DispatchSemaphore(value: Constants.maxBuffersInFlight)
    // Used to determine _uniformBufferStride each frame.
    // This is the current frame number modulo kMaxBuffersInFlight
    fileprivate var uniformBufferIndex: Int = 0
    fileprivate var worldInitiationTime: Double = 0
    fileprivate var lastFrameTime: Double = 0
    
    // Modules
    fileprivate var renderModules: [RenderModule] = [CameraPlaneRenderModule()]
    fileprivate var sharedModulesForModule = [String: [SharedRenderModule]]()
    fileprivate var cameraRenderModule: CameraPlaneRenderModule?
    fileprivate var sharedBuffersRenderModule: SharedBuffersRenderModule?
    fileprivate var anchorsRenderModule: AnchorsRenderModule?
    fileprivate var unanchoredRenderModule: UnanchoredRenderModule?
    fileprivate var pathsRenderModule: PathsRenderModule?
    fileprivate var surfacesRenderModule: SurfacesRenderModule?
    fileprivate var trackingPointRenderModule: TrackingPointsRenderModule?
    
    // Viewport
    fileprivate var viewportSize: CGSize = CGSize()
    fileprivate var viewportSizeDidChange: Bool = false
    
    // Metal objects
    fileprivate let textureLoader: MTKTextureLoader
    fileprivate var defaultLibrary: MTLLibrary?
    fileprivate var commandQueue: MTLCommandQueue?
    
    // Keeping track of objects to render
    //fileprivate var anchorIdentifiersForType = [String: Set<UUID>]()
    fileprivate var geometriesForRenderModule = [String: [AKGeometricEntity]]()
    fileprivate var augmentedAnchors = [AKAugmentedAnchor]()
    fileprivate var trackers = [AKAugmentedTracker]()
    fileprivate var paths = [UUID: [AKAugmentedAnchor]]()
    fileprivate var gazeTargets = [GazeTarget]()
    
    fileprivate var moduleErrors = [AKError]()
    
    // MARK: ARKit Session Configuration
    
    fileprivate func createNewConfiguration() -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        // Setting this to .gravityAndHeading aligns the the origin of the scene to compass direction
        configuration.worldAlignment = .gravityAndHeading
        
        // Enable horizontal plane detection
        configuration.planeDetection = [.horizontal, .vertical]
        
        return configuration
    }
    
    // MARK: Bootstrap
    
    fileprivate func loadMetal() {
        
        //
        // Create and load our basic Metal state objects
        //
        
        // Set the default formats needed to render
        renderDestination.depthStencilPixelFormat = .depth32Float_stencil8
        renderDestination.colorPixelFormat = .bgra8Unorm
        renderDestination.sampleCount = 1
        
        // Load the default metal library file which contains all of the compiled .metal files
        guard let libraryFile = Bundle(for: Renderer.self).path(forResource: "default", ofType: "metallib") else {
            print("failed to create a default library for the device.")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeRenderPipelineInitializationFailed, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: nil, underlyingError: underlyingError))))
            NotificationCenter.default.post(name: .abortedDueToErrors, object: self, userInfo: ["errors": [newError]])
            return
        }
        
        defaultLibrary = {
            do {
                return try device.makeLibrary(filepath: libraryFile)
            } catch let error {
                print("failed to create a default library for the device.")
                let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: nil, underlyingError: error))))
                NotificationCenter.default.post(name: .abortedDueToErrors, object: self, userInfo: ["errors": [newError]])
                fatalError()
            }
        }()
        
        commandQueue = device.makeCommandQueue()
        
    }
    
    // Adds a module to the renderModules array witout being initialized.
    // initializeModules() must be called
    fileprivate func addModule(forModuelIdentifier moduleIdentifier: String) {
        
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
        case UnanchoredRenderModule.identifier:
            if unanchoredRenderModule == nil {
                let newUnanchoredModule = UnanchoredRenderModule()
                unanchoredRenderModule = newUnanchoredModule
                renderModules.append(newUnanchoredModule)
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
    fileprivate func gatherModules() {
        
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
    fileprivate func initializeModules() {
        
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
                        self?.moduleErrors.append(contentsOf: module.errors)
                        if let moduleErrors = self?.moduleErrors {
                            let seriousErrors: [AKError] =  {
                                return moduleErrors.filter(){
                                    switch $0 {
                                    case .seriousError(_):
                                        return true
                                    default:
                                        return false
                                    }
                                }
                            }()
                            if seriousErrors.count > 0 {
                                NotificationCenter.default.post(name: .abortedDueToErrors, object: self, userInfo: ["errors": seriousErrors])
                            }
                        }
                    }
                })
            }
            
        }
        
        hasUninitializedModules = false
        
    }
    
    // MARK: Shared Modules
    
    fileprivate func setupSharedModule(forModuleIdentifier moduleIdentifier: String) -> SharedRenderModule? {
        
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

// MARK: - InternalAugmentedTracker

// An internal instance of a `AKAugmentedTracker` that can be used and manipulated privately
fileprivate class InternalAugmentedTracker: AKAugmentedTracker {
    
    static var type: String {
        return "AnyTracker"
    }
    
    // Contains the target world location which may not be the actual location
    // if the instance ins currently interpolating
    var position: AKRelativePosition
    var model: AKModel
    var identifier: UUID?
    var effects: [AnyEffect<Any>]?
    
    init(withAKAugmentedTracker akAugmentedTracker: AKAugmentedTracker) {
        self.model = akAugmentedTracker.model
        self.identifier = akAugmentedTracker.identifier
        self.position = akAugmentedTracker.position
        self.effects = akAugmentedTracker.effects
    }
    
}

// MARK: - InternalAugmentedAnchor

// An internal instance of a `AKAugmentedAnchor` that can be used and manipulated privately
fileprivate class InternalAugmentedAnchor: AKAugmentedAnchor {
    
    static var type: String {
        return "AnyAnchor"
    }
    
    // Contains the target world location which may not be the actual location
    // if the instance ins currently interpolating
    var worldLocation: AKWorldLocation
    var model: AKModel
    var identifier: UUID?
    var effects: [AnyEffect<Any>]?
    
    init(withAKAugmentedAnchor akAugmentedAnchor: AKAugmentedAnchor) {
        self.model = akAugmentedAnchor.model
        self.identifier = akAugmentedAnchor.identifier
        self.worldLocation = akAugmentedAnchor.worldLocation
        self.effects = akAugmentedAnchor.effects
    }
    
}

// MARK: - InterpolatingAugmentedObject

// A subclass of `InternalAugmentedAnchor` that interpolates between locations
// in order to achieve smoothing.
// Set the interpolation progress with `interpolation`
// Call `update()` to do the terpolation calculations.
// After calling `update()`, `currentLocation` contains the interpolated transform with
// the `latitude`, `longitude`, and `elevation` set to the final values
fileprivate class InterpolatingAugmentedObject: InternalAugmentedAnchor {
    
    // When interpolating, this contains the old location
    var lastLocaion: AKWorldLocation?
    // When interpolating, this contains the current location which is somewhere
    // between the lastLocaion (old) and worldLocation (new)
    private(set) var currentLocation: AKWorldLocation?
    var progress: Float = 1.0 {
        didSet {
            if progress > 1 {
                progress = 1
            } else if progress < 0 {
                progress = 0
            } else if progress == 1 {
                lastLocaion = nil
                currentLocation = nil
                needsUpdate = false
            } else if progress == 0 {
                currentLocation = lastLocaion
                needsUpdate = false
            } else {
                needsUpdate = true
            }
            
        }
    }
    
    var interval: Float = 0.1
    
    func update() {
        
        guard needsUpdate else {
            return
        }
        
        needsUpdate = false
        
        guard let lastLocaion = lastLocaion else {
            return
        }
        
        var diff = worldLocation.transform - lastLocaion.transform
        
        guard !diff.isZero() else {
            return
        }
        
        diff = diff * progress
        currentLocation = WorldLocation(transform: lastLocaion.transform + diff, latitude: worldLocation.latitude, longitude: worldLocation.longitude, elevation: worldLocation.elevation)
        
    }
    
    // Updates the progress and calls `update()`
    func calculateNextPosition() {
        
        guard progress + interval < 1 else {
            progress = 1
            return
        }
        
        progress += interval
        update()
        
    }
    
    func updateLocationWithInterpolation(_ newWorldLocation: AKWorldLocation) {
        progress = 0
        lastLocaion = worldLocation
        worldLocation = newWorldLocation
        calculateNextPosition()
    }
    
    // MARK: Private
    
    private var needsUpdate = false
    
}
