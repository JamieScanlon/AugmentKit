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
    var anchorModel: AKModel?
    
    @IBOutlet var debugInfoAnchorCounts: UILabel?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view to use the default device
        if let view = self.view as? MTKView {
            
            view.backgroundColor = UIColor.clear
            
            let worldConfiguration = AKWorldConfiguration(usesLocation: true)
            let myWorld = AKWorld(renderDestination: view, configuration: worldConfiguration)
            
            // Debugging
            myWorld.renderer.showGuides = false // Change to `true` to enable rendering of tracking points and horizontal planes.
            myWorld.renderer.logger = self
            
            // Set the initial orientation
            myWorld.renderer.orientation = UIApplication.shared.statusBarOrientation
            
            // Begin
            myWorld.begin()
            
            world = myWorld
            
            loadAnchorModel()
            
            // Add a user tracking anchor.
            if let asset = MDLAssetTools.assetFromImage(withName: "compass_512.png") {
                let myUserTrackerModel = AKMDLAssetModel(asset: asset)
                // Position it 3 meters down from the camera
                let offsetTransform = matrix_identity_float4x4.translate(x: 0, y: -3, z: 0)
                let userTracker = AKUserTracker(withModel: myUserTrackerModel, withUserRelativeTransform: offsetTransform)
                userTracker.position.heading = AKWorldHeading(withWorld: myWorld, worldHeadingType: .north)
                myWorld.add(tracker: userTracker)
            }
            
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
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        
        super.viewWillTransition(to: size, with: coordinator)
        
        world?.renderer.drawRectResized(size: size)
        coordinator.animate(alongsideTransition: nil) { [weak self](context) in
            self?.world?.renderer.orientation = UIApplication.shared.statusBarOrientation
        }
        
    }
    
    @objc
    private func handleTap(gestureRecognize: UITapGestureRecognizer) {
        
        guard let anchorModel = anchorModel else {
            return
        }
        
        guard let currentWorldLocation = world?.currentWorldLocation else {
            return
        }
        
        // Create a new anchor at the current locaiton
        let newObject = AKObject(withAKModel: anchorModel, at: currentWorldLocation)
        world?.add(anchor: newObject)
        
    }
    
    // MARK: - Private
    
    fileprivate func loadAnchorModel() {
        
        let url = URL(string: "https://s3-us-west-2.amazonaws.com/com.tenthlettermade.public/PinAKModelArchive.zip")!
        
        //
        // Download a zipped Model
        //
        
        let remoteModel = AKRemoteArchivedModel(remoteURL: url)
        remoteModel.compressor = Compressor()
        anchorModel = remoteModel
        
        
        //
        // Get a Model from the app bundle
        //
        
//        // Setup the model that will be used for AKObject anchors
//        guard let asset = AKSceneKitUtils.mdlAssetFromScene(named: "Pin.scn", world: myWorld) else {
//            print("ERROR: Could not load the SceneKit model")
//            return
//        }
//
//        anchorModel = AKMDLAssetModel(asset: asset)
        
    }
    
}

// MARK: - RenderDebugLogger

extension ViewController: RenderDebugLogger {
    
    func updatedAnchors(count: Int, numAnchors: Int, numPlanes: Int, numTrackingPoints: Int) {
        debugInfoAnchorCounts?.text = "Total Anchor Count: \(count) - User: \(numAnchors), planes: \(numPlanes), points: \(numTrackingPoints)"
    }
}

// MARK: - Model Compressor

class Compressor: ModelCompressor {
    
    func zipModel(withFileURLs fileURLs: [URL], toDestinationFilePath destinationFilePath: String) -> URL? {
        
        guard let zipFileURL = try? Zip.quickZipFiles(fileURLs, fileName: destinationFilePath) else {
            print("SerializeUtil: Serious Error. Could not archive the model file at \(fileURLs.first?.path ?? "nil")")
            return nil
        }
        
        return zipFileURL
        
    }
    
    func unzipModel(withFileURL filePath: URL) -> URL? {
        do {
            let unzipDirectory = try Zip.quickUnzipFile(filePath)
            return unzipDirectory
        } catch {
            print(error.localizedDescription)
            return nil
        }
    }
}
