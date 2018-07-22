//
//  AnchorsRenderModule.swift
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

class AnchorsRenderModule: RenderModule, SkinningModule {
    
    static var identifier = "AnchorsRenderModule"
    
    //
    // Setup
    //
    
    var moduleIdentifier: String {
        return AnchorsRenderModule.identifier
    }
    var renderLayer: Int {
        return 11
    }
    var isInitialized: Bool = false
    var sharedModuleIdentifiers: [String]? = [SharedBuffersRenderModule.identifier]
    var renderDistance: Double = 500
    var errors = [AKError]()
    
    // The number of anchor instances to render
    private(set) var anchorInstanceCount: Int = 0
    
    func initializeBuffers(withDevice aDevice: MTLDevice, maxInFlightBuffers: Int) {
        
        guard device == nil else {
            return
        }
        
        device = aDevice
        
        // Calculate our uniform buffer sizes. We allocate Constants.maxBuffersInFlight instances for uniform
        // storage in a single buffer. This allows us to update uniforms in a ring (i.e. triple
        // buffer the uniforms) so that the GPU reads from one slot in the ring wil the CPU writes
        // to another. Anchor uniforms should be specified with a max instance count for instancing.
        // Also uniform storage must be aligned (to 256 bytes) to meet the requirements to be an
        // argument in the constant address space of our shading functions.
        let anchorUniformBufferSize = Constants.alignedAnchorInstanceUniformsSize * maxInFlightBuffers
        let materialUniformBufferSize = RenderModuleConstants.alignedMaterialSize * maxInFlightBuffers
        let paletteBufferSize = Constants.alignedPaletteSize * Constants.maxPaletteSize * maxInFlightBuffers
        let effectsUniformBufferSize = Constants.alignedEffectsUniformSize * maxInFlightBuffers
        
        // Create and allocate our uniform buffer objects. Indicate shared storage so that both the
        // CPU can access the buffer
        anchorUniformBuffer = device?.makeBuffer(length: anchorUniformBufferSize, options: .storageModeShared)
        anchorUniformBuffer?.label = "AnchorUniformBuffer"
        
        materialUniformBuffer = device?.makeBuffer(length: materialUniformBufferSize, options: .storageModeShared)
        materialUniformBuffer?.label = "MaterialUniformBuffer"
        
        paletteBuffer = device?.makeBuffer(length: paletteBufferSize, options: [])
        paletteBuffer?.label = "PaletteBuffer"
        
        effectsUniformBuffer = device?.makeBuffer(length: effectsUniformBufferSize, options: .storageModeShared)
        effectsUniformBuffer?.label = "EffectsUniformBuffer"
        
    }
    
    func loadAssets(forGeometricEntities geometricEntities: [AKGeometricEntity], fromModelProvider modelProvider: ModelProvider?, textureLoader aTextureLoader: MTKTextureLoader, completion: (() -> Void)) {
        
        guard let modelProvider = modelProvider else {
            print("Serious Error - Model Provider not found.")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeModelProviderNotFound, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            completion()
            return
        }
        
        textureLoader = aTextureLoader
        
        //
        // Create and load our models
        //
        
        var numModels = geometricEntities.count
        
        // Load the default model
        modelProvider.loadAsset(forObjectType: "AnyAnchor", identifier: nil) { [weak self] asset in
            
            guard let asset = asset else {
                print("Warning (AnchorsRenderModule) - Failed to get a MDLAsset for type  \"AnyAnchor\") from the modelProvider. Aborting the render phase.")
                let newError = AKError.warning(.modelError(.modelNotFound(ModelErrorInfo(type:  "AnyAnchor"))))
                recordNewError(newError)
                completion()
                return
            }
            
            self?.modelAssetsForAnchorsByUUID[generalUUID] = asset
            
            if numModels == 0 {
                completion()
            }
            
        }
        
        // Load the per-geometry models
        for geometricEntity in geometricEntities {
            
            if let identifier = geometricEntity.identifier {
                modelProvider.loadAsset(forObjectType:  "AnyAnchor", identifier: identifier) { [weak self] asset in
                    
                    guard let asset = asset else {
                        print("Warning (AnchorsRenderModule) - Failed to get a MDLAsset for type \"AnyAnchor\") with identifier \(identifier) from the modelProvider. Aborting the render phase.")
                        let newError = AKError.warning(.modelError(.modelNotFound(ModelErrorInfo(type:  "AnyAnchor", identifier: identifier))))
                        recordNewError(newError)
                        completion()
                        return
                    }
                    
                    self?.modelAssetsForAnchorsByUUID[identifier] = asset
                }
            }
            
            numModels -= 1
            if numModels <= 0 {
                completion()
            }
            
        }
        
    }
    
    func loadPipeline(withMetalLibrary metalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider, textureBundle: Bundle) {
        
        guard let device = device else {
            print("Serious Error - device not found")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeDeviceNotFound, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return
        }
            
        // Make sure there is at least one general purpose model
        guard modelAssetsForAnchorsByUUID[generalUUID] != nil else {
            print("Warning (AnchorsRenderModule) - Anchor Model was not found. Aborting the render phase.")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeModelNotFound, userInfo: nil)
            let newError = AKError.warning(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return
        }
        
        for item in modelAssetsForAnchorsByUUID {
            
            let uuid = item.key
            let mdlAsset = item.value
            
            meshGPUDataForAnchorsByUUID[uuid] = ModelIOTools.meshGPUData(from: mdlAsset, device: device, textureBundle: textureBundle, vertexDescriptor: MetalUtilities.createStandardVertexDescriptor())
            
            guard let meshGPUData = meshGPUDataForAnchorsByUUID[uuid] else {
                print("Serious Error - ERROR: No meshGPUData found for anchor when trying to load the pipeline.")
                let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeIntermediateMeshDataNotFound, userInfo: nil)
                let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
                recordNewError(newError)
                return
            }
            
            if meshGPUData.drawData.count > 1 {
                print("WARNING: More than one mesh was found. Currently only one mesh per anchor is supported.")
                let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeModelNotSupported, userInfo: nil)
                let newError = AKError.warning(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
                recordNewError(newError)
            }
            
            createPipelineStates(forUUID: uuid, withMetalLibrary: metalLibrary, renderDestination: renderDestination)
            
        }
        
        
        let anchorDepthStateDescriptor = MTLDepthStencilDescriptor()
        anchorDepthStateDescriptor.depthCompareFunction = .less
        anchorDepthStateDescriptor.isDepthWriteEnabled = true
        anchorDepthState = device.makeDepthStencilState(descriptor: anchorDepthStateDescriptor)
        
        isInitialized = true
        
    }
    
    //
    // Per Frame Updates
    //
    
    func updateBufferState(withBufferIndex bufferIndex: Int) {
        
        anchorUniformBufferOffset = Constants.alignedAnchorInstanceUniformsSize * bufferIndex
        materialUniformBufferOffset = RenderModuleConstants.alignedMaterialSize * bufferIndex
        paletteBufferOffset = Constants.alignedPaletteSize * Constants.maxPaletteSize * bufferIndex
        effectsUniformBufferOffset = Constants.alignedEffectsUniformSize * bufferIndex
        
        anchorUniformBufferAddress = anchorUniformBuffer?.contents().advanced(by: anchorUniformBufferOffset)
        materialUniformBufferAddress = materialUniformBuffer?.contents().advanced(by: materialUniformBufferOffset)
        paletteBufferAddress = paletteBuffer?.contents().advanced(by: paletteBufferOffset)
        effectsUniformBufferAddress = effectsUniformBuffer?.contents().advanced(by: effectsUniformBufferOffset)
        
    }
    
    func updateBuffers(withARFrame frame: ARFrame, cameraProperties: CameraProperties) {
        
        // Update the anchor uniform buffer with transforms of the current frame's anchors
        anchorInstanceCount = 0
        var horizPlaneInstanceCount = 0
        var vertPlaneInstanceCount = 0
        anchorsByUUID = [:]
        
        // In the buffer, the anchors ar layed out by UUID in sorted order. So if there are
        // 5 anchors with UUID = "A..." and 3 UUIDs = "B..." and 1 UUID = "C..." then that's
        // how they will layed out in memory. Therefor updating the buffers is a 2 step process.
        // First, loop through all of the ARAnchors and gather the UUIDs as well as the counts for each.
        // Second, layout and update the buffers in the desired order.
        
        //
        // Gather the UUID's
        //
        
        for index in 0..<frame.anchors.count {
            
            let anchor = frame.anchors[index]
            var isAnchor = false
            
            if let plane = anchor as? ARPlaneAnchor {
                if plane.alignment == .horizontal {
                    horizPlaneInstanceCount += 1
                } else {
                    vertPlaneInstanceCount += 1
                }
            } else {
                isAnchor = true
            }
            
            guard isAnchor else {
                continue
            }
            
            // Ignore anchors that are beyond the renderDistance
            let distance = anchorDistance(withTransform: anchor.transform, cameraProperties: cameraProperties)
            guard Double(distance) < renderDistance else {
                continue
            }
            
            anchorInstanceCount += 1
            
            if anchorInstanceCount > Constants.maxAnchorInstanceCount {
                anchorInstanceCount = Constants.maxAnchorInstanceCount
                break
            }
            
            let uuid: UUID = {
                if modelAssetsForAnchorsByUUID[anchor.identifier] != nil {
                    return anchor.identifier
                } else {
                    return generalUUID
                }
            }()
            
            if let currentAnchors = anchorsByUUID[uuid] {
                var mutableCurrentAnchors = currentAnchors
                mutableCurrentAnchors.append(anchor)
                anchorsByUUID[uuid] = mutableCurrentAnchors
            } else {
                anchorsByUUID[uuid] = [anchor]
            }
            
        }
        
        //
        // Update the Anchor uniform
        //
        
        let orderedArray = anchorsByUUID.sorted {
            $0.key.uuidString < $1.key.uuidString
        }
        
        var anchorIndex = 0
        
        for item in orderedArray {
            
            let uuid = item.key
            let anchors = item.value
            
            for anchor in anchors {
                
                // Flip Z axis to convert geometry from right handed to left handed
                var coordinateSpaceTransform = matrix_identity_float4x4
                coordinateSpaceTransform.columns.2.z = -1.0
                
                // Apply the world transform (as defined in the imported model) if applicable
                // We currenly only support a single mesh so we just use the first item
                if let drawData = meshGPUDataForAnchorsByUUID[uuid]?.drawData.first {
                    let worldTransform: matrix_float4x4 = {
                        if drawData.worldTransformAnimations.count > 0 {
                            let index = Int(cameraProperties.currentFrame % UInt(drawData.worldTransformAnimations.count))
                            return drawData.worldTransformAnimations[index]
                        } else {
                            return drawData.worldTransform
                        }
                    }()
                    coordinateSpaceTransform = simd_mul(coordinateSpaceTransform, worldTransform)
                }
                
                let modelMatrix = anchor.transform * coordinateSpaceTransform
                let anchorUniforms = anchorUniformBufferAddress?.assumingMemoryBound(to: AnchorInstanceUniforms.self).advanced(by: anchorIndex)
                anchorUniforms?.pointee.modelMatrix = modelMatrix
                
                //
                // Update puppet animation
                //
                
                let uuid: UUID = {
                    if modelAssetsForAnchorsByUUID[uuid] != nil {
                        return anchor.identifier
                    } else {
                        return generalUUID
                    }
                }()
                if let drawData = meshGPUDataForAnchorsByUUID[uuid]?.drawData.first {
                    updatePuppetAnimation(from: drawData, frameNumber: cameraProperties.currentFrame)
                }
                
                //
                // Update Effects uniform
                //
                
                let effectsUniforms = effectsUniformBufferAddress?.assumingMemoryBound(to: AnchorEffectsUniforms.self).advanced(by: anchorIndex)
                effectsUniforms?.pointee.alpha = 1 // TODO: Implement
                effectsUniforms?.pointee.glow = 0 // TODO: Implement
                effectsUniforms?.pointee.tint = float3(1,1,1) // TODO: Implement
                
                anchorIndex += 1
                
            }
            
        }
        
    }
    
    func updateBuffers(withTrackers: [AKAugmentedTracker], targets: [AKTarget], cameraProperties: CameraProperties) {
        // Do Nothing
    }
    
    func updateBuffers(withPaths: [AKPath], cameraProperties: CameraProperties) {
        // Do Nothing
    }
    
    func draw(withRenderEncoder renderEncoder: MTLRenderCommandEncoder, sharedModules: [SharedRenderModule]?) {
        
        guard anchorInstanceCount > 0 else {
            return
        }
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("Draw Anchors")
        
        // Set render command encoder state
        renderEncoder.setCullMode(.back)
        
        if let sharedBuffer = sharedModules?.first(where: {$0.moduleIdentifier == SharedBuffersRenderModule.identifier}) {
            
            renderEncoder.pushDebugGroup("Draw Shared Uniforms")
            
            renderEncoder.setVertexBuffer(sharedBuffer.sharedUniformBuffer, offset: sharedBuffer.sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
            renderEncoder.setFragmentBuffer(sharedBuffer.sharedUniformBuffer, offset: sharedBuffer.sharedUniformBufferOffset, index: Int(kBufferIndexSharedUniforms.rawValue))
            
            renderEncoder.popDebugGroup()
            
        }
        
        if let effectsBuffer = effectsUniformBuffer {
            
            renderEncoder.pushDebugGroup("Draw Effects Uniforms")
            renderEncoder.setFragmentBuffer(effectsBuffer, offset: effectsUniformBufferOffset, index: Int(kBufferIndexAnchorEffectsUniforms.rawValue))
            renderEncoder.popDebugGroup()
            
        }
        
        let orderedArray = anchorsByUUID.sorted {
            $0.key.uuidString < $1.key.uuidString
        }
        
        
        var baseIndex = 0
        
        for item in orderedArray {
            
            let uuid = item.key
            
            guard let meshGPUData = meshGPUDataForAnchorsByUUID[uuid] else {
                print("Error: Could not find meshGPUData for UUID: \(uuid)")
                let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeIntermediateMeshDataNotAvailable, userInfo: nil)
                let newError = AKError.recoverableError(.renderPipelineError(.drawAborted(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
                recordNewError(newError)
                continue
            }
            
            guard let myPipelineStates = pipelineStatesForAnchorsByUUID[uuid] else {
                continue
            }
            
            let anchorcount = (anchorsByUUID[uuid] ?? []).count
            
            // While the Mesh GPU Data can techically contain multiple meshes each
            // with their own pipline state, the current implementation of the
            // renderer only supports one. So while we are saving all of the states
            // in the myPipelineStates array, only the first will be used.
            for (drawDataIdx, drawData) in meshGPUData.drawData.enumerated() {
                
                if drawDataIdx < myPipelineStates.count {
                    renderEncoder.setRenderPipelineState(myPipelineStates[drawDataIdx])
                    renderEncoder.setDepthStencilState(anchorDepthState)
                    
                    // Set any buffers fed into our render pipeline
                    renderEncoder.setVertexBuffer(anchorUniformBuffer, offset: anchorUniformBufferOffset, index: Int(kBufferIndexAnchorInstanceUniforms.rawValue))
                    renderEncoder.setVertexBuffer(paletteBuffer, offset: paletteBufferOffset, index: Int(kBufferIndexMeshPalettes.rawValue))
                    
                    var mutableDrawData = drawData
                    mutableDrawData.instCount = anchorcount
                    
                    // Set the mesh's vertex data buffers
                    encode(meshGPUData: meshGPUData, fromDrawData: mutableDrawData, with: renderEncoder, baseIndex: baseIndex)
                    
                }
                
            }
            
             baseIndex += anchorcount
            
        }
        
        renderEncoder.popDebugGroup()
        
    }
    
    func frameEncodingComplete() {
        //
    }
    
    //
    // Util
    //
    
    func recordNewError(_ akError: AKError) {
        errors.append(akError)
    }
    
    // MARK: - Private
    
    private enum Constants {
        static let maxAnchorInstanceCount = 256
        static let maxPaletteSize = 100
        static let alignedAnchorInstanceUniformsSize = ((MemoryLayout<AnchorInstanceUniforms>.stride * Constants.maxAnchorInstanceCount) & ~0xFF) + 0x100
        static let alignedPaletteSize = (MemoryLayout<matrix_float4x4>.stride & ~0xFF) + 0x100
        static let alignedEffectsUniformSize = ((MemoryLayout<AnchorEffectsUniforms>.stride * Constants.maxAnchorInstanceCount) & ~0xFF) + 0x100
    }
    
    private var device: MTLDevice?
    private var textureLoader: MTKTextureLoader?
    private var generalUUID = UUID()
    private var modelAssetsForAnchorsByUUID = [UUID: MDLAsset]()
    private var anchorUniformBuffer: MTLBuffer?
    private var materialUniformBuffer: MTLBuffer?
    private var paletteBuffer: MTLBuffer?
    private var effectsUniformBuffer: MTLBuffer?
    private var pipelineStatesForAnchorsByUUID = [UUID: [MTLRenderPipelineState]]()
    private var anchorDepthState: MTLDepthStencilState?
    
    // MetalKit meshes containing vertex data and index buffer for our anchor geometry
    private var meshGPUDataForAnchorsByUUID = [UUID: MeshGPUData]()
    
    // Offset within anchorUniformBuffer to set for the current frame
    private var anchorUniformBufferOffset: Int = 0
    
    // Offset within materialUniformBuffer to set for the current frame
    private var materialUniformBufferOffset: Int = 0
    
    // Offset within paletteBuffer to set for the current frame
    private var paletteBufferOffset = 0
    
    // Offset within effectsUniformBuffer to set for the current frame
    private var effectsUniformBufferOffset: Int = 0
    
    // Addresses to write anchor uniforms to each frame
    private var anchorUniformBufferAddress: UnsafeMutableRawPointer?
    
    // Addresses to write anchor uniforms to each frame
    private var materialUniformBufferAddress: UnsafeMutableRawPointer?
    
    // Addresses to write palette to each frame
    private var paletteBufferAddress: UnsafeMutableRawPointer?
    
    // Addresses to write material uniforms to each frame
    private var effectsUniformBufferAddress: UnsafeMutableRawPointer?
    
    // number of frames in the anchor animation by anchor index
    private var anchorAnimationFrameCount = [Int]()
    
    private var anchorsByUUID = [UUID: [ARAnchor]]()
    
    private func createPipelineStates(forUUID uuid: UUID, withMetalLibrary metalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider) {
        
        guard let device = device else {
            print("Serious Error - device not found")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeDeviceNotFound, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return
        }
        
        guard let meshGPUData = meshGPUDataForAnchorsByUUID[uuid] else {
            print("Serious Error - ERROR: No meshGPUData found when trying to load the pipeline.")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeIntermediateMeshDataNotFound, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return
        }
        
        let myVertexDescriptor = meshGPUData.vertexDescriptors.first
        
        guard let anchorVertexDescriptor = myVertexDescriptor else {
            print("Serious Error - Failed to create a MetalKit vertex descriptor from ModelIO.")
            let underlyingError = NSError(domain: AKErrorDomain, code: AKErrorCodeInvalidMeshData, userInfo: nil)
            let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: underlyingError))))
            recordNewError(newError)
            return
        }
        
        // While the Mesh GPU Data can techically contain multiple meshes each
        // with their own pipline state, the current implementation of the
        // renderer only supports one. So while we are saving all of the states
        // in the myPipelineStates array, only the first will be used.
        var myPipelineStates = [MTLRenderPipelineState]()
        for (drawIdx, drawData) in meshGPUData.drawData.enumerated() {
            let anchorPipelineStateDescriptor = MTLRenderPipelineDescriptor()
            do {
                let funcConstants = MetalUtilities.getFuncConstants(forDrawData: drawData)
                // Specify which shader to use based on if the model has skinned puppet suppot
                let vertexName = (drawData.paletteStartIndex != nil) ? "anchorGeometryVertexTransformSkinned" : "anchorGeometryVertexTransform"
                let fragFunc = try metalLibrary.makeFunction(name: "anchorGeometryFragmentLighting", constantValues: funcConstants)
                let vertFunc = try metalLibrary.makeFunction(name: vertexName, constantValues: funcConstants)
                anchorPipelineStateDescriptor.vertexDescriptor = anchorVertexDescriptor
                anchorPipelineStateDescriptor.vertexFunction = vertFunc
                anchorPipelineStateDescriptor.fragmentFunction = fragFunc
                anchorPipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
                anchorPipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = true
                anchorPipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                anchorPipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                anchorPipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
                anchorPipelineStateDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
                anchorPipelineStateDescriptor.sampleCount = renderDestination.sampleCount
            } catch let error {
                print("Failed to create pipeline state descriptor, error \(error)")
                let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: error))))
                recordNewError(newError)
            }
            
            do {
                try myPipelineStates.append(device.makeRenderPipelineState(descriptor: anchorPipelineStateDescriptor))
            } catch let error {
                print("Failed to create pipeline state, error \(error)")
                let newError = AKError.seriousError(.renderPipelineError(.failedToInitialize(PipelineErrorInfo(moduleIdentifier: moduleIdentifier, underlyingError: error))))
                recordNewError(newError)
            }
        }
        
        pipelineStatesForAnchorsByUUID[uuid] = myPipelineStates
        
    }
    
    private func updatePuppetAnimation(from drawData: DrawData, frameNumber: UInt) {
        return
        let capacity = Constants.alignedPaletteSize * Constants.maxPaletteSize
        
        let boundPaletteData = paletteBufferAddress?.bindMemory(to: matrix_float4x4.self, capacity: capacity)
        
        let paletteData = UnsafeMutableBufferPointer<matrix_float4x4>(start: boundPaletteData, count: Constants.maxPaletteSize)
        
        var jointPaletteOffset = 0
        for skin in drawData.skins {
            if let animationIndex = skin.animationIndex {
                let curAnimation = drawData.skeletonAnimations[animationIndex]
                let worldPose = evaluateAnimation(curAnimation, at: (Double(frameNumber) * 1.0 / 60.0))
                let matrixPalette = evaluateMatrixPalette(worldPose, skin)
                
                for k in 0..<matrixPalette.count {
                    paletteData[k + jointPaletteOffset] = matrixPalette[k]
                }
                
                jointPaletteOffset += matrixPalette.count
            }
        }
    }
    
}
