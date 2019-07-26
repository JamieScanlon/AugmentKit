//
//  DefaultComputeModule.swift
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

import Foundation
import AugmentKitShader

// TODO: Eventually we would like to eliminate ShaderModule's and rely compltely on ComputePas's and RenderPass's
class DefaultComputeModule<Out>: ComputeModule {
    
    weak var computePass: ComputePass<Out>?
    var device: MTLDevice?
    var frameCount: Int = 1
    var instanceCount: Int = 1
    var threadgroupDepth: Int = 1
    
    var moduleIdentifier: String {
        return "DefaultComputeModule"
    }
    var state: ShaderModuleState = .uninitialized
    var renderLayer: Int {
        return -2
    }
    var sharedModuleIdentifiers: [String]?
    var errors = [AKError]()
    
    func initializeBuffers(withDevice device: MTLDevice, maxInFlightFrames: Int, maxInstances: Int) {
        self.device = device
        frameCount = maxInFlightFrames
//        instanceCount = maxInstances
    }
    
    func loadPipeline(withMetalLibrary metalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider, textureBundle: Bundle, forComputePass computePass: ComputePass<Out>?) -> ThreadGroup? {
        
        if self.computePass == nil {
            print("WARNING: ComputePass is nil. DefaultComputeModule relies on the compute pass being set before loadPipeline is called. Check your setup.")
        }
        
        self.computePass?.initializeBuffers(withDevice: device)
        self.computePass?.loadPipeline(withMetalLibrary: metalLibrary, instanceCount: instanceCount, threadgroupDepth: threadgroupDepth)
        
        state = .ready
        return self.computePass?.threadGroup
        
    }
    
    func updateBufferState(withBufferIndex index: Int) {
        if computePass == nil {
            print("WARNING: ComputePass is nil. DefaultComputeModule relies on the compute pass being set before updateBufferState is called. Check your setup.")
        }
        computePass?.updateBuffers(withFrameIndex: index)
    }
    
    func dispatch(withComputePass computePass: ComputePass<Out>?, sharedModules: [SharedRenderModule]?) {
        if self.computePass == nil {
            print("WARNING: ComputePass is nil. DefaultComputeModule relies on the compute pass being set before updateBufferState is called. Check your setup.")
        }
        self.computePass?.dispatch()
    }
    
    
    
    func frameEncodingComplete(renderPasses: [RenderPass]) {
        //
    }
    
    func recordNewError(_ akError: AKError) {
        //
    }
    
}
