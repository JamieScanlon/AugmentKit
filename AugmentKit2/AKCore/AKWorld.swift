//
//  AKWorld.swift
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
//
// A single class to hold all world state. It manades it's own Metal Device, Renderer,
// and ARSession. Initialize it with a MetalKit View which this class will render into.
// There should only be one of these per AR View.
//

import Foundation
import ARKit
import Metal
import MetalKit
import CoreLocation

struct AKWorldConfiguration {
    var usesLocation = true
}

class AKWorld: NSObject {
    
    let session: ARSession
    let renderer: Renderer
    let device: MTLDevice
    let renderDestination: MTKView
    
    init(renderDestination: MTKView, configuration: AKWorldConfiguration = AKWorldConfiguration()) {
        
        self.renderDestination = renderDestination
        self.session = ARSession()
        guard let aDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        self.device = aDevice
        self.renderer = Renderer(session: self.session, metalDevice: self.device, renderDestination: renderDestination)
        super.init()
        
        // Self is fully initialized, now do additional setup
        
        self.renderDestination.device = self.device
        self.renderer.drawRectResized(size: renderDestination.bounds.size)
        self.renderer.meshProvider = self
        self.session.delegate = self
        self.renderDestination.delegate = self
        
        if configuration.usesLocation {
            WorldLocationManager.shared.startServices()
            NotificationCenter.default.addObserver(forName: .locationDelegateUpdateLocationNotification, object: self, queue: nil, using: { [weak self] notification in
                if let location = notification.userInfo?["location"] as? CLLocation {
                    self?.associateLocationWithCameraPosition(location)
                }
            })
        }
        
    }
    
    func setAnchor(_ anchor: AKAnchor, forAnchorType type: String) {
        switch type {
        case AKObject.type:
            anchorAsset = anchor.mdlAsset
        default:
            return
        }
    }
    
    func begin() {
        renderer.initialize()
        renderer.reset()
    }
    
    func add(anchor: AKAugmentedAnchor) {
        
        // Add a new anchor to the session
        let anchor = ARAnchor(transform: anchor.transform)
        session.add(anchor: anchor)
        
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Private

    fileprivate var anchorAsset: MDLAsset?
    
    private func associateLocationWithCameraPosition(_ location: CLLocation) {
        // TODO: Implement
    }
    
}

// MARK: - MTKViewDelegate

extension AKWorld: MTKViewDelegate {
    
    // Called whenever view changes orientation or layout is changed
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        renderer.drawRectResized(size: size)
    }
    
    // Called whenever the view needs to render
    func draw(in view: MTKView) {
        renderer.update()
    }
    
}

// MARK: - ARSessionDelegate

extension AKWorld: ARSessionDelegate {
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        
    }
    
}

// MARK: - MeshProvider

extension AKWorld: MeshProvider {
    
    func loadMesh(forType type: MeshType, completion: (MDLAsset?) -> Void) {
        
        switch type {
        case .anchor:
            if let anchorAsset = anchorAsset {
                completion(anchorAsset)
            } else {
                fatalError("Failed to find an anchor model.")
            }
        case .horizPlane:
            // Use the default guide
            completion(nil)
        case .vertPlane:
            completion(nil)
        }
        
        
        
    }
}

// MARK: - RenderDestinationProvider

extension MTKView : RenderDestinationProvider {
    
}
