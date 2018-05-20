//
//  ViewController.swift
//  AugmentKit - Example
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

import UIKit
import Metal
import MetalKit
import ARKit
import AugmentKit

class ViewController: UIViewController {
    
    var world: AKWorld?
    var pinModel: AKModel?
    var shipModel: AKModel?
    
    @IBOutlet var debugInfoAnchorCounts: UILabel?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view to use the default device
        if let view = self.view as? MTKView {
            
            view.backgroundColor = UIColor.clear
            
            let worldConfiguration = AKWorldConfiguration(usesLocation: true)
            let myWorld = AKWorld(renderDestination: view, configuration: worldConfiguration)
            
            // Debugging
            myWorld.renderer.showGuides = false // Change to `true` to enable rendering of tracking points and surface planes.
            myWorld.monitor = self
            
            // Set the initial orientation
            myWorld.renderer.orientation = UIApplication.shared.statusBarOrientation
            
            // Begin
            myWorld.begin()
            
            world = myWorld
            
            loadAnchorModels()
            
            // Add a user tracking anchor.
            if let asset = MDLAssetTools.assetFromImage(withName: "compass_512.png") {
                let myUserTrackerModel = AKAnchorAssetModel(asset: asset)
                // Position it 3 meters down from the camera
                let offsetTransform = matrix_identity_float4x4.translate(x: 0, y: -3, z: 0)
                let userTracker = UserTracker(withModel: myUserTrackerModel, withUserRelativeTransform: offsetTransform)
                userTracker.position.heading = WorldHeading(withWorld: myWorld, worldHeadingType: .north)
                myWorld.add(tracker: userTracker)
            }
            
            // Add a Gaze Target
            // Make it about 20cm square.
            if let asset = MDLAssetTools.assetFromImage(withName: "Gaze_Target.png", extension: "", scale: 0.2) {
                let myGazeTargetModel = AKAnchorAssetModel(asset: asset)
                let gazeTarget = GazeTarget(withModel: myGazeTargetModel, withUserRelativeTransform: matrix_identity_float4x4)
                myWorld.add(gazeTarget: gazeTarget)
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
        
        guard let world = world else {
            return
        }
        
        guard let currentWorldLocation = world.currentWorldLocation else {
            return
        }
        
        // Example:
        // Create a new anchor at the current locaiton
        guard let newObject = getRandomAnchor() else {
            return
        }
        world.add(anchor: newObject)
        
        // Example:
        // Create a square path
//        guard let location1 = world.worldLocationFromCurrentLocation(withMetersEast: 1, metersUp: 0, metersSouth: 0) else {
//            return
//        }
//
//        guard let location2 = world.worldLocationFromCurrentLocation(withMetersEast: 1, metersUp: 1, metersSouth: 0) else {
//            return
//        }
//
//        guard let location3 = world.worldLocationFromCurrentLocation(withMetersEast: 0, metersUp: 1, metersSouth: 0) else {
//            return
//        }
//
//        let path = PathAnchor(withWorldLocaitons: [currentWorldLocation, location1, location2, location3, currentWorldLocation])
//        world.add(akPath: path)
        
        
        // Example:
        // Create a path around the Apple Park building
//        guard let location1 = world.worldLocation(withLatitude: 37.3335, longitude: -122.0106, elevation: currentWorldLocation.elevation) else {
//            return
//        }
//
//        guard let location2 = world.worldLocation(withLatitude: 37.3349, longitude: -122.0113, elevation: currentWorldLocation.elevation) else {
//            return
//        }
//
//        guard let location3 = world.worldLocation(withLatitude: 37.3362, longitude: -122.0106, elevation: currentWorldLocation.elevation) else {
//            return
//        }
//
//        guard let location4 = world.worldLocation(withLatitude: 37.3367, longitude: -122.0090, elevation: currentWorldLocation.elevation) else {
//            return
//        }
//
//        guard let location5 = world.worldLocation(withLatitude: 37.3365, longitude: -122.0079, elevation: currentWorldLocation.elevation) else {
//            return
//        }
//
//        guard let location6 = world.worldLocation(withLatitude: 37.3358, longitude: -122.0070, elevation: currentWorldLocation.elevation) else {
//            return
//        }
//
//        guard let location7 = world.worldLocation(withLatitude: 37.3348, longitude: -122.0067, elevation: currentWorldLocation.elevation) else {
//            return
//        }
//
//        guard let location8 = world.worldLocation(withLatitude: 37.3336, longitude: -122.0074, elevation: currentWorldLocation.elevation) else {
//            return
//        }
//
//        guard let location9 = world.worldLocation(withLatitude: 37.3330, longitude: -122.0090, elevation: currentWorldLocation.elevation) else {
//            return
//        }
//
//        let path = PathAnchor(withWorldLocaitons: [location1, location2, location3, location4, location5, location6, location7, location8, location9, location1])
//        world.add(akPath: path)

    }
    
    // MARK: - Private
    
    fileprivate func loadAnchorModels() {
        
        //
        // Download a zipped Model
        //
        
//        let url = URL(string: "https://s3-us-west-2.amazonaws.com/com.tenthlettermade.public/PinAKModelArchive.zip")!
//        let remoteModel = AKRemoteArchivedModel(remoteURL: url)
//        remoteModel.compressor = Compressor()
//        pinModel = remoteModel
        
        
        //
        // Get a Model from the app bundle
        //
        
        // Setup the model that will be used for AugmentedAnchor anchors
        guard let world = world else {
            print("ERROR: The AKWorld has not been initialized")
            return
        }
        
        guard let pinAsset = AKSceneKitUtils.mdlAssetFromScene(named: "Pin.scn", world: world) else {
            print("ERROR: Could not load the SceneKit model")
            return
        }
        
        guard let shipAsset = AKSceneKitUtils.mdlAssetFromScene(named: "ship.scn", world: world) else {
            print("ERROR: Could not load the SceneKit model")
            return
        }

        pinModel = AKMDLAssetModel(asset: pinAsset, vertexDescriptor: AKMDLAssetModel.newAnchorVertexDescriptor())
        shipModel = AKMDLAssetModel(asset: shipAsset, vertexDescriptor: AKMDLAssetModel.newAnchorVertexDescriptor())
        
    }
    
    fileprivate func getRandomAnchor() -> AKAugmentedAnchor? {
        
        
        let random = arc4random_uniform(2)
        
        let model: AKModel? = {
            if random == 0 {
                return pinModel
            } else if random == 1 {
                return shipModel
            } else {
                return nil
            }
        }()
        
        guard let anchorModel = model else {
            return nil
        }
        
        guard let world = world else {
            return nil
        }
        
        guard let currentWorldLocation = world.currentWorldLocation else {
            return nil
        }
        
        let anchorLocation: AKWorldLocation = {
            if random == 0 {
                return GroundFixedWorldLocation(worldLocation: currentWorldLocation, world: world)
            } else {
                return currentWorldLocation
            }
        }()
        
        return AugmentedAnchor(withAKModel: anchorModel, at: anchorLocation)
        
    }
    
}

// MARK: - RenderMonitor

extension ViewController: AKWorldMonitor {
    
    func update(renderStats: RenderStats) {
        debugInfoAnchorCounts?.text = "ARKit Anchor Count: \(renderStats.arKitAnchorCount)\nAugmentKit Anchors: \(renderStats.numAnchors)\nplanes: \(renderStats.numPlanes)\ntracking points: \(renderStats.numTrackingPoints)\ntrackers: \(renderStats.numTrackers)\ntargets: \(renderStats.numTargets)\npath segments \(renderStats.numPathSegments)"
    }
    
    func update(worldStatus: AKWorldStatus) {
        // TODO: Implement
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
