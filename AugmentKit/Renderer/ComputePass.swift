//
//  ComputePass.swift
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

// MARK: - ThreadGroup

/// Represents a group of threads (kernel function calls) to be executed in parallel.
struct ThreadGroup {

    /// this value must be at least as big as the number of threads in this group. This value need to be the same for all `ThreadGroup`'s executed in this pass. This value also can't exceed `maxTotalThreadsPerThreadgroup`
    var threadsPerGroup: (width: Int, height: Int)
    var size: (width: Int, height: Int, depth: Int)
    var uuid: UUID
    var computePipelineState: MTLComputePipelineState
    
    /// See: https://developer.apple.com/documentation/metal/calculating_threadgroup_and_grid_sizes
    init(computePipelineState: MTLComputePipelineState, uuid: UUID = UUID(), size: (width: Int, height: Int, depth: Int) = (width: 16, height: 16, depth: 1)) {
        self.computePipelineState = computePipelineState
        self.size = size
        let w = computePipelineState.threadExecutionWidth
        let h = computePipelineState.maxTotalThreadsPerThreadgroup / w
        self.threadsPerGroup = (width: w, height: h)
        self.uuid = uuid
    }
    
    init(withDevice device: MTLDevice, computePipelineDescriptor: MTLComputePipelineDescriptor, size: (width: Int, height: Int, depth: Int) = (width: 16, height: 16, depth: 1)) {
        
        let myPipelineState: MTLComputePipelineState = {
            do {
                return try device.makeComputePipelineState(descriptor: computePipelineDescriptor, options: [], reflection: nil)
            } catch let error {
                print("failed to create render pipeline state for the device. ERROR: \(error)")
                let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: nil, underlyingError: error))))
                NotificationCenter.default.post(name: .abortedDueToErrors, object: nil, userInfo: ["errors": [newError]])
                fatalError()
            }
        }()
        self.init(computePipelineState: myPipelineState, size: size)
        
    }
    
    /// Prepares the Compute Command Encoder with the compute pipeline state.
    /// You must call `prepareRenderCommandEncoder(withCommandBuffer:)` before calling this method
    func prepareThreadGroup(withComputePass computePass: ComputePass) {
        
        guard let computeCommandEncoder = computePass.computeCommandEncoder else {
            return
        }
        
        computeCommandEncoder.setComputePipelineState(computePipelineState)
        
    }
    
}

// MARK: - ComputePass

class ComputePass {
    
    fileprivate(set) var computeCommandEncoder: MTLComputeCommandEncoder?
    
    var device: MTLDevice
    var name: String?
    var uuid: UUID
    var threadGroup: ThreadGroup?
    
    var usesGeometry = true
    var usesLighting = false
    var usesSharedBuffer = true
    var usesEnvironment = true
    var usesEffects = true
    var usesCameraOutput = false
    var usesShadows = false
    
    init(withDevice device: MTLDevice, uuid: UUID = UUID()) {
        self.device = device
        self.uuid = uuid
    }
    
    func prepareRenderCommandEncoder(withCommandBuffer commandBuffer: MTLCommandBuffer) {
        
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()
        commandEncoder?.label = name
        
        computeCommandEncoder = commandEncoder
        
    }
    
    /// Create a `MTLComputePipelineDescriptor` configured for this ComputePass
    func computePipelineDescriptor(withComputeFunction computeFunction: MTLFunction? = nil) -> MTLComputePipelineDescriptor? {
        
        let pipelineDescriptor = MTLComputePipelineDescriptor()
        pipelineDescriptor.computeFunction = computeFunction
        return pipelineDescriptor
        
    }
    
    func threadGroup(withComputePipelineDescriptor computePipelineDescriptor: MTLComputePipelineDescriptor) -> ThreadGroup {
        return ThreadGroup(withDevice: device, computePipelineDescriptor: computePipelineDescriptor)
    }
    
    func threadGroup(withComputeFunction computeFunction: MTLFunction? = nil, size: (width: Int, height: Int, depth: Int) = (width: 16, height: 16, depth: 1)) -> ThreadGroup? {
        guard let computePipelineDescriptor = computePipelineDescriptor(withComputeFunction: computeFunction) else {
            return nil
        }
        return ThreadGroup(withDevice: device, computePipelineDescriptor: computePipelineDescriptor, size: size)
    }
    
}
