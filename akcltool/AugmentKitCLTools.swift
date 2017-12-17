//
//  AugmentKitCLTools.swift
//  AugmentKitCLTools
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

import Foundation
import AugmentKitShader
import Metal
import MetalKit
import ModelIO
import SceneKit.ModelIO

enum OptionType: String {
    case serialize = "s"
    case help = "h"
    case verify = "v"
    case unknown
    
    init(value: String) {
        switch value {
        case "s": self = .serialize
        case "h": self = .help
        case "v": self = .verify
        default: self = .unknown
        }
    }
}

class AugmentKitCLTools {
    
    func staticMode() {
        
        ConsoleIO.writeMessage("WARNING: THIS TOOL IS STILL IN DEVELOPEMNT. There are known problems serializing a file on the filesystem. The generated file may be missing mesh data.", to: .standard)
        
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
        case .verify:
            deserializeAndPrint()
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
            ConsoleIO.writeMessage("Model file not found. \(url.absoluteString)", to: .error)
            return
        }
        
        // Load meshes into the model
        model = AKMDLAssetModel(asset: asset)
        
        guard let model = model else {
            ConsoleIO.writeMessage("Could not parse the model file.", to: .error)
            return
        }
        
        NSKeyedArchiver.archiveRootObject(AKModelCodingWrapper(model: model), toFile: url.deletingLastPathComponent().appendingPathComponent("model.dat").path)
        
    }
    
    fileprivate func deserializeAndPrint() {
        
        guard let url = url else {
            ConsoleIO.printUsage()
            return
        }
        
        guard let data = try? Data(contentsOf: url) else {
            ConsoleIO.writeMessage("File not found. \(url.absoluteString)", to: .error)
            return
        }
        
        if let wrapper = NSKeyedUnarchiver.unarchiveObject(with: data) as? AKModelCodingWrapper {
            
            guard let archivedModel = wrapper.model else {
                ConsoleIO.writeMessage("AKModel is empty.", to: .error)
                return
            }
            
            ConsoleIO.writeMessage("indexBuffers: \(archivedModel.indexBuffers)", to: .standard)
            ConsoleIO.writeMessage("instanceCount: \(archivedModel.instanceCount)", to: .standard)
            ConsoleIO.writeMessage("jointRootID: \(archivedModel.jointRootID)", to: .standard)
            ConsoleIO.writeMessage("localTransformAnimationIndices: \(archivedModel.localTransformAnimationIndices)", to: .standard)
            ConsoleIO.writeMessage("localTransformAnimations: \(archivedModel.localTransformAnimations)", to: .standard)
            ConsoleIO.writeMessage("localTransforms: \(archivedModel.localTransforms)", to: .standard)
            ConsoleIO.writeMessage("meshes: \(archivedModel.meshes)", to: .standard)
            ConsoleIO.writeMessage("meshNodeIndices: \(archivedModel.meshNodeIndices)", to: .standard)
            ConsoleIO.writeMessage("meshSkinIndices: \(archivedModel.meshSkinIndices)", to: .standard)
            ConsoleIO.writeMessage("nodeNames: \(archivedModel.nodeNames)", to: .standard)
            ConsoleIO.writeMessage("parentIndices: \(archivedModel.parentIndices)", to: .standard)
            ConsoleIO.writeMessage("sampleTimes: \(archivedModel.sampleTimes)", to: .standard)
            ConsoleIO.writeMessage("skeletonAnimations: \(archivedModel.skeletonAnimations)", to: .standard)
            ConsoleIO.writeMessage("skins: \(archivedModel.skins)", to: .standard)
            ConsoleIO.writeMessage("texturePaths: \(archivedModel.texturePaths)", to: .standard)
            ConsoleIO.writeMessage("vertexBuffers: \(archivedModel.vertexBuffers)", to: .standard)
            ConsoleIO.writeMessage("vertexDescriptors: \(archivedModel.vertexDescriptors)", to: .standard)
            ConsoleIO.writeMessage("worldTransformAnimationIndices: \(archivedModel.worldTransformAnimationIndices)", to: .standard)
            ConsoleIO.writeMessage("worldTransformAnimations: \(archivedModel.worldTransformAnimations)", to: .standard)
            ConsoleIO.writeMessage("worldTransforms: \(archivedModel.worldTransforms)", to: .standard)
            
        } else {
            
            ConsoleIO.writeMessage("Could not unarchive the model file.", to: .error)
            
        }
    }
    
}
