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

// MARK: - RenderStats

public struct RenderStats {
    public var arKitAnchorCount: Int
    public var numAnchors: Int
    public var numPlanes: Int
    public var numTrackingPoints: Int
    public var numTrackers: Int
    public var numTargets: Int
    public var numPathSegments: Int
}

// MARK: - RenderMonitor

public protocol RenderMonitor {
    func update(renderStats: RenderStats)
    func update(renderErrors: [AKError])
}

// MARK: - RenderDelegate

public protocol RenderDelegate {
    
    func renderer(_ renderer: Renderer, didFailWithError error: AKError)
    func rendererWasInterrupted(_ renderer: Renderer)
    func rendererInterruptionEnded(_ renderer: Renderer)
    
}

// MARK: - CameraProperties

public struct CameraProperties {
    var orientation: UIInterfaceOrientation
    var viewportSize: CGSize
    var viewportSizeDidChange: Bool
    var position: float3
    var currentFrame: UInt
    var frameRate: Double = 60
    var arCamera: ARCamera
    var capturedImage: CVPixelBuffer
    var displayTransform: CGAffineTransform
    var rawFeaturePoints: ARPointCloud?
    
    init(orientation: UIInterfaceOrientation, viewportSize: CGSize, viewportSizeDidChange: Bool, position: float3, currentFrame: UInt, frame: ARFrame, frameRate: Double = 60) {
        self.orientation = orientation
        self.viewportSize = viewportSize
        self.viewportSizeDidChange = viewportSizeDidChange
        self.position = position
        self.currentFrame = currentFrame
        self.frameRate = frameRate
        self.arCamera = frame.camera
        self.capturedImage = frame.capturedImage
        self.displayTransform = frame.displayTransform(for: orientation, viewportSize: viewportSize)
        self.rawFeaturePoints = frame.rawFeaturePoints
    }
}

// MARK: - EnvironmentProperties

public struct EnvironmentProperties {
    var lightEstimate: ARLightEstimate?
    var environmentAnchorsWithReatedAnchors: [AREnvironmentProbeAnchor: [UUID]] = [:]
}

// MARK: - Renderer

public class Renderer: NSObject {
    
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
    public let textureBundle: Bundle
    
    public var modelProvider: ModelProvider? = AKModelProvider.sharedInstance
    public var delegate: RenderDelegate?
    
    // Guides for debugging. Turning this on will show the tracking points used by
    // ARKit as well as detected surfaces. Setting this to true will
    // affect performance.
    public var showGuides = false {
        didSet {
            if showGuides {
                if renderModules.filter({$0 is TrackingPointsRenderModule}).isEmpty {
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
    public var currentFrameNumber: UInt {
        guard worldInitiationTime > 0 && lastFrameTime > 0 else {
            return 0
        }
        
        let elapsedTime = lastFrameTime - worldInitiationTime
        return UInt(floor(elapsedTime * frameRate))
    }
    public var frameRate: Double {
        return 60
    }
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
            return hitTestResult.worldTransform
        } else {
            return matrix_identity_float4x4
        }
        
    }
    
    public init(session: ARSession, metalDevice device: MTLDevice, renderDestination: RenderDestinationProvider, textureBundle: Bundle) {
        
        self.session = session
        self.device = device
        self.renderDestination = renderDestination
        self.textureBundle = textureBundle
        self.textureLoader = MTKTextureLoader(device: device)
        super.init()
        
        self.session.delegate = self
        
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
            worldInitiationTime = currentFrame.timestamp
        }
        
        lastFrameTime = currentFrame.timestamp
        
        hasDetectedSurfaces = hasDetectedSurfaces || (lowestHorizPlaneAnchor != nil) || (realAnchors.count > 0)
        
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
        // Initialize Modules
        //
        
        // Add surface modules for rendering if necessary
        if surfacesRenderModule == nil && showGuides && realAnchors.count > 0  {
            
            let metalAllocator = MTKMeshBufferAllocator(device: device)
            modelProvider?.registerAsset(GuideSurfaceAnchor.createModelAsset(inBundle: textureBundle, withAllocator: metalAllocator)!, forObjectType: GuideSurfaceAnchor.type, identifier: nil)
            
            addModule(forModuelIdentifier: SurfacesRenderModule.identifier)
            
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
                let updatedGazeTargets: [GazeTarget] = gazeTargets.map {
                    $0.position.parentPosition?.transform = gazeTransform
                    $0.position.updateTransforms()
                    return $0
                }
                gazeTargets = updatedGazeTargets
            }
            
        }
        
        //
        // Environment Properties
        //
        
        var environmentProperties = EnvironmentProperties()
        environmentProperties.environmentAnchorsWithReatedAnchors = environmentAnchorsWithReatedAnchors
        environmentProperties.lightEstimate = currentFrame.lightEstimate
        
        //
        // Camera Properties
        //
        
        let cameraPosition: float3 = {
            if let currentCameraPositionTransform = currentCameraPositionTransform {
                return float3(currentCameraPositionTransform.columns.3.x, currentCameraPositionTransform.columns.3.y, currentCameraPositionTransform.columns.3.z)
            } else {
                return float3(0, 0, 0)
            }
        }()
        
        let cameraProperties = CameraProperties(orientation: orientation, viewportSize: viewportSize, viewportSizeDidChange: viewportSizeDidChange, position: cameraPosition, currentFrame: currentFrameNumber, frame: currentFrame, frameRate: frameRate)
        
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
            
            // Update Buffers
            for module in renderModules {
                if module.isInitialized {
                    module.updateBuffers(withAugmentedAnchors: augmentedAnchors, cameraProperties: cameraProperties, environmentProperties: environmentProperties)
                    module.updateBuffers(withRealAnchors: realAnchors, cameraProperties: cameraProperties, environmentProperties: environmentProperties)
                    module.updateBuffers(withTrackers: trackers, targets: gazeTargets, cameraProperties: cameraProperties, environmentProperties: environmentProperties)
                    module.updateBuffers(withPaths: paths, cameraProperties: cameraProperties, environmentProperties: environmentProperties)
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
    public func add(akAnchor: AKAugmentedAnchor) {
        
        let arAnchor = ARAnchor(transform: akAnchor.worldLocation.transform)
        akAnchor.setIdentifier(arAnchor.identifier)
        
        let anchorType = type(of: akAnchor).type
        
        // Resgister the AKModel with the model provider.
        modelProvider?.registerAsset(akAnchor.asset, forObjectType: anchorType, identifier: akAnchor.identifier)
        
        // Keep track of the anchor bucketed by the RenderModule
        // This will be used to load individual models per anchor.
        if let existingGeometries = geometriesForRenderModule[AnchorsRenderModule.identifier] {
            var mutableExistingGeometries = existingGeometries
            mutableExistingGeometries.append(akAnchor)
            geometriesForRenderModule[AnchorsRenderModule.identifier] = mutableExistingGeometries
            anchorsRenderModule?.isInitialized = false
            hasUninitializedModules = true
        } else {
            geometriesForRenderModule[AnchorsRenderModule.identifier] = [akAnchor]
        }
        
        augmentedAnchors.append(akAnchor)
        
        // Add a new anchor to the session
        session.add(anchor: arAnchor)
        
    }
    
    //  Add a new AKAugmentedTracker to the AR world
    public func add(akTracker: AKAugmentedTracker) {
        
        let identifier = UUID()
        
        if let userTracker = akTracker as? UserTracker {
            // If a UserTracker instance was passed in, use that directly instead of the
            // internal type
            userTracker.setIdentifier(identifier)
        } else {
            akTracker.setIdentifier(identifier)
        }
        
        let anchorType = type(of: akTracker).type
        
        // Resgister the AKModel with the model provider.
        modelProvider?.registerAsset(akTracker.asset, forObjectType: anchorType, identifier: akTracker.identifier)
        
        // Keep track of the tracker bucketed by the RenderModule
        // This will be used to load individual models per anchor.
        if let existingGeometries = geometriesForRenderModule[UnanchoredRenderModule.identifier] {
            var mutableExistingGeometries = existingGeometries
            mutableExistingGeometries.append(akTracker)
            geometriesForRenderModule[UnanchoredRenderModule.identifier] = mutableExistingGeometries
        } else {
            geometriesForRenderModule[UnanchoredRenderModule.identifier] = [akTracker]
        }
        
        trackers.append(akTracker)
        
    }
    
    //  Add a new path to the AR world
    public func add(akPath: AKPath) {
        
        let identifier = UUID()
    
        akPath.setIdentifier(identifier)
        
        let anchorType = type(of: akPath).type
        
        // Resgister the AKModel with the model provider.
        modelProvider?.registerAsset(akPath.asset, forObjectType: anchorType, identifier: akPath.identifier)
        
        // Update the segment anchors by adding the ARAnchor identifier which will allow us
        // to trace back the ARAnchors to the path they belong to.
        akPath.segmentPoints.forEach {
            
            // Add a new anchor to the session
            let arAnchor = ARAnchor(transform: $0.worldLocation.transform)
            session.add(anchor: arAnchor)
            
            $0.setIdentifier(arAnchor.identifier)
            
        }
        
        paths.append(akPath)
        
    }
    
    public func add(gazeTarget: GazeTarget) {
        
        let theType = type(of: gazeTarget).type
        let identifier = UUID()
        gazeTarget.identifier = identifier
        
        // Resgister the AKModel with the model provider.
        modelProvider?.registerAsset(gazeTarget.asset, forObjectType: theType, identifier: gazeTarget.identifier)
        
        // Keep track of the tracker bucketed by the RenderModule
        // This will be used to load individual models per anchor.
        if let existingGeometries = geometriesForRenderModule[UnanchoredRenderModule.identifier] {
            var mutableExistingGeometries = existingGeometries
            mutableExistingGeometries.append(gazeTarget)
            geometriesForRenderModule[UnanchoredRenderModule.identifier] = mutableExistingGeometries
        } else {
            geometriesForRenderModule[UnanchoredRenderModule.identifier] = [gazeTarget]
        }
        
        gazeTargets.append(gazeTarget)
        
    }
    
    // MARK: - Removing objects
    
    public func remove(akAnchor: AKAugmentedAnchor) {
        
        guard let akAnchorIndex = augmentedAnchors.index(where: {$0.identifier == akAnchor.identifier}) else {
            return
        }
        
        augmentedAnchors.remove(at: akAnchorIndex)
        
        let anchorType = type(of: akAnchor).type
        modelProvider?.unregisterAsset(forObjectType: anchorType, identifier: akAnchor.identifier)
        var existingGeometries = geometriesForRenderModule[AnchorsRenderModule.identifier]
        if let index = existingGeometries?.index(where: {$0.identifier == akAnchor.identifier}) {
            existingGeometries?.remove(at: index)
        }
        geometriesForRenderModule[AnchorsRenderModule.identifier] = existingGeometries
        
        guard let arAnchor = session.currentFrame?.anchors.first(where: {$0.identifier == akAnchor.identifier}) else {
            return
        }
        
        session.remove(anchor: arAnchor)
        
    }
    
    public func remove(akTracker: AKAugmentedTracker) {
        
        guard let akTrackerIndex = trackers.index(where: {$0.identifier == akTracker.identifier}) else {
            return
        }
        
        trackers.remove(at: akTrackerIndex)
        
        let anchorType = type(of: akTracker).type
        modelProvider?.unregisterAsset(forObjectType: anchorType, identifier: akTracker.identifier)
        var existingGeometries = geometriesForRenderModule[UnanchoredRenderModule.identifier]
        if let index = existingGeometries?.index(where: {$0.identifier == akTracker.identifier}) {
            existingGeometries?.remove(at: index)
        }
        geometriesForRenderModule[UnanchoredRenderModule.identifier] = existingGeometries
        
    }
    
    public func remove(akPath: AKPath) {
        
        guard let akPathIndex = paths.index(where: {$0.identifier == akPath.identifier}) else {
            return
        }
        
        paths.remove(at: akPathIndex)
        
        akPath.segmentPoints.forEach { segment in
            if let arAnchor = session.currentFrame?.anchors.first(where: {$0.identifier == segment.identifier}) {
                session.remove(anchor: arAnchor)
            }
        }
        
        let anchorType = type(of: akPath).type
        modelProvider?.unregisterAsset(forObjectType: anchorType, identifier: akPath.identifier)
        
    }
    
    public func remove(gazeTarget: GazeTarget) {
        
        guard let gazeTargetIndex = gazeTargets.index(where: {$0.identifier == gazeTarget.identifier}) else {
            return
        }
        
        gazeTargets.remove(at: gazeTargetIndex)
        
        let anchorType = type(of: gazeTarget).type
        modelProvider?.unregisterAsset(forObjectType: anchorType, identifier: gazeTarget.identifier)
        var existingGeometries = geometriesForRenderModule[UnanchoredRenderModule.identifier]
        if let index = existingGeometries?.index(where: {$0.identifier == gazeTarget.identifier}) {
            existingGeometries?.remove(at: index)
        }
        geometriesForRenderModule[UnanchoredRenderModule.identifier] = existingGeometries
        
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
    fileprivate var geometriesForRenderModule = [String: [AKGeometricEntity]]()
    fileprivate var augmentedAnchors = [AKAugmentedAnchor]()
    fileprivate var realAnchors = [AKRealAnchor]()
    fileprivate var trackers = [AKAugmentedTracker]()
    fileprivate var paths = [AKPath]()
    fileprivate var gazeTargets = [GazeTarget]()
    fileprivate var environmentProbeAnchors = [AREnvironmentProbeAnchor]()
    fileprivate var environmentAnchorsWithReatedAnchors = [AREnvironmentProbeAnchor: [UUID]]()
    
    fileprivate var moduleErrors = [AKError]()
    
    // MARK: ARKit Session Configuration
    
    fileprivate func createNewConfiguration() -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        // Setting this to .gravityAndHeading aligns the the origin of the scene to compass direction
        configuration.worldAlignment = .gravityAndHeading
        
        // Enable horizontal plane detection
        configuration.planeDetection = [.horizontal, .vertical]
        
        // Enable environment texturing
        configuration.environmentTexturing = .automatic
        
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
                let geometricEntities = geometriesForRenderModule[module.moduleIdentifier] ?? []
                module.loadAssets(forGeometricEntities: geometricEntities, fromModelProvider: modelProvider, textureLoader: textureLoader, completion: { [weak self] in
                    if let defaultLibrary = self?.defaultLibrary, let renderDestination = self?.renderDestination {
                        module.loadPipeline(withMetalLibrary: defaultLibrary, renderDestination: renderDestination, textureBundle: textureBundle)
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

// MARK: - ARSessionDelegate

extension Renderer: ARSessionDelegate {
    
    public func session(_ session: ARSession, didFailWithError error: Error) {
        let newError = AKError.recoverableError(.arkitError(UnderlyingErrorInfo(underlyingError: error)))
        delegate?.renderer(self, didFailWithError: newError)
    }
    
    public func sessionWasInterrupted(_ session: ARSession) {
        delegate?.rendererWasInterrupted(self)
    }
    
    public func sessionInterruptionEnded(_ session: ARSession) {
        delegate?.rendererWasInterrupted(self)
    }
    
    /**
     This is called when a new frame has been updated.
     
     @param session The session being run.
     @param frame The frame that has been updated.
     */
//    func session(_ session: ARSession, didUpdate frame: ARFrame)
    
    
    /**
     This is called when new anchors are added to the session.
     
     @param session The session being run.
     @param anchors An array of added anchors.
     */
    public func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        anchors.forEach { anchor in
            if let planeAnchor = anchor as? ARPlaneAnchor {
                
                if let akAnchor = realAnchors.first(where: { k in
                    k.identifier == planeAnchor.identifier
                }) {
                    akAnchor.setARAnchor(planeAnchor)
                } else {
                    let newRealAnchor = RealSurfaceAnchor(at: WorldLocation(transform: planeAnchor.transform))
                    newRealAnchor.setARAnchor(planeAnchor)
                    newRealAnchor.setIdentifier(planeAnchor.identifier)
                    realAnchors.append(newRealAnchor)
                }
                
                //
                // Update the lowest surface plane
                //
                
                for index in 0..<realAnchors.count {
                    let realAnchor = realAnchors[index]
                    if let plane = realAnchor as? AKRealSurfaceAnchor, plane.orientation == .horizontal {
                        // Keep track of the lowest horizontal plane. This can be assumed to be the ground.
                        if lowestHorizPlaneAnchor != nil {
                            if plane.worldLocation.transform.columns.1.y < lowestHorizPlaneAnchor?.transform.columns.1.y ?? 0 {
                                lowestHorizPlaneAnchor = plane.arAnchor as? ARPlaneAnchor
                            }
                        } else {
                            lowestHorizPlaneAnchor = plane.arAnchor as? ARPlaneAnchor
                        }
                    }
                }
                
            } else if let environmentProbeAnchor = anchor as? AREnvironmentProbeAnchor {
                
                environmentProbeAnchors.append(environmentProbeAnchor)
                
                // The AREnvironmentProbeAnchor probes that are provided by ARKit onlt apply
                // to a certain range. This maps the AREnvironmentProbeAnchor's with the
                // identifiers of the AKAnchors that fall inside
                environmentAnchorsWithReatedAnchors = [:]
                environmentProbeAnchors.forEach { environmentAnchor in
                    let environmentPosition = simd_float3(environmentAnchor.transform.columns.3.x, environmentAnchor.transform.columns.3.y, environmentAnchor.transform.columns.3.z)
                    let cube = Cube(position: environmentPosition, extent: environmentAnchor.extent)
                    let anchorIDs: [UUID] = augmentedAnchors.compactMap{ normalAnchor in
                        let anchorPosition = simd_float3(normalAnchor.worldLocation.transform.columns.3.x, normalAnchor.worldLocation.transform.columns.3.y, normalAnchor.worldLocation.transform.columns.3.z)
                        if cube.contains(anchorPosition) {
                            return normalAnchor.identifier
                        } else {
                            return nil
                        }
                    }
                    environmentAnchorsWithReatedAnchors[environmentAnchor] = anchorIDs
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
            }
        }
    }
    
    
    /**
     This is called when anchors are updated.
     
     @param session The session being run.
     @param anchors An array of updated anchors.
     */
    public func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        anchors.forEach { anchor in
            if let planeAnchor = anchor as? ARPlaneAnchor {
                
                if let akAnchor = realAnchors.first(where: { k in
                    k.identifier == planeAnchor.identifier
                }) {
                    akAnchor.setARAnchor(planeAnchor)
                }
                
                //
                // Update the lowest surface plane
                //
                
                for index in 0..<realAnchors.count {
                    let realAnchor = realAnchors[index]
                    if let plane = realAnchor as? AKRealSurfaceAnchor, plane.orientation == .horizontal {
                        // Keep track of the lowest horizontal plane. This can be assumed to be the ground.
                        if lowestHorizPlaneAnchor != nil {
                            if plane.worldLocation.transform.columns.1.y < lowestHorizPlaneAnchor?.transform.columns.1.y ?? 0 {
                                lowestHorizPlaneAnchor = plane.arAnchor as? ARPlaneAnchor
                            }
                        } else {
                            lowestHorizPlaneAnchor = plane.arAnchor as? ARPlaneAnchor
                        }
                    }
                }
                
            } else if let environmentProbeAnchor = anchor as? AREnvironmentProbeAnchor {
                
                if let index = environmentProbeAnchors.firstIndex(of: environmentProbeAnchor) {
                    
                    environmentProbeAnchors.replaceSubrange(index..<(index + 1), with: [environmentProbeAnchor])
                    
                    // The AREnvironmentProbeAnchor probes that are provided by ARKit onlt apply
                    // to a certain range. This maps the AREnvironmentProbeAnchor's with the
                    // identifiers of the AKAnchors that fall inside
                    environmentAnchorsWithReatedAnchors = [:]
                    environmentProbeAnchors.forEach { environmentAnchor in
                        let environmentPosition = simd_float3(environmentAnchor.transform.columns.3.x, environmentAnchor.transform.columns.3.y, environmentAnchor.transform.columns.3.z)
                        let cube = Cube(position: environmentPosition, extent: environmentAnchor.extent)
                        let anchorIDs: [UUID] = augmentedAnchors.compactMap{ normalAnchor in
                            let anchorPosition = simd_float3(normalAnchor.worldLocation.transform.columns.3.x, normalAnchor.worldLocation.transform.columns.3.y, normalAnchor.worldLocation.transform.columns.3.z)
                            if cube.contains(anchorPosition) {
                                return normalAnchor.identifier
                            } else {
                                return nil
                            }
                        }
                        environmentAnchorsWithReatedAnchors[environmentAnchor] = anchorIDs
                    }
                    
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
            }
        }
    }
    
    
    /**
     This is called when anchors are removed from the session.
     
     @param session The session being run.
     @param anchors An array of removed anchors.
     */
//    public func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {}
    
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
    var asset: MDLAsset
    var identifier: UUID?
    var effects: [AnyEffect<Any>]?
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
    
    public func setIdentifier(_ identifier: UUID) {
        self.identifier = identifier
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

// MARK: - Cube
fileprivate struct Cube {
    var position: simd_float3
    var extent: simd_float3
    func contains(_ point: simd_float3) -> Bool {
        let minX = position.x - extent.x
        let minY = position.y - extent.y
        let minZ = position.z - extent.z
        let maxX = position.x + extent.x
        let maxY = position.y + extent.y
        let maxZ = position.z + extent.z
        
        return ( point.x > minX && point.y > minY && point.z > minZ ) && ( point.x < maxX && point.y < maxY && point.z < maxZ )
    }
}
