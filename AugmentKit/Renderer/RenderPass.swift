//
//  RenderPass.swift
//  AugmentKit
//
//  Created by Marvin Scanlon on 10/28/18.
//  Copyright © 2018 TenthLetterMade. All rights reserved.
//

import Foundation

/// Represents a draw call which is a single mesh geometry that is rendered with a Vertex / Fragment Shader. A single draw call can have many submeshes. Each submesh calls `drawIndexPrimitives`
struct DrawCall {
    
    var uuid: UUID
    var renderPipelineState: MTLRenderPipelineState
    var depthStencilState: MTLDepthStencilState?
    var cullMode: MTLCullMode = .back
    var depthBias: RenderPass.DepthBias?
    
    init(renderPipelineState: MTLRenderPipelineState, depthStencilState: MTLDepthStencilState? = nil, cullMode: MTLCullMode = .back, depthBias: RenderPass.DepthBias? = nil, uuid: UUID = UUID()) {
        self.uuid = uuid
        self.renderPipelineState = renderPipelineState
        self.depthStencilState = depthStencilState
        self.cullMode = cullMode
        self.depthBias = depthBias
    }
    
    init(withDevice device: MTLDevice, renderPipelineDescriptor: MTLRenderPipelineDescriptor, depthStencilDescriptor: MTLDepthStencilDescriptor? = nil, cullMode: MTLCullMode = .back, depthBias: RenderPass.DepthBias? = nil) {
        
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
        self.init(renderPipelineState: myPipelineState, depthStencilState: myDepthStencilState, cullMode: cullMode, depthBias: depthBias)
        
    }
    
    /// Prepares the Render Command Encoder with the draw call state.
    /// You must call `prepareRenderCommandEncoder(withCommandBuffer:)` before calling this method
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

/// An abstraction for a collection of `DrawCall`'s. A `DrawCallGroup` helps organize a sequence of `DrawCall`'s into a logical group. Multiple `DrawCallGroup`'s can then be rendered, in order, in a single pass.
class DrawCallGroup {
    
    var uuid: UUID
    var moduleIdentifier: String?
    var numDrawCalls: Int {
        return drawCalls.count
    }
    var drawCalls = [DrawCall]()
    
    init(drawCalls: [DrawCall] = [], uuid: UUID = UUID()) {
        self.uuid = uuid
        self.drawCalls = drawCalls
    }
    
}

class RenderPass {
    
    enum MergePolicy {
        case preferTemplate
        case preferInstance
    }
    
    struct DepthBias {
        var bias: Float
        var slopeScale: Float
        var clamp: Float
    }
    
    var renderPassDescriptor: MTLRenderPassDescriptor?
    fileprivate(set) var renderCommandEncoder: MTLRenderCommandEncoder?
    
    var device: MTLDevice
    var name: String?
    var uuid: UUID
    
    var usesGeomentry = true
    var usesLighting = true
    var usesSharedBuffer = true
    var usesEnvironment = true
    var usesEffects = true
    var usesCameraOutput = true
    
    var drawCallGroups = [DrawCallGroup]()
    
    var templateRenderPipelineDescriptor: MTLRenderPipelineDescriptor?
    var vertexDescriptorMergePolicy = MergePolicy.preferInstance
    var vertexFunctionMergePolicy = MergePolicy.preferInstance
    var fragmentFunctionMergePolicy = MergePolicy.preferInstance
    
    var depthCompareFunction: MTLCompareFunction?
    var depthCompareFunctionMergePolicy = MergePolicy.preferInstance
    var isDepthWriteEnabled = true
    var isDepthWriteEnabledMergePolicy = MergePolicy.preferInstance
    
    // The following are used to create DrawCall objects
    var cullMode: MTLCullMode = .back
    var depthBias: DepthBias?
    
    init(withDevice device: MTLDevice, renderPassDescriptor: MTLRenderPassDescriptor? = nil, uuid: UUID = UUID()) {
        self.device = device
        self.renderPassDescriptor = renderPassDescriptor
        self.uuid = uuid
    }
    
    func prepareRenderCommandEncoder(withCommandBuffer commandBuffer: MTLCommandBuffer) {
        
        guard let renderPassDescriptor = renderPassDescriptor else {
            return
        }
        
        let commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        commandEncoder?.label = name
        
        renderCommandEncoder = commandEncoder
        
    }
    
    /// Create a `MTLRenderPipelineDescriptor` configured for this RenderPass
    /// The `vertexDescriptor`, `vertexFunction`, and `fragmentFunction` properties will only get overriden if the corresponding `MergePolicy`'s are `.preferInstance`
    func renderPipelineDescriptor(withVertexDescriptor vertexDescriptor: MTLVertexDescriptor? = nil, vertexFunction: MTLFunction? = nil, fragmentFunction: MTLFunction? = nil) -> MTLRenderPipelineDescriptor? {
        
        guard let templateRenderPipelineDescriptor = templateRenderPipelineDescriptor else {
            return nil
        }
        
        if usesGeomentry {
            if case .preferInstance = vertexDescriptorMergePolicy {
                templateRenderPipelineDescriptor.vertexDescriptor = vertexDescriptor
            }
            if case .preferInstance = vertexFunctionMergePolicy {
                templateRenderPipelineDescriptor.vertexFunction = vertexFunction
            }
        } else {
            templateRenderPipelineDescriptor.vertexDescriptor = nil
            templateRenderPipelineDescriptor.vertexFunction = nil
        }
        if usesLighting {
            if case .preferInstance = fragmentFunctionMergePolicy {
                templateRenderPipelineDescriptor.fragmentFunction = fragmentFunction
            }
        } else {
            templateRenderPipelineDescriptor.fragmentFunction = nil
        }
        
        return templateRenderPipelineDescriptor
        
    }
    
    /// Create a `MTLDepthStencilDescriptor` configured for this RenderPass
    func depthStencilDescriptor(withDepthComareFunction aDepthCompareFunction: MTLCompareFunction? = nil, isDepthWriteEnabled instanceIsDepthWriteEnabled: Bool? = nil) -> MTLDepthStencilDescriptor {
        let depthStateDescriptor = MTLDepthStencilDescriptor()
        depthStateDescriptor.label = name
        if case .preferInstance = depthCompareFunctionMergePolicy {
            if let aDepthCompareFunction = aDepthCompareFunction {
                depthStateDescriptor.depthCompareFunction =  aDepthCompareFunction
            }
        } else {
            if let depthCompareFunction = depthCompareFunction {
                depthStateDescriptor.depthCompareFunction =  depthCompareFunction
            } else if let aDepthCompareFunction = aDepthCompareFunction {
                depthStateDescriptor.depthCompareFunction =  aDepthCompareFunction
            }
        }
        if case .preferInstance = isDepthWriteEnabledMergePolicy {
            if let instanceIsDepthWriteEnabled = instanceIsDepthWriteEnabled {
                depthStateDescriptor.isDepthWriteEnabled = instanceIsDepthWriteEnabled
            } else {
                depthStateDescriptor.isDepthWriteEnabled = isDepthWriteEnabled
            }
        } else {
            depthStateDescriptor.isDepthWriteEnabled = isDepthWriteEnabled
        }
        return depthStateDescriptor
    }
    
    func drawCall(withRenderPipelineDescriptor renderPipelineDescriptor: MTLRenderPipelineDescriptor, depthStencilDescriptor: MTLDepthStencilDescriptor) -> DrawCall {
        return DrawCall(withDevice: device, renderPipelineDescriptor: renderPipelineDescriptor, depthStencilDescriptor: depthStencilDescriptor, cullMode: cullMode, depthBias: depthBias)
    }
    
}
