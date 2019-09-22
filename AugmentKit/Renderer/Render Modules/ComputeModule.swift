//
//  ComputeModule.swift
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
import simd
import AugmentKitShader

// MARK: - ComputeModule

/// A module to perform a compute function
protocol ComputeModule: ShaderModule {
    
    associatedtype Out
    
    //
    // Bootstrap
    //
    
    /// After this function is called, The Compute Pass Desciptors, Textures, Buffers, Compute Pipeline State Descriptors should all be set up.
    func loadPipeline(withMetalLibrary metalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider, textureBundle: Bundle, forComputePass computePass: ComputePass<Out>?) -> ThreadGroup?
    
    //
    // Per Frame Updates
    //
    
    /// Update and dispatch the command encoder. At the end of this method it is expected that `dispatchThreads` or dispatchThreadgroups` is called.
    func dispatch(withComputePass computePass: ComputePass<Out>?, sharedModules: [SharedRenderModule]?)
}

/// A `ComputePass` that is part of a render pipeline and used to prepare data for subsequent draw calls
protocol PreRenderComputeModule: ComputeModule where Self.Out == PrecalculatedParameters {
    
    //
    // Per Frame Updates
    //
    
    /// Update the buffer(s) data from information about the render
    func prepareToDraw(withAllEntities: [AKEntity], cameraProperties: CameraProperties, environmentProperties: EnvironmentProperties, shadowProperties: ShadowProperties, computePass: ComputePass<Out>, renderPass: RenderPass?)
    
}

extension PreRenderComputeModule {
    
    // MARK: Util
    
    func getRGB(from colorTemperature: CGFloat) -> SIMD3<Float> {
        
        let temp = Float(colorTemperature) / 100
        
        var red: Float = 127
        var green: Float = 127
        var blue: Float = 127
        
        if temp <= 66 {
            red = 255
            green = temp
            green = 99.4708025861 * log(green) - 161.1195681661
            if temp <= 19 {
                blue = 0
            } else {
                blue = temp - 10
                blue = 138.5177312231 * log(blue) - 305.0447927307
            }
        } else {
            red = temp - 60
            red = 329.698727446 * pow(red, -0.1332047592)
            green = temp - 60
            green = 288.1221695283 * pow(green, -0.0755148492 )
            blue = 255
        }
        
        let clamped = clamp(SIMD3<Float>(red, green, blue), min: 0, max: 255) / 255
        return SIMD3<Float>(clamped.x, clamped.y, clamped.z)
        
    }
}

//
// Type Erasure
//

private class _AnyComputeModuleBase<Out>: ComputeModule {

    init() {
        guard type(of: self) != _AnyComputeModuleBase.self else {
            fatalError("_AnyComputeModuleBase<Out> instances can not be created; create a subclass instance instead")
        }
    }
    
    var moduleIdentifier: String {
        fatalError("Must override")
    }
    
    var state: ShaderModuleState {
        fatalError("Must override")
    }
    
    var renderLayer: Int {
        fatalError("Must override")
    }
    
    var errors: [AKError] {
        get {
            fatalError("Must override")
        }
        set {
            fatalError("Must override")
        }
    }
    
    var sharedModuleIdentifiers: [String]? {
        fatalError("Must override")
    }
    
    func initializeBuffers(withDevice: MTLDevice, maxInFlightFrames: Int, maxInstances: Int) {
        fatalError("Must override")
    }
    
    func updateBufferState(withBufferIndex: Int) {
        fatalError("Must override")
    }
    
    func frameEncodingComplete(renderPasses: [RenderPass]) {
        fatalError("Must override")
    }
    
    func recordNewError(_ akError: AKError) {
        fatalError("Must override")
    }
    
    func loadPipeline(withMetalLibrary metalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider, textureBundle: Bundle, forComputePass computePass: ComputePass<Out>?) -> ThreadGroup? {
        fatalError("Must override")
    }
    
    func dispatch(withComputePass computePass: ComputePass<Out>?, sharedModules: [SharedRenderModule]?) {
        fatalError("Must override")
    }
}

private final class _AnyComputeModuleBox<Concrete: ComputeModule>: _AnyComputeModuleBase<Concrete.Out> {
    // variable used since we're calling mutating functions
    var concrete: Concrete
    
    init(_ concrete: Concrete) {
        self.concrete = concrete
    }
    
    // MARK: Trampoline variables and functions forward along to base
    
    override var moduleIdentifier: String {
        return concrete.moduleIdentifier
    }
    
    override var state: ShaderModuleState {
        return concrete.state
    }
    
    override var renderLayer: Int {
        return concrete.renderLayer
    }
    
    override var errors: [AKError] {
        get {
            return concrete.errors
        }
        set {
            concrete.errors = newValue
        }
    }
    
    override var sharedModuleIdentifiers: [String]? {
        return concrete.sharedModuleIdentifiers
    }
    
    override func initializeBuffers(withDevice device: MTLDevice, maxInFlightFrames: Int, maxInstances: Int) {
        concrete.initializeBuffers(withDevice: device, maxInFlightFrames: maxInFlightFrames, maxInstances: maxInstances)
    }
    
    override func updateBufferState(withBufferIndex bufferIndex: Int) {
        concrete.updateBufferState(withBufferIndex: bufferIndex)
    }
    
    override func frameEncodingComplete(renderPasses: [RenderPass]) {
        concrete.frameEncodingComplete(renderPasses: renderPasses)
    }
    
    override func recordNewError(_ akError: AKError) {
        concrete.recordNewError(akError)
    }
    
    override func loadPipeline(withMetalLibrary metalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider, textureBundle: Bundle, forComputePass computePass: ComputePass<Out>?) -> ThreadGroup? {
        concrete.loadPipeline(withMetalLibrary: metalLibrary, renderDestination: renderDestination, textureBundle: textureBundle, forComputePass: computePass)
    }
    
    override func dispatch(withComputePass computePass: ComputePass<Out>?, sharedModules: [SharedRenderModule]?) {
        concrete.dispatch(withComputePass: computePass, sharedModules: sharedModules)
    }
}

/**
 A type erased `ComputeModule`
 */
final class AnyComputeModule<Out>: ComputeModule {
    private let box: _AnyComputeModuleBase<Out>
    
    /**
     Initializer takes a concrete implementation
     */
    init<Concrete: ComputeModule>(_ concrete: Concrete) where Concrete.Out == Out {
        box = _AnyComputeModuleBox(concrete)
    }
    
    var moduleIdentifier: String {
        return box.moduleIdentifier
    }
    
    var state: ShaderModuleState {
        return box.state
    }
    
    var renderLayer: Int {
        return box.renderLayer
    }
    
    var errors: [AKError] {
        get {
            return box.errors
        }
        set {
            box.errors = newValue
        }
    }
    
    var sharedModuleIdentifiers: [String]? {
        return box.sharedModuleIdentifiers
    }
    
    func initializeBuffers(withDevice device: MTLDevice, maxInFlightFrames: Int, maxInstances: Int) {
        box.initializeBuffers(withDevice: device, maxInFlightFrames: maxInFlightFrames, maxInstances: maxInstances)
    }
    
    func updateBufferState(withBufferIndex bufferIndex: Int) {
        box.updateBufferState(withBufferIndex: bufferIndex)
    }
    
    func frameEncodingComplete(renderPasses: [RenderPass]) {
        box.frameEncodingComplete(renderPasses: renderPasses)
    }
    
    func recordNewError(_ akError: AKError) {
        box.recordNewError(akError)
    }
    
    func loadPipeline(withMetalLibrary metalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider, textureBundle: Bundle, forComputePass computePass: ComputePass<Out>?) -> ThreadGroup? {
        return box.loadPipeline(withMetalLibrary: metalLibrary, renderDestination: renderDestination, textureBundle: textureBundle, forComputePass: computePass)
    }
    
    func dispatch(withComputePass computePass: ComputePass<Out>?, sharedModules: [SharedRenderModule]?) {
        box.dispatch(withComputePass: computePass, sharedModules: sharedModules)
    }
    
}

