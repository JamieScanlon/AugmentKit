//
//  ViewController.swift
//  AugmentKit2
//
//  Created by Jamie Scanlon on 7/3/17.
//  Copyright © 2017 TenthLetterMade. All rights reserved.
//

import UIKit
import Metal
import MetalKit
import ARKit
import SceneKit.ModelIO

class ViewController: UIViewController {
    
    var session: ARSession?
    var renderer: Renderer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegate
        let mySession = ARSession()
        mySession.delegate = self
        
        // Set the view to use the default device
        if let view = self.view as? MTKView {
            
            guard let device = MTLCreateSystemDefaultDevice() else {
                print("Metal is not supported on this device")
                return
            }
            view.device = device
            view.backgroundColor = UIColor.clear
            view.delegate = self
            
            // Configure the renderer to draw to the view
            renderer = Renderer(session: mySession, metalDevice: device, renderDestination: view, meshProvider: self)
            renderer?.drawRectResized(size: view.bounds.size)
            
            // Debugging
            renderer?.showGuides = true
            
        }
        
        session = mySession
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(ViewController.handleTap(gestureRecognize:)))
        view.addGestureRecognizer(tapGesture)
        
        WorldLocationManager.shared.startServices()
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        renderer?.run()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        renderer?.pause()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }
    
    @objc
    private func handleTap(gestureRecognize: UITapGestureRecognizer) {
        
        guard let session = session else {
            return
        }
        
        // Create anchor using the camera's current position
        if let currentFrame = session.currentFrame {
            
            // Create a transform with a translation of 0.2 meters in front of the camera
            var translation = matrix_identity_float4x4
            translation.columns.3.z = -0.2
            let transform = simd_mul(currentFrame.camera.transform, translation)
            
            // Add a new anchor to the session
            let anchor = ARAnchor(transform: transform)
            session.add(anchor: anchor)
        }
        
    }
    
}

// MARK: - MTKViewDelegate

extension ViewController: MTKViewDelegate {
    
    // Called whenever view changes orientation or layout is changed
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        renderer?.drawRectResized(size: size)
    }
    
    // Called whenever the view needs to render
    func draw(in view: MTKView) {
        renderer?.update()
    }
    
}

// MARK: - ARSessionDelegate

extension ViewController: ARSessionDelegate {
    
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

extension ViewController: MeshProvider {
    
    func loadMesh(forType type: MeshType, metalAllocator: MTKMeshBufferAllocator, completion: (MDLAsset?) -> Void) {
        
        switch type {
        case .anchor:
            guard let scene = SCNScene(named: "Pin.scn") else {
                fatalError("Failed to find model file.")
            }
            let asset = MDLAsset(scnScene: scene, bufferAllocator: metalAllocator)
            completion(asset)
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
