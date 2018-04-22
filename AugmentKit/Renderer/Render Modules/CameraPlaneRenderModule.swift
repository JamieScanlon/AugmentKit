//
//  CameraPlaneRenderModule.swift
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

class CameraPlaneRenderModule: RenderModule {
    
    static var identifier = "CameraPlaneRenderModule"
    
    //
    // Setup
    //
    
    var moduleIdentifier: String {
        return CameraPlaneRenderModule.identifier
    }
    var renderLayer: Int {
        return 0
    }
    var isInitialized: Bool = false
    var sharedModuleIdentifiers: [String]? = nil
    var renderDistance: Double = 500
    
    func initializeBuffers(withDevice aDevice: MTLDevice, maxInFlightBuffers: Int) {
        
        device = aDevice
        
        // Create a vertex buffer with our image plane vertex data.
        let imagePlaneVertexDataCount = Constants.imagePlaneVertexData.count * MemoryLayout<Float>.size
        imagePlaneVertexBuffer = device?.makeBuffer(bytes: Constants.imagePlaneVertexData, length: imagePlaneVertexDataCount, options: [])
        imagePlaneVertexBuffer?.label = "ImagePlaneVertexBuffer"
        
    }
    
    func loadAssets(fromModelProvider: ModelProvider?, textureLoader: MTKTextureLoader, completion: (() -> Void)) {
        completion()
    }
    
    func loadPipeline(withMetalLibrary metalLibrary: MTLLibrary, renderDestination: RenderDestinationProvider) {
        
        guard let device = device else {
            print("Serious Error - device not found")
            return
        }
        
        guard let capturedImageVertexTransform = metalLibrary.makeFunction(name: "capturedImageVertexTransform") else {
            print("Serious Error - failed to create the capturedImageVertexTransform function")
            return
        }
        
        guard let capturedImageFragmentShader = metalLibrary.makeFunction(name: "capturedImageFragmentShader") else {
            print("Serious Error - failed to create the capturedImageFragmentShader function")
            return
        }
        
        let capturedImageVertexFunction = capturedImageVertexTransform
        let capturedImageFragmentFunction = capturedImageFragmentShader
        
        // Create a vertex descriptor for our image plane vertex buffer
        let imagePlaneVertexDescriptor = MTLVertexDescriptor()
        
        // Positions.
        imagePlaneVertexDescriptor.attributes[0].format = .float2
        imagePlaneVertexDescriptor.attributes[0].offset = 0
        imagePlaneVertexDescriptor.attributes[0].bufferIndex = Int(kBufferIndexMeshPositions.rawValue)
        
        // Texture coordinates.
        imagePlaneVertexDescriptor.attributes[1].format = .float2
        imagePlaneVertexDescriptor.attributes[1].offset = 8
        imagePlaneVertexDescriptor.attributes[1].bufferIndex = Int(kBufferIndexMeshPositions.rawValue)
        
        // Buffer Layout
        imagePlaneVertexDescriptor.layouts[0].stride = 16
        imagePlaneVertexDescriptor.layouts[0].stepRate = 1
        imagePlaneVertexDescriptor.layouts[0].stepFunction = .perVertex
        
        // Create a pipeline state for rendering the captured image
        let capturedImagePipelineStateDescriptor = MTLRenderPipelineDescriptor()
        capturedImagePipelineStateDescriptor.label = "MyCapturedImagePipeline"
        capturedImagePipelineStateDescriptor.sampleCount = renderDestination.sampleCount
        capturedImagePipelineStateDescriptor.vertexFunction = capturedImageVertexFunction
        capturedImagePipelineStateDescriptor.fragmentFunction = capturedImageFragmentFunction
        capturedImagePipelineStateDescriptor.vertexDescriptor = imagePlaneVertexDescriptor
        capturedImagePipelineStateDescriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        capturedImagePipelineStateDescriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        capturedImagePipelineStateDescriptor.stencilAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        
        do {
            try capturedImagePipelineState = device.makeRenderPipelineState(descriptor: capturedImagePipelineStateDescriptor)
        } catch let error {
            print("Serious Error - Failed to create captured image pipeline state, error \(error)")
            return
        }
        
        let capturedImageDepthStateDescriptor = MTLDepthStencilDescriptor()
        capturedImageDepthStateDescriptor.depthCompareFunction = .always
        capturedImageDepthStateDescriptor.isDepthWriteEnabled = false
        capturedImageDepthState = device.makeDepthStencilState(descriptor: capturedImageDepthStateDescriptor)
        
        // Create captured image texture cache
        var textureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        capturedImageTextureCache = textureCache
        
        isInitialized = true
        
    }
    
    //
    // Per Frame Updates
    //
    
    func updateBufferState(withBufferIndex: Int) {
        
        // Retain our CVMetalTextures for the duration of the rendering cycle. The MTLTextures
        // we use from the CVMetalTextures are not valid unless their parent CVMetalTextures
        // are retained. Since we may release our CVMetalTexture ivars during the rendering
        // cycle, we must retain them separately here.
        textureReferences = [capturedImageTextureY, capturedImageTextureCbCr]
        
    }
    
    func updateBuffers(withARFrame frame: ARFrame, cameraProperties: CameraProperties) {
        
        // Create two textures (Y and CbCr) from the provided frame's captured image
        let pixelBuffer = frame.capturedImage
        
        if (CVPixelBufferGetPlaneCount(pixelBuffer) < 2) {
            return
        }
        
        capturedImageTextureY = createTexture(fromPixelBuffer: pixelBuffer, pixelFormat:.r8Unorm, planeIndex:0)
        capturedImageTextureCbCr = createTexture(fromPixelBuffer: pixelBuffer, pixelFormat:.rg8Unorm, planeIndex:1)
        
        if cameraProperties.viewportSizeDidChange {
            // Update the texture coordinates of our image plane to aspect fill the viewport
            let displayToCameraTransform = frame.displayTransform(for: cameraProperties.orientation, viewportSize: cameraProperties.viewportSize).inverted()
            
            if let vertexData = imagePlaneVertexBuffer?.contents().assumingMemoryBound(to: Float.self) {
                for index in 0...3 {
                    let textureCoordIndex = 4 * index + 2
                    let textureCoord = CGPoint(x: CGFloat(Constants.imagePlaneVertexData[textureCoordIndex]), y: CGFloat(Constants.imagePlaneVertexData[textureCoordIndex + 1]))
                    let transformedCoord = textureCoord.applying(displayToCameraTransform)
                    vertexData[textureCoordIndex] = Float(transformedCoord.x)
                    vertexData[textureCoordIndex + 1] = Float(transformedCoord.y)
                }
            }
        }
        
    }
    
    func updateBuffers(withTrackers: [AKAugmentedTracker], targets: [AKTarget], cameraProperties: CameraProperties) {
        // Do Nothing
    }
    
    func updateBuffers(withPaths: [UUID: [AKAugmentedAnchor]], cameraProperties: CameraProperties) {
        // Do Nothing
    }
    
    func draw(withRenderEncoder renderEncoder: MTLRenderCommandEncoder, sharedModules: [SharedRenderModule]?) {
        
        guard let textureY = capturedImageTextureY, let textureCbCr = capturedImageTextureCbCr else {
            return
        }
        
        guard let capturedImagePipelineState = capturedImagePipelineState else {
            print("Serious Error - Captured Image Pipeline State is nil")
            return
        }
        
        // Push a debug group allowing us to identify render commands in the GPU Frame Capture tool
        renderEncoder.pushDebugGroup("Draw Captured Image")
        
        // Set render command encoder state
        renderEncoder.setCullMode(.none)
        renderEncoder.setRenderPipelineState(capturedImagePipelineState)
        renderEncoder.setDepthStencilState(capturedImageDepthState)
        
        // Set mesh's vertex buffers
        renderEncoder.setVertexBuffer(imagePlaneVertexBuffer, offset: 0, index: Int(kBufferIndexMeshPositions.rawValue))
        
        // Set any textures read/sampled from our render pipeline
        renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(textureY), index: Int(kTextureIndexY.rawValue))
        renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(textureCbCr), index: Int(kTextureIndexCbCr.rawValue))
        
        // Draw each submesh of our mesh
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        
        renderEncoder.popDebugGroup()
        
    }
    
    func frameEncodingComplete() {
        textureReferences.removeAll()
    }
    
    // MARK: - Private
    
    private enum Constants {
        
        // Captured Image Plane
        static let imagePlaneVertexData: [Float] = [
            -1.0, -1.0,  0.0, 1.0,
            1.0, -1.0,  1.0, 1.0,
            -1.0,  1.0,  0.0, 0.0,
            1.0,  1.0,  1.0, 0.0,
        ]
        
    }
    
    private var device: MTLDevice?
    private var imagePlaneVertexBuffer: MTLBuffer?
    private var capturedImagePipelineState: MTLRenderPipelineState?
    private var capturedImageDepthState: MTLDepthStencilState?
    private var capturedImageTextureCache: CVMetalTextureCache?
    private var capturedImageTextureY: CVMetalTexture?
    private var capturedImageTextureCbCr: CVMetalTexture?
    
    private var textureReferences = [CVMetalTexture?]()
    
    private func createTexture(fromPixelBuffer pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat, planeIndex: Int) -> CVMetalTexture? {
        
        guard let capturedImageTextureCache = capturedImageTextureCache else {
            print("Serious Error - Cptured Image Texture Cache is nil")
            return nil
        }
        
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
        
        var texture: CVMetalTexture? = nil
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, capturedImageTextureCache, pixelBuffer, nil, pixelFormat, width, height, planeIndex, &texture)
        
        if status != kCVReturnSuccess {
            texture = nil
        }
        
        return texture
    }
    
}
