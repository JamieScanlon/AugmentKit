//
//  ViewController.swift
//  AugmentKitCLTools
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
import AugmentKitShader
import Metal
import MetalKit
import ModelIO
import SceneKit.ModelIO

class ViewController: UIViewController {
    
    @IBOutlet var serializeButton: UIButton!
    @IBOutlet var deserializeButton: UIButton!
    
    var documentsDirectory: URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last!
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        print("Documents directory: \(documentsDirectory)")
        
        guard let originalFileURL = Bundle.main.url(forResource: "Pin", withExtension: "scn") else {
            print("Pin.scn file not found in bundle")
            return
        }
        
        guard let originalContents = try? Data(contentsOf: originalFileURL) else {
            print("Cannot readt the contents of Pin.scn")
            return
        }
        
        let writableFileURL = documentsDirectory.appendingPathComponent("Pin.scn")
        
        print("Copying file: \(originalFileURL.absoluteString) to: \(writableFileURL.absoluteString)")
        try? originalContents.write(to: writableFileURL, options: .atomic)
        
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    @IBAction func serializeTapped(sender: UIButton) {
        let url = documentsDirectory.appendingPathComponent("Pin.scn")
        print("serialize file at path: \(url.absoluteString)")
        serializeMDLAsset(withURL: url)
    }
    
    @IBAction func deserializeTapped(sender: UIButton) {
        let url = documentsDirectory.appendingPathComponent("model.dat")
        print("deserialize file at path: \(url.absoluteString)")
        deserializeAndPrint(withURL: url)
    }
    
    @IBAction func shareRawDataFile(sender: UIButton) {
        let url = documentsDirectory.appendingPathComponent("model.dat")
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activityVC.popoverPresentationController?.sourceView = sender
        present(activityVC, animated: true, completion: nil)
    }
    
    @IBAction func shareArchive(sender: UIButton) {
        
        guard let zipFilePath = zipFilePath else {
            print("No Archive Found")
            return
        }
        
        let activityVC = UIActivityViewController(activityItems: [zipFilePath], applicationActivities: nil)
        activityVC.popoverPresentationController?.sourceView = sender
        present(activityVC, animated: true, completion: nil)
        
    }
    
    fileprivate var zipFilePath: URL?
    
    fileprivate func serializeMDLAsset(withURL url: URL) {
        
        var error: NSError?
        let myAsset: MDLAsset? = {
            if url.pathExtension == "scn" {
                guard let scene = try? SCNScene(url: url, options: nil) else {
                    return nil
                }
                return MDLAsset(scnScene: scene)
            } else {
                return MDLAsset(url: url, vertexDescriptor: AKSimpleModel.newAnchorVertexDescriptor(), bufferAllocator: nil, preserveTopology: false, error: &error)
            }
        }()
        
        guard let asset = myAsset, error == nil else {
            print("Model file not found. \(url.absoluteString)")
            return
        }
        
        // Load meshes into the model
        let model = AKMDLAssetModel(asset: asset)
        let dataFileURL = url.deletingLastPathComponent().appendingPathComponent("model.dat")
        NSKeyedArchiver.archiveRootObject(AKModelCodingWrapper(model: model), toFile: dataFileURL.path)
        
        do {
            zipFilePath = try Zip.quickZipFiles([dataFileURL], fileName: "AKModelArchive") // Zip
        }
        catch {
            print("Something went wrong")
        }
        
        
    }
    
    fileprivate func deserializeAndPrint(withURL url: URL) {
        
        print("Deserializing file at \(url)")
        
        guard let data = try? Data(contentsOf: url) else {
            print("File not found. \(url.absoluteString)")
            return
        }
        
        if let wrapper = NSKeyedUnarchiver.unarchiveObject(with: data) as? AKModelCodingWrapper {
            
            guard let archivedModel = wrapper.model else {
                print("AKModel is empty.")
                return
            }
            
            print("indexBuffers: \(archivedModel.indexBuffers)")
            print("instanceCount: \(archivedModel.instanceCount)")
            print("jointRootID: \(archivedModel.jointRootID)")
            print("localTransformAnimationIndices: \(archivedModel.localTransformAnimationIndices)")
            print("localTransformAnimations: \(archivedModel.localTransformAnimations)")
            print("localTransforms: \(archivedModel.localTransforms)")
            print("meshes: \(archivedModel.meshes)")
            print("meshNodeIndices: \(archivedModel.meshNodeIndices)")
            print("meshSkinIndices: \(archivedModel.meshSkinIndices)")
            print("nodeNames: \(archivedModel.nodeNames)")
            print("parentIndices: \(archivedModel.parentIndices)")
            print("sampleTimes: \(archivedModel.sampleTimes)")
            print("skeletonAnimations: \(archivedModel.skeletonAnimations)")
            print("skins: \(archivedModel.skins)")
            print("texturePaths: \(archivedModel.texturePaths)")
            print("vertexBuffers: \(archivedModel.vertexBuffers)")
            print("vertexDescriptors: \(archivedModel.vertexDescriptors)")
            print("worldTransformAnimationIndices: \(archivedModel.worldTransformAnimationIndices)")
            print("worldTransformAnimations: \(archivedModel.worldTransformAnimations)")
            print("worldTransforms: \(archivedModel.worldTransforms)")
            
        } else {
            
            print("Could not unarchive the model file.")
            
        }
    }


}



