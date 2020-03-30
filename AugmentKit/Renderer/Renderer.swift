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
    /**
     A Notification issued when the render's state has changed
     */
    static let rendererStateChanged = Notification.Name("com.tenthlettermade.augmentKit.notificaiton.rendererStateChanged")
    /**
     A Notification issued when the renderer has detected the first surface
     */
    static let surfaceDetectionStateChanged = Notification.Name("com.tenthlettermade.augmentKit.notificaiton.surfaceDetectionStateChanged")
    /**
     A Notification issued when the renderer has aborted due to errors.
     */
    static let abortedDueToErrors = Notification.Name("com.tenthlettermade.augmentKit.notificaiton.abortedDueToErrors")
}

// MARK: - RenderDestinationProvider

/**
 Defines an objecgt that provides the `CAMetalDrawable` as well as the current `MTLRenderPassDescriptor` and some other render properties.
 */
public protocol RenderDestinationProvider {
    /**
     The current `MTLRenderPassDescriptor`
     */
    var currentRenderPassDescriptor: MTLRenderPassDescriptor? { get }
    /**
     The current `CAMetalDrawable`
     */
    var currentDrawable: CAMetalDrawable? { get }
    /**
     The color `MTLPixelFormat` for the render target
     */
    var colorPixelFormat: MTLPixelFormat { get set }
    /**
     The depth `MTLPixelFormat` for the render target
     */
    var depthStencilPixelFormat: MTLPixelFormat { get set }
    /**
     The pipeline state sample count
     */
    var sampleCount: Int { get set }
    /**
     A Boolean value that determines whether the drawable can be used for texture sampling or read/write operations.
     */
    var framebufferOnly: Bool { get set }
}

// MARK: - RenderStats
/**
 An object that contains the current statistics about the render session
 */
public struct RenderStats {
    /**
     The number of ARKit `ARAnchor`'s being rendered
     */
    public var arKitAnchorCount: Int
    /**
     The total number of `AKAnchor`'s rendered
     */
    public var numAnchors: Int
    /**
     The total number of planes detected
     */
    public var numPlanes: Int
    /**
     The total number of tracking points detected
     */
    public var numTrackingPoints: Int
    /**
     The total number of `AKTracker`'s rendered
     */
    public var numTrackers: Int
    /**
     The total number of `AKTarget`'s rendered
     */
    public var numTargets: Int
    /**
     The total number of `AKPathSegmentAnchor`'s rendered
     */
    public var numPathSegments: Int
}

// MARK: - RenderOptions
/**
 Options that change the behavior of the `Renderer`. These options are mainly useful for debugging purposes.
 */
public struct RenderOptions: OptionSet {
    public let rawValue: Int
    
    static let showTrackingPoints       = RenderOptions(rawValue: 1 << 0)
    static let showDetectedSurfaces     = RenderOptions(rawValue: 1 << 1)
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

// MARK: - RenderMonitor
/**
 Describes an object that can be updated with the latest statistics and errors
 */
public protocol RenderMonitor {
    /**
     Called when there is an update to the render statistics
     - Parameters:
        - renderStats: The new `RenderStats`
     */
    func update(renderStats: RenderStats)
    /**
     Called when there is a new error
     - Parameters:
        - renderErrors: An array of the recorded `AKError`'s
     */
    func update(renderErrors: [AKError])
}

// MARK: - RenderDelegate
/**
 Describes an object that will be updated with status about the current render state
 */
public protocol RenderDelegate {
    /**
     Called when there was an error in the render.
     - Parameters:
        - _: The `Renderer`
        - didFailWithError: The `AKError` that occurred
     */
    func renderer(_ renderer: Renderer, didFailWithError error: AKError)
    /**
     Called when the render was interrupted.
     - Parameters:
        - _: The `Renderer`
     */
    func rendererWasInterrupted(_ renderer: Renderer)
    /**
     Called when the render resumed after interruption.
     - Parameters:
        - _: The `Renderer`
     */
    func rendererInterruptionEnded(_ renderer: Renderer)
    
}

// MARK: - CameraProperties
/**
 An object that stores information about the curent state of the camera
 */
public struct CameraProperties {
    /**
     Orientation
     */
    var orientation: UIInterfaceOrientation
    /**
     View port size
     */
    var viewportSize: CGSize
    /**
     `true` when the view port size has changed.
     */
    var viewportSizeDidChange: Bool
    /**
     Position relative to the world origin
     */
    var position: SIMD3<Float>
    /**
     Heading as a rotation arount the y axis
     */
    var heading: Double
    /**
     The current frame number
     */
    var currentFrame: UInt
    /**
     Frame rate
     */
    var frameRate: Double = 60
    /**
     The `ARCamera`
     */
    var arCamera: ARCamera
    /**
     The captured image coming off og the camera sensor
     */
    var capturedImage: CVPixelBuffer
    /**
     The display transform of the `ARCamera`
     */
    var displayTransform: CGAffineTransform
    /**
     The feature points detected by `ARKit`
     */
    var rawFeaturePoints: ARPointCloud?
    /// Should be `true` when `ARSession` configureation's `frameSemantics` is  `personSegmentationWithDepth` so that the shader can perform depth-based occlusion.
    var useDepth: Bool
    /**
     Initialize e new object with a `UIInterfaceOrientation`, view port size, a viewport size change state, a position, a heading, a current frame number, a `ARFrame`, and the frame rate
     - Parameters:
        - orientation: divice orientation
        - viewportSize: View port size
        - viewportSizeDidChange: `true` if the view port size changed
        - position: The position relative to the world axis
        - heading: The heading as a rotation around the y axis
        - currentFrame: The currnet frame number
        - frame: The current `ARFrame`
        - frameRate: The frame rate
     */
    init(orientation: UIInterfaceOrientation, viewportSize: CGSize, viewportSizeDidChange: Bool, position: SIMD3<Float>, heading: Double, currentFrame: UInt, frame: ARFrame, frameRate: Double = 60, useDepth: Bool = false) {
        self.orientation = orientation
        self.viewportSize = viewportSize
        self.viewportSizeDidChange = viewportSizeDidChange
        self.position = position
        self.heading = heading
        self.currentFrame = currentFrame
        self.frameRate = frameRate
        self.arCamera = frame.camera
        self.capturedImage = frame.capturedImage
        self.displayTransform = frame.displayTransform(for: orientation, viewportSize: viewportSize)
        self.rawFeaturePoints = frame.rawFeaturePoints
        self.useDepth = useDepth
    }
}

// MARK: - EnvironmentProperties
/**
 An object that stores information about the environment
 */
public struct EnvironmentProperties {
    /**
     ARKit's estimated light properties
     */
    var lightEstimate: ARLightEstimate?
    /**
     A dictionary of `AREnvironmentProbeAnchor`'s and the identifiers of the anchors that they apply to.
     */
    var environmentAnchorsWithReatedAnchors: [AREnvironmentProbeAnchor: [UUID]] = [:]
    /**
     The direction the primary light source is pointing
     */
    var directionalLightDirection: SIMD3<Float> = SIMD3<Float>(0, -1, 0)
    /**
     The Model View Projection matrix of the primary light
     */
    var directionalLightMVP: float4x4 = matrix_identity_float4x4
}

// MARK: - ShadowProperties
/**
 An object that stores information about the environment
 */
public struct ShadowProperties {
    /**
     Texture for the shadow depth map
     */
    var shadowMap: MTLTexture?
    /**
     The `directionalLightMVP` with flipped y/t coordinate and converted from the [-1, 1] range of clip coordinates to [0, 1] range. used for texture sampling the shadow map.
     */
    var shadowMVPTransformMatrix: float4x4 = matrix_identity_float4x4
}

// MARK: - ShadowProperties
/**
 An object that stores information about the environment
 */
public struct ArgumentBufferProperties {
    /**
     Argument Buffer For the vertex shader
     */
    var vertexArgumentBuffer: MTLBuffer?
    /**
     Argument Buffer For the fragment shader
     */
    var fragmentArgumentBuffer: MTLBuffer?
    /**
     The size of a single frames worth of argemt data. Since the `vertexArgumentBuffer` contains data for multiple frames, this allows us to calculate the offset into the buffer for a single frame.
     */
    var vertexArgumentBufferSize: Int = 0
    /**
     The size of a single frames worth of argemt data. Since the `vertexArgumentBuffer` contains data for multiple frames, this allows us to calculate the offset into the buffer for a single frame.
     */
    var fragmentArgumentBufferSize: Int = 0
    
    /**
     Calculates the offset into the `vertexArgumentBuffer` for a specific frame
     - parameters:
        - forFrame: The frame number modulus the number of frames in flight
     - returns: The offset into `vertexArgumentBuffer` for the given frame.
     */
    func vertexArgumentBufferOffset(forFrame frame: Int) -> Int {
        return vertexArgumentBufferSize * frame
    }
    /**
     Calculates the offset into the `fragmentArgumentBuffer` for a specific frame
     - parameters:
        - forFrame: The frame number modulus the number of frames in flight
     - returns: The offset into `fragmentArgumentBuffer` for the given frame.
     */
    func fragmentArgumentBufferOffset(forFrame frame: Int) -> Int {
        return fragmentArgumentBufferSize * frame
    }
}

// MARK: - Renderer
/**
 AumentKit's main Metal based render.
 */
open class Renderer: NSObject {
    
    /**
     When set, the monitor gets notified of render status changes.
     */
    public var monitor: RenderMonitor?
    
    /**
     Device orientation. Changing this parameter while the renderer is running triggers a recalculation of the target view port.
     */
    public var orientation: UIInterfaceOrientation = .portrait {
        didSet {
            viewportSizeDidChange = true
        }
    }
    
    /**
     Constants
     */
    public enum Constants {
        /**
         Maximim number of in flight render passes
         */
        static let maxInFlightFrames = 3
        /**
         Maximim number of instances that will be rendered
         */
        static let maxInstances = 2048
        /**
         Used for Level Of Detail calculations to determaile the number of quality levels to set up. Quality levels requires `AKCapabilities.LevelOfDetail == true`
         */
        static let numQualityLevels = 3
    }
    /**
     State of the renderer
     */
    public enum RendererState {
        /**
         Uninitialized
         */
        case uninitialized
        /**
         Metal and the render piplinge has been initialized
         */
        case initialized
        /**
         Currently Running
         */
        case running
        /**
         Currently Paused
         */
        case paused
    }
    /**
     State of surface detection. Many features of AugmentKit rely on the AR engine to have detected at least one surface so monitoring surface dettection state gives a good indication of the readyness of the render to perform AR calculations reliably
     */
    public enum SurfaceDetectionState {
        /**
         No surfaces have been detected
         */
        case noneDetected
        /**
         At least one surface has been detected
         */
        case detected
    }
    /**
     Current renderer state
     */
    public fileprivate(set) var state: RendererState = .uninitialized {
        didSet {
            if state != oldValue {
                NotificationCenter.default.post(Notification(name: .rendererStateChanged, object: self, userInfo: ["newValue": state, "oldValue": oldValue]))
            }
        }
    }
    /**
     At least one surface has been detected. Many features of AugmentKit rely on the AR engine to have detected at least one surface so monitoring this property gives a good indication of the readyness of the render to perform AR calculations reliably
     */
    public fileprivate(set) var hasDetectedSurfaces = false {
        didSet {
            if hasDetectedSurfaces != oldValue {
                let newState: SurfaceDetectionState = {
                    if hasDetectedSurfaces {
                        return .detected
                    } else {
                        return .noneDetected
                    }
                }()
                NotificationCenter.default.post(Notification(name: .surfaceDetectionStateChanged, object: self, userInfo: ["newState": newState]))
            }
        }
    }
    /**
     The ARKit session
     */
    public let session: ARSession
    /**
     The Metal device
     */
    public let device: MTLDevice
    /**
     The bundle from which texture assets will be loaded.
     */
    public let textureBundle: Bundle
    /**
     A `ModelProvider` instance which helps with loading and caching of models
     */
    public var modelProvider: ModelProvider? = AKModelProvider.sharedInstance
    /**
     This `RenderDelegate` will get callbacks for errors or interruptions of AR tracking
     */
    public var delegate: RenderDelegate?
    
    /**
     Guides for debugging. Turning this on will show the tracking points used by ARKit as well as detected surfaces. Setting this to true might affect performance.
     */
    public var options: RenderOptions = [] {
        didSet {
            if options.contains(.showTrackingPoints) {
                if renderModules.filter({$0 is TrackingPointsRenderModule}).isEmpty {
                    var updatedRenderModules: [RenderModule] = renderModules
                    updatedRenderModules.append(TrackingPointsRenderModule())
                    renderModules = updatedRenderModules.sorted(by: {$0.renderLayer < $1.renderLayer})
                }
            } else {
                var newModules: [RenderModule] = []
                renderModules.forEach { module in
                    if !(module is TrackingPointsRenderModule) {
                        newModules.append(module)
                    }
                }
                renderModules = newModules
            }
            reset()
        }
    }
    /**
     If provided, this world map is used during initialization of the ARKit engine
     */
    public var worldMap: ARWorldMap?
    
    /**
     A transform matrix that represents the current position of the camera in world space. There is no rotation component.
     */
    public fileprivate(set) var currentCameraPositionTransform: matrix_float4x4?
    /**
     A transform matrix that represents the current rotation of the camera relative to world space. There is no postion component.
     */
    public var currentCameraRotation: matrix_float4x4? {
        guard let currentCameraQuaternionRotation = currentCameraQuaternionRotation else {
            return nil
        }
        return currentCameraQuaternionRotation.toMatrix4()
    }
    /**
     A Quaternion that represents the current rotation of the camera relative to world space. There is no postion component.
     */
    public fileprivate(set) var currentCameraQuaternionRotation: simd_quatf?
    /**
     The current device's heading. A heading is the degrees, in radians around the Y axis. 0° is due north and the units go from 0 to π in the counter-clockwise direction and 0 to -π in the clockwise direction.
     */
    public fileprivate(set) var currentCameraHeading: Double?
    /**
     The anchor the ARKit has identified as the ground.
     */
    public fileprivate(set) var groundPlaneAnchor: ARPlaneAnchor?
    public var currentFrameNumber: UInt {
        guard worldInitiationTime > 0 && lastFrameTime > 0 else {
            return 0
        }
        
        let elapsedTime = lastFrameTime - worldInitiationTime
        return UInt(floor(elapsedTime * frameRate))
    }
    /**
     Fixed to 60
     */
    public var frameRate: Double {
        return 60
    }
    /**
     A transform that represents the intersection of the current devices gaze (what is dead center in front of it) and the closes detected surface.
     */
    public var currentGazeTransform: matrix_float4x4 {
        
        guard let currentFrame = session.currentFrame else {
            return matrix_identity_float4x4
        }
        
        let results = currentFrame.hitTest(CGPoint(x: 0.5, y: 0.5), types: [.existingPlaneUsingGeometry, .estimatedVerticalPlane, .estimatedHorizontalPlane])
        hasDetectedSurfaces = hasDetectedSurfaces || results.count > 0
        
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
                if let groundPlaneAnchor = groundPlaneAnchor, let planeAnchor = infinitePlaneResult.anchor as? ARPlaneAnchor, planeAnchor.alignment == .horizontal {
                    if case .floor = planeAnchor.classification, planeAnchor.identifier == groundPlaneAnchor.identifier {
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
            return hitTestResult.worldTransform
        } else {
            return matrix_identity_float4x4
        }
        
    }
    /**
     Initialize the renderer with an `ARSession`, a `MTLDevice`, a `RenderDestinationProvider`, and a `Bundle`
     - Parameters:
        - session: an ARKit session
        - metalDevice: A metal device (GPU)
        - renderDestination: Provides the drawable that the renderer will render to.
        - textureBundle: The default bundle whe texture assets will attempt to load from
     */
    public init(session: ARSession, metalDevice device: MTLDevice, renderDestination: RenderDestinationProvider, textureBundle: Bundle) {
        
        self.session = session
        self.device = device
        self.renderDestination = renderDestination
        self.textureBundle = textureBundle
        self.textureLoader = MTKTextureLoader(device: device)
        self.matteGenerator = ARMatteGenerator(device: device, matteResolution: .half)
        super.init()
        
        self.session.delegate = self
        
    }
    
    // MARK: - Viewport changes
    
    /**
     Call when the viewport size changes tell the renderer to readjust
     */
    public func drawRectResized(size: CGSize) {
        viewportSize = size
        viewportSizeDidChange = true
    }
    
    // MARK: - Lifecycle
    
    /**
     Initialize Metal and the render pipeline.
     */
    public func initialize() {
        
        guard state == .uninitialized else {
            return
        }
        
        loadMetal()
        
        addModule(forModuelIdentifier: CameraPlaneRenderModule.identifier)
        
        if let _ = renderModules.first(where: {$0.state == .uninitialized}) {
            hasUninitializedModules = true
        }
        
        initializeModules()
        
        captureScope = sharedCaptureManager.makeCaptureScope(device: device)
        
        state = .initialized
        
        
    }
    /**
     Start the AR session and begin AR tracking
     */
    public func run() {
        guard state != .uninitialized else {
            return
        }
        session.run(createNewConfiguration())
        state = .running
    }
    
    /**
     Pause the AR session and AR tracking
     */
    public func pause() {
        guard state != .uninitialized else {
            return
        }
        session.pause()
        state = .paused
    }
    
    /**
     Reset the AR session and AR tracking
     */
    public func reset(options: ARSession.RunOptions = [.removeExistingAnchors, .resetTracking]) {
        guard state != .uninitialized else {
            return
        }
        hasDetectedSurfaces = false
        session.run(createNewConfiguration(), options: options)
        state = .running
    }
    
    // MARK: Per-frame update call
    
    /**
     Begins a render pass. This method is usually called once per frame.
     */
    public func update() {
        
        guard let commandQueue = commandQueue else {
            return
        }
        
        guard let currentFrame = session.currentFrame else {
            return
        }
        
        if worldInitiationTime == 0 {
            worldInitiationTime = currentFrame.timestamp
        }
        
        lastFrameTime = currentFrame.timestamp
        
        hasDetectedSurfaces = hasDetectedSurfaces || (groundPlaneAnchor != nil) || (realAnchors.count > 0)
        
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
        let eulerAngles = EulerAngles(roll: currentFrame.camera.eulerAngles.z, yaw: currentFrame.camera.eulerAngles.y, pitch: currentFrame.camera.eulerAngles.x)
        let cameraQuaternion = QuaternionUtilities.quaternionFromEulerAngles(eulerAngles: eulerAngles)
        var positionOnlyTransform = matrix_identity_float4x4
        positionOnlyTransform = positionOnlyTransform.translate(x: currentFrame.camera.transform.columns.3.x, y: currentFrame.camera.transform.columns.3.y, z: currentFrame.camera.transform.columns.3.z)
        currentCameraPositionTransform = positionOnlyTransform
        currentCameraQuaternionRotation = cameraQuaternion
        currentCameraHeading = Double(currentFrame.camera.eulerAngles.y)
        
        //
        // Initialize Modules
        //
        
        // Add surface modules for rendering if necessary
        if surfacesRenderModule == nil && realAnchors.count > 0  {
            
            let metalAllocator = MTKMeshBufferAllocator(device: device)
            if options.contains(.showDetectedSurfaces) {
                modelProvider?.registerAsset(DetectedSurfaceAnchor.createModelAsset(inBundle: textureBundle, withAllocator: metalAllocator)!, forObjectType: "AnySurface", identifier: nil)
            } else {
                // The base color is clear black. The alpha channel will be adjusted according to the shadow map.
                modelProvider?.registerAsset(RealSurfaceAnchor.createModelAsset(withName: "Default Real Surface base amterial", allocator: metalAllocator, baseColor: SIMD4<Float>(0, 0, 0, 0)), forObjectType: "AnySurface", identifier: nil)
            }
            
            realAnchors.forEach { anAnchor in
                // Keep track of the anchor bucketed by the RenderModule
                // This will be used to load individual models per anchor.
                if let existingGeometries = entitiesForRenderModule[SurfacesRenderModule.identifier] {
                    var mutableExistingGeometries = existingGeometries
                    mutableExistingGeometries.append(anAnchor)
                    entitiesForRenderModule[SurfacesRenderModule.identifier] = mutableExistingGeometries
                    anchorsRenderModule?.state = .uninitialized
                    hasUninitializedModules = true
                } else {
                    entitiesForRenderModule[SurfacesRenderModule.identifier] = [anAnchor]
                }
            }
            
            addModule(forModuelIdentifier: SurfacesRenderModule.identifier)
            
        } else if surfacesRenderModule != nil && (entitiesForRenderModule[SurfacesRenderModule.identifier]?.count ?? 0) != realAnchors.count {
            
            // Update the geometries as they get added or removed
            entitiesForRenderModule[SurfacesRenderModule.identifier] = []
            realAnchors.forEach { anAnchor in
                // Keep track of the anchor bucketed by the RenderModule
                // This will be used to load individual models per anchor.
                if let existingGeometries = entitiesForRenderModule[SurfacesRenderModule.identifier] {
                    var mutableExistingGeometries = existingGeometries
                    mutableExistingGeometries.append(anAnchor)
                    entitiesForRenderModule[SurfacesRenderModule.identifier] = mutableExistingGeometries
                    anchorsRenderModule?.state = .uninitialized
                    hasUninitializedModules = true
                } else {
                    entitiesForRenderModule[SurfacesRenderModule.identifier] = [anAnchor]
                }
            }
            
        }
        
        //
        // Add new Modules
        //
        
        // Add anchor modules if necessary
        if anchorsRenderModule == nil && augmentedAnchors.count > 0 {
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
        let cameraRelativePosition = AKRelativePosition(withTransform: cameraPositionTransform)
        
        //
        // Update Trackers
        //
        
        trackers.forEach {
            if let userTracker = $0 as? AKAugmentedUserTracker {
                userTracker.userPosition()?.transform = cameraPositionTransform
                userTracker.position.updateTransforms()
            } else {
                $0.position.updateTransforms()
            }
        }
        
        //
        // Update Gaze Targets
        //
        
        let results = currentFrame.hitTest(CGPoint(x: 0.5, y: 0.5), types: [.existingPlaneUsingGeometry, .estimatedVerticalPlane, .estimatedHorizontalPlane])
        hasDetectedSurfaces = hasDetectedSurfaces || results.count > 0
        
        if gazeTargets.count > 0 {
            
            let gazeTransform = currentGazeTransform
            if gazeTransform != matrix_identity_float4x4 {
                gazeTargets.forEach {
                    $0.position.parentPosition?.transform = gazeTransform
                    $0.position.updateTransforms()
                }
            }
            
        }
        
        //
        // Update Headings
        //
        
        let allAKAnchors: [AKAnchor] = entitiesForRenderModule.flatMap({$0.value}).compactMap { geometry in
            if let anAKAnchor = geometry as? AKAnchor {
                return anAKAnchor
            } else {
                return nil
            }
        }
        allAKAnchors.forEach {
            $0.heading.updateHeading(withPosition: cameraRelativePosition)
        }
        
        //
        // Camera Properties
        //
        
        let cameraPosition: SIMD3<Float> = {
            if let currentCameraPositionTransform = currentCameraPositionTransform {
                return SIMD3<Float>(currentCameraPositionTransform.columns.3.x, currentCameraPositionTransform.columns.3.y, currentCameraPositionTransform.columns.3.z)
            } else {
                return SIMD3<Float>(0, 0, 0)
            }
        }()
        
        let useDepth: Bool = {
             if #available(iOS 13.0, *) {
                return session.configuration?.frameSemantics == ARConfiguration.FrameSemantics.personSegmentationWithDepth
             } else {
                return false
            }
        }()
        
        let cameraProperties = CameraProperties(orientation: orientation, viewportSize: viewportSize, viewportSizeDidChange: viewportSizeDidChange, position: cameraPosition, heading: currentCameraHeading ?? 0, currentFrame: currentFrameNumber, frame: currentFrame, frameRate: frameRate, useDepth: useDepth)
        
        //
        // Environment Properties
        //
        
        var environmentProperties = EnvironmentProperties()
        environmentProperties.environmentAnchorsWithReatedAnchors = environmentAnchorsWithReatedAnchors
        environmentProperties.lightEstimate = currentFrame.lightEstimate
        
        let depthProjectionMatrix = float4x4.makeOrtho(left: -10, right: 10, bottom: -10, top: 10, nearZ: -10, farZ: 10)
        let depthViewMatrix = float4x4.makeLookAt(eyeX: 0, eyeY: 10, eyeZ: 0, centerX: 0, centerY: 0, centerZ: 0, upX: 0, upY: 1, upZ: 0)
        environmentProperties.directionalLightMVP = depthProjectionMatrix * depthViewMatrix
        
        //
        // Shadow Properties
        //
        
        var shadowProperties = ShadowProperties()
        shadowProperties.shadowMap = shadowMap
        let shadowScale = matrix_identity_float4x4.scale(x: 0.5, y: -0.5, z: 1)
        let shadowTranslate = matrix_identity_float4x4.translate(x: 0.5, y: 0.5, z: 0)
        let shadowTransform = shadowTranslate * shadowScale
        shadowProperties.shadowMVPTransformMatrix = shadowTransform
        
        //
        // Shadow Properties
        //
        let argumentBufferProperties = ArgumentBufferProperties(vertexArgumentBuffer: precalculationOutputBuffer?.buffer, fragmentArgumentBuffer: nil, vertexArgumentBufferSize: precalculationOutputBuffer?.alignedSize ?? 0, fragmentArgumentBufferSize: 0)
        
        //
        // Encode Cammand Buffer
        //
        
        // Wait to ensure only `maxInFlightFrames` are getting proccessed by any stage in the Metal
        // pipeline (App, Metal, Drivers, GPU, etc)
        let _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        uniformBufferIndex = (uniformBufferIndex + 1) % Constants.maxInFlightFrames
        
        // Update Buffer States
        renderModules.forEach { module in
            if module.state == .ready {
                module.updateBufferState(withBufferIndex: uniformBufferIndex)
            }
        }
        computeModules.forEach { module in
            if  module.state == .ready {
                module.updateBufferState(withBufferIndex: uniformBufferIndex)
            }
        }
        
        captureScope?.begin()
        
        // Create a new command buffer to process the IBL pre-render if necessary
        // TODO: Kernels to precalculate values for IBL
        if AKCapabilities.ImageBasedLighting {
            if let computeCommandBuffer = commandQueue.makeCommandBuffer(), let environmentTexture = environmentTexture, hasEnvironmentTextureChanged {

                computeCommandBuffer.label = "IBLCommandBuffer"

                // Update Textures
                diffuseIBLCubePass?.inputTextures = [environmentTexture]
                diffuseIBLCubePass?.prepareTextures()
                specularIBLCubePass?.inputTextures = [environmentTexture]
                specularIBLCubePass?.prepareTextures()

                //
                // Dispatch IBL Passes
                //

                dispatchIBLPasses(withCommandBuffer: computeCommandBuffer)

                computeCommandBuffer.commit()
                hasEnvironmentTextureChanged = false

            }
        }
        
        // Create a new command buffer for the frame render
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            
            //
            // Matte Textures
            //
            
            alphaTexture = matteGenerator.generateMatte(from: currentFrame, commandBuffer: commandBuffer)
            dilatedDepthTexture = matteGenerator.generateDilatedDepth(from: currentFrame, commandBuffer: commandBuffer)
            
            commandBuffer.label = "RenderCommandBuffer"
            var renderPasses = [RenderPass]()
            
            // TODO: Dispatch compute and render passes in render layer order
            //
            // Setup render passes
            //
            
            //
            // Prepare compute passses that require knowledge of the main render pass (i.e. the precalculation pass that requires knowledge of the objects that will be rendered in the main pass)
            //
            
            prepareToDraw(forCameraProperties: cameraProperties, environmentProperties: environmentProperties, shadowProperties: shadowProperties, renderPass: mainRenderPass)
            
            //
            // Dispatch Compute Passes
            //
            
            dispatchComputePasses(withCommandBuffer: commandBuffer)
            
            //
            // Shadow Map Pass
            //
            
            if let shadowRenderPass = shadowRenderPass {
                
                // Update Buffers
                updateBuffers(forCameraProperties: cameraProperties, environmentProperties: environmentProperties, shadowProperties: shadowProperties, argumentBufferProperties: argumentBufferProperties, renderPass: shadowRenderPass)
                
                // Draw
                shadowRenderPass.prepareCommandEncoder(withCommandBuffer: commandBuffer)
                if let shadowRenderEncoder = shadowRenderPass.renderCommandEncoder {
                    drawShadowPass(with: shadowRenderEncoder)
                } else {
                    print("WARNING: Could not create MTLRenderCommandEncoder for the shadow pass. Aborting.")
                }
                
                renderPasses.append(shadowRenderPass)
                
            }
            
            //
            // Main Pass
            //
            
            if let mainRenderPass = mainRenderPass {
                
                // Update Buffers
                updateBuffers(forCameraProperties: cameraProperties, environmentProperties: environmentProperties, shadowProperties: shadowProperties, argumentBufferProperties: argumentBufferProperties, renderPass: mainRenderPass)
                
                // Getting the currentRenderPassDescriptor from the RenderDestinationProvider should be called as
                // close as possible to presenting it with the command buffer. The currentDrawable is
                // a scarce resource and holding on to it too long may affect performance
                if let mainRenderPassDescriptor = renderDestination.currentRenderPassDescriptor, let currentDrawable = renderDestination.currentDrawable {
                    
                    // First setup offline draw pass
                    guard let sceneRenderDescriptor = mainRenderPassDescriptor.copy() as? MTLRenderPassDescriptor else {
                        fatalError("Unable to create a render pass descriptor.")
                    }
                    
                    sceneRenderDescriptor.colorAttachments[0].texture = sceneColorTexture
                    sceneRenderDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
                    sceneRenderDescriptor.colorAttachments[0].loadAction = .clear
                    sceneRenderDescriptor.colorAttachments[0].storeAction = .store
                    
                    sceneRenderDescriptor.depthAttachment.texture = sceneDepthTexture
                    sceneRenderDescriptor.stencilAttachment.texture = sceneDepthTexture
                    sceneRenderDescriptor.depthAttachment.clearDepth = 1.0
                    sceneRenderDescriptor.depthAttachment.loadAction = .clear
                    sceneRenderDescriptor.depthAttachment.storeAction = .store
                    
                    mainRenderPass.renderPassDescriptor = sceneRenderDescriptor
                    mainRenderPass.prepareCommandEncoder(withCommandBuffer: commandBuffer)
                    
                    // Draw
                    if let renderEncoder = mainRenderPass.renderCommandEncoder {
                        drawMainPass(with: renderEncoder)
                    } else {
                        print("WARNING: Could not create MTLRenderCommandEncoder. Aborting draw pass.")
                    }
                    
                    // Perform final composite pass
                    // Here we take the targets we just rendered camera and scene into and decide whether
                    // to hide or show virtual content.
                    if let compositeRenderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: mainRenderPassDescriptor) {
                        
                        compositeRenderEncoder.label = "Composite Render Pass"
                        
                        // Composite images to final render targets
                        drawCompositePass(with: compositeRenderEncoder)
                        
                    }

//                    mainRenderPass.renderPassDescriptor = mainRenderPassDescriptor
//                    mainRenderPass.prepareCommandEncoder(withCommandBuffer: commandBuffer)
//
//                    // Draw
//                    if let renderEncoder = mainRenderPass.renderCommandEncoder {
//                        drawMainPass(with: renderEncoder)
//                    } else {
//                        print("WARNING: Could not create MTLRenderCommandEncoder. Aborting draw pass.")
//                    }
//
                    // Schedule a present once the framebuffer is complete using the current drawable
                    commandBuffer.present(currentDrawable)

                }
                
                renderPasses.append(mainRenderPass)
            }
            
            //
            // Setup Bloom Downsample pass
            //
            
            // TODO: implement
            
            //
            // Setup Bloom Blur pass
            //
            
            // TODO: implement
            
            //
            // Finalize rendering: push the command buffer to the GPU
            //
            
            // Add completion hander which signal _inFlightSemaphore when Metal and the GPU has fully
            // finished proccssing the commands we're encoding this frame.  This indicates when the
            // dynamic buffers, that we're writing to this frame, will no longer be needed by Metal
            // and the GPU.
            commandBuffer.addCompletedHandler{ [weak self] commandBuffer in
                if let strongSelf = self {
                    strongSelf.inFlightSemaphore.signal()
                    strongSelf.renderModules.forEach { module in
                        module.frameEncodingComplete(renderPasses: renderPasses)
                    }
                }
            }
            
            commandBuffer.commit()
            
        }
        
        captureScope?.end()
        
        // Update viewportSizeDidChange state
        if viewportSizeDidChange {
            viewportSizeDidChange = false
        }
        
        let errors = renderModules.flatMap {
            $0.errors
        }
        monitor?.update(renderErrors: errors)
        
        let stats = RenderStats(arKitAnchorCount: currentFrame.anchors.count, numAnchors: anchorsRenderModule?.anchorInstanceCount ?? 0, numPlanes: surfacesRenderModule?.instanceCount ?? 0, numTrackingPoints: trackingPointRenderModule?.trackingPointCount ?? 0, numTrackers: unanchoredRenderModule?.trackerInstanceCount ?? 0, numTargets: unanchoredRenderModule?.targetInstanceCount ?? 0, numPathSegments: pathsRenderModule?.pathSegmentInstanceCount ?? 0)
        monitor?.update(renderStats: stats)
        
    }
    
    // MARK: - Adding objects for render
    
    /**
     Add a new AKAugmentedAnchor to the AR world
     - Parameters:
        - akAnchor: The anchor to add
     */
    public func add(akAnchor: AKAugmentedAnchor) {
        
        let arAnchor = ARAnchor(transform: akAnchor.worldLocation.transform)
        akAnchor.identifier = arAnchor.identifier
        
        let anchorType = type(of: akAnchor).type
        
        // Resgister the AKModel with the model provider.
        modelProvider?.registerAsset(akAnchor.asset, forObjectType: anchorType, identifier: akAnchor.identifier)
        
        // Keep track of the anchor bucketed by the RenderModule
        // This will be used to load individual models per anchor.
        if let existingGeometries = entitiesForRenderModule[AnchorsRenderModule.identifier] {
            var mutableExistingGeometries = existingGeometries
            mutableExistingGeometries.append(akAnchor)
            entitiesForRenderModule[AnchorsRenderModule.identifier] = mutableExistingGeometries
            anchorsRenderModule?.state = .uninitialized
            hasUninitializedModules = true
        } else {
            entitiesForRenderModule[AnchorsRenderModule.identifier] = [akAnchor]
        }
        
        // Add a new anchor to the session
        session.add(anchor: arAnchor)
        
    }
    
    /**
     Add a new AKAugmentedTracker to the AR world
     - Parameters:
        - akTracker: The tracker to add
     */
    public func add(akTracker: AKAugmentedTracker) {
        
        let identifier = UUID()
        
        if let userTracker = akTracker as? UserTracker {
            // If a UserTracker instance was passed in, use that directly instead of the
            // internal type
            userTracker.identifier = identifier
        } else {
            akTracker.identifier = identifier
        }
        
        let anchorType = type(of: akTracker).type
        
        // Resgister the AKModel with the model provider.
        modelProvider?.registerAsset(akTracker.asset, forObjectType: anchorType, identifier: akTracker.identifier)
        
        // Keep track of the tracker bucketed by the RenderModule
        // This will be used to load individual models per anchor.
        if let existingGeometries = entitiesForRenderModule[UnanchoredRenderModule.identifier] {
            var mutableExistingGeometries = existingGeometries
            mutableExistingGeometries.append(akTracker)
            entitiesForRenderModule[UnanchoredRenderModule.identifier] = mutableExistingGeometries
            unanchoredRenderModule?.state = .uninitialized
            hasUninitializedModules = true
        } else {
            entitiesForRenderModule[UnanchoredRenderModule.identifier] = [akTracker]
        }
        
    }
    
    /**
     Add a new path to the AR world
     - Parameters:
        - akPath: The path to add
     */
    public func add(akPath: AKPath) {
        
        let anchorType = type(of: akPath).type
        
        // Resgister the AKModel with the model provider.
        akPath.geometries.forEach { [weak self] geometry in
            self?.modelProvider?.registerAsset(geometry.asset, forObjectType: anchorType, identifier: akPath.identifier)
        }
        
        
        // Update the segment anchors by adding the ARAnchor identifier which will allow us
        // to trace back the ARAnchors to the path they belong to.
        akPath.segmentPoints.forEach {
            
            // Add a new anchor to the session
            let arAnchor = ARAnchor(transform: $0.worldLocation.transform)
            session.add(anchor: arAnchor)
            
            $0.identifier = arAnchor.identifier
            
        }
        
        // Keep track of the path bucketed by the RenderModule
        if let existingGeometries = entitiesForRenderModule[PathsRenderModule.identifier] {
            var mutableExistingGeometries = existingGeometries
            mutableExistingGeometries.append(akPath)
            entitiesForRenderModule[PathsRenderModule.identifier] = mutableExistingGeometries
        } else {
            entitiesForRenderModule[PathsRenderModule.identifier] = [akPath]
        }
        
        paths.append(akPath)
        
    }
    
    /**
     Add a new gaze target to the AR world
     - Parameters:
        - gazeTarget: The gaze target to add
     */
    public func add(gazeTarget: GazeTarget) {
        
        let theType = type(of: gazeTarget).type
        let identifier = UUID()
        gazeTarget.identifier = identifier
        
        // Resgister the AKModel with the model provider.
        modelProvider?.registerAsset(gazeTarget.asset, forObjectType: theType, identifier: gazeTarget.identifier)
        
        // Keep track of the tracker bucketed by the RenderModule
        // This will be used to load individual models per anchor.
        if let existingGeometries = entitiesForRenderModule[UnanchoredRenderModule.identifier] {
            var mutableExistingGeometries = existingGeometries
            mutableExistingGeometries.append(gazeTarget)
            entitiesForRenderModule[UnanchoredRenderModule.identifier] = mutableExistingGeometries
            unanchoredRenderModule?.state = .uninitialized
            hasUninitializedModules = true
        } else {
            entitiesForRenderModule[UnanchoredRenderModule.identifier] = [gazeTarget]
        }
        
    }
    
    // MARK: - Removing objects
    
    /**
     Remove a new AKAugmentedAnchor to the AR world
     - Parameters:
        - akAnchor: The anchor to remove
     */
    public func remove(akAnchor: AKAugmentedAnchor) {
        
        if let uuid = akAnchor.identifier {
            freeTextureMemory(for: [uuid])
        }
        
        let anchorType = type(of: akAnchor).type
        modelProvider?.unregisterAsset(forObjectType: anchorType, identifier: akAnchor.identifier)
        var existingGeometries = entitiesForRenderModule[AnchorsRenderModule.identifier]
        if let index = existingGeometries?.firstIndex(where: {$0.identifier == akAnchor.identifier}) {
            existingGeometries?.remove(at: index)
        }
        entitiesForRenderModule[AnchorsRenderModule.identifier] = existingGeometries
        
        guard let arAnchor = session.currentFrame?.anchors.first(where: {$0.identifier == akAnchor.identifier}) else {
            return
        }
        
        session.remove(anchor: arAnchor)
        
    }
    /**
     Remove a new AKAugmentedTracker to the AR world
     - Parameters:
        - akTracker: The tracker to remove
     */
    public func remove(akTracker: AKAugmentedTracker) {
        
        if let uuid = akTracker.identifier {
            freeTextureMemory(for: [uuid])
        }
        
        let anchorType = type(of: akTracker).type
        modelProvider?.unregisterAsset(forObjectType: anchorType, identifier: akTracker.identifier)
        var existingGeometries = entitiesForRenderModule[UnanchoredRenderModule.identifier]
        if let index = existingGeometries?.firstIndex(where: {$0.identifier == akTracker.identifier}) {
            existingGeometries?.remove(at: index)
        }
        entitiesForRenderModule[UnanchoredRenderModule.identifier] = existingGeometries
        
        unanchoredRenderModule?.state = .uninitialized
        hasUninitializedModules = true
    }
    /**
     Remove a new path to the AR world
     - Parameters:
        - akPath: The path to remove
     */
    public func remove(akPath: AKPath) {
        
        var uuids = [UUID]()
        akPath.segmentPoints.forEach { segment in
            if let uuid = segment.identifier {
                uuids.append(uuid)
            }
            if let arAnchor = session.currentFrame?.anchors.first(where: {$0.identifier == segment.identifier}) {
                session.remove(anchor: arAnchor)
            }
        }
        if let uuid = akPath.identifier {
            uuids.append(uuid)
        }
        
        freeTextureMemory(for: uuids)
        
        let anchorType = type(of: akPath).type
        modelProvider?.unregisterAsset(forObjectType: anchorType, identifier: akPath.identifier)
        var existingGeometries = entitiesForRenderModule[PathsRenderModule.identifier]
        if let index = existingGeometries?.firstIndex(where: {$0.identifier == akPath.identifier}) {
            existingGeometries?.remove(at: index)
        }
        entitiesForRenderModule[PathsRenderModule.identifier] = existingGeometries
        
    }
    
    /**
     Remove a new gaze target to the AR world
     - Parameters:
        - gazeTarget: The gaze target to remove
     */
    public func remove(gazeTarget: GazeTarget) {
        
        if let uuid = gazeTarget.identifier {
            freeTextureMemory(for: [uuid])
        }
        
        let anchorType = type(of: gazeTarget).type
        modelProvider?.unregisterAsset(forObjectType: anchorType, identifier: gazeTarget.identifier)
        var existingGeometries = entitiesForRenderModule[UnanchoredRenderModule.identifier]
        if let index = existingGeometries?.firstIndex(where: {$0.identifier == gazeTarget.identifier}) {
            existingGeometries?.remove(at: index)
        }
        entitiesForRenderModule[UnanchoredRenderModule.identifier] = existingGeometries
        
        unanchoredRenderModule?.state = .uninitialized
        hasUninitializedModules = true
    }
    
    // MARK: - Private
    
    fileprivate var hasUninitializedModules = false
    fileprivate var renderDestination: RenderDestinationProvider
    fileprivate var matteGenerator: ARMatteGenerator
    fileprivate let inFlightSemaphore = DispatchSemaphore(value: Constants.maxInFlightFrames)
    // This is the current frame number modulo `maxInFlightFrames`
    fileprivate var uniformBufferIndex: Int = 0
    fileprivate var worldInitiationTime: Double = 0
    fileprivate var lastFrameTime: Double = 0
    
    // Modules
    fileprivate var renderModules: [RenderModule] = []
    fileprivate var computeModules = [ShaderModule]()
    fileprivate var sharedModulesForModule = [String: [SharedRenderModule]]()
    fileprivate var cameraRenderModule: CameraPlaneRenderModule?
    fileprivate var sharedBuffersRenderModule: SharedBuffersRenderModule?
    fileprivate var anchorsRenderModule: AnchorsRenderModule?
    fileprivate var unanchoredRenderModule: UnanchoredRenderModule?
    fileprivate var pathsRenderModule: PathsRenderModule?
    fileprivate var surfacesRenderModule: SurfacesRenderModule?
    fileprivate var trackingPointRenderModule: TrackingPointsRenderModule?
    
    // Environment
    fileprivate var environmentTexture: GPUPassTexture?
    fileprivate var hasEnvironmentTextureChanged = false
    
    // Shared Uniforms Buffer
    fileprivate var sharedUniformsBuffer: GPUPassBuffer<SharedUniforms>?
    
    // Camera buffers
    fileprivate var imagePlaneVertexBuffer: GPUPassBuffer<Float>?
    fileprivate var scenePlaneVertexBuffer: GPUPassBuffer<Float>?
    
    // Viewport
    fileprivate var viewportSize: CGSize = CGSize()
    fileprivate var viewportSizeDidChange: Bool = false
    
    // Metal objects
    fileprivate let textureLoader: MTKTextureLoader
    fileprivate var defaultLibrary: MTLLibrary?
    fileprivate var commandQueue: MTLCommandQueue?
    
    // Precalculation Pass
    fileprivate var precalculationComputeModule: PrecalculationModule?
    fileprivate var precalculationPass: ComputePass<PrecalculatedParameters>?
    fileprivate var precalculationOutputBuffer: GPUPassBuffer<PrecalculatedParameters>?
    
    // IBL Passes
    fileprivate var diffuseIBLCubePass: ComputePass<Any>?
    fileprivate var specularIBLCubePass: ComputePass<Any>?
    fileprivate var computeBDRFLookupPass: ComputePass<Any>?
    fileprivate var diffuseIBLCubeTexture: GPUPassTexture?
    fileprivate var specularIBLCubeTexture:GPUPassTexture?
    fileprivate var brdfLUTTexture: GPUPassTexture?
    
    // Main Pass
    fileprivate var mainRenderPass: RenderPass?
    
    // Shadow Render Pass
    fileprivate var shadowMap: MTLTexture?
    fileprivate var shadowRenderPass: RenderPass?
    
    // Matting textures to be filled by ARMattingGenerator
    fileprivate var alphaTexture: MTLTexture?
    fileprivate var dilatedDepthTexture: MTLTexture?
    
    // Composite Pass
    fileprivate var sceneColorTexture: MTLTexture?
    fileprivate var sceneDepthTexture: MTLTexture?
    fileprivate var compositePipelineState: MTLRenderPipelineState?
    fileprivate var compositeDepthState: MTLDepthStencilState?
    
    // Keeping track of objects to render
    fileprivate var entitiesForRenderModule = [String: [AKEntity]]()
    fileprivate var augmentedAnchors: [AKAugmentedAnchor] {
        return entitiesForRenderModule[AnchorsRenderModule.identifier]?.compactMap({$0 as? AKAugmentedAnchor}) ?? []
    }
    fileprivate var realAnchors: [AKRealAnchor] {
        return entitiesForRenderModule[SurfacesRenderModule.identifier]?.compactMap({$0 as? AKRealAnchor}) ?? []
    }
    fileprivate var trackers: [AKAugmentedTracker] {
        return entitiesForRenderModule[UnanchoredRenderModule.identifier]?.compactMap({$0 as? AKAugmentedTracker}) ?? []
    }
    fileprivate var paths = [AKPath]()
    fileprivate var gazeTargets: [GazeTarget] {
        return entitiesForRenderModule[UnanchoredRenderModule.identifier]?.compactMap({$0 as? GazeTarget}) ?? []
    }
    fileprivate var environmentProbeAnchors = [AREnvironmentProbeAnchor]()
    fileprivate var environmentAnchorsWithReatedAnchors = [AREnvironmentProbeAnchor: [UUID]]()
    
    fileprivate var moduleErrors = [AKError]()
    
    fileprivate let sharedCaptureManager = MTLCaptureManager.shared()
    fileprivate var captureScope: MTLCaptureScope?
    
    // MARK: ARKit Session Configuration
    
    fileprivate func createNewConfiguration() -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        // Setting this to .gravityAndHeading aligns the the origin of the scene to compass direction
        configuration.worldAlignment = .gravityAndHeading
        
        // Enable horizontal plane detection
        configuration.planeDetection = [.horizontal, .vertical]
        
        // Enable environment texturing
        configuration.environmentTexturing = .automatic
        
        // Enable people occlusion
        if #available(iOS 13.0, *), ARConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            configuration.frameSemantics.insert(.personSegmentationWithDepth)
        }
        
        if let worldMap = worldMap {
            configuration.initialWorldMap = worldMap
        }
        
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
        
        //
        // Buffers
        //
        
        sharedUniformsBuffer = GPUPassBuffer<SharedUniforms>(shaderAttributeIndex: Int(kBufferIndexSharedUniforms.rawValue), instanceCount: 1, frameCount: Constants.maxInFlightFrames, label: "Shared Uniforms Buffer", resourceOptions: .storageModeShared)
        
        precalculationOutputBuffer = GPUPassBuffer<PrecalculatedParameters>(shaderAttributeIndex: Int(kBufferIndexPrecalculationOutputBuffer.rawValue), instanceCount: Constants.maxInstances, frameCount: Constants.maxInFlightFrames, label: "Precalculation Pass Output Buffer", resourceOptions: .storageModePrivate)
        
        imagePlaneVertexBuffer = GPUPassBuffer<Float>(shaderAttributeIndex: Int(kBufferIndexCameraVertices.rawValue), instanceCount: 1, frameCount: 1, label: "Image Plane Vertex Buffer", resourceOptions: .storageModeShared)
        scenePlaneVertexBuffer = GPUPassBuffer<Float>(shaderAttributeIndex: Int(kBufferIndexSceneVerticies.rawValue), instanceCount: 1, frameCount: 1, label: "Scene Plane Vertex Buffer", resourceOptions: .storageModeShared)
        
        //
        // Compute Passes
        //
        
        var mutableComputeModules = computeModules
        
        // Precalculation Pass
        
        precalculationPass = ComputePass(withDevice: device)
        precalculationPass?.name = "Precalculation Pass"
        precalculationPass?.usesGeometry = true
        precalculationPass?.usesLighting = false
        precalculationPass?.usesSharedBuffer = true
        precalculationPass?.usesEnvironment = true
        precalculationPass?.usesEffects = true
        precalculationPass?.usesCameraOutput = false
        precalculationPass?.usesShadows = false
        precalculationPass?.outputBuffer = precalculationOutputBuffer
        precalculationPass?.sharedUniformsBuffer = sharedUniformsBuffer
        precalculationPass?.functionName = "precalculationComputeShader"
        
        let preComputeModule = PrecalculationModule()
        preComputeModule.computePass = precalculationPass
        mutableComputeModules.append(AnyComputeModule(preComputeModule))
        precalculationComputeModule = preComputeModule
        
        if AKCapabilities.ImageBasedLighting {
            
            // Diffuse IBL
            
            diffuseIBLCubePass = ComputePass(withDevice: device)
            diffuseIBLCubePass?.name = "Diffuse IBL Pass"
            diffuseIBLCubePass?.usesGeometry = false
            diffuseIBLCubePass?.usesLighting = false
            diffuseIBLCubePass?.usesSharedBuffer = false
            diffuseIBLCubePass?.usesEnvironment = true
            diffuseIBLCubePass?.usesEffects = false
            diffuseIBLCubePass?.usesCameraOutput = false
            diffuseIBLCubePass?.usesShadows = false
            diffuseIBLCubePass?.functionName = "compute_irradiance"
            
            let diffuseIBLTextureDesc = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: .rgba16Float, size: 64, mipmapped: false)
            diffuseIBLTextureDesc.resourceOptions = .storageModePrivate
            diffuseIBLTextureDesc.usage = [.shaderRead, .shaderWrite]
            let diffuseIBLCube = device.makeTexture(descriptor: diffuseIBLTextureDesc)
            diffuseIBLCube?.label = "Diffuse IBL Cubemap"
            diffuseIBLCubeTexture = GPUPassTexture(texture: diffuseIBLCube, label: "Diffuse IBL Cubemap", shaderAttributeIndex: Int(kTextureIndexDiffuseIBLMap.rawValue))
            diffuseIBLCubePass?.outputTexture = diffuseIBLCubeTexture
            
            let diffuseIBLComputeModule = DefaultComputeModule<Any>()
            diffuseIBLComputeModule.instanceCount = 64 * 64 * 6
            diffuseIBLComputeModule.threadgroupDepth = 6
            diffuseIBLComputeModule.computePass = diffuseIBLCubePass
            mutableComputeModules.append(AnyComputeModule(diffuseIBLComputeModule))
            
            // Specular IBL
            
            specularIBLCubePass = ComputePass(withDevice: device)
            specularIBLCubePass?.name = "Specular IBL Pass"
            specularIBLCubePass?.usesGeometry = false
            specularIBLCubePass?.usesLighting = false
            specularIBLCubePass?.usesSharedBuffer = false
            specularIBLCubePass?.usesEnvironment = true
            specularIBLCubePass?.usesEffects = false
            specularIBLCubePass?.usesCameraOutput = false
            specularIBLCubePass?.usesShadows = false
            specularIBLCubePass?.functionName = "compute_prefiltered_specular"
            
            let specularIBLTextureDesc = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: .rgba16Float, size: 256, mipmapped: true)
            specularIBLTextureDesc.resourceOptions = .storageModePrivate
            specularIBLTextureDesc.usage = [.shaderRead, .shaderWrite]
            let specularIBLCube = device.makeTexture(descriptor: specularIBLTextureDesc)
            specularIBLCube?.label = "Specular IBL Cubemap"
            specularIBLCubeTexture = GPUPassTexture(texture: specularIBLCube, label: "Specular IBL Cubemap", shaderAttributeIndex: Int(kTextureIndexSpecularIBLMap.rawValue), mipLevels: 9)
            specularIBLCubePass?.outputTexture = specularIBLCubeTexture
            
            let specularIBLComputeModule = DefaultComputeModule<Any>()
            specularIBLComputeModule.instanceCount = 256 * 256 * 6
            specularIBLComputeModule.threadgroupDepth = 6
            specularIBLComputeModule.computePass = specularIBLCubePass
            mutableComputeModules.append(AnyComputeModule(specularIBLComputeModule))
            
            // BRDF Lookup Table
            
            computeBDRFLookupPass = ComputePass(withDevice: device)
            computeBDRFLookupPass?.name = "BDRF Lookup Pass"
            computeBDRFLookupPass?.usesGeometry = false
            computeBDRFLookupPass?.usesLighting = false
            computeBDRFLookupPass?.usesSharedBuffer = false
            computeBDRFLookupPass?.usesEnvironment = true
            computeBDRFLookupPass?.usesEffects = false
            computeBDRFLookupPass?.usesCameraOutput = false
            computeBDRFLookupPass?.usesShadows = false
            computeBDRFLookupPass?.functionName = "integrate_brdf"
            
            let brdfLUTTextureDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg16Float, width: 128, height: 128, mipmapped: false)
            brdfLUTTextureDesc.resourceOptions = .storageModePrivate
            brdfLUTTextureDesc.usage = [.shaderRead, .shaderWrite]
            let brdfLUT = device.makeTexture(descriptor: brdfLUTTextureDesc)
            brdfLUT?.label = "BDRF Lookup"
            brdfLUTTexture = GPUPassTexture(texture: brdfLUT, label: "BDRF Lookup", shaderAttributeIndex: Int(kTextureIndexBDRFLookupMap.rawValue))
            computeBDRFLookupPass?.outputTexture = brdfLUTTexture
            
            let computeBDRFLookupComputeModule = DefaultComputeModule<Any>()
            computeBDRFLookupComputeModule.instanceCount = 128 * 128
            computeBDRFLookupComputeModule.threadgroupDepth = 1
            computeBDRFLookupComputeModule.computePass = computeBDRFLookupPass
            mutableComputeModules.append(AnyComputeModule(computeBDRFLookupComputeModule))
        }
        
        hasUninitializedModules = true
        computeModules = mutableComputeModules
        
        //
        // Setup Shadow Pass
        //
        
        // Create depth texture for shadow pass
        let shadowTextureDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: 2048, height: 2048, mipmapped: false)
        shadowTextureDesc.resourceOptions = .storageModePrivate
        shadowTextureDesc.usage = [.renderTarget, .shaderRead]
        shadowMap = device.makeTexture(descriptor: shadowTextureDesc)
        shadowMap?.label = "Shadow Map"
        
        // Create shadow render pass descriptor
        let shadowRenderPassDescriptor = MTLRenderPassDescriptor()
        shadowRenderPassDescriptor.depthAttachment.texture = shadowMap
        shadowRenderPassDescriptor.depthAttachment.loadAction = .clear
        shadowRenderPassDescriptor.depthAttachment.storeAction = .store
        shadowRenderPassDescriptor.depthAttachment.clearDepth = 1
        
        // Create shadow render pass
        shadowRenderPass = RenderPass(withDevice: device, renderPassDescriptor: shadowRenderPassDescriptor)
        shadowRenderPass?.name = "Shadow Render Pass"
        shadowRenderPass?.usesGeometry = true
        shadowRenderPass?.usesLighting = false
        shadowRenderPass?.usesEffects = true
        shadowRenderPass?.usesEnvironment = true
        shadowRenderPass?.usesCameraOutput = false
        shadowRenderPass?.usesSharedBuffer = true
        shadowRenderPass?.usesShadows = false // the shadow pass does not use the results of the shadow pass (obviously)
        shadowRenderPass?.vertexFunctionMergePolicy = .preferTemplate
        shadowRenderPass?.fragmentFunctionMergePolicy = .preferTemplate
        shadowRenderPass?.depthBias = RenderPass.DepthBias(bias: 0.015, slopeScale: 7, clamp: 0.02)
//        #if REVERSE_DEPTH
//        shadowRenderPass?.depthCompareFunction = .greaterEqual
//        #else
        shadowRenderPass?.depthCompareFunction = .lessEqual
        shadowRenderPass?.isDepthWriteEnabled = true
        
        // Create render pipeline descriptor for shadow pass
        let shadowVertexFunction = defaultLibrary?.makeFunction(name: "shadowVertexShader")
        let shadowRenderPipelineDescriptor = MTLRenderPipelineDescriptor()
        shadowRenderPipelineDescriptor.label = "Shadow Gen Pass"
        shadowRenderPipelineDescriptor.vertexFunction = shadowVertexFunction
        shadowRenderPipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        shadowRenderPass?.templateRenderPipelineDescriptor = shadowRenderPipelineDescriptor
        shadowRenderPass?.drawCallGroupFilterFunction = { drawCallGroup in
            return drawCallGroup?.generatesShadows == true
        }
        
        //
        // Setup Main Pass
        //
        
        // Create main render pass
        mainRenderPass = RenderPass(withDevice: device)
        mainRenderPass?.name = "Main Render Pass"
        mainRenderPass?.usesGeometry = true
        mainRenderPass?.usesLighting = true
        mainRenderPass?.usesEffects = true
        mainRenderPass?.usesEnvironment = true
        mainRenderPass?.usesCameraOutput = true
        mainRenderPass?.usesSharedBuffer = true
        mainRenderPass?.usesShadows = true
        mainRenderPass?.depthCompareFunction = .less
        mainRenderPass?.isDepthWriteEnabled = true
        
        // Create render pipeline descriptor for main pass
        let mainRenderPipelineDescriptor = MTLRenderPipelineDescriptor()
        mainRenderPipelineDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        mainRenderPipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        mainRenderPipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        mainRenderPipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        mainRenderPipelineDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        mainRenderPipelineDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        mainRenderPipelineDescriptor.sampleCount = renderDestination.sampleCount
        mainRenderPass?.templateRenderPipelineDescriptor = mainRenderPipelineDescriptor
        
        //
        // Setup Composite Pass
        //
        
        // Create render targets for offscreen camera image and scene render
        let width = renderDestination.currentDrawable?.texture.width ?? 0
        let height = renderDestination.currentDrawable?.texture.height ?? 0
        
        let colorDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: renderDestination.colorPixelFormat, width: width, height: height, mipmapped: false)
        colorDesc.usage = [.renderTarget, .shaderRead]
        colorDesc.resourceOptions = .storageModePrivate
        sceneColorTexture = device.makeTexture(descriptor: colorDesc)
        sceneColorTexture?.label = "Composite Color"
        
        let depthDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: renderDestination.depthStencilPixelFormat, width: width, height: height, mipmapped: false)
        depthDesc.usage = [.renderTarget, .shaderRead]
        depthDesc.resourceOptions = .storageModePrivate
        sceneDepthTexture = device.makeTexture(descriptor: depthDesc)
        sceneDepthTexture?.label = "Composite Depth"
        
        // Create composite pipeline
        let compositeImageVertexFunction = defaultLibrary?.makeFunction(name: "compositeImageVertexTransform")
        let compositeImageFragmentFunction = defaultLibrary?.makeFunction(name: "compositeImageFragmentShader")
        
        let compositePipelineStateDescriptor = MTLRenderPipelineDescriptor()
        compositePipelineStateDescriptor.label = "Composite Pipeline"
        compositePipelineStateDescriptor.sampleCount = renderDestination.sampleCount
        compositePipelineStateDescriptor.vertexFunction = compositeImageVertexFunction
        compositePipelineStateDescriptor.fragmentFunction = compositeImageFragmentFunction
        compositePipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        compositePipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        compositePipelineStateDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        
        do {
            try compositePipelineState = device.makeRenderPipelineState(descriptor: compositePipelineStateDescriptor)
        } catch let error {
            print("Failed to create composite pipeline state, error \(error)")
        }
        
        let compositeDepthStateDescriptor = MTLDepthStencilDescriptor()
        compositeDepthStateDescriptor.depthCompareFunction = .always
        compositeDepthStateDescriptor.isDepthWriteEnabled = false
        compositeDepthState = device.makeDepthStencilState(descriptor: compositeDepthStateDescriptor)
        
    }
    
    // Adds a module to the renderModules array witout being initialized.
    // initializeModules() must be called
    fileprivate func addModule(forModuelIdentifier moduleIdentifier: String) {
        
        var updatedRenderModules: [RenderModule] = renderModules
        
        switch moduleIdentifier {
        case CameraPlaneRenderModule.identifier:
            if cameraRenderModule == nil {
                let newCameraModule = CameraPlaneRenderModule()
                cameraRenderModule = newCameraModule
                cameraRenderModule?.imagePlaneVertexBuffer = imagePlaneVertexBuffer
                cameraRenderModule?.scenePlaneVertexBuffer = scenePlaneVertexBuffer
                updatedRenderModules.append(newCameraModule)
                hasUninitializedModules = true
            }
        case SharedBuffersRenderModule.identifier:
            if sharedBuffersRenderModule == nil {
                let newSharedModule = SharedBuffersRenderModule()
                sharedBuffersRenderModule = newSharedModule
                sharedBuffersRenderModule?.sharedUniformsBuffer = sharedUniformsBuffer
                updatedRenderModules.append(newSharedModule)
                hasUninitializedModules = true
            }
        case SurfacesRenderModule.identifier:
            if surfacesRenderModule == nil {
                let newSurfacesModule = SurfacesRenderModule()
                surfacesRenderModule = newSurfacesModule
                updatedRenderModules.append(newSurfacesModule)
                hasUninitializedModules = true
            }
        case AnchorsRenderModule.identifier:
            if anchorsRenderModule == nil {
                let newAnchorsModule = AnchorsRenderModule()
                anchorsRenderModule = newAnchorsModule
                updatedRenderModules.append(newAnchorsModule)
                hasUninitializedModules = true
            }
        case UnanchoredRenderModule.identifier:
            if unanchoredRenderModule == nil {
                let newUnanchoredModule = UnanchoredRenderModule()
                unanchoredRenderModule = newUnanchoredModule
                updatedRenderModules.append(newUnanchoredModule)
                hasUninitializedModules = true
            }
        case PathsRenderModule.identifier:
            if pathsRenderModule == nil {
                let newPathsModule = PathsRenderModule()
                pathsRenderModule = newPathsModule
                updatedRenderModules.append(newPathsModule)
                hasUninitializedModules = true
            }
        case TrackingPointsRenderModule.identifier:
            if trackingPointRenderModule == nil {
                let newSharedModule = TrackingPointsRenderModule()
                trackingPointRenderModule = newSharedModule
                updatedRenderModules.append(newSharedModule)
                hasUninitializedModules = true
            }
        default:
            break
        }
        
        renderModules = updatedRenderModules.sorted(by: {$0.renderLayer < $1.renderLayer})
    
    }
    
    /// Updates the renderModules array with all of the required modules. Also updates the sharedModulesForModule map
    fileprivate func gatherModules() {
        
        var sharedModules: [SharedRenderModule] = []
        var updatedRenderModules: [RenderModule] = []
        
        renderModules.forEach { module in
            
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
        renderModules.forEach { module in
            if let sharedModuleIdentifiers = module.sharedModuleIdentifiers, sharedModuleIdentifiers.count > 0 {
                let foundSharedModules = sharedModules.filter({sharedModuleIdentifiers.contains($0.moduleIdentifier)})
                sharedModulesForModule[module.moduleIdentifier] = foundSharedModules
            }
        }
        computeModules.forEach { module in
            if let sharedModuleIdentifiers = module.sharedModuleIdentifiers, sharedModuleIdentifiers.count > 0 {
                let foundSharedModules = sharedModules.filter({sharedModuleIdentifiers.contains($0.moduleIdentifier)})
                sharedModulesForModule[module.moduleIdentifier] = foundSharedModules
            }
        }
            
    }
    
    /// Initializes any uninitialized modules. If a module has already been initialized, the initilization functions are _not_ called again. Also calls `loadAssets` on uninitalized modules.
    fileprivate func initializeModules() {
        
        guard hasUninitializedModules else {
            return
        }
        
        gatherModules()
        
        let uninitializedCount = renderModules.filter({$0.state == .uninitialized}).count + computeModules.filter({$0.state == .uninitialized}).count
        var loadedCount = 0
        var modulesLoaded = [String]()
        
        renderModules.forEach { module in
            
            if module.state == .uninitialized {
                modulesLoaded.append(module.moduleIdentifier)
                // Initialize the module
                module.initializeBuffers(withDevice: device, maxInFlightFrames: Constants.maxInFlightFrames, maxInstances: Constants.maxInstances)
                
                // Get all of the AKGeometricEntity's associated with this module
                var geometricEntities: [AKGeometricEntity] = (entitiesForRenderModule[module.moduleIdentifier] ?? []).compactMap({
                    if let geoEntity = $0 as? AKGeometricEntity {
                        return geoEntity
                    } else {
                        return nil
                    }
                })
                let geometricEntityGroups: [AKGeometricEntityGroup] = (entitiesForRenderModule[module.moduleIdentifier] ?? []).compactMap({
                    if let geoEntity = $0 as? AKGeometricEntityGroup {
                        return geoEntity
                    } else {
                        return nil
                    }
                })
                let groupGeometries = geometricEntityGroups.flatMap({$0.geometries})
                geometricEntities.append(contentsOf: groupGeometries)
                
                // Load the assets
                module.loadAssets(forGeometricEntities: geometricEntities, fromModelProvider: modelProvider, textureLoader: textureLoader, completion: { [weak self] in
                   
                    loadedCount += 1
                        
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
                    
                    if loadedCount == uninitializedCount {
                        loadPipelines(for: modulesLoaded)
                    }
                })
            }
            
        }
        
        computeModules.forEach { module in
            if module.state == .uninitialized {
                modulesLoaded.append(module.moduleIdentifier)
                // Initialize the module
                module.initializeBuffers(withDevice: device, maxInFlightFrames: Constants.maxInFlightFrames, maxInstances: Constants.maxInstances)
                loadedCount += 1
                if loadedCount == uninitializedCount {
                    loadPipelines(for: modulesLoaded)
                }
            }
        }
        
        hasUninitializedModules = false
        
    }
    
    fileprivate func loadPipelines(for moduleIdentifiers: [String]) {
        
        guard !moduleIdentifiers.isEmpty else {
            return
        }
        
        guard let defaultLibrary = defaultLibrary else {
            return
        }
        
        var mutableShadowPassDrawCallGroups = shadowRenderPass?.drawCallGroups ?? []
        var mutableMainPassDrawCallGroups = mainRenderPass?.drawCallGroups ?? []
        let numQualityLevels: Int = {
            if AKCapabilities.LevelOfDetail {
                return Constants.numQualityLevels
            } else {
                return 1
            }
        }()
        
        renderModules.filter({moduleIdentifiers.contains($0.moduleIdentifier)}).forEach { module in
            module.loadPipeline(withModuleEntities: entitiesForRenderModule[module.moduleIdentifier] ?? [], metalLibrary: defaultLibrary, renderDestination: renderDestination, textureBundle: textureBundle, renderPass: shadowRenderPass, numQualityLevels: numQualityLevels) { [weak self] drawCallGroups in
                let removeIDs = drawCallGroups.map({$0.uuid})
                mutableShadowPassDrawCallGroups.removeAll(where: {removeIDs.contains($0.uuid)})
                mutableShadowPassDrawCallGroups.append(contentsOf: drawCallGroups)
                self?.shadowRenderPass?.drawCallGroups = mutableShadowPassDrawCallGroups
            }
            module.loadPipeline(withModuleEntities: entitiesForRenderModule[module.moduleIdentifier] ?? [], metalLibrary: defaultLibrary, renderDestination: renderDestination, textureBundle: textureBundle, renderPass: mainRenderPass, numQualityLevels: numQualityLevels) { [weak self] drawCallGroups in
                let removeIDs = drawCallGroups.map({$0.uuid})
                mutableMainPassDrawCallGroups.removeAll(where: {removeIDs.contains($0.uuid)})
                mutableMainPassDrawCallGroups.append(contentsOf: drawCallGroups)
                self?.mainRenderPass?.drawCallGroups = mutableMainPassDrawCallGroups
            }
        }
        computeModules.filter({moduleIdentifiers.contains($0.moduleIdentifier)}).forEach { module in
            if let precalculationModule = module as? AnyComputeModule<PrecalculatedParameters> {
                precalculationPass?.threadGroup = precalculationModule.loadPipeline(withMetalLibrary: defaultLibrary, renderDestination: renderDestination, textureBundle: textureBundle, forComputePass: precalculationPass)
            } else if let defaultComputeModule = module as? AnyComputeModule<Any> {
                let _ = defaultComputeModule.loadPipeline(withMetalLibrary: defaultLibrary, renderDestination: renderDestination, textureBundle: textureBundle, forComputePass: nil)
            }
        }
        
    }
    
    fileprivate func prepareToDraw(forCameraProperties cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties, shadowProperties: ShadowProperties, renderPass: RenderPass?) {
        
        let allEntities: [AKEntity] = entitiesForRenderModule.flatMap { (key, value) in
            return value
        }
        // Update precalculation module
        if let preRenderComputeModule = precalculationComputeModule, let precalculationPass = precalculationPass, preRenderComputeModule.state == .ready {
            preRenderComputeModule.prepareToDraw(withAllEntities: allEntities, cameraProperties: cameraProperties, environmentProperties: environmentProperties, shadowProperties: shadowProperties, computePass: precalculationPass, renderPass: renderPass)
        }
    }
    
    fileprivate func updateBuffers(forCameraProperties cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties, shadowProperties: ShadowProperties, argumentBufferProperties: ArgumentBufferProperties, renderPass: RenderPass ) {
        
        // Update Buffers
        renderModules.forEach { module in
            if module.state == .ready {
                module.updateBuffers(withModuleEntities: entitiesForRenderModule[module.moduleIdentifier] ?? [], cameraProperties: cameraProperties, environmentProperties: environmentProperties, shadowProperties: shadowProperties, argumentBufferProperties: argumentBufferProperties, forRenderPass: renderPass)
            }
        }
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
                sharedBuffersRenderModule?.sharedUniformsBuffer = sharedUniformsBuffer
                return newSharedModule
            }
        default:
            return nil
        }
    }
    
    // MARK: IBL Prerender Passes
    
    /// Draw to the depth texture from the directional lights point of view to generate the shadow map
    fileprivate func dispatchIBLPasses(withCommandBuffer commandBuffer: MTLCommandBuffer) {
        
        guard AKCapabilities.ImageBasedLighting else {
            return
        }
        
        diffuseIBLCubePass?.prepareCommandEncoder(withCommandBuffer: commandBuffer)
        diffuseIBLCubePass?.dispatch()
        specularIBLCubePass?.prepareCommandEncoder(withCommandBuffer: commandBuffer)
        specularIBLCubePass?.dispatch()
        computeBDRFLookupPass?.prepareCommandEncoder(withCommandBuffer: commandBuffer)
        computeBDRFLookupPass?.dispatch()
        
    }
    
    // MARK: Shadow Pass
    
    /// Draw to the depth texture from the directional lights point of view to generate the shadow map
    fileprivate func drawShadowPass(with commandEncoder: MTLRenderCommandEncoder) {
        
        // Draw
        renderModules.forEach { module in
            if let shadowRenderPass = shadowRenderPass, module.state == .ready {
                 module.draw(withRenderPass: shadowRenderPass, sharedModules: sharedModulesForModule[module.moduleIdentifier])
            }
        }
        
        commandEncoder.endEncoding()
    }
    
    // MARK: Main Pass
    
    fileprivate func drawMainPass(with commandEncoder: MTLRenderCommandEncoder) {
        
        // Draw
        renderModules.forEach { module in
            if let mainRenderPass = mainRenderPass, module.state == .ready {
                module.draw(withRenderPass: mainRenderPass, sharedModules: sharedModulesForModule[module.moduleIdentifier])
            }
        }
        
        // We're done encoding commands
        commandEncoder.endEncoding()
        
    }
    
    fileprivate func freeTextureMemory(for enitityIDs: [UUID]) {
        
        let existingMainPassDrawCallGroups = mainRenderPass?.drawCallGroups ?? []
        
        // For the current DrawCallGroup's that have been removed, Mark the textures associated with those draw calls purgable so the system can free up the memory
        let removedMainPassGroups = existingMainPassDrawCallGroups.filter({ enitityIDs.contains($0.uuid) })
        removedMainPassGroups.forEach{ $0.markTexturesAsVolitile() }
    }
    
    // MARK: Precomute pass
    
    /// Draw to the depth texture from the directional lights point of view to generate the shadow map
    fileprivate func dispatchComputePasses(withCommandBuffer commandBuffer: MTLCommandBuffer) {
        
        // Dispatch
        computeModules.forEach { module in
            if let precalculationModule = module as? AnyComputeModule<PrecalculatedParameters>, let precalculationPass = precalculationPass, let sharedModules = sharedModulesForModule[precalculationModule.moduleIdentifier], precalculationModule.state == .ready, sharedModules.count > 0 {
                precalculationPass.prepareCommandEncoder(withCommandBuffer: commandBuffer)
                precalculationModule.dispatch(withComputePass: precalculationPass, sharedModules: sharedModules)
                precalculationPass.computeCommandEncoder?.endEncoding()
            }
        }
    }
    
    // MARK: Composite Pass
    
    fileprivate func drawCompositePass(with commandEncoder: MTLRenderCommandEncoder) {
        
        guard let cameraRenderModule = cameraRenderModule else {
            return
        }
        
        guard let textureY = cameraRenderModule.capturedImageTextureY, let textureCbCr = cameraRenderModule.capturedImageTextureCbCr else {
            return
        }
        
        guard let compositePipelineState = compositePipelineState, let compositeDepthState = compositeDepthState else {
            return
        }
                
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        commandEncoder.pushDebugGroup("CompositePass")
                
        // Set render command encoder state
        commandEncoder.setCullMode(.none)
        commandEncoder.setRenderPipelineState(compositePipelineState)
        commandEncoder.setDepthStencilState(compositeDepthState)
                
        // Setup plane vertex buffers
        let sharedBuffer = sharedUniformsBuffer?.buffer
        let sharedBufferOffset = sharedUniformsBuffer?.currentBufferFrameOffset ?? 0
        let sharedBufferIndex = sharedUniformsBuffer?.shaderAttributeIndex ?? 0
        commandEncoder.setVertexBuffer(sharedBuffer, offset: sharedBufferOffset, index: sharedBufferIndex)
        commandEncoder.setVertexBuffer(cameraRenderModule.imagePlaneVertexBuffer?.buffer, offset: 0, index: Int(kBufferIndexCameraVertices.rawValue))
        commandEncoder.setVertexBuffer(cameraRenderModule.scenePlaneVertexBuffer?.buffer, offset: 0, index: Int(kBufferIndexSceneVerticies.rawValue))
                
        // Set any textures read/sampled from our render pipeline
        commandEncoder.setFragmentTexture(CVMetalTextureGetTexture(textureY), index: Int(kTextureIndexY.rawValue))
        commandEncoder.setFragmentTexture(CVMetalTextureGetTexture(textureCbCr), index: Int(kTextureIndexCbCr.rawValue))
        
        commandEncoder.setFragmentTexture(CVMetalTextureGetTexture(textureY), index: Int(kTextureIndexY.rawValue))
        commandEncoder.setFragmentTexture(CVMetalTextureGetTexture(textureCbCr), index: Int(kTextureIndexCbCr.rawValue))
        commandEncoder.setFragmentTexture(sceneColorTexture, index: Int(kTextureIndexSceneColor.rawValue))
        commandEncoder.setFragmentTexture(sceneDepthTexture, index: Int(kTextureIndexSceneDepth.rawValue))
        commandEncoder.setFragmentTexture(alphaTexture, index: Int(kTextureIndexAlpha.rawValue))
        commandEncoder.setFragmentTexture(dilatedDepthTexture, index: Int(kTextureIndexDialatedDepth.rawValue))
        
        // Draw each submesh of our mesh
        commandEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        
        commandEncoder.popDebugGroup()
        
        // We're done encoding commands
        commandEncoder.endEncoding()
        
    }
    
    // MARK: Environment maps
    
    fileprivate func remapEnvironmentProbes() {
        // The AREnvironmentProbeAnchor probes that are provided by ARKit onlt apply
        // to a certain range. This maps the AREnvironmentProbeAnchor's with the
        // identifiers of the AKAnchors that fall inside
        environmentAnchorsWithReatedAnchors = [:]
        environmentProbeAnchors.forEach { environmentAnchor in
            let environmentPosition = SIMD3<Float>(environmentAnchor.transform.columns.3.x, environmentAnchor.transform.columns.3.y, environmentAnchor.transform.columns.3.z)
            let cube = AKCube(position: AKVector(environmentPosition), extent: AKVector(environmentAnchor.extent))
            let anchorIDs: [UUID] = augmentedAnchors.compactMap{ normalAnchor in
                let anchorPosition = AKVector(x: normalAnchor.worldLocation.transform.columns.3.x, y: normalAnchor.worldLocation.transform.columns.3.y, z: normalAnchor.worldLocation.transform.columns.3.z)
                if cube.contains(anchorPosition) {
                    return normalAnchor.identifier
                } else {
                    return nil
                }
            }
            environmentAnchorsWithReatedAnchors[environmentAnchor] = anchorIDs
        }
    }
    
}

// MARK: - ARSessionDelegate

extension Renderer: ARSessionDelegate {
    
    /// :nodoc:
    public func session(_ session: ARSession, didFailWithError error: Error) {
        let newError = AKError.recoverableError(.arkitError(UnderlyingErrorInfo(underlyingError: error)))
        delegate?.renderer(self, didFailWithError: newError)
    }
     /// :nodoc:
    public func sessionWasInterrupted(_ session: ARSession) {
        delegate?.rendererWasInterrupted(self)
    }
     /// :nodoc:
    public func sessionInterruptionEnded(_ session: ARSession) {
        delegate?.rendererWasInterrupted(self)
    }
    
     /// :nodoc:
    public func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        
        var modulesToUpdate = Set<String>()
        
        anchors.forEach { anchor in
            if let planeAnchor = anchor as? ARPlaneAnchor {
                
                modulesToUpdate.insert(SurfacesRenderModule.identifier)
                
                if var akAnchor = realAnchors.first(where: { k in
                    k.identifier == planeAnchor.identifier
                }) as? AKRealSurfaceAnchor {
                    akAnchor.setARAnchor(planeAnchor)
                    akAnchor.planeGeometry = planeAnchor.geometry
                    akAnchor.needsMeshUpdate = true
                } else {
                    let newRealAnchor = RealSurfaceAnchor(at: WorldLocation(transform: planeAnchor.transform), planeGeometry: planeAnchor.geometry)
                    newRealAnchor.setARAnchor(planeAnchor)
                    newRealAnchor.identifier = planeAnchor.identifier
                    if let existingGeometries = entitiesForRenderModule[SurfacesRenderModule.identifier] {
                        var mutableExistingGeometries = existingGeometries
                        mutableExistingGeometries.append(newRealAnchor)
                        entitiesForRenderModule[SurfacesRenderModule.identifier] = mutableExistingGeometries
                    } else {
                        entitiesForRenderModule[SurfacesRenderModule.identifier] = [newRealAnchor]
                    }
                }
                
                //
                // Update the lowest surface plane
                //
                
                if case .floor = planeAnchor.classification {
                    groundPlaneAnchor = planeAnchor
                }
                
            } else if let environmentProbeAnchor = anchor as? AREnvironmentProbeAnchor, let environmentCubeMap = environmentProbeAnchor.environmentTexture {
                environmentProbeAnchors.append(environmentProbeAnchor)
                remapEnvironmentProbes()
                if environmentProbeAnchor.extent.x.isInfinite {
                    let aGPUTexture = GPUPassTexture(texture: environmentCubeMap, label: "Global Environment Texture", shaderAttributeIndex: Int(kTextureIndexEnvironmentMap.rawValue))
                    environmentTexture = aGPUTexture
                    hasEnvironmentTextureChanged = true
                }
            } else if let _ = anchor as? ARObjectAnchor {
                
            } else if let _ = anchor as? ARImageAnchor {
                
            } else if let _ = anchor as? ARFaceAnchor {
                
            } else {
                if let akAnchor = augmentedAnchors.first(where: { k in
                    k.identifier == anchor.identifier
                }) {
                    akAnchor.setARAnchor(anchor)
                }
                modulesToUpdate.insert(AnchorsRenderModule.identifier)
                remapEnvironmentProbes()
            }
        }
        
        loadPipelines(for: Array(modulesToUpdate))
        
    }
    
    /// :nodoc:
    public func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        
        anchors.forEach { anchor in
            if let planeAnchor = anchor as? ARPlaneAnchor {
                
                if var akAnchor = realAnchors.first(where: { k in
                    k.identifier == planeAnchor.identifier
                }) as? AKRealSurfaceAnchor {
                    akAnchor.setARAnchor(planeAnchor)
                    akAnchor.planeGeometry = planeAnchor.geometry
                    akAnchor.needsMeshUpdate = true
                }
                
                //
                // Update the lowest surface plane
                //
                
                if case .floor = planeAnchor.classification {
                    groundPlaneAnchor = planeAnchor
                }
                
            } else if let environmentProbeAnchor = anchor as? AREnvironmentProbeAnchor, let environmentCubeMap = environmentProbeAnchor.environmentTexture {
                
                if let index = environmentProbeAnchors.firstIndex(of: environmentProbeAnchor) {
                    environmentProbeAnchors.replaceSubrange(index..<(index + 1), with: [environmentProbeAnchor])
                    remapEnvironmentProbes()
                }
                if environmentProbeAnchor.extent.x.isInfinite {
                    let aGPUTexture = GPUPassTexture(texture: environmentCubeMap, label: "Global Environment Texture", shaderAttributeIndex: Int(kTextureIndexEnvironmentMap.rawValue))
                    environmentTexture = aGPUTexture
                    hasEnvironmentTextureChanged = true
                }
            } else if let _ = anchor as? ARObjectAnchor {
                
            } else if let _ = anchor as? ARImageAnchor {
                
            } else if let _ = anchor as? ARFaceAnchor {
                
            } else {
                if let akAnchor = augmentedAnchors.first(where: { k in
                    k.identifier == anchor.identifier
                }) {
                    akAnchor.setARAnchor(anchor)
                }
                remapEnvironmentProbes()
            }
        }
    }
    
    /// :nodoc:
    public func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        
        var modulesToUpdate = Set<String>()
        
        anchors.forEach { anchor in
            if let planeAnchor = anchor as? ARPlaneAnchor {
                
                modulesToUpdate.insert(SurfacesRenderModule.identifier)
                
                if let anchorIndex = realAnchors.firstIndex(where: { k in
                    k.identifier == planeAnchor.identifier
                }) {
                    var updatedAnchors = entitiesForRenderModule[SurfacesRenderModule.identifier]
                    updatedAnchors?.remove(at: anchorIndex)
                    entitiesForRenderModule[SurfacesRenderModule.identifier] = updatedAnchors
                }
                
                //
                // Update the lowest surface plane
                //
                
                if case .floor = planeAnchor.classification {
                    groundPlaneAnchor = planeAnchor
                }
                
            } else if let environmentProbeAnchor = anchor as? AREnvironmentProbeAnchor {
                
                if let index = environmentProbeAnchors.firstIndex(of: environmentProbeAnchor) {
                    environmentProbeAnchors.remove(at: index)
                    remapEnvironmentProbes()
                }
            } else if let _ = anchor as? ARObjectAnchor {
                
            } else if let _ = anchor as? ARImageAnchor {
                
            } else if let _ = anchor as? ARFaceAnchor {
                
            } else {
                //
                modulesToUpdate.insert(AnchorsRenderModule.identifier)
            }
            
            loadPipelines(for: Array(modulesToUpdate))
        }
    }
    
}

// MARK: - InterpolatingAugmentedAnchor

// A subclass of `InternalAugmentedAnchor` that interpolates between locations
// in order to achieve smoothing.
// Set the interpolation progress with `interpolation`
// Call `update()` to do the terpolation calculations.
// After calling `update()`, `currentLocation` contains the interpolated transform with
// the `latitude`, `longitude`, and `elevation` set to the final values
fileprivate class InterpolatingAugmentedAnchor: AKAugmentedAnchor {
    
    static var type: String {
        return "InterpolatingAugmentedAnchor"
    }

    var worldLocation: AKWorldLocation
    var heading: AKHeading = SameHeading()
    var asset: MDLAsset
    var identifier: UUID?
    var effects: [AnyEffect<Any>]?
    var shaderPreference: ShaderPreference = .pbr
    var generatesShadows: Bool = true
    var needsColorTextureUpdate: Bool = false
    var needsMeshUpdate: Bool = false
    var arAnchor: ARAnchor?

    init(withAKAugmentedAnchor akAugmentedAnchor: AKAugmentedAnchor) {
        self.asset = akAugmentedAnchor.asset
        self.identifier = akAugmentedAnchor.identifier
        self.worldLocation = akAugmentedAnchor.worldLocation
        self.effects = akAugmentedAnchor.effects
    }
    
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
    
    func setARAnchor(_ arAnchor: ARAnchor) {
        self.arAnchor = arAnchor
        if identifier == nil {
            identifier = arAnchor.identifier
        }
        worldLocation.transform = arAnchor.transform
    }
    
    // MARK: Private
    
    private var needsUpdate = false
    
}

