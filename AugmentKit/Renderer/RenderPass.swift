//
//  RenderPass.swift
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

// MARK: - DrawCallGroup

/// An abstraction for a collection of `DrawCall`'s. A `DrawCallGroup` helps organize a sequence of `DrawCall`'s into a logical group. Multiple `DrawCallGroup`'s can then be rendered, in order, in a single pass.
class DrawCallGroup {
    
    /// The `uuid` is usually set to match the `identifier` property of the corresponding `AKGeometricEntity`
    var uuid: UUID
    var moduleIdentifier: String?
    var numDrawCalls: Int {
        return drawCalls.count
    }
    /// The value of this property is set automatically when initializing with an array of draw calls and is `true` if any `DrawCall` uses skins. When this is false the renderer can skip steps for calculating skinned animations resulting in some efficiency gain.
    var useSkins = false
    
    /// The order of `drawCalls` is usually taken directly from the order in which the meshes are parsed from the MDLAsset.
    /// see: `ModelIOTools.meshGPUData(from asset: MDLAsset, device: MTLDevice, textureBundle: Bundle, vertexDescriptor: MDLVertexDescriptor?, frameRate: Double = 60, shaderPreference: ShaderPreference = .pbr)`
    var drawCalls = [DrawCall]()
    
    init(drawCalls: [DrawCall] = [], uuid: UUID = UUID()) {
        self.uuid = uuid
        self.drawCalls = drawCalls
        if drawCalls.first(where: {$0.usesSkins}) != nil {
            self.useSkins = true
        }
    }
    
}

extension DrawCallGroup: CustomDebugStringConvertible, CustomStringConvertible {
    
    /// :nodoc:
    var description: String {
        return debugDescription
    }
    /// :nodoc:
    var debugDescription: String {
         let myDescription = "<DrawCallGroup: \(Unmanaged.passUnretained(self).toOpaque())> uuid: \(uuid), moduleIdentifier:\(moduleIdentifier?.debugDescription ?? "None"), numDrawCalls: \(numDrawCalls), useSkins: \(useSkins)"
        return myDescription
    }
}

// MARK: - RenderPass

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
    var usesShadows = true
    
    var drawCallGroups = [DrawCallGroup]()
    
    var templateRenderPipelineDescriptor: MTLRenderPipelineDescriptor?
    var vertexDescriptorMergePolicy = MergePolicy.preferInstance
    var vertexFunctionMergePolicy = MergePolicy.preferInstance
    var fragmentFunctionMergePolicy = MergePolicy.preferInstance
    
    var depthCompareFunction: MTLCompareFunction?
    var depthCompareFunctionMergePolicy = MergePolicy.preferInstance
    var isDepthWriteEnabled = true
    var isDepthWriteEnabledMergePolicy = MergePolicy.preferInstance
    
    // Allows the render pass to filter out certain geometries for rendering. Return `false` in order to skip rendering for the given `AKGeometricEntity`
    var geometryFilterFunction: ((AKGeometricEntity?) -> Bool)?
    
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
    
    func drawCall(withRenderPipelineDescriptor renderPipelineDescriptor: MTLRenderPipelineDescriptor, depthStencilDescriptor: MTLDepthStencilDescriptor, drawData: DrawData? = nil) -> DrawCall {
        let aDrawCall = DrawCall(withDevice: device, renderPipelineDescriptor: renderPipelineDescriptor, depthStencilDescriptor: depthStencilDescriptor, cullMode: cullMode, depthBias: depthBias, drawData: drawData)
        return aDrawCall
    }
    
}
