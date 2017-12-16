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
            
            let worldConfiguration = AKWorldConfiguration(usesLocation: false) // Turn locaion off for now because it's not fully implemented yet.
            let myWorld = AKWorld(renderDestination: view, configuration: worldConfiguration)
            
            // Debugging
            myWorld.renderer.showGuides = true
            myWorld.renderer.logger = self
            
            // Set the initial orientation
            myWorld.renderer.orientation = UIApplication.shared.statusBarOrientation
            
            // Begin
            myWorld.begin()
            
            world = myWorld
            
            loadAnchorModel()
            
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
    
    fileprivate var documentsDirectory: URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last!
    }
    fileprivate func loadAnchorModel() {
        
        // If the model has already been loaded and saved to the documents directory
        // just unarchive it.
        guard !FileManager.default.fileExists(atPath: documentsDirectory.appendingPathComponent("archivedModel").appendingPathComponent("model.dat").path) else {
            unarchiveAnchorModel(withFilePath: documentsDirectory.appendingPathComponent("archivedModel").appendingPathComponent("model.dat"))
            return
        }
        
        //
        // Download a zipped Model
        //
        
        if FileManager.default.fileExists(atPath: documentsDirectory.appendingPathComponent("archivedModel").path) {
            try? FileManager.default.removeItem(atPath: documentsDirectory.appendingPathComponent("archivedModel").path)
        }
        
        guard let modelArchiveRemoteURL = URL(string: "https://s3-us-west-2.amazonaws.com/com.tenthlettermade.public/PinAKModelArchive.zip") else {
            print("Invalid URL: 'https://s3-us-west-2.amazonaws.com/com.tenthlettermade.public/PinAKModelArchive.zip'")
            return
        }
        
        let sessionConfig = URLSessionConfiguration.default
        let session = URLSession(configuration: sessionConfig)
        var request = URLRequest(url: modelArchiveRemoteURL)
        request.httpMethod = "GET"
        
        let modelArchiveLocalURL = documentsDirectory.appendingPathComponent("archivedModel.zip")
        
        let task = session.downloadTask(with: request) { [weak self] (tempLocalUrl, response, error) in
            if let tempLocalUrl = tempLocalUrl, error == nil {
                // Success
                if let statusCode = (response as? HTTPURLResponse)?.statusCode {
                    print("Success: \(statusCode)")
                }
                
                do {
                    if FileManager.default.fileExists(atPath: modelArchiveLocalURL.path) {
                        try FileManager.default.removeItem(atPath: modelArchiveLocalURL.path)
                    }
                    try FileManager.default.copyItem(at: tempLocalUrl, to: modelArchiveLocalURL)
                    let unzipDirectory = try Zip.quickUnzipFile(modelArchiveLocalURL)
                    self?.unarchiveAnchorModel(withFilePath: unzipDirectory.appendingPathComponent("model.dat"))
                } catch {
                    print("Could not unzip the archived model at \(modelArchiveLocalURL.absoluteString) : \(error.localizedDescription)")
                }
                
            } else {
                if let error = error {
                    print("Failure: \(error.localizedDescription)")
                } else if let tempLocalUrl = tempLocalUrl {
                    print("Failure: url: \(tempLocalUrl.absoluteString)")
                } else {
                    print("Failure")
                }
            }
            
            
        }
        task.resume()
        
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
    
    fileprivate func unarchiveAnchorModel(withFilePath filePath: URL) {
        
        guard let data = try? Data(contentsOf: filePath) else {
            print("File not found. \(filePath.absoluteString)")
            return
        }
        
        // This is a litle hacky but... When the AKModelCodingWrapper is archived from the
        // AugmentKitCLTools target, it gets prepended with the module name so we have
        // to map it back to a class in this module.
        NSKeyedUnarchiver.setClass(AKModelCodingWrapper.self, forClassName: "AugmentKitCLTools.AKModelCodingWrapper")
        
        if let wrapper = NSKeyedUnarchiver.unarchiveObject(with: data) as? AKModelCodingWrapper {
            
            guard let archivedModel = wrapper.model else {
                print("AKModel is empty.")
                return
            }
            
            anchorModel = archivedModel
            
        } else {
            print("Data file at \(filePath.absoluteString) is not an AKModelCodingWrapper")
        }
    }
    
}

// MARK: - RenderDebugLogger

extension ViewController: RenderDebugLogger {
    
    func updatedAnchors(count: Int, numAnchors: Int, numPlanes: Int, numTrackingPoints: Int) {
        debugInfoAnchorCounts?.text = "Total Anchor Count: \(count) - User: \(numAnchors), planes: \(numPlanes), points: \(numTrackingPoints)"
    }
}
