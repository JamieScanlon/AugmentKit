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

// MARK: - DrawCall

/// Represents a draw call which is a single mesh geometry that is rendered with a Vertex / Fragment Shader. A single draw call can have many submeshes. Each submesh calls `drawIndexPrimitives`
struct DrawCall {
    
    var uuid: UUID
    var renderPipelineState: MTLRenderPipelineState
    var depthStencilState: MTLDepthStencilState?
    var cullMode: MTLCullMode = .back
    var depthBias: RenderPass.DepthBias?
    var drawData: DrawData?
    var usesSkins: Bool {
        if let myDrawData = drawData {
            return myDrawData.skins.count > 0
        } else {
            return false
        }
    }
    var vertexFunction: MTLFunction?
    var fragmentFunction: MTLFunction?
    
    init(renderPipelineState: MTLRenderPipelineState, depthStencilState: MTLDepthStencilState? = nil, cullMode: MTLCullMode = .back, depthBias: RenderPass.DepthBias? = nil, drawData: DrawData? = nil, uuid: UUID = UUID()) {
        self.uuid = uuid
        self.renderPipelineState = renderPipelineState
        self.depthStencilState = depthStencilState
        self.cullMode = cullMode
        self.depthBias = depthBias
        self.drawData = drawData
    }
    
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
    
    init(metalLibrary: MTLLibrary, renderPass: RenderPass, vertexFunctionName: String, fragmentFunctionName: String, vertexDescriptor: MTLVertexDescriptor? = nil, depthComareFunction: MTLCompareFunction = .less, depthWriteEnabled: Bool = true, cullMode: MTLCullMode = .back, depthBias: RenderPass.DepthBias? = nil, drawData: DrawData? = nil, uuid: UUID = UUID()) {
        
        let funcConstants = RenderUtilities.getFuncConstants(forDrawData: drawData)
        
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
                // Specify which shader to use based on if the model has skinned puppet suppot
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
        
        let depthStencilDescriptor = renderPass.depthStencilDescriptor(withDepthComareFunction: depthComareFunction, isDepthWriteEnabled: depthWriteEnabled)
        let myDepthStencilState: MTLDepthStencilState? = renderPass.device.makeDepthStencilState(descriptor: depthStencilDescriptor)
        
        self.uuid = uuid
        self.vertexFunction = vertFunc
        self.fragmentFunction = fragFunc
        self.renderPipelineState = renderPipelineState
        self.depthStencilState = myDepthStencilState
        self.cullMode = cullMode
        self.depthBias = depthBias
        self.drawData = drawData
    }
    
    /// Prepares the Render Command Encoder with the draw call state.
    /// You must call `prepareCommandEncoder(withCommandBuffer:)` before calling this method
    func prepareDrawCall(withRenderPass renderPass: RenderPass) {
        
        guard let renderCommandEncoder = renderPass.renderCommandEncoder else {
            return
        }
        
        renderCommandEncoder.setRenderPipelineState(renderPipelineState)
        renderCommandEncoder.setDepthStencilState(depthStencilState)
        renderCommandEncoder.setCullMode(cullMode)
        if let depthBias = depthBias {
            renderCommandEncoder.setDepthBias(depthBias.bias, slopeScale: depthBias.slopeScale, clamp: depthBias.clamp)
        }
        
    }
    
}

extension DrawCall: CustomDebugStringConvertible, CustomStringConvertible {
    
    /// :nodoc:
    var description: String {
        return debugDescription
    }
    /// :nodoc:
    var debugDescription: String {
        let myDescription = "<DrawCall: > uuid: \(uuid), renderPipelineState:\(String(describing: renderPipelineState.debugDescription)), depthStencilState:\(depthStencilState?.debugDescription ?? "None"), cullMode: \(cullMode), usesSkins: \(usesSkins), vertexFunction: \(vertexFunction?.debugDescription ?? "None"), fragmentFunction: \(fragmentFunction?.debugDescription ?? "None")"
        return myDescription
    }
}
