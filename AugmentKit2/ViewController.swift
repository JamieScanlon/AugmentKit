//
//  ViewController.swift
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

import UIKit
import Metal
import MetalKit
import ARKit
import AugmentKit

class ViewController: UIViewController {
    
    var world: AKWorld?
    var anchorAsset: MDLAsset?
    
    @IBOutlet var debugInfoAnchorCounts: UILabel?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view to use the default device
        if let view = self.view as? MTKView {
            
            view.backgroundColor = UIColor.clear
            
            let worldConfiguration = AKWorldConfiguration(usesLocation: false) // Turn locaion off for now because it's not fully implemented yet.
            let myWorld = AKWorld(renderDestination: view, configuration: worldConfiguration)
            
            // Debugging
            myWorld.renderer.showGuides = true
            myWorld.renderer.logger = self
            
            // Setup the model that will be used for AKObject anchors
            guard let asset = AKObject.mdlAssetFromScene(named: "Pin.scn", world: myWorld) else {
                print("ERROR: Could not load the SceneKit model")
                return
            }
            let anchor = AKObject(withMDLAsset: asset, at: AKWorldLocation())
            myWorld.setAnchor(anchor, forAnchorType: AKObject.type) // TODO: Stil working on removing the need for this step.
            
            // Begin
            myWorld.begin()
            
            world = myWorld
            anchorAsset = asset
            
        }
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(ViewController.handleTap(gestureRecognize:)))
        view.addGestureRecognizer(tapGesture)
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        world?.renderer.run()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        world?.renderer.pause()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }
    
    @objc
    private func handleTap(gestureRecognize: UITapGestureRecognizer) {
        
        guard let anchorAsset = anchorAsset else {
            return
        }
        
        guard let currentWorldLocation = world?.currentWorldLocation else {
            return
        }
        
        // Create a new anchor at the current locaiton
        let newObject = AKObject(withMDLAsset: anchorAsset, at: currentWorldLocation)
        world?.add(anchor: newObject)
        
    }
    
}

// MARK: - RenderDebugLogger

extension ViewController: RenderDebugLogger {
    
    func updatedAnchors(count: Int, numAnchors: Int, numPlanes: Int) {
        debugInfoAnchorCounts?.text = "Total Anchor Count: \(count) - User: \(numAnchors), planes: \(numPlanes)"
    }
}
