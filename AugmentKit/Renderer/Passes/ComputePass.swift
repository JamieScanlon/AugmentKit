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
import AugmentKitShader

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
    
}

// MARK: - ComputePass

class ComputePass<Out> {
    
    fileprivate(set) var computeCommandEncoder: MTLComputeCommandEncoder?
    
    var device: MTLDevice
    var name: String?
    var uuid: UUID
    var threadGroup: ThreadGroup?
    var functionName: String?
    
    var usesGeometry = true
    var hasSkeleton = false
    var usesLighting = false
    var usesSharedBuffer = true
    var usesEnvironment = true
    var usesEffects = true
    var usesCameraOutput = false
    var usesShadows = false
    
    var geometryBuffer: GPUPassBuffer<AnchorInstanceUniforms>?
    var paletteBuffer: GPUPassBuffer<AnchorInstanceUniforms>?
    var materialBuffer: GPUPassBuffer<MaterialUniforms>?
    var sharedUniformsBuffer: GPUPassBuffer<SharedUniforms>?
    var environmentBuffer: GPUPassBuffer<EnvironmentUniforms>?
    var effectsBuffer: GPUPassBuffer<AnchorEffectsUniforms>?
    
    var outputBuffer: GPUPassBuffer<Out>?
    
    var inputTextures = [GPUPassTexture]()
    var outputTexture: GPUPassTexture?
    
    init(withDevice device: MTLDevice, uuid: UUID = UUID()) {
        self.device = device
        self.uuid = uuid
    }
    
    func prepareCommandEncoder(withCommandBuffer commandBuffer: MTLCommandBuffer) {
        
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()
        commandEncoder?.label = name
        
        computeCommandEncoder = commandEncoder
        
    }
    
    /// Create a `MTLComputePipelineDescriptor` configured for this ComputePass
    func computePipelineDescriptor(withComputeFunction computeFunction: MTLFunction? = nil) -> MTLComputePipelineDescriptor {
        let pipelineDescriptor = MTLComputePipelineDescriptor()
        pipelineDescriptor.computeFunction = computeFunction
        return pipelineDescriptor
    }
    
    func threadGroup(withComputePipelineDescriptor computePipelineDescriptor: MTLComputePipelineDescriptor) -> ThreadGroup {
        return ThreadGroup(withDevice: device, computePipelineDescriptor: computePipelineDescriptor)
    }
    
    func threadGroup(withComputeFunction computeFunction: MTLFunction? = nil, size: (width: Int, height: Int, depth: Int) = (width: 16, height: 16, depth: 1)) -> ThreadGroup {
        let computePipelineDescriptor = self.computePipelineDescriptor(withComputeFunction: computeFunction)
        return ThreadGroup(withDevice: device, computePipelineDescriptor: computePipelineDescriptor, size: size)
    }
    
    /// Prepares the Compute Command Encoder with the compute pipeline state.
    /// You must call `prepareCommandEncoder(withCommandBuffer:)` before calling this method
    func prepareThreadGroup() {
        guard let computeCommandEncoder = computeCommandEncoder, let threadGroup = threadGroup else {
            return
        }
        computeCommandEncoder.setComputePipelineState(threadGroup.computePipelineState)
    }
    
    /// Prepares the input and output textures for rendering by generating mipmaps. This should be called once before rendering and every time the input / output textures change.
    func prepareTextures() {
        inputTextures.forEach {
            $0.generateMippedTextures()
        }
        outputTexture?.generateMippedTextures()
    }
    
    // MARK: - Lifecycle
    
    func initializeBuffers(withDevice device: MTLDevice?) {
        
        guard let device = device else {
            return
        }
        
        if usesGeometry == true {
            geometryBuffer?.initialize(withDevice: device)
            if hasSkeleton {
                paletteBuffer?.initialize(withDevice: device)
            }
        }
        if usesSharedBuffer == true {
            sharedUniformsBuffer?.initialize(withDevice: device)
        }
        if usesLighting == true {
            materialBuffer?.initialize(withDevice: device)
        }
        if usesEffects == true {
            effectsBuffer?.initialize(withDevice: device)
        }
        if usesLighting == true {
            materialBuffer?.initialize(withDevice: device)
        }
        if usesEnvironment == true {
            environmentBuffer?.initialize(withDevice: device)
        }
        
        outputBuffer?.initialize(withDevice: device)
        
    }
    
    func loadPipeline(withMetalLibrary metalLibrary: MTLLibrary, instanceCount: Int = 1, threadgroupDepth: Int = 1) {
        
        guard let functionName = functionName else {
            print("Serious Error - tried to load ComputePass pipleine but functionName is undefined. Check your setup.")
            return
        }
        
        guard let computeFunction = metalLibrary.makeFunction(name: functionName) else {
            print("Serious Error - failed to create the compute function")
//            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeShaderInitializationFailed, userInfo: nil)
//            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
//            recordNewError(newError)
//            state = .uninitialized
            return
        }
        
        // If all of the instances are layed out in a square, how big is that square.
        let instancesPerLayer = ceil(Double(instanceCount) / Double(threadgroupDepth))
        let gridSize = Int(ceil(instancesPerLayer.squareRoot()))
//        let gridSize = Int(Float(instanceCount).squareRoot())
        threadGroup = self.threadGroup(withComputeFunction: computeFunction, size: (width: gridSize, height: gridSize, depth: threadgroupDepth))
        prepareTextures()
    }
    
    func updateBuffers(withFrameIndex index: Int) {
        
        if usesGeometry == true {
            geometryBuffer?.update(toFrame: index)
            if hasSkeleton {
                paletteBuffer?.update(toFrame: index)
            }
        }
        if usesSharedBuffer == true {
            sharedUniformsBuffer?.update(toFrame: index)
        }
        if usesLighting == true {
            materialBuffer?.update(toFrame: index)
        }
        if usesEffects == true {
            effectsBuffer?.update(toFrame: index)
        }
        if usesEnvironment == true {
            environmentBuffer?.update(toFrame: index)
        }
        
        outputBuffer?.update(toFrame: index)
        
    }
    
    func dispatch(lod: Int = 0) {
        
        defer {
            computeCommandEncoder?.endEncoding()
        }
        
        guard let computeEncoder = computeCommandEncoder else {
            return
        }
        
        guard let threadGroup = threadGroup else {
            return
        }
        
        computeEncoder.pushDebugGroup("Dispatch \(name ?? "Compute Pass") Level: \(lod)")
        
        //
        // Textures
        //
        
        // Input Textures
        inputTextures.forEach {
            if lod < $0.mippedTextures.count {
                computeEncoder.pushDebugGroup($0.label ?? "Input Texture")
                computeEncoder.setTexture($0.mippedTextures[lod], index: $0.shaderAttributeIndex)
                computeEncoder.popDebugGroup()
            }
        }
        
        // Output Texture
        if let outputTexture = outputTexture, lod < outputTexture.mippedTextures.count {
            computeEncoder.pushDebugGroup(outputTexture.label ?? "Output Texture")
            computeEncoder.setTexture(outputTexture.mippedTextures[lod], index: outputTexture.shaderAttributeIndex)
            var roughness = outputTexture.roughness(for: lod)
            computeEncoder.setBytes(&roughness, length: MemoryLayout<Float>.size, index: Int(kBufferIndexLODRoughness.rawValue))
            computeEncoder.popDebugGroup()
        }
        
        //
        // Buffers
        //
        
        if let geometryBuffer = geometryBuffer, usesGeometry {
            computeEncoder.pushDebugGroup(geometryBuffer.label ?? "Geometry Buffer")
            computeEncoder.setBuffer(geometryBuffer.buffer, offset: geometryBuffer.currentBufferFrameOffset, index: geometryBuffer.shaderAttributeIndex)
            computeEncoder.popDebugGroup()
        }
        
        if let paletteBuffer = paletteBuffer, usesGeometry, hasSkeleton {
            computeEncoder.pushDebugGroup(paletteBuffer.label ?? "Palette Buffer")
            computeEncoder.setBuffer(paletteBuffer.buffer, offset: paletteBuffer.currentBufferFrameOffset, index: paletteBuffer.shaderAttributeIndex)
            computeEncoder.popDebugGroup()
        }
        
        if let sharedBuffer = sharedUniformsBuffer, usesSharedBuffer {
            computeEncoder.pushDebugGroup(sharedBuffer.label ?? "Shared Buffer")
            computeEncoder.setBuffer(sharedBuffer.buffer, offset: sharedBuffer.currentBufferFrameOffset, index: sharedBuffer.shaderAttributeIndex)
            computeEncoder.popDebugGroup()
        }
        
        if let materialBuffer = materialBuffer, usesLighting {
            computeEncoder.pushDebugGroup(materialBuffer.label ?? "material Buffer")
            computeEncoder.setBuffer(materialBuffer.buffer, offset: materialBuffer.currentBufferFrameOffset, index: materialBuffer.shaderAttributeIndex)
            computeEncoder.popDebugGroup()
        }
        
        if let environmentBuffer = environmentBuffer, usesEnvironment {
            computeEncoder.pushDebugGroup(environmentBuffer.label ?? "Environment Buffer")
            computeEncoder.setBuffer(environmentBuffer.buffer, offset: environmentBuffer.currentBufferFrameOffset, index: environmentBuffer.shaderAttributeIndex)
            computeEncoder.popDebugGroup()
        }
        
        if let effectsBuffer = effectsBuffer, usesEffects {
            computeEncoder.pushDebugGroup(effectsBuffer.label ?? "Effects Buffer")
            computeEncoder.setBuffer(effectsBuffer.buffer, offset: effectsBuffer.currentBufferFrameOffset, index: effectsBuffer.shaderAttributeIndex)
            computeEncoder.popDebugGroup()
        }
        
        // Output Buffer
        if let outputBuffer = outputBuffer {
            computeEncoder.pushDebugGroup(outputBuffer.label ?? "Output Buffer")
            computeEncoder.setBuffer(outputBuffer.buffer, offset: outputBuffer.currentBufferFrameOffset, index: outputBuffer.shaderAttributeIndex)
            computeEncoder.popDebugGroup()
        }
        
        //
        // Dispatch
        //
        
        prepareThreadGroup()
        
        // Requires the device supports non-uniform threadgroup sizes
        computeEncoder.dispatchThreads(MTLSize(width: threadGroup.size.width, height: threadGroup.size.height, depth: threadGroup.size.depth), threadsPerThreadgroup: MTLSize(width: threadGroup.threadsPerGroup.width, height: threadGroup.threadsPerGroup.height, depth: 1))
        
        computeEncoder.popDebugGroup()
        
    }
    
    // MARK: - Private
    
}
