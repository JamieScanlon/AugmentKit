//
//  ViewController.swift
//  AugmentKitCLTools
//
//  Created by Jamie Scanlon on 12/9/17.
//  Copyright © 2017 TenthLetterMade. All rights reserved.
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
                return MDLAsset(url: url, vertexDescriptor: AKSimpleModel.newVertexDescriptor(), bufferAllocator: nil, preserveTopology: false, error: &error)
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
//            let unzipDirectory = try Zip.quickUnzipFile(filePath) // Unzip
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



