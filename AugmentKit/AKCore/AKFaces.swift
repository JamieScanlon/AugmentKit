//
//  AKFaces.swift
//  AugmentKit
//
//  MIT License
//
//  Copyright (c) 2020 JamieScanlon
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
import MetalKit
import ARKit

// MARK: - AKFacesConfiguration

/**
 A configuration object used to initialize the AR face tracking session.
 */
public struct AKFacesConfiguration {
    
    public init() {
    }
    
}

// MARK: - AKFacesSessionStatus

/**
 A struct representing the state of the face tracking session at an instance in time.
 */
public struct AKFacesSessionStatus {
    
    /**
     Represents the current world initialization and ready state.
     */
    public enum Status {
        case notInitialized
        case initializing(ARKitInitializationPhase, FacesInitializationPhase)
        case ready
        case interupted
        case error
    }
    
    /**
     Represents the initialization phase when the world is initializing
     */
    public enum ARKitInitializationPhase {
        case notStarted
        case initializingARKit
        case ready
    }
    
    /**
     Represents the state of surface detection.
     */
    public enum FacesInitializationPhase {
        case notStarted
        case findingFaces
        case ready
    }
    
    /**
     Represents the quality of tracking data
     */
    public enum Quality {
        case notAvailable
        case limited(ARCamera.TrackingState.Reason)
        case normal
    }
    
    /**
     The current `AKWorldStatus.Status`.
     */
    public var status = Status.notInitialized
    
    /**
     The current `AKWorldStatus.Quality`.
     */
    public var quality = Quality.notAvailable
    
    /**
     An array of `AKError` objects that have been reported so far.
     */
    public var errors = [AKError]()
    
    /**
     The point in time that this `AKWorldStatus` object describes
     */
    public var timestamp: Date
    
    /**
     Initialize a new `AKWorldStatus` object for a point in time
     - Parameters:
     - timestamp: The point in time that this `AKWorldStatus` object describes
     */
    public init(timestamp: Date) {
        self.timestamp = timestamp
    }
    
    /**
     Filters the `errors` array and returns only the serious errors.
     */
    public func getSeriousErrors() -> [AKError] {
        return errors.filter(){
            switch $0 {
            case .seriousError(_):
                return true
            default:
                return false
            }
        }
    }
    
    /**
     Filters the `errors` array and returns only the warnings and recoverable errors.
     */
    public func getRecoverableErrorsAndWarnings() -> [AKError] {
        return errors.filter(){
            switch $0 {
            case .recoverableError(_):
                return true
            case .warning(_):
                return true
            default:
                return false
            }
        }
    }
    
}

// MARK: - AKFacesMonitor

/**
 An object that adheres to the `AKFacesMonitor` protocol can receive updates when the face tracking session state changes.
 */
public protocol AKFacesMonitor {
    /**
     Called when the face tracking session status changes
     - Parameters:
     - session: The new `AKFacesSessionStatus` object
     */
    func update(sessionStatus: AKFacesSessionStatus)
    /**
     Called when the render statistics changes
     - Parameters:
     - renderStats: The new `RenderStats` object
     */
    func update(renderStats: RenderStats)
}

// MARK: - AKFaces

/**
 A single class to manage AR face tracking. It manages it's own Metal Device, Renderer, and ARSession. Initialize it with a MetalKit View which this class will render into. There should only be one of these per AR View.
 */
open class AKFaces: NSObject {

    // MARK: Properties
    
    /**
     The `ARSession` object asociatted with the `AKFaces` object.
     */
    public let session: ARSession
    /**
     The `Renderer` object asociatted with the `AKFaces` object.
     */
    public let renderer: Renderer
    /**
     The `MTLDevice` object asociatted with the `AKFaces` object.
     */
    public let device: MTLDevice
    /**
     The `MTKView` to which the AR world will be rendered.
     */
    public let renderDestination: MTKView
    
    /**
     The current `AKWorldStatus`
     */
    public private(set) var sessionStatus: AKFacesSessionStatus {
        didSet {
            monitor?.update(sessionStatus: sessionStatus)
        }
    }
    
    /**
     If provided, the `monitor` will be called when `sessionStatus` or `renderStatus` changes. The `monitor` can be used to provide feedback to the user about the state of the AR face tracking session and the state of the render pipeline.
     */
    public var monitor: AKFacesMonitor?
    
    public init(renderDestination: MTKView, configuration: AKFacesConfiguration = AKFacesConfiguration(), textureBundle: Bundle? = nil, worldTrackingEnabled: Bool = false) {
        
        let bundle: Bundle = {
            if let textureBundle = textureBundle {
                return textureBundle
            } else {
                return Bundle.main
            }
        }()
        self.renderDestination = renderDestination
        self.session = ARSession()
        guard let aDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        self.device = aDevice
        self.renderer = Renderer(session: self.session, metalDevice: self.device, renderDestination: renderDestination, textureBundle: bundle, sessionType: worldTrackingEnabled ? .faceTrackingWithWorldTracking : .faceTracking)
        self.sessionStatus = AKFacesSessionStatus(timestamp: Date())
        super.init()
        
        // Self is fully initialized, now do additional setup
        
        NotificationCenter.default.addObserver(self, selector: #selector(AKFaces.handleRendererStateChanged(notif:)), name: .rendererStateChanged, object: self.renderer)
        NotificationCenter.default.addObserver(self, selector: #selector(AKFaces.handleFaceDetectionStateChanged(notif:)), name: .surfaceDetectionStateChanged, object: self.renderer)
        NotificationCenter.default.addObserver(self, selector: #selector(AKFaces.handleAbortedDueToErrors(notif:)), name: .abortedDueToErrors, object: self.renderer)
        
        self.renderDestination.device = self.device
        self.renderer.monitor = self
        self.renderer.drawRectResized(size: renderDestination.bounds.size)
        self.renderer.delegate = self
        self.renderDestination.delegate = self
        
        self.configuration = configuration
    }
    
    /**
     Starts AR tracking and rendering.
     */
    public func begin() {
        renderer.run()
    }
    
    /**
     Pauses AR tracking and rendering.
     */
    public func pause() {
        renderer.pause()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    /**
     Initializes AR tracking and rendering.
     */
    public func initialize() {
        var newStatus = AKFacesSessionStatus(timestamp: Date())
        newStatus.status = .initializing(.initializingARKit, .notStarted)
        sessionStatus = newStatus
        renderer.initialize()
    }
    
    // MARK: Adding and removing anchors
    
    // MARK: - Private
    
    fileprivate var configuration: AKFacesConfiguration? {
        didSet {
            //
        }
    }
    
    @objc private func handleRendererStateChanged(notif: NSNotification) {
        
        guard notif.name == .rendererStateChanged else {
            return
        }
        
        guard let state = notif.userInfo?["newState"] as? Renderer.RendererState else {
            return
        }
        
        switch state {
        case .uninitialized:
            let newStatus = AKFacesSessionStatus(timestamp: Date())
            sessionStatus = newStatus
        case .initialized:
            renderer.reset()
        case .running:
            var newStatus = AKFacesSessionStatus(timestamp: Date())
            newStatus.status = .initializing(.ready, .findingFaces)
            sessionStatus = newStatus
        case .paused:
            break
        }
    }
    
    @objc private func handleFaceDetectionStateChanged(notif: NSNotification) {
        
        guard notif.name == .faceDetectionStateChanged else {
            return
        }
        
        guard let state = notif.userInfo?["newState"] as? Renderer.FaceDetectionState else {
            return
        }
        
        switch state {
        case .noneDetected:
            var newStatus = AKFacesSessionStatus(timestamp: Date())
            let arKitPhase: AKFacesSessionStatus.ARKitInitializationPhase = {
                switch renderer.state {
                case .uninitialized:
                    return .notStarted
                case .initialized:
                    return .initializingARKit
                case .running:
                    return .ready
                case .paused:
                    return .ready
                }
            }()
            newStatus.status = .initializing(arKitPhase, .findingFaces)
            sessionStatus = newStatus
        case .detected:
            var newStatus = AKFacesSessionStatus(timestamp: Date())
            newStatus.status = .initializing(.ready, .ready)
            sessionStatus = newStatus
        }
    }
    
    @objc private func handleAbortedDueToErrors(notif: NSNotification) {
        
        guard notif.name == .abortedDueToErrors else {
            return
        }
        
        guard let errors = notif.userInfo?["errors"] as? [AKError] else {
            return
        }
        
        var newStatus = AKFacesSessionStatus(timestamp: Date())
        newStatus.errors.append(contentsOf: errors)
        newStatus.status = .error
        sessionStatus = newStatus
        
    }
}

// MARK: - MTKViewDelegate

extension AKFaces: MTKViewDelegate {
    
    // Called whenever view changes orientation or layout is changed
    /// :nodoc:
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        renderer.drawRectResized(size: size)
    }
    
    // Called whenever the view needs to render
    /// :nodoc:
    public func draw(in view: MTKView) {
        renderer.update()
    }
    
}

// MARK: - ARSessionDelegate

extension AKFaces: RenderDelegate {
    
    /// :nodoc:
    public func renderer(_ renderer: Renderer, didFailWithError error: AKError) {
        var newStatus = AKFacesSessionStatus(timestamp: Date())
        var errors = sessionStatus.errors
        errors.append(error)
        newStatus.errors = errors
        if newStatus.getSeriousErrors().count > 0 {
            newStatus.status = .error
        } else {
            newStatus.status = sessionStatus.status
        }
        sessionStatus = newStatus
    }
    
    /// :nodoc:
    public func rendererWasInterrupted(_ renderer: Renderer) {
        var newStatus = AKFacesSessionStatus(timestamp: Date())
        newStatus.status = .interupted
        newStatus.errors = sessionStatus.errors
        sessionStatus = newStatus
    }
    
    /// :nodoc:
    public func rendererInterruptionEnded(_ renderer: Renderer) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        var newStatus = AKFacesSessionStatus(timestamp: Date())
        newStatus.status = .interupted
        newStatus.errors = sessionStatus.errors
        sessionStatus = newStatus
    }
}

// MARK: - RenderMonitor

extension AKFaces: RenderMonitor {
    
    /// :nodoc:
    public func update(renderStats: RenderStats) {
        monitor?.update(renderStats: renderStats)
    }
    
    /// :nodoc:
    public func update(renderErrors: [AKError]) {
        var newStatus = AKFacesSessionStatus(timestamp: Date())
        newStatus.errors = renderErrors
        if newStatus.getSeriousErrors().count > 0 {
            newStatus.status = .error
        } else {
            newStatus.status = sessionStatus.status
        }
        sessionStatus = newStatus
    }
}
