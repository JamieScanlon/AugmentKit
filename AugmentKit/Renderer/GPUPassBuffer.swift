//
//  GPUPassBuffer.swift
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
import Metal

/// A class that holds a reference to a `MTLBuffer` that is used as an attachment to a GPU shader. This class helps to initialize and update the buffer by making the following assumptions
/// - The buffer contains a homogenious sequnce of `T` objects. Interleaving heterogeneous objects can be achieved by wrapping them in a stuct and using that struct as the buffer type `T`
/// - The buffer may contain one or more instances of type `T` per draw call or dispatch as represented by the `instanceCount` parameter.
/// - The buffer may contain one or more frames worth of data as represented by the `frameCount` parameter. Each frame would contain `instanceCount` instances of `T`
class GPUPassBuffer<T> {
    
    var buffer: MTLBuffer?
    var currentBufferFrameOffset: Int = 0
    var currentBufferFrameAddress: UnsafeMutableRawPointer?
    var alignedSize: Int = 0
    var frameCount: Int = 1
    var instanceCount: Int = 1
    var label: String?
    var resourceOptions: MTLResourceOptions = []
    var shaderAttributeIndex: Int
    
    /// Get a pointer to the beginning og the current frame
    var currentBufferFramePointer: UnsafeMutablePointer<T>? {
        return currentBufferFrameAddress?.assumingMemoryBound(to: T.self)
    }
    
    /// Get the total buffer size which is the size of `T` x `instanceCount` x `frameCount`
    var totalBufferSize: Int {
        return alignedSize * frameCount
    }
    
    /// Initialize with the number of instances of `T` per frame and the number of frames. Creating a `GPUPassBuffer` instance does not create the buffer. This lets you control when and how this is done. To create the buffer you can either call `initialize(withDevice device:, options:)` or you can create an `MTLBuffer` yourself and assign it ti the `buffer` property. Until a buffer is initialized, all of the pointer methods will return nil.
    /// - Parameter shaderAttributeIndex: The metal buffer attribute index. This index should correspond with the shader argument definition (i.e. `device T *myBuffer [[buffer(shaderAttributeIndex)]]`)
    /// - Parameter instanceCount: The number of instances of `T` per pass. Defaults to `1`
    /// - Parameter frameCount: The number of frames worth of data that the buffer contains. Defaults to `1`
    /// - Parameter label: A label used for helping to identify this buffer. If a label is provided, it will be assigned to the buffers label property when calling `initialize(withDevice device:, options:)`
    init(shaderAttributeIndex: Int, instanceCount: Int = 1, frameCount: Int = 1, label: String? = nil) {
        self.shaderAttributeIndex = shaderAttributeIndex
        self.instanceCount = instanceCount
        self.frameCount = frameCount
        self.label = label
    }
    
    /// Initialize a new buffer with the `MTLDevice` and `MTLResourceOptions` provided. If a buffer was previously initialized, calling this again will replace the existing buffer
    /// - Parameter device: the `MTLDevice` that will be used to create the buffer
    /// - Parameter options: the `MTLResourceOptions` that will be used to create the buffer
    func initialize(withDevice device: MTLDevice, options: MTLResourceOptions = []) {
        resourceOptions = options
        alignedSize = ((MemoryLayout<T>.stride * instanceCount) & ~0xFF) + 0x100
        buffer = device.makeBuffer(length: totalBufferSize, options: resourceOptions)
        if let label = label {
            buffer?.label = label
        }
        
    }
    
    /// Update the current frame index. When `resourceOptions` is `.storageModeShared`, this will cause subsequent calls to `currentBufferFramePointer` and `currentBufferInstancePointer(withInstanceIndex:)` to return updated pointer addresses. When `resourceOptions` is `.storageModePrivate` or `.storageModeMemoryless` access to the buffer is restricted and attempting to retrieve a pointer fails.
    /// - Parameter frameIndex: The frame index. Must be less than the frame count.
    func update(toFrame frameIndex: Int) {
        guard frameIndex < frameCount else {
            return
        }
        currentBufferFrameOffset = alignedSize * frameIndex
        if resourceOptions == .storageModeShared {
             currentBufferFrameAddress = buffer?.contents().advanced(by: currentBufferFrameOffset)
        }
    }
    
    /// Returns a pointer to the instance of the `T` object at the given inxex. This method takes into account the frame index as set by `update(toFrame:)`
    /// - Parameter instanceIndex: The index of the `T` object
    func currentBufferInstancePointer(withInstanceIndex instanceIndex: Int = 0) -> UnsafeMutablePointer<T>? {
        guard instanceIndex < instanceCount else {
            return nil
        }
        return currentBufferFramePointer?.advanced(by: instanceIndex)
    }
}
