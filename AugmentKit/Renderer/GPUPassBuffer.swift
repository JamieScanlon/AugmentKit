//
//  GPUPassBuffer.swift
//  
//
//  Created by Marvin Scanlon on 7/13/19.
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
    
    /// Get a pointer to the beginning og the current frame
    var currentBufferFramePointer: UnsafeMutablePointer<T>? {
        return currentBufferFrameAddress?.assumingMemoryBound(to: T.self)
    }
    
    /// Get the total buffer size which is the size of `T` x `instanceCount` x `frameCount`
    var totalBufferSize: Int {
        return alignedSize * frameCount
    }
    
    /// Initialize with the number of instances of `T` per frame and the number of frames. Creating a `GPUPassBuffer` instance does not create the buffer. This lets you control when and how this is done. To create the buffer you can either call `initialize(withDevice device:, options:)` or you can create an `MTLBuffer` yourself and assign it ti the `buffer` property. Until a buffer is initialized, all of the pointer methods will return nil.
    /// - Parameter instanceCount: The number of instances of `T` per pass. Defaults to `1`
    /// - Parameter frameCount: The number of frames worth of data that the buffer contains. Defaults to `1`
    /// - Parameter label: A label used for helping to identify this buffer. If a label is provided, it will be assigned to the buffers label property when calling `initialize(withDevice device:, options:)`
    init(instanceCount: Int = 1, frameCount: Int = 1, label: String? = nil) {
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
    
    /// Update the current frame index. This will cause subsequent calls to `currentBufferFramePointer` and `currentBufferInstancePointer(withInstanceIndex:)` to return updated pointer addresses.
    /// - Parameter frameIndex: The frame index. Must be less than the frame count.
    func update(toFrame frameIndex: Int) {
        guard frameIndex < frameCount else {
            return
        }
        currentBufferFrameOffset = alignedSize * frameIndex
        currentBufferFrameAddress = buffer?.contents().advanced(by: currentBufferFrameOffset)
    }
    
    /// Returns a pointer to the onstance of the `T` object at the given inxex. This method takes into account the frame index as set by `update(toFrame:)`
    /// - Parameter instanceIndex: The index of the `T` object
    func currentBufferInstancePointer(withInstanceIndex instanceIndex: Int = 0) -> UnsafeMutablePointer<T>? {
        guard instanceIndex < instanceCount else {
            return nil
        }
        return currentBufferFramePointer?.advanced(by: instanceIndex)
    }
}
