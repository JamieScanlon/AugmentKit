//
//  SharedBuffersRenderModule.swift
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
import ARKit
import AugmentKitShader
import MetalKit

// Module for creating and updating the shared data used across all render elements
class SharedBuffersRenderModule: SharedRenderModule {
    
    static var identifier = "SharedBuffersRenderModule"
    
    //
    // Setup
    //
    
    var moduleIdentifier: String {
        return SharedBuffersRenderModule.identifier
    }
    var renderLayer: Int {
        return -1
    }
    var state: ShaderModuleState = .uninitialized
    var sharedModuleIdentifiers: [String]? = nil
    var renderDistance: Double = 500
    var errors = [AKError]()
    
    // MARK: - SharedRenderModule
        
    var sharedUniformsBuffer: GPUPassBuffer<SharedUniforms>?
    
    // MARK: - RenderModule
    
    func initializeBuffers(withDevice device: MTLDevice, maxInFlightFrames: Int, maxInstances: Int) {
        
        state = .initializing
        sharedUniformsBuffer?.initialize(withDevice: device)
        
    }
    
    func loadAssets(forGeometricEntities: [AKGeometricEntity], fromModelProvider: ModelProvider?, textureLoader: MTKTextureLoader, completion: (() -> Void)) {
        completion()
    }
    
    func loadPipeline(withModuleEntities: [AKEntity], metalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider, textureBundle: Bundle, renderPass: RenderPass? = nil, completion: (([DrawCallGroup]) -> Void)? = nil) {
        state = .ready
        completion?([])
    }
    
    //
    // Per Frame Updates
    //
    
    func updateBufferState(withBufferIndex bufferIndex: Int) {
        sharedUniformsBuffer?.update(toFrame: bufferIndex)
    }
    
    func updateBuffers(withModuleEntities: [AKEntity], cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties, shadowProperties: ShadowProperties, argumentBufferProperties: ArgumentBufferProperties, forRenderPass renderPass: RenderPass) {
        let uniforms = sharedUniformsBuffer?.currentBufferInstancePointer()
        uniforms?.pointee.viewMatrix = cameraProperties.arCamera.viewMatrix(for: cameraProperties.orientation)
        uniforms?.pointee.projectionMatrix = cameraProperties.arCamera.projectionMatrix(for: cameraProperties.orientation, viewportSize: cameraProperties.viewportSize, zNear: 0.001, zFar: CGFloat(renderDistance))
        uniforms?.pointee.useDepth = cameraProperties.useDepth ? 1 : 0
    }
    
    func draw(withRenderPass renderPass: RenderPass, sharedModules: [SharedRenderModule]?) {
        // Since this is a shared module, it is up to the module that depends on it to setup
        // the vertex and fragment shaders and issue the draw calls
    }
    
    func frameEncodingComplete(renderPasses: [RenderPass]) {
        //
    }
    
    //
    // Util
    //
    
    func recordNewError(_ akError: AKError) {
        errors.append(akError)
    }
}
