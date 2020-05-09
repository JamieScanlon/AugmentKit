//
//  DrawCall.swift
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
import AugmentKitShader

// MARK: - DrawCall

/// Represents a draw call which is a single mesh geometry that is rendered with a Vertex / Fragment Shader. A single draw call can have many submeshes. Each submesh calls `drawIndexPrimitives`
struct DrawCall {
    
    var uuid: UUID
    var renderPipelineState: MTLRenderPipelineState {
        guard qualityRenderPipelineStates.count > 0 else {
            fatalError("Attempting to fetch the `renderPipelineState` property before the render pipelines states have not been initialized")
        }
        return qualityRenderPipelineStates[0]
    }
    var qualityRenderPipelineStates = [MTLRenderPipelineState]()
    var depthStencilState: MTLDepthStencilState?
    var cullMode: MTLCullMode = .back
    var depthBias: RenderPass.DepthBias?
    var drawData: DrawData?
    var usesSkeleton: Bool {
        if let myDrawData = drawData {
            return myDrawData.skeleton != nil
        } else {
            return false
        }
    }
    var vertexFunction: MTLFunction? {
        guard qualityVertexFunctions.count > 0 else {
            return nil
        }
        return qualityVertexFunctions[0]
    }
    var qualityVertexFunctions = [MTLFunction]()
    var fragmentFunction: MTLFunction? {
        guard qualityFragmentFunctions.count > 0 else {
            return nil
        }
        return qualityFragmentFunctions[0]
    }
    var qualityFragmentFunctions = [MTLFunction]()
    
    /// Create a new `DralCall`
    /// - Parameters:
    ///   - renderPipelineState: A render pipeline state used for the command encoder
    ///   - depthStencilState: The depth stencil state used for the command encoder
    ///   - cullMode: The `cullMode` property that will be used for the render encoder
    ///   - depthBias: The optional `depthBias` property that will be used for the render encoder
    ///   - drawData: The draw call data
    ///   - uuid: An unique identifier for this draw call
    init(renderPipelineState: MTLRenderPipelineState, depthStencilState: MTLDepthStencilState? = nil, cullMode: MTLCullMode = .back, depthBias: RenderPass.DepthBias? = nil, drawData: DrawData? = nil, uuid: UUID = UUID()) {
        self.uuid = uuid
        self.qualityRenderPipelineStates.append(renderPipelineState)
        self.depthStencilState = depthStencilState
        self.cullMode = cullMode
        self.depthBias = depthBias
        self.drawData = drawData
    }
    
    /// Create a new `DralCall`
    /// - Parameters:
    ///   - qualityRenderPipelineStates: An array of render pipeline states for each quality level. The index of the render pipeline state will be it's quality level. the number of `qualityRenderPipelineStates` determines the number of distinct Levels of Detail. The descriptor at 0 should be the **highest** quality state with the quality level reducing as the index gets higher.
    ///   - depthStencilState: The depth stencil state used for the command encoder
    ///   - cullMode: The `cullMode` property that will be used for the render encoder
    ///   - depthBias: The optional `depthBias` property that will be used for the render encoder
    ///   - drawData: The draw call data
    ///   - uuid: An unique identifier for this draw call
    init(qualityRenderPipelineStates: [MTLRenderPipelineState], depthStencilState: MTLDepthStencilState? = nil, cullMode: MTLCullMode = .back, depthBias: RenderPass.DepthBias? = nil, drawData: DrawData? = nil, uuid: UUID = UUID()) {
        self.uuid = uuid
        self.qualityRenderPipelineStates = qualityRenderPipelineStates
        self.qualityRenderPipelineStates.append(renderPipelineState)
        self.depthStencilState = depthStencilState
        self.cullMode = cullMode
        self.depthBias = depthBias
        self.drawData = drawData
    }
    
    /// Create a new `DralCall`
    /// - Parameters:
    ///   - device: The metal device used to create the render pipeline state
    ///   - renderPipelineDescriptor: The render pass descriptor used to create the render pipeline state
    ///   - depthStencilDescriptor: The depth stencil descriptor used to make the depth stencil state
    ///   - cullMode: The `cullMode` property that will be used for the render encoder
    ///   - depthBias: The optional `depthBias` property that will be used for the render encoder
    ///   - drawData: The draw call data
    init(withDevice device: MTLDevice, renderPipelineDescriptor: MTLRenderPipelineDescriptor, depthStencilDescriptor: MTLDepthStencilDescriptor? = nil, cullMode: MTLCullMode = .back, depthBias: RenderPass.DepthBias? = nil, drawData: DrawData? = nil) {
        
        let myPipelineState: MTLRenderPipelineState = {
            do {
                return try device.makeRenderPipelineState(descriptor: renderPipelineDescriptor)
            } catch let error {
                print("failed to create render pipeline state for the device. ERROR: \(error)")
                let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: nil, underlyingError: error))))
                NotificationCenter.default.post(name: .abortedDueToErrors, object: nil, userInfo: ["errors": [newError]])
                fatalError()
            }
        }()
        let myDepthStencilState: MTLDepthStencilState? = {
            if let depthStencilDescriptor = depthStencilDescriptor {
                return device.makeDepthStencilState(descriptor: depthStencilDescriptor)
            } else {
                return nil
            }
        }()
        self.init(renderPipelineState: myPipelineState, depthStencilState: myDepthStencilState, cullMode: cullMode, depthBias: depthBias, drawData: drawData)
        
    }
    
    /// Create a new `DralCall`
    /// - Parameters:
    ///   - device: The metal device used to create the render pipeline state
    ///   - qualityRenderPipelineDescriptors: An array of render pipeline descriptors used to create render pipeline states for each quality level. The index of the render pipeline descriptor will be it's quality level. the number of `qualityRenderPipelineDescriptors` determines the number of distinct Levels of Detail. The descriptor at 0 should be the **highest** quality descriptor with the quality level reducing as the index gets higher.
    ///   - depthStencilDescriptor: The depth stencil descriptor used to make the depth stencil state
    ///   - cullMode: The `cullMode` property that will be used for the render encoder
    ///   - depthBias: The optional `depthBias` property that will be used for the render encoder
    ///   - drawData: The draw call data
    init(withDevice device: MTLDevice, qualityRenderPipelineDescriptors: [MTLRenderPipelineDescriptor], depthStencilDescriptor: MTLDepthStencilDescriptor? = nil, cullMode: MTLCullMode = .back, depthBias: RenderPass.DepthBias? = nil, drawData: DrawData? = nil) {
        
        let myPipelineStates: [MTLRenderPipelineState] = qualityRenderPipelineDescriptors.map {
            do {
                return try device.makeRenderPipelineState(descriptor: $0)
            } catch let error {
                print("failed to create render pipeline state for the device. ERROR: \(error)")
                let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: nil, underlyingError: error))))
                NotificationCenter.default.post(name: .abortedDueToErrors, object: nil, userInfo: ["errors": [newError]])
                fatalError()
            }
        }
        let myDepthStencilState: MTLDepthStencilState? = {
            if let depthStencilDescriptor = depthStencilDescriptor {
                return device.makeDepthStencilState(descriptor: depthStencilDescriptor)
            } else {
                return nil
            }
        }()
        self.init(qualityRenderPipelineStates: myPipelineStates, depthStencilState: myDepthStencilState, cullMode: cullMode, depthBias: depthBias, drawData: drawData)
        
    }
    
    /// All shader function and pipeline states are created during initialization so it is reccommended that these objects be created on an asynchonous thread
    /// - Parameters:
    ///   - metalLibrary: The metal library for the compiled render functions
    ///   - renderPass: The `RenderPass` associated with this draw call
    ///   - vertexFunctionName: The name of the vertex function that will be created.
    ///   - fragmentFunctionName: The name of the fragment function that will be created.
    ///   - vertexDescriptor: The vertex decriptor that will be used for the render pipeline state
    ///   - depthComareFunction: The depth compare function that will be used for the depth stencil state
    ///   - depthWriteEnabled: The `depthWriteEnabled` flag that will be used for the depth stencil state
    ///   - cullMode: The `cullMode` property that will be used for the render encoder
    ///   - depthBias: The optional `depthBias` property that will be used for the render encoder
    ///   - drawData: The draw call data
    ///   - uuid: An unique identifier for this draw call
    ///   - numQualityLevels: When using Level Of Detail optimizations in the renderer, this parameter indecates the number of distinct levels and also determines how many pipeline states are set up. This value must be greater than 0
    init(metalLibrary: MTLLibrary, renderPass: RenderPass, vertexFunctionName: String, fragmentFunctionName: String, vertexDescriptor: MTLVertexDescriptor? = nil, depthComareFunction: MTLCompareFunction = .less, depthWriteEnabled: Bool = true, cullMode: MTLCullMode = .back, depthBias: RenderPass.DepthBias? = nil, drawData: DrawData? = nil, uuid: UUID = UUID(), numQualityLevels: Int = 1) {
        
        guard numQualityLevels > 0 else {
            fatalError("Invalid number of quality levels provided. Must be at least 1")
        }
        
        var myPipelineStates = [MTLRenderPipelineState]()
        var myVertexFunctions = [MTLFunction]()
        var myFragmentFunctions = [MTLFunction]()
        
        for level in 0..<numQualityLevels {
            
            let funcConstants = RenderUtilities.getFuncConstants(forDrawData: drawData, qualityLevel: QualityLevel(rawValue: UInt32(level)))
            
            let fragFunc: MTLFunction = {
                do {
                    return try metalLibrary.makeFunction(name: fragmentFunctionName, constantValues: funcConstants)
                } catch let error {
                    print("Failed to create fragment function for pipeline state descriptor, error \(error)")
                    let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: nil, underlyingError: error))))
                    NotificationCenter.default.post(name: .abortedDueToErrors, object: nil, userInfo: ["errors": [newError]])
                    fatalError()
                }
            }()
            
            let vertFunc: MTLFunction = {
                do {
                    // Specify which shader to use based on if the model has skinned skeleton suppot
                    return try metalLibrary.makeFunction(name: vertexFunctionName, constantValues: funcConstants)
                } catch let error {
                    print("Failed to create vertex function for pipeline state descriptor, error \(error)")
                    let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: nil, underlyingError: error))))
                    NotificationCenter.default.post(name: .abortedDueToErrors, object: nil, userInfo: ["errors": [newError]])
                    fatalError()
                }
            }()
            
            guard let renderPipelineStateDescriptor = renderPass.renderPipelineDescriptor(withVertexDescriptor: vertexDescriptor, vertexFunction: vertFunc, fragmentFunction: fragFunc) else {
                print("failed to create render pipeline state descriptorfor the device.")
                let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: nil, underlyingError: nil))))
                NotificationCenter.default.post(name: .abortedDueToErrors, object: nil, userInfo: ["errors": [newError]])
                fatalError()
            }
            
            let renderPipelineState: MTLRenderPipelineState = {
                do {
                    return try renderPass.device.makeRenderPipelineState(descriptor: renderPipelineStateDescriptor)
                } catch let error {
                    print("failed to create render pipeline state for the device. ERROR: \(error)")
                    let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: nil, underlyingError: error))))
                    NotificationCenter.default.post(name: .abortedDueToErrors, object: nil, userInfo: ["errors": [newError]])
                    fatalError()
                }
            }()
            
            myVertexFunctions.append(vertFunc)
            myFragmentFunctions.append(fragFunc)
            myPipelineStates.append(renderPipelineState)
        }
        
        let depthStencilDescriptor = renderPass.depthStencilDescriptor(withDepthComareFunction: depthComareFunction, isDepthWriteEnabled: depthWriteEnabled)
        let myDepthStencilState: MTLDepthStencilState? = renderPass.device.makeDepthStencilState(descriptor: depthStencilDescriptor)
        
        self.uuid = uuid
        self.qualityVertexFunctions = myVertexFunctions
        self.qualityFragmentFunctions = myFragmentFunctions
        self.qualityRenderPipelineStates = myPipelineStates
        self.depthStencilState = myDepthStencilState
        self.cullMode = cullMode
        self.depthBias = depthBias
        self.drawData = drawData
    }
    
    /// Prepares the Render Command Encoder with the draw call state.
    /// You must call `prepareCommandEncoder(withCommandBuffer:)` before calling this method
    /// - Parameters:
    ///   - renderPass: The `RenderPass` associated with this draw call
    ///   - qualityLevel:  Indicates at which texture quality the pass will be rendered. a `qualityLevel` of 0 indicates **highest** quality. The higher the number the lower the quality. The level must be less than the number of `qualityRenderPasses` or `numQualityLevels` passed in durring initialization
    func prepareDrawCall(withRenderPass renderPass: RenderPass, qualityLevel: Int = 0) {
        
        guard let renderCommandEncoder = renderPass.renderCommandEncoder else {
            return
        }
        
        renderCommandEncoder.setRenderPipelineState(renderPipelineState(for: qualityLevel))
        renderCommandEncoder.setDepthStencilState(depthStencilState)
        renderCommandEncoder.setCullMode(cullMode)
        if let depthBias = depthBias {
            renderCommandEncoder.setDepthBias(depthBias.bias, slopeScale: depthBias.slopeScale, clamp: depthBias.clamp)
        }
        
    }
    
    /// Returns the `MTLRenderPipelineState` for the given quality level
    /// - Parameter qualityLevel:  Indicates at which texture quality the pass will be rendered. a `qualityLevel` of 0 indicates **highest** quality. The higher the number the lower the quality. The level must be less than the number of `qualityRenderPasses` or `numQualityLevels` passed in durring initialization
    func renderPipelineState(for qualityLevel: Int = 0 ) -> MTLRenderPipelineState {
        guard qualityLevel < qualityRenderPipelineStates.count else {
            fatalError("The qualityLevel must be less than the number of `qualityRenderPasses` or `numQualityLevels` passed in durring initialization")
        }
        return qualityRenderPipelineStates[qualityLevel]
    }
    
    func markTexturesAsVolitile() {
        drawData?.markTexturesAsVolitile()
    }
    
    func markTexturesAsNonVolitile() {
        drawData?.markTexturesAsNonVolitile()
    }
    
}

extension DrawCall: CustomDebugStringConvertible, CustomStringConvertible {
    
    /// :nodoc:
    var description: String {
        return debugDescription
    }
    /// :nodoc:
    var debugDescription: String {
        let myDescription = "<DrawCall: > uuid: \(uuid), renderPipelineState:\(String(describing: renderPipelineState.debugDescription)), depthStencilState:\(depthStencilState?.debugDescription ?? "None"), cullMode: \(cullMode), usesSkeleton: \(usesSkeleton), vertexFunction: \(vertexFunction?.debugDescription ?? "None"), fragmentFunction: \(fragmentFunction?.debugDescription ?? "None")"
        return myDescription
    }
}
