//
//  AKRemoteArchivedModel.swift
//  AugmentKit
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
import ModelIO
import simd

public class AKRemoteArchivedModel: AKModel {
    
    public enum Status {
        case uninitilized
        case loading
        case ready
        case error
    }
    
    public var jointRootID: String = String()
    public var nodeNames: [String] = [String]()
    public var texturePaths: [String] = [String]()
    public var localTransforms: [matrix_float4x4] = [matrix_float4x4]()
    public var worldTransforms: [matrix_float4x4] = [matrix_float4x4]()
    public var parentIndices: [Int?] = [Int?]()
    public var meshNodeIndices: [Int] = [Int]()
    public var meshSkinIndices: [Int?] = [Int?]()
    public var instanceCount: [Int] = [Int]()
    public var vertexDescriptors: [MDLVertexDescriptor] = [MDLVertexDescriptor]()
    public var vertexBuffers: [Data] = [Data]()
    public var indexBuffers: [Data] = [Data]()
    public var meshes: [MeshData] = [MeshData]()
    public var skins: [SkinData] = [SkinData]()
    public var sampleTimes: [Double] = [Double]()
    public var localTransformAnimations: [[matrix_float4x4]] = [[matrix_float4x4]]()
    public var worldTransformAnimations: [[matrix_float4x4]] = [[matrix_float4x4]]()
    public var localTransformAnimationIndices: [Int?] = [Int?]()
    public var worldTransformAnimationIndices: [Int?] = [Int?]()
    public var skeletonAnimations: [AnimatedSkeleton] = [AnimatedSkeleton]()
    
    public var status: AKRemoteArchivedModel.Status = .uninitilized
    
    public var compressor: ModelCompressor?
    
    public init() {}
    
    public init(remoteURL url: URL) {
        
        status = .uninitilized
        
        loadAnchorModel(withURL: url) { [weak self] (aModel, error) in
            
            guard let aModel = aModel else {
                return
            }
            
            self?.jointRootID = aModel.jointRootID
            self?.nodeNames = aModel.nodeNames
            self?.texturePaths = aModel.texturePaths
            self?.localTransforms = aModel.localTransforms
            self?.worldTransforms = aModel.worldTransforms
            self?.parentIndices = aModel.parentIndices
            self?.meshNodeIndices = aModel.meshNodeIndices
            self?.meshSkinIndices = aModel.meshSkinIndices
            self?.instanceCount = aModel.instanceCount
            self?.vertexDescriptors = aModel.vertexDescriptors
            self?.vertexBuffers = aModel.vertexBuffers
            self?.indexBuffers = aModel.indexBuffers
            self?.meshes = aModel.meshes
            self?.skins = aModel.skins
            self?.sampleTimes = aModel.sampleTimes
            self?.localTransformAnimations = aModel.localTransformAnimations
            self?.worldTransformAnimations = aModel.worldTransformAnimations
            self?.localTransformAnimationIndices = aModel.localTransformAnimationIndices
            self?.worldTransformAnimationIndices = aModel.worldTransformAnimationIndices
            self?.skeletonAnimations = aModel.skeletonAnimations
            
        }
        
    }
    
    fileprivate var documentsDirectory: URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last!
    }
    
    // Testing Example: "https://s3-us-west-2.amazonaws.com/com.tenthlettermade.public/PinAKModelArchive.zip"
    fileprivate func loadAnchorModel(withURL url: URL, withCompletion completion: ((AKModel?, Error?) -> Void)? = nil) {
        
        status = .loading
        
        let fileName: String = {
            if url.lastPathComponent.hasSuffix(".zip") {
                let endIndex =  url.lastPathComponent.index(url.lastPathComponent.endIndex, offsetBy: -5)
                return String(url.lastPathComponent[...endIndex])
            } else {
                return url.lastPathComponent
            }
        }()

        // Setup the directory that will store all archives
        if !FileManager.default.fileExists(atPath: documentsDirectory.appendingPathComponent("ModelArchives").path) {
            try? FileManager.default.createDirectory(at: documentsDirectory.appendingPathComponent("ModelArchives"), withIntermediateDirectories: true, attributes: nil)
        }
        
        // If the model has already been loaded and saved to the documents directory
        // just unarchive it.
        guard !FileManager.default.fileExists(atPath: documentsDirectory.appendingPathComponent("ModelArchives").appendingPathComponent("\(fileName).dat").path) else {
            status = .ready
            if let completion = completion {
                completion(AKArchivedModel(filePath: documentsDirectory.appendingPathComponent("ModelArchives").appendingPathComponent("\(fileName).dat").path), nil)
            }
            return
        }
        
        //
        // Download a zipped Model
        //
        
        let sessionConfig = URLSessionConfiguration.default
        let session = URLSession(configuration: sessionConfig)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let modelArchiveLocalURL = documentsDirectory.appendingPathComponent("ModelArchives").appendingPathComponent("\(fileName).zip")
        
        let task = session.downloadTask(with: request) { [weak self] (tempLocalUrl, response, error) in
            if let tempLocalUrl = tempLocalUrl, error == nil {
                    
                // Success
                guard let statusCode = (response as? HTTPURLResponse)?.statusCode, statusCode < 400 else {
                    let myStatusCode = "\((response as? HTTPURLResponse)?.statusCode ?? 0)"
                    print("AKRemoteArchivedModel: Networking Error: \(myStatusCode)")
                    self?.status = .error
                    if let completion = completion {
                        let error = NSError(domain: "com.tenthlettermade.AugmentKit.errordomain", code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Networking error. Returned status code \(myStatusCode)"])
                        completion(nil, error)
                    }
                    return
                }
                
                do {
                    if FileManager.default.fileExists(atPath: modelArchiveLocalURL.path) {
                        try FileManager.default.removeItem(atPath: modelArchiveLocalURL.path)
                    }
                    try FileManager.default.copyItem(at: tempLocalUrl, to: modelArchiveLocalURL)
                    guard let unzipDirectory = self?.compressor?.unzipModel(withFileURL: modelArchiveLocalURL) else {
                        print("AKRemoteArchivedModel: Serious Error. Could not unzip the archived model at \(modelArchiveLocalURL.path)")
                        self?.status = .error
                        if let completion = completion {
                            completion(nil, error)
                        }
                        return
                    }
                    self?.status = .ready
                    if let completion = completion {
                        if FileManager.default.fileExists(atPath: unzipDirectory.appendingPathComponent("\(fileName).dat").path) {
                            completion(AKArchivedModel(filePath: unzipDirectory.appendingPathComponent("\(fileName).dat").path), nil)
                        } else if FileManager.default.fileExists(atPath: unzipDirectory.appendingPathComponent("model.dat").path)  {
                            // Support for a secondary configuration where the model data file is simply named `model.dat`
                            completion(AKArchivedModel(filePath: unzipDirectory.appendingPathComponent("model.dat").path), nil)
                        } else {
                            print("AKRemoteArchivedModel: Warning. Could not find the unzipped data file at \(unzipDirectory.appendingPathComponent("\(fileName).dat").path)")
                            completion(nil, nil)
                        }
                       
                    }
                } catch {
                    print("AKRemoteArchivedModel: Serious Error. Could not unzip the archived model at \(modelArchiveLocalURL.path) : \(error.localizedDescription)")
                    self?.status = .error
                    if let completion = completion {
                        completion(nil, error)
                    }
                }
                
            } else {
                if let error = error {
                    print("AKRemoteArchivedModel: Serious Error. \(error.localizedDescription)")
                    self?.status = .error
                    if let completion = completion {
                        completion(nil, error)
                    }
                } else if let response = response {
                    print("AKRemoteArchivedModel: Serious Error. response: \(response.debugDescription)")
                    self?.status = .error
                    let error = NSError(domain: "com.tenthlettermade.AugmentKit.errordomain", code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Networking error. Returned response \(response.debugDescription)"])
                    if let completion = completion {
                        completion(nil, error)
                    }
                } else {
                    print("AKRemoteArchivedModel: Serious Error.")
                    self?.status = .error
                    let error = NSError(domain: "com.tenthlettermade.AugmentKit.errordomain", code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Networking error."])
                    if let completion = completion {
                        completion(nil, error)
                    }
                }
            }
            
        }
        
        task.resume()
        
    }

}
