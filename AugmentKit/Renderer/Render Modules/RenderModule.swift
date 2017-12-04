//
//  RenderModule.swift
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
import ARKit
import Metal
import MetalKit

protocol RenderModule {
    
    //
    // Setup
    //
    
    var moduleIdentifier: String { get }
    var isInitialized: Bool { get }
    // Lower layer modules are rendered first
    var renderLayer: Int { get }
    // An array of shared module identifiers that it this module will rely on in the draw phase.
    var sharedModuleIdentifiers: [String]? { get }
    
    // Initialize the buffers that will me managed and updated in this module.
    func initializeBuffers(withDevice: MTLDevice, maxInFlightBuffers: Int)
    
    // Load the data from the Model Provider.
    func loadAssets(fromModelProvider: ModelProvider?, textureLoader: MTKTextureLoader, completion: (() -> Void))
    
    // This funciton should set up the vertex descriptors, pipeline / depth state descriptors,
    // textures, etc.
    func loadPipeline(withMetalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider)
    
    //
    // Per Frame Updates
    //
    
    // The buffer index is the index into the ring on in flight buffers
    func updateBufferState(withBufferIndex: Int)
    
    // Update the buffer data
    func updateBuffers(withARFrame: ARFrame, viewportProperties: ViewportProperies)
    
    // Update the render encoder for the draw call. At the end of this method it is expected that
    // drawPrimatives or drawIndexedPrimatives is called.
    func draw(withRenderEncoder: MTLRenderCommandEncoder, sharedModules: [SharedRenderModule]?)
    
    // Called when Metal and the GPU has fully finished proccssing the commands we're encoding
    // this frame. This indicates when the dynamic buffers, that we're writing to this frame,
    // will no longer be needed by Metal and the GPU. This gets called per frame.
    func frameEncodingComplete()
    
}

// A shared render module is a render module responsible for setting up and updating
// shared buffers. Although it does have a draw() method, typically this method does
// not do anything. Instead, the module that uses this shared module is responsible
// for encoding the shared buffer and issuing the draw call
protocol SharedRenderModule: RenderModule {
    var sharedUniformBuffer: MTLBuffer? { get }
    var sharedUniformBufferOffset: Int { get }
    var sharedUniformBufferAddress: UnsafeMutableRawPointer? { get }
}
