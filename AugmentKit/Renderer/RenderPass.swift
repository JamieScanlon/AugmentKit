//
//  RenderPass.swift
//  AugmentKit
//
//  Created by Marvin Scanlon on 10/28/18.
//  Copyright © 2018 TenthLetterMade. All rights reserved.
//

import Foundation

class RenderPass {
    
    /// Represents a draw call which is a single mesh geometry that is rendered with a Vertex / Fragment Shader. A single draw call can have many submeshes. Each submesh calls `drawIndexPrimitives`
    struct DrawCall {
        var uuid: UUID
        var renderPipelineState: MTLRenderPipelineState
        var depthStencilState: MTLDepthStencilState?
        var cullMode: MTLCullMode = .back
        
        init(renderPipelineState: MTLRenderPipelineState, depthStencilState: MTLDepthStencilState? = nil, cullMode: MTLCullMode = .back, uuid: UUID = UUID()) {
            self.uuid = uuid
            self.renderPipelineState = renderPipelineState
            self.depthStencilState = depthStencilState
            self.cullMode = cullMode
        }
        
        // TODO: Depth Bias
        init(withDevice device: MTLDevice, renderPipelineDescriptor: MTLRenderPipelineDescriptor, depthStencilDescriptor: MTLDepthStencilDescriptor? = nil, cullMode: MTLCullMode = .back) {
            
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
            self.init(renderPipelineState: myPipelineState, depthStencilState: myDepthStencilState, cullMode: cullMode)
            
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
            // TODO: DepthBias
//        renderCommandEncoder.setDepthBias(0.015, slopeScale:7, clamp:0.02)
            
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
    
    enum MergePolicy {
        case preferTemplate
        case preferInstance
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
    var isDepthWriteEnabled = true
    
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
    
    func depthStencilDescriptor(withDepthComareFunction aDepthCompareFunction: MTLCompareFunction? = nil) -> MTLDepthStencilDescriptor? {
        let depthStateDescriptor = MTLDepthStencilDescriptor()
        depthStateDescriptor.label = name
        if let depthCompareFunction = depthCompareFunction {
            depthStateDescriptor.depthCompareFunction =  depthCompareFunction
        } else if let aDepthCompareFunction = aDepthCompareFunction {
            depthStateDescriptor.depthCompareFunction =  aDepthCompareFunction
        }
        depthStateDescriptor.isDepthWriteEnabled = isDepthWriteEnabled
        return depthStateDescriptor
    }
    
    
}
