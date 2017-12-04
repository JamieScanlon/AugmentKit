//
//  AugmentKitCLTools.swift
//  AugmentKitCLTools
//
//  Created by Jamie Scanlon on 12/2/17.
//  Copyright © 2017 TenthLetterMade. All rights reserved.
//

import Foundation
import AugmentKitShader
import Metal
import MetalKit
import ModelIO
import SceneKit.ModelIO

enum OptionType: String {
    case serialize = "s"
    case help = "h"
    case unknown
    
    init(value: String) {
        switch value {
        case "s": self = .serialize
        case "h": self = .help
        default: self = .unknown
        }
    }
}

class AugmentKitCLTools {
    
    let consoleIO = ConsoleIO()
    
    func staticMode() {
        
        for argument in CommandLine.arguments[1...] {
            if argument.hasPrefix("-") {
                setOption(argument)
            } else {
                setPath(argument)
            }
        }
        
        switch option {
        case .serialize:
            serializeMDLAsset()
        default:
            ConsoleIO.printUsage()
        }
        
    }
    
    // MARK: - Private
    
    fileprivate var option: OptionType = .unknown
    fileprivate var url: URL?
    private var model: AKModel?
    
    fileprivate func setOption(_ optionString: String) {
        let startIndex = optionString.index(optionString.startIndex, offsetBy: 1)
        option = OptionType(value: String(optionString[startIndex...]))
    }
    
    fileprivate func setPath(_ path: String) {
        url = URL(fileURLWithPath: path)
    }
    
    fileprivate func serializeMDLAsset() {
        
        guard let url = url else {
            ConsoleIO.printUsage()
            return
        }
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            ConsoleIO.writeMessage("Metal is not supported on this device", to: .error)
            return
        }
        
        let metalAllocator = MTKMeshBufferAllocator(device: device)
        
        var error: NSError?
        let myAsset: MDLAsset? = {
            if url.pathExtension == "scn" {
                guard let scene = try? SCNScene(url: url, options: nil) else {
                    return nil
                }
                return MDLAsset(scnScene: scene, bufferAllocator: metalAllocator)
            } else {
                return MDLAsset(url: url, vertexDescriptor: AKSimpleModel.newVertexDescriptor(), bufferAllocator: metalAllocator, preserveTopology: false, error: &error)
            }
        }()
        
        guard let asset = myAsset, error == nil else {
            ConsoleIO.writeMessage("Model file not found.", to: .error)
            return
        }
        
        // Load meshes into the model
        model = AKMDLAssetModel(asset: asset)
        
        guard let model = model else {
            ConsoleIO.writeMessage("Could not parse the model file.", to: .error)
            return
        }
        
        NSKeyedArchiver.archiveRootObject(AKModelCodingWrapper(model: model), toFile: url.deletingLastPathComponent().appendingPathComponent("scene.dat").path)
        
    }
    
}
