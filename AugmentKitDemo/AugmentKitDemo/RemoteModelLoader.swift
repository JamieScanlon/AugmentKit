//
//  RemoteModelLoader.swift
//  AugmentKit
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

import Foundation
import AugmentKit

public class RemoteModelLoader {
    
    public enum Status {
        case uninitilized
        case loading
        case ready
        case error
    }
    
    public var status: RemoteModelLoader.Status = .uninitilized
    
    fileprivate var documentsDirectory: URL {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last!
    }
    
    // Testing Example: "https://s3-us-west-2.amazonaws.com/com.tenthlettermade.public/PinAKModelArchive.zip"
    public func loadModel(withURL url: URL, withCompletion completion: ((String?, Error?) -> Void)? = nil) {
        
        status = .loading
        
        let fileName = url.lastPathComponent

        // Setup the directory that will store all archives
        if !FileManager.default.fileExists(atPath: documentsDirectory.appendingPathComponent("ModelArchives").path) {
            try? FileManager.default.createDirectory(at: documentsDirectory.appendingPathComponent("ModelArchives"), withIntermediateDirectories: true, attributes: nil)
        }
        
        //
        // Download a file
        //
        
        let sessionConfig = URLSessionConfiguration.default
        let session = URLSession(configuration: sessionConfig)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let modelArchiveLocalURL = documentsDirectory.appendingPathComponent("ModelArchives").appendingPathComponent("\(fileName)")
        
        let task = session.downloadTask(with: request) { [weak self] (tempLocalUrl, response, error) in
            if let tempLocalUrl = tempLocalUrl, error == nil {
                    
                // Success
                guard let statusCode = (response as? HTTPURLResponse)?.statusCode, statusCode < 400 else {
                    let myStatusCode = "\((response as? HTTPURLResponse)?.statusCode ?? 0)"
                    print("RemoteModelLoader: Networking Error: \(myStatusCode)")
                    self?.status = .error
                    if let completion = completion {
                        let error = NSError(domain: AKErrorDomain, code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Networking error. Returned status code \(myStatusCode)"])
                        completion(nil, error)
                    }
                    return
                }
                
                do {
                    if FileManager.default.fileExists(atPath: modelArchiveLocalURL.path) {
                        try FileManager.default.removeItem(atPath: modelArchiveLocalURL.path)
                    }
                    try FileManager.default.copyItem(at: tempLocalUrl, to: modelArchiveLocalURL)
                    self?.status = .ready
                    if let completion = completion {
                        if FileManager.default.fileExists(atPath: modelArchiveLocalURL.appendingPathComponent("\(fileName)").path) {
                            completion(modelArchiveLocalURL.appendingPathComponent("\(fileName)").path, nil)
                        } else {
                            print("RemoteModelLoader: Warning. Could not find the unzipped data file at \(modelArchiveLocalURL.appendingPathComponent("\(fileName)").path)")
                            completion(nil, nil)
                        }
                       
                    }
                } catch {
                    print("RemoteModelLoader: Serious Error. Could not unzip the archived model at \(modelArchiveLocalURL.path) : \(error.localizedDescription)")
                    self?.status = .error
                    if let completion = completion {
                        completion(nil, error)
                    }
                }
                
            } else {
                if let error = error {
                    print("RemoteModelLoader: Serious Error. \(error.localizedDescription)")
                    self?.status = .error
                    if let completion = completion {
                        completion(nil, error)
                    }
                } else if let response = response {
                    print("RemoteModelLoader: Serious Error. response: \(response.debugDescription)")
                    self?.status = .error
                    let error = NSError(domain: AKErrorDomain, code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Networking error. Returned response \(response.debugDescription)"])
                    if let completion = completion {
                        completion(nil, error)
                    }
                } else {
                    print("RemoteModelLoader: Serious Error.")
                    self?.status = .error
                    let error = NSError(domain: AKErrorDomain, code: 1, userInfo: [NSLocalizedFailureReasonErrorKey: "Networking error."])
                    if let completion = completion {
                        completion(nil, error)
                    }
                }
            }
            
        }
        
        task.resume()
        
    }

}
