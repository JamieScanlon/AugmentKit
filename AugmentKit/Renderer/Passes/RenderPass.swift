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

// MARK: - RenderPass

class RenderPass {
    
    enum MergePolicy {
        case preferTemplate
        case preferInstance
    }
    
    struct DepthBias: CustomStringConvertible, CustomDebugStringConvertible {
        var description: String {
            return debugDescription
        }
        
        var debugDescription: String {
            let myDescription = "DepthBias - bias: \(bias), slopeScale: \(slopeScale), clamp: \(clamp)"
            return myDescription
        }
        
        var bias: Float
        var slopeScale: Float
        var clamp: Float
    }
    
    var renderPassDescriptor: MTLRenderPassDescriptor?
    fileprivate(set) var renderCommandEncoder: MTLRenderCommandEncoder?
    
    var device: MTLDevice
    var name: String?
    var uuid: UUID
    
    var usesGeometry = true
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
    
    // Allows the render pass to filter out certain draw call groups for rendering. Return `false` in order to skip rendering for the given `DrawCallGroup`
    var drawCallGroupFilterFunction: ((DrawCallGroup?) -> Bool)?
    
    // The following are used to create DrawCall objects
    var cullMode: MTLCullMode = .back
    var depthBias: DepthBias?
    
    init(withDevice device: MTLDevice, renderPassDescriptor: MTLRenderPassDescriptor? = nil, uuid: UUID = UUID()) {
        self.device = device
        self.renderPassDescriptor = renderPassDescriptor
        self.uuid = uuid
    }
    
    func prepareCommandEncoder(withCommandBuffer commandBuffer: MTLCommandBuffer) {
        
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
        
        let renderPassDescriptor = MTLRenderPipelineDescriptor()
        renderPassDescriptor.depthAttachmentPixelFormat = templateRenderPipelineDescriptor.depthAttachmentPixelFormat
        renderPassDescriptor.isAlphaToCoverageEnabled = templateRenderPipelineDescriptor.isAlphaToCoverageEnabled
        renderPassDescriptor.isAlphaToOneEnabled = templateRenderPipelineDescriptor.isAlphaToOneEnabled
        renderPassDescriptor.isRasterizationEnabled = templateRenderPipelineDescriptor.isRasterizationEnabled
        renderPassDescriptor.isTessellationFactorScaleEnabled = templateRenderPipelineDescriptor.isTessellationFactorScaleEnabled
        if let label = templateRenderPipelineDescriptor.label {
            renderPassDescriptor.label = label
        }
        renderPassDescriptor.maxTessellationFactor = templateRenderPipelineDescriptor.maxTessellationFactor
        renderPassDescriptor.rasterSampleCount = templateRenderPipelineDescriptor.rasterSampleCount
        renderPassDescriptor.sampleCount = templateRenderPipelineDescriptor.sampleCount
        renderPassDescriptor.stencilAttachmentPixelFormat = templateRenderPipelineDescriptor.stencilAttachmentPixelFormat
        renderPassDescriptor.supportIndirectCommandBuffers = templateRenderPipelineDescriptor.supportIndirectCommandBuffers
        renderPassDescriptor.tessellationControlPointIndexType = templateRenderPipelineDescriptor.tessellationControlPointIndexType
        renderPassDescriptor.tessellationFactorFormat = templateRenderPipelineDescriptor.tessellationFactorFormat
        renderPassDescriptor.tessellationFactorStepFunction = templateRenderPipelineDescriptor.tessellationFactorStepFunction
        renderPassDescriptor.tessellationOutputWindingOrder = templateRenderPipelineDescriptor.tessellationOutputWindingOrder
        renderPassDescriptor.tessellationPartitionMode = templateRenderPipelineDescriptor.tessellationPartitionMode
        renderPassDescriptor.vertexFunction = templateRenderPipelineDescriptor.vertexFunction
        for index in 0..<8 {
            renderPassDescriptor.colorAttachments[index].alphaBlendOperation = templateRenderPipelineDescriptor.colorAttachments[index].alphaBlendOperation
            renderPassDescriptor.colorAttachments[index].destinationAlphaBlendFactor = templateRenderPipelineDescriptor.colorAttachments[index].destinationAlphaBlendFactor
            renderPassDescriptor.colorAttachments[index].destinationRGBBlendFactor = templateRenderPipelineDescriptor.colorAttachments[index].destinationRGBBlendFactor
            renderPassDescriptor.colorAttachments[index].isBlendingEnabled = templateRenderPipelineDescriptor.colorAttachments[index].isBlendingEnabled
            renderPassDescriptor.colorAttachments[index].pixelFormat = templateRenderPipelineDescriptor.colorAttachments[index].pixelFormat
            renderPassDescriptor.colorAttachments[index].rgbBlendOperation = templateRenderPipelineDescriptor.colorAttachments[index].rgbBlendOperation
            renderPassDescriptor.colorAttachments[index].sourceAlphaBlendFactor = templateRenderPipelineDescriptor.colorAttachments[index].sourceAlphaBlendFactor
            renderPassDescriptor.colorAttachments[index].sourceRGBBlendFactor = templateRenderPipelineDescriptor.colorAttachments[index].sourceRGBBlendFactor
        }
        
        if usesGeometry {
            if case .preferInstance = vertexDescriptorMergePolicy {
                if let vertexDescriptor = vertexDescriptor {
                    renderPassDescriptor.vertexDescriptor = vertexDescriptor
                }
            } else {
                renderPassDescriptor.vertexDescriptor = templateRenderPipelineDescriptor.vertexDescriptor
            }
            if case .preferInstance = vertexFunctionMergePolicy {
                renderPassDescriptor.vertexFunction = vertexFunction
            }
        } else {
            renderPassDescriptor.vertexFunction = nil
        }
        if usesLighting {
            if case .preferInstance = fragmentFunctionMergePolicy {
                renderPassDescriptor.fragmentFunction = fragmentFunction
            }
        }
        
        return renderPassDescriptor
        
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

extension RenderPass: CustomStringConvertible, CustomDebugStringConvertible {
    /// :nodoc:
    public var description: String {
        return debugDescription
    }
    /// :nodoc:
    public var debugDescription: String {
        let myDescription = "<\(type(of: self)): \(Unmanaged.passUnretained(self).toOpaque())> name: \(name ?? "none"), uuid: \(uuid), drawCallGroups: \(drawCallGroups), usesGeometry: \(usesGeometry), usesLighting: \(usesLighting), usesSharedBuffer: \(usesSharedBuffer), usesEnvironment: \(usesEnvironment), usesEffects: \(usesEffects), usesCameraOutput: \(usesCameraOutput), usesShadows: \(usesShadows), templateRenderPipelineDescriptor: \(templateRenderPipelineDescriptor?.debugDescription ?? "none"), vertexDescriptorMergePolicy: \(vertexDescriptorMergePolicy), vertexFunctionMergePolicy: \(vertexFunctionMergePolicy), fragmentFunctionMergePolicy: \(fragmentFunctionMergePolicy), depthCompareFunction: \(depthCompareFunction?.debugDescription ?? "none"), depthCompareFunctionMergePolicy: \(depthCompareFunctionMergePolicy), isDepthWriteEnabled: \(isDepthWriteEnabled), isDepthWriteEnabledMergePolicy: \(isDepthWriteEnabledMergePolicy), cullMode: \(cullMode), depthBias: \(depthBias?.debugDescription ?? "none")"
        return myDescription
    }
}
