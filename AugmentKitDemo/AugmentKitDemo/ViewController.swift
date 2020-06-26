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
import ModelIO
import ARKit
import AugmentKit

class ViewController: UIViewController {
    
    var world: AKWorld?
    var usdzAsset: MDLAsset?
    var rkAsset: MDLAsset?
    var pinAsset: MDLAsset?
    var shipAsset: MDLAsset?
    var maxAsset: MDLAsset?
    var demoVC: UIViewController?
    
    @IBOutlet var infoView: UIView?
    @IBOutlet var debugInfoAnchorCounts: UILabel?
    @IBOutlet var errorInfo: UILabel?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view to use the default device
        if let view = self.view as? MTKView {
            
            view.backgroundColor = UIColor.clear
            
            let worldConfiguration = AKWorldConfiguration(usesLocation: true)
            let myWorld = AKWorld(renderDestination: view, configuration: worldConfiguration)
            
            // Debugging
            myWorld.monitor = self
            
            // Set the initial orientation
            myWorld.renderer.orientation = UIApplication.shared.statusBarOrientation
            
            // Initialize
            myWorld.initialize()
            
            world = myWorld
            
            loadAnchorModels()
            
            // Add a user tracking anchor.
            if let asset = MDLAssetTools.assetFromImage(inBundle: Bundle.main, withName: "compass_512.png") {
                // Position it 3 meters down from the camera
                let offsetTransform = matrix_identity_float4x4.translate(x: 0, y: -3, z: 0)
                let userTracker = UserTracker(withModelAsset: asset, withUserRelativeTransform: offsetTransform)
                userTracker.position.heading = WorldHeading(withWorld: myWorld, worldHeadingType: .north(0))
                myWorld.add(tracker: userTracker)
            }
            
            // Add a Gaze Target
            // Make it about 20cm square.
            // Add an effect to make it fade in and out
            if let asset = MDLAssetTools.assetFromImage(inBundle: Bundle.main, withName: "Gaze_Target.png", extension: "", scale: 0.2) {
                let gazeTarget = GazeTarget(withModelAsset: asset, withUserRelativeTransform: matrix_identity_float4x4)
                let alphaEffect = PulsingAlphaEffect(minValue: 0.2, maxValue: 1)
                gazeTarget.effects = [AnyEffect(alphaEffect)]
                myWorld.add(gazeTarget: gazeTarget)
            }
            
        }
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(ViewController.handleTap(gestureRecognize:)))
        view.addGestureRecognizer(tapGesture)
        
        infoView?.isHidden = true
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        world?.begin()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        world?.pause()
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
    
    // MARK: - Private
    
    @objc
    fileprivate func handleTap(gestureRecognize: UITapGestureRecognizer) {
        
        guard let world = world else {
            return
        }
        
        guard let currentWorldLocation = world.currentWorldLocation else {
            return
        }
        
        guard let gazeLocation = world.currentGazeLocation else {
            return
        }
        
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
//        let path = PathAnchor(withWorldLocaitons: [currentWorldLocation, location1, location2, location3, currentWorldLocation], color: UIColor(red: 38/255, green: 167/255, blue: 186/255, alpha: 0.9))
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
        
        // Example:
        // Render a UIView as a surface in the AR World 2 meters in from of the current location. Use an AlwaysFacingMeHeading
        // Heading to follow me as I walk around.
        //        let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 300, height: 500))
        //        textView.font = UIFont(descriptor: .preferredFontDescriptor(withTextStyle: .body), size: 14)
        //        textView.textColor = UIColor(red: 200/255, green: 109/255, blue: 215/255, alpha: 1)
        //        textView.text = """
        //A way out west there was a fella,
        //fella I want to tell you about, fella
        //by the name of Jeff Lebowski. At
        //least, that was the handle his lovin'
        //parents gave him, but he never had
        //much use for it himself. This
        //Lebowski, he called himself the Dude.
        //Now, Dude, that's a name no one would
        //self-apply where I come from. But
        //then, there was a lot about the Dude
        //that didn't make a whole lot of sense
        //to me. And a lot about where he
        //lived, like- wise. But then again,
        //maybe that's why I found the place
        //s'durned innarestin'...
        //"""
        //        textView.backgroundColor = .clear
//                let location = world.worldLocationWithDistanceFromMe(metersAbove: 0, metersInFront: 2)!
//                let heading = AlwaysFacingMeHeading(withWorldLocaiton: location)
//                let viewSurface = AugmentedUIViewSurface(withView: textView, at: location, heading: heading)
//                world.add(anchor: viewSurface)
        
        
        // Example:
        // Render a UINavigationViewController stack as a surface in the AR World 2 meters in from of the current location. Use an AlwaysFacingMeHeading
        // This is still a work in progress. In order for mapkit to render, it must be in the view heirarchy but I still haven't found a great way to render with animations (Core Animation) because it automatically turns off animations if it is not on screen.
//        if demoVC == nil {
//            demoVC = storyboard?.instantiateViewController(withIdentifier: "AutoNavigationController")
//            demoVC!.view.frame = CGRect(x: 0, y: -view.bounds.height, width: view.bounds.width, height: view.bounds.height)
//            view.addSubview(demoVC!.view)
//        }
//        let location = world.worldLocationWithDistanceFromMe(metersAbove: 0, metersInFront: 2)!
//        let heading = AlwaysFacingMeHeading(withWorldLocaiton: location)
//        if let demoView = demoVC?.view {
//            let viewSurface = AugmentedUIViewSurface(withView: demoView, at: location, heading: heading)
//            world.add(anchor: viewSurface)
//        }
        
        
    }
    
    @IBAction func exportButtonClicked(_ sender: UIButton) {
        guard let world = world else {
            return
        }
        world.getArchivedWorldMap() { (fileURL, error) in
            if let fileURL = fileURL {
                let activityItems = [fileURL]
                let activityViewController = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
                DispatchQueue.main.async { [weak self] in
                    self?.present(activityViewController, animated: true, completion: nil)
                }
            }
        }
    }
    
    @IBAction fileprivate func markerTapped(_ sender: UIButton) {
        
        // Create a new anchor at the current locaiton
        
        guard let anchorModel = pinAsset else {
            return
        }
        
        guard let world = world else {
            return
        }
        
        guard let location = world.currentGazeLocation else {
            return
        }
        
        let anchorLocation = GroundFixedWorldLocation(worldLocation: location, world: world)
        let newObject = AugmentedAnchor(withModelAsset: anchorModel, at: anchorLocation)
        newObject.shaderPreference = .blinn
        world.add(anchor: newObject)
        
    }
    
    @IBAction fileprivate func usdzTapped(_ sender: UIButton) {
        
        // Create a new anchor at the current locaiton
        
        guard let anchorModel = usdzAsset else {
            return
        }
        
        guard let world = world else {
            return
        }
        
        guard let location = world.currentGazeLocation else {
            return
        }
        
//        let anchorLocation = GroundFixedWorldLocation(worldLocation: location, world: world)
        let newObject = AugmentedAnchor(withModelAsset: anchorModel, at: location)
        let scaleEffect = ConstantScaleEffect(scaleValue: 0.01)
        newObject.effects = [AnyEffect(scaleEffect)]
        world.add(anchor: newObject)
        
    }
    
    @IBAction fileprivate func blinnTapped(_ sender: UIButton) {
        
        // Create a new anchor at the current locaiton
        
        guard let anchorModel = shipAsset else {
            return
        }
        
        guard let world = world else {
            return
        }
        
        guard let location = world.currentGazeLocation else {
            return
        }
        
        let newObject = AugmentedAnchor(withModelAsset: anchorModel, at: location)
        newObject.shaderPreference = .blinn
        world.add(anchor: newObject)
        
    }
    
    fileprivate func loadAnchorModels() {
        
        //
        // Download a usdz Model
        //
        
        //        let url = URL(string: "https://example.com/path/to/model.usdz")!
        //        let remoteModel = RemoteModelLoader().loadModel(withURL: url) { (filePath, error) in
        //            let url = URL(fileURLWithPath: filePath)
        //            let remoteAsset = MDLAsset(url: url)
        //            self.pinModel = remoteAsset
        //        }
        
        
        //
        // Get a Model from the app bundle
        //
        
        // Setup the model that will be used for AugmentedAnchor anchors
        guard let world = world else {
            print("ERROR: The AKWorld has not been initialized")
            return
        }
        
        // Simple asset that uses Blinn-Phong shader
        guard let aPinAsset = AKSceneKitUtils.mdlAssetFromScene(named: "Pin.scn", world: world) else {
            print("ERROR: Could not load the SceneKit model")
            return
        }
        
        // Animated USDZ asset
        guard let animatedUSDZAsset = MDLAssetTools.asset(named: "toy_robot_vintage.usdz", inBundle: Bundle.main) else {
            print("ERROR: Could not load the USDZ model")
            return
        }
        
        // USDZ
        guard let aUSDZAsset = MDLAssetTools.asset(named: "retrotv.usdz", inBundle: Bundle.main) else {
            print("ERROR: Could not load the USDZ model")
            return
        }
        
        // Simple asset that uses Blinn-Phong shader
        guard let aShipAsset = AKSceneKitUtils.mdlAssetFromScene(named: "ship.scn", world: world) else {
            print("ERROR: Could not load the SceneKit model")
            return
        }
        
        // SceneKit Asset
        guard let aMaxAsset = AKSceneKitUtils.mdlAssetFromScene(named: "Art.scnassets/character/max.scn", world: world) else {
            print("ERROR: Could not load the SceneKit model")
            return
        }
        
        // RealityKit Asset
        guard let aRKAsset = MDLAssetTools.asset(named: "RedBall.reality", inBundle: Bundle.main) else {
            print("ERROR: Could not load the USDZ model")
            return
        }
        
        usdzAsset = aUSDZAsset
        pinAsset = aPinAsset
        shipAsset = aShipAsset
        maxAsset = aMaxAsset
//        rkAsset = aRKAsset
        
    }
    
}

// MARK: - RenderMonitor

extension ViewController: AKWorldMonitor {
    
    @IBAction func infoButtonClicked(_ sender: UIButton) {
        if let infoView = infoView {
            infoView.isHidden = !infoView.isHidden
        }
    }
    
    func update(renderStats: RenderStats) {
        debugInfoAnchorCounts?.text = "ARKit Anchor Count: \(renderStats.arKitAnchorCount)\nAugmentKit Anchors: \(renderStats.numAnchors)\nplanes: \(renderStats.numPlanes)\ntracking points: \(renderStats.numTrackingPoints)\ntrackers: \(renderStats.numTrackers)\ntargets: \(renderStats.numTargets)\npath segments \(renderStats.numPathSegments)"
    }
    
    func update(worldStatus: AKWorldStatus) {
        
        guard let errorInfo = errorInfo else {
            return
        }
        
        if worldStatus.errors.count > 0 {
            errorInfo.text = ""
            for error in worldStatus.errors {
                errorInfo.text = (errorInfo.text ?? "") + "Error: \(error.localizedDescription)\n\n"
            }
        }
    }
    
}
