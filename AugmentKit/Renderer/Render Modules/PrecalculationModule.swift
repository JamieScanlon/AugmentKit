//
//  PrecalculationModule.swift
//  AugmentKit
//
//  MIT License
//
//  Copyright (c) 2019 JamieScanlon
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
//

import AugmentKitShader
import Foundation
import MetalKit

class PrecalculationModule: ComputeModule {
    
    var moduleIdentifier: String {
        return "PrecalculationModule"
    }
    var isInitialized: Bool = false
    var renderLayer: Int {
        return -3
    }
    
    var errors = [AKError]()
    
    func initializeBuffers(withDevice device: MTLDevice, maxInFlightBuffers: Int, maxInstances: Int) {
        
        argumentBuffer = device.makeBuffer(length: MemoryLayout<PrecalculatedParameters>.stride * maxInstances, options: .storageModePrivate)
        
    }
    
    func loadPipeline(withMetalLibrary metalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider, textureBundle: Bundle, forComputePass computePass: ComputePass?) -> [ThreadGroup] {
        
        guard let precalculationFunction = metalLibrary.makeFunction(name: "precalculationComputeShader") else {
            print("Serious Error - failed to create the precalculationComputeShader function")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeShaderInitializationFailed, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return []
        }
        
        guard let threadGroup = computePass?.threadGroup(withComputeFunction: precalculationFunction) else {
            return []
        }
      
        return [threadGroup]
    }
    
    func updateBufferState(withBufferIndex: Int) {
        //
    }
    
    func dispatch(withComputePass computePass: ComputePass) {
        //
    }
    
    func frameEncodingComplete() {
        //
    }
    
    func recordNewError(_ akError: AKError) {
        errors.append(akError)
    }
    
    // MARK: - Private
    
    fileprivate var argumentBuffer: MTLBuffer?
    
    
}
