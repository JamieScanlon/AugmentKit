//
//  FilterRenderer.swift
//  AccessibleVideo
//
//  Copyright (c) 2016 Tenth Letter Made LLC. All rights reserved.
//

import Foundation
import CoreVideo
import Metal
import MetalKit
import MetalPerformanceShaders
import AVFoundation
import UIKit
// FIXME: comparison operators with optionals were removed from the Swift Standard Libary.
// Consider refactoring the code to use the non-optional operators.
fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

// FIXME: comparison operators with optionals were removed from the Swift Standard Libary.
// Consider refactoring the code to use the non-optional operators.
fileprivate func > <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l > r
  default:
    return rhs < lhs
  }
}


protocol RendererControlDelegate {
    var primaryColor:UIColor { get set }
    var secondaryColor:UIColor { get set }
    var invertScreen:Bool { get set }
    var highQuality:Bool { get }
}

enum RendererSetupError: Error {
    case missingDevice
    case shaderListNotFound
    case failedBufferCreation
    case failedLibraryCreation
}

enum PassSetupError: Error {
    case missingDevice
}

class FilterRenderer: NSObject, RendererControlDelegate {
    
    enum MPSFilerType: String {
        case AreaMax
        case AreaMin
        case Box
        case Tent
        case Convolution
        case Dialate
        case Erode
        case GaussianBlur
        case HistogramEqualization
        case HistogramSpecification
        case Integral
        case IntegralOfSquares
        case LanczosScale
        case Median
        case Sobel
        case ThresholdBinary
        case ThresholdBinaryInverse
        case ThresholdToZero
        case ThresholdToZeroInverse
        case ThresholdTruncate
        case Transpose
    }
    
    var device:MTLDevice? {
        return _device
    }
    
    var highQuality:Bool = false
    
    var primaryColor:UIColor = UIColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 0.75) {
        didSet {
            setFilterBuffer()
        }
    }
    
    var secondaryColor:UIColor = UIColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 0.75){
        didSet {
            setFilterBuffer()
        }
    }
    
    var invertScreen:Bool = false {
        didSet {
            setFilterBuffer()
        }
    }
    
    fileprivate var _controller:UIViewController
    
    lazy fileprivate var _device = MTLCreateSystemDefaultDevice()
    lazy fileprivate var _vertexStart = [UIInterfaceOrientation : Int]()

    fileprivate var _vertexBuffer:MTLBuffer? = nil
    fileprivate var _filterArgs:MetalBufferArray<FilterBuffer>? = nil
    fileprivate var _colorArgs:MetalBufferArray<ColorBuffer>? = nil
    
    fileprivate var _currentFilterBuffer:Int = 0 {
        didSet {
            _currentFilterBuffer = _currentFilterBuffer % _numberShaderBuffers
        }
    }
    
    fileprivate var _currentColorBuffer:Int = 0 {
        didSet {
            _currentColorBuffer = _currentColorBuffer % _numberShaderBuffers
        }
    }
    
    fileprivate var _screenBlitState:MTLRenderPipelineState? = nil
    fileprivate var _screenInvertState:MTLRenderPipelineState? = nil
    
    fileprivate var _commandQueue: MTLCommandQueue? = nil
    
    fileprivate var _intermediateTextures = [MTLTexture]()
    fileprivate var _intermediateRenderPassDescriptor = [MTLRenderPassDescriptor]()

    
    fileprivate var _rgbTexture:MTLTexture? = nil
    fileprivate var _rgbDescriptor:MTLRenderPassDescriptor? = nil
    
    // ping/pong index variable
    fileprivate var _currentSourceTexture:Int = 0 {
        didSet {
            _currentSourceTexture = _currentSourceTexture % 2
        }
    }
    
    fileprivate var _currentDestTexture:Int {
        return (_currentSourceTexture + 1) % 2
    }
    
    fileprivate var _numberBufferedFrames:Int = 3
    fileprivate var _numberShaderBuffers:Int {
        return _numberBufferedFrames + 1
    }
    
    fileprivate var _renderSemaphore: DispatchSemaphore? = nil
    
    fileprivate var _textureCache: CVMetalTextureCache? = nil
    
    fileprivate var _vertexDesc: MTLVertexDescriptor? = nil
    
    fileprivate var _shaderLibrary: MTLLibrary? = nil
    fileprivate var _shaderDictionary: NSDictionary? = nil
    fileprivate var _shaderPipelineStates = [String : MTLRenderPipelineState]()
    fileprivate var _computePipelineStates = [String : MTLComputePipelineState]()

    fileprivate var _shaderArguments = [String : NSObject]() // MTLRenderPipelineReflection or MTLComputePipelineReflection
    
    fileprivate var _samplerStates = [MTLSamplerState]()
    
    fileprivate var _currentVideoFilter = [Any]() // MTLRenderPipelineState or MTLComputePipelineState, or MPSFilterType
    fileprivate var _currentColorFilter:MTLRenderPipelineState? = nil
    fileprivate var _currentColorConvolution:[Float32] = [] {
        didSet {
            setColorBuffer()
        }
    }
    
    lazy fileprivate var _isiPad:Bool = (UIDevice.current.userInterfaceIdiom == .pad)
    
    fileprivate var _viewport:MTLViewport = MTLViewport()
    
    fileprivate var threadsPerGroup:MTLSize!
    fileprivate var numThreadgroups: MTLSize!
    
    init(viewController:UIViewController) throws {
        _controller = viewController
        super.init()
        try setupRenderer()
    }
    
    // MARK: Setup
    
    func setupRenderer() throws
    {
        
        guard let device = device else {
            throw RendererSetupError.missingDevice
        }
        
        // load the shader dictionary
        guard let path = Bundle.main.path(forResource: "Shaders", ofType: "plist") else {
            throw RendererSetupError.shaderListNotFound
        }
        
        _shaderDictionary = NSDictionary(contentsOfFile: path)
        
        // create the render buffering semaphore
        _renderSemaphore = DispatchSemaphore(value: _numberBufferedFrames)
        
        // create texture caches for CoreVideo
        CVMetalTextureCacheCreate(nil, nil, _device!, nil, &_textureCache)
        
        // set up the full screen quads
        let data:[Float] = [
            // landscape right & passthrough
            -1.0,  -1.0,  0.0, 1.0,
            1.0,  -1.0,  1.0, 1.0,
            -1.0,   1.0,  0.0, 0.0,
            1.0,  -1.0,  1.0, 1.0,
            -1.0,   1.0,  0.0, 0.0,
            1.0,   1.0,  1.0, 0.0,
            // landscape left
            -1.0,  -1.0,  1.0, 0.0,
            1.0,  -1.0,  0.0, 0.0,
            -1.0,   1.0,  1.0, 1.0,
            1.0,  -1.0,  0.0, 0.0,
            -1.0,   1.0,  1.0, 1.0,
            1.0,   1.0,  0.0, 1.0,
            // portrait
            -1.0,  -1.0,  1.0, 1.0,
            1.0,  -1.0,  1.0, 0.0,
            -1.0,   1.0,  0.0, 1.0,
            1.0,  -1.0,  1.0, 0.0,
            -1.0,   1.0,  0.0, 1.0,
            1.0,   1.0,  0.0, 0.0,
            // portrait upside down
            -1.0,  -1.0,  0.0, 0.0,
            1.0,  -1.0,  0.0, 1.0,
            -1.0,   1.0,  1.0, 0.0,
            1.0,  -1.0,  0.0, 1.0,
            -1.0,   1.0,  1.0, 0.0,
            1.0,   1.0,  1.0, 1.0
        ]
        
        // set up vertex buffer
        let dataSize = data.count * MemoryLayout.size(ofValue: data[0]) // 1
        let options = MTLResourceOptions().union(MTLResourceOptions())
        _vertexBuffer = device.makeBuffer(bytes: data, length: dataSize, options: options)

        // set vertex indicies start for each rotation
        _vertexStart[.landscapeRight] = 0
        _vertexStart[.landscapeLeft] = 6
        _vertexStart[.portrait] = 12
        _vertexStart[.portraitUpsideDown] = 18
        
        // create default shader library
        guard let library = device.newDefaultLibrary() else {
            throw RendererSetupError.failedLibraryCreation
        }
        _shaderLibrary = library
        print("Loading shader library...")
        for str in library.functionNames {
            print("Found shader: \(str)")
        }
        
        // create the full screen quad vertex attribute descriptor
        let vert = MTLVertexAttributeDescriptor()
        vert.format = .float2
        vert.bufferIndex = 0
        vert.offset = 0
        
        let tex = MTLVertexAttributeDescriptor()
        tex.format = .float2
        tex.bufferIndex = 0
        tex.offset = 2 * MemoryLayout<Float>.size
        
        let layout = MTLVertexBufferLayoutDescriptor()
        layout.stride = 4 * MemoryLayout<Float>.size
        layout.stepFunction = MTLVertexStepFunction.perVertex
        
        
        let vertexDesc = MTLVertexDescriptor()
        
        vertexDesc.layouts[0] = layout
        vertexDesc.attributes[0] = vert
        vertexDesc.attributes[1] = tex
        
        _vertexDesc = vertexDesc
        
        
        // create filter parameter buffer
        // create common pipeline states

        _currentColorFilter = cachedRenderPipelineStateFor("yuv_rgb")

        _screenBlitState = cachedRenderPipelineStateFor("blit")
        _screenInvertState = cachedRenderPipelineStateFor("invert")

        if let blitArgs = _shaderArguments["blit"] as? MTLRenderPipelineReflection,
           let fragmentArguments = blitArgs.fragmentArguments {
            
            let myFragmentArgs = fragmentArguments.filter({$0.name == "filterParameters"})
            if myFragmentArgs.count == 1 {
                _filterArgs = MetalBufferArray<FilterBuffer>(arguments: myFragmentArgs[0], count: _numberShaderBuffers)
            }
            
        }
        
        if let yuvrgbArgs = _shaderArguments["yuv_rgb"] as? MTLRenderPipelineReflection,
           let fragmentArguments = yuvrgbArgs.fragmentArguments {
            
            let myFragmentArgs = fragmentArguments.filter({$0.name == "colorParameters"})
            if myFragmentArgs.count == 1 {
                _colorArgs = MetalBufferArray<ColorBuffer>(arguments: myFragmentArgs[0], count: _numberShaderBuffers)
            }
            
        }
        
        if device.supportsFeatureSet(.iOS_GPUFamily2_v1) {
            
            print("Using high quality")
            highQuality = true
            
        } else {
           highQuality = false
        }
        
        setFilterBuffer()
 
        let nearest = MTLSamplerDescriptor()
        nearest.label = "nearest"
        
        let bilinear = MTLSamplerDescriptor()
        bilinear.label = "bilinear"
        bilinear.minFilter = .linear
        bilinear.magFilter = .linear
        _samplerStates = [nearest, bilinear].map {device.makeSamplerState(descriptor: $0)}
        
        // create the command queue
        _commandQueue = device.makeCommandQueue()
        
    }
    
    // MARK: Render
    
    // create a pipeline state descriptor for a vertex/fragment shader combo
    func pipelineStateFor(label:String, fragmentShader:String, vertexShader: String?) -> (MTLRenderPipelineState?, MTLRenderPipelineReflection?) {
        
        if  let device = device,
            let shaderLibrary = _shaderLibrary,
            let fragmentProgram = shaderLibrary.makeFunction(name: fragmentShader),
            let vertexProgram = shaderLibrary.makeFunction(name: vertexShader ?? "defaultVertex") {
            
            let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
            pipelineStateDescriptor.label = label
            pipelineStateDescriptor.vertexFunction = vertexProgram
            pipelineStateDescriptor.fragmentFunction = fragmentProgram
            
            pipelineStateDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            
            pipelineStateDescriptor.vertexDescriptor = _vertexDesc
            
            // create the actual pipeline state
            var info:MTLRenderPipelineReflection? = nil
            
            do {
                let pipelineState = try device.makeRenderPipelineState(descriptor: pipelineStateDescriptor, options: MTLPipelineOption.bufferTypeInfo, reflection: &info)
                return (pipelineState, info)
            } catch let pipelineError as NSError {
                print("Failed to create pipeline state for shaders \(vertexShader!):\(fragmentShader) error \(pipelineError)")
            }
        }
        return (nil, nil)
    }
    
    func cachedRenderPipelineStateFor(_ shaderName:String) -> MTLRenderPipelineState? {
        guard let pipeline = _shaderPipelineStates[shaderName] else {
            
            var fragment = shaderName
            var vertex:String? = nil
            
            if  let shaderDictionary = _shaderDictionary,
                let s = shaderDictionary.object(forKey: shaderName) as? NSDictionary {
                
                vertex = s.object(forKey: "vertex") as? String
                if let frag:String = s.object(forKey: "fragment") as? String {
                    fragment = frag
                }
                
            }
            
            let (state, reflector) = pipelineStateFor(label:shaderName, fragmentShader: fragment, vertexShader: vertex)
            _shaderPipelineStates[shaderName] = state
            _shaderArguments[shaderName] = reflector
            return state
        }
        return pipeline
        
        
    }
    
    // MARK: Compute
    
    // create a pipeline state descriptor for a vertex/fragment shader combo
    func computePipelineStateFor(shaderName:String) throws -> (MTLComputePipelineState?, MTLComputePipelineReflection?) {
        
        if  let shaderLibrary = _shaderLibrary,
            let computeProgram = shaderLibrary.makeFunction(name: shaderName) {
            
            guard let device = device else {
                throw RendererSetupError.missingDevice
            }
            
            let pipelineStateDescriptor = MTLComputePipelineDescriptor()
            pipelineStateDescriptor.label = shaderName
            pipelineStateDescriptor.computeFunction = computeProgram
            
            // create the actual pipeline state
            var info:MTLComputePipelineReflection? = nil
            
            let pipelineState = try device.makeComputePipelineState(descriptor: pipelineStateDescriptor, options: MTLPipelineOption.bufferTypeInfo, reflection: &info)
            
            return (pipelineState, info)
            
        }
        
        return (nil, nil)
        
    }
    
    func cachedComputePipelineStateFor(_ shaderName:String) throws -> MTLComputePipelineState? {
        
        guard let pipeline = _computePipelineStates[shaderName] else {
            
            let (state, reflector) = try computePipelineStateFor(shaderName:shaderName)
            _computePipelineStates[shaderName] = state
            _shaderArguments[shaderName] = reflector
            return state
            
        }
        
        return pipeline
        
    }
    
    // MARK: Video
    
    func setVideoFilter(_ filter:VideoFilter)
    {
        _currentVideoFilter = filter.passes.map {self.cachedPipelineStateFor($0)!}
    }
    
    func setColorFilter(_ filter:InputFilter) {
        
        guard let shader = cachedPipelineStateFor(filter.shaderName) else {
            print("Fatal error: could not set color filter to \(filter.shaderName)")
            return
        }
        
        let nextBuffer = (_currentColorBuffer + 1) % _numberShaderBuffers
        
        _currentColorFilter = shader
        
        _colorArgs?[nextBuffer].setConvolution(filter.convolution)
        _currentColorBuffer += 1
    }
    
    func setColorBuffer() {
        
        guard let colorArgs = _colorArgs else {
            print("Warning: The colorArgs buffer was nil. Abouting")
            return
        }
        
        let nextBuffer = (_currentColorBuffer + 1) % _numberShaderBuffers
        _currentColorBuffer += 1

        if _currentColorConvolution.count == 9 {
            colorArgs[nextBuffer].yuvToRGB?.set(
                (
                    (_currentColorConvolution[0], _currentColorConvolution[1], _currentColorConvolution[2]),
                    (_currentColorConvolution[3], _currentColorConvolution[4], _currentColorConvolution[5]),
                    (_currentColorConvolution[6], _currentColorConvolution[7], _currentColorConvolution[8])
                )
            )
        } else {
            colorArgs[nextBuffer].yuvToRGB?.clearIdentity()
        }

    }
    
    func setFilterBuffer() {
        
        guard let filterArgs = _filterArgs else {
            print("Warning: The filterArgs buffer was nil. Abouting")
            return
        }
        
        let nextBuffer = (_currentFilterBuffer + 1) % _numberShaderBuffers
        _currentFilterBuffer += 1

        let currentBuffer = filterArgs[nextBuffer]
        if invertScreen {
            currentBuffer.primaryColor?.inverseColor = primaryColor
            currentBuffer.secondaryColor?.inverseColor = secondaryColor
        } else {
            currentBuffer.primaryColor?.color = primaryColor
            currentBuffer.secondaryColor?.color = secondaryColor
        }
        
        if highQuality {
            currentBuffer.lowThreshold = 0.05
            currentBuffer.highThreshold = 0.10
        } else {
            currentBuffer.lowThreshold = 0.15
            currentBuffer.highThreshold = 0.25
        }
        
    }
 
    // MARK: - Methods
    
    // MARK: Create Shaders
    
    // create generic render pass
    func createRenderPass(_ commandBuffer: MTLCommandBuffer,
                          pipeline:MTLRenderPipelineState,
                          vertexIndex:Int,
                          fragmentBuffers:[(MTLBuffer,Int)],
                          sourceTextures:[MTLTexture],
                          descriptor: MTLRenderPassDescriptor,
                          viewport:MTLViewport?) {
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        
        let name:String = pipeline.label ?? "Unnamed Render Pass"
        renderEncoder.pushDebugGroup(name)
        renderEncoder.label = name
        if let view = viewport {
            renderEncoder.setViewport(view)
        }
        renderEncoder.setRenderPipelineState(pipeline)
        
        renderEncoder.setVertexBuffer(_vertexBuffer, offset: 0, at: 0)
        
        for (index,(buffer, offset)) in fragmentBuffers.enumerated() {
            renderEncoder.setFragmentBuffer(buffer, offset: offset, at: index)
        }
        for (index,texture) in sourceTextures.enumerated() {
            renderEncoder.setFragmentTexture(texture, at: index)
        }
        for (index,samplerState) in _samplerStates.enumerated() {
            renderEncoder.setFragmentSamplerState(samplerState, at: index)
        }
        
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: vertexIndex, vertexCount: 6, instanceCount: 1)
        renderEncoder.popDebugGroup()
        renderEncoder.endEncoding()
    }
    
    func createComputePass(_ commandBuffer: MTLCommandBuffer,
                           pipeline:MTLComputePipelineState,
                           textures:[MTLTexture],
                           descriptor: MTLRenderPassDescriptor,
                           viewport:MTLViewport?,
                           name: String?) {
        
        let computeEncoder = commandBuffer.makeComputeCommandEncoder()
        let aName:String = name ?? "Unnamed Compute Pass"
        
        computeEncoder.pushDebugGroup(aName)
        computeEncoder.label = aName
        computeEncoder.setComputePipelineState(pipeline)
        
        for (index,texture) in textures.enumerated() {
            computeEncoder.setTexture(texture, at: index)
        }
        
        computeEncoder.dispatchThreadgroups(numThreadgroups, threadsPerThreadgroup: threadsPerGroup)
        
        computeEncoder.popDebugGroup()
        computeEncoder.endEncoding()
        
    }
    
    func createMPSPass(_ commandBuffer: MTLCommandBuffer,
                       texture:MTLTexture,
                       type: MPSFilerType,
                       sigma: Float?,
                       diameter: Int?) {
        
        // TODO: New datatype to encapsulate params MPSPipelineState
        
        guard let device = device else {
            //throw PassSetupError.MissingDevice
            return
        }
        
        var kernel: MPSUnaryImageKernel? = nil
        
        switch type {
        case .AreaMax:
            /*
            if let kernelWidth = kernelWidth, kernelHeight = kernelHeight {
                kernel = MPSImageAreaMax(device: device, kernelWidth: kernelWidth, kernelHeight: kernelHeight)
            }
            */
            break
        case .AreaMin:
            /*
            if let kernelWidth = kernelWidth, kernelHeight = kernelHeight {
                kernel = MPSImageAreaMin(device: device, kernelWidth: kernelWidth, kernelHeight: kernelHeight)
            }
             */
            break
        case .Box:
            /*
            if let kernelWidth = kernelWidth, kernelHeight = kernelHeight {
                kernel = MPSImageBox(device: device, kernelWidth: kernelWidth, kernelHeight: kernelHeight)
            }
            */
            break
        case .Convolution:
            /*
            if let kernelWidth = kernelWidth, kernelHeight = kernelHeight {
                kernel = MPSImageConvolution(device: device, kernelWidth: kernelWidth, kernelHeight: kernelHeight, weights: nil)
            }
             */
            break
        case .Dialate:
            /*
            if let kernelWidth = kernelWidth, kernelHeight = kernelHeight {
                kernel = MPSImageDilate(device: device, kernelWidth: kernelWidth, kernelHeight: kernelHeight, values: nil)
            }
             */
            break
        case .Erode:
            /*
            if let kernelWidth = kernelWidth, kernelHeight = kernelHeight {
                kernel = MPSImageErode(device: device, kernelWidth: kernelWidth, kernelHeight: kernelHeight, values: nil)
            }
             */
            break
        case .GaussianBlur:
            if let sigma = sigma {
                kernel = MPSImageGaussianBlur(device: device, sigma: sigma)
            }
        case .HistogramEqualization:
            //kernel = MPSImageHistogramEqualization(device: device, histogramInfo: nil)
            break
        case .HistogramSpecification:
            //kernel = MPSImageHistogramSpecification(device: device, histogramInfo: nil)
            break
        case .Integral:
            kernel = MPSImageIntegral(device: device)
        case .IntegralOfSquares:
            kernel = MPSImageIntegralOfSquares(device: device)
        case .LanczosScale:
            kernel = MPSImageLanczosScale(device: device)
        case .Median:
            /*
            if let diameter = diameter {
                kernel = MPSImageMedian(device: device, kernelDiameter:diameter )
            }
             */
            break
        case .Sobel:
            kernel = MPSImageSobel(device: device)
        case .ThresholdBinary:
            //kernel = MPSImageThresholdBinary(device: device)
            break
        case .ThresholdBinaryInverse:
            //kernel = MPSImageThresholdBinaryInverse(device: device)
            break
        case .ThresholdToZero:
            //kernel = MPSImageThresholdToZero(device: device)
            break
        case .ThresholdToZeroInverse:
            //kernel = MPSImageThresholdToZeroInverse(device: device)
            break
        case .ThresholdTruncate:
            //kernel = MPSImageThresholdTruncate(device: device)
            break
        case .Transpose:
            kernel = MPSImageTranspose(device: device)
        default: break
        }
     
        if let unwrappedKernel = kernel {
            
            let inPlaceTexture = UnsafeMutablePointer<MTLTexture>.allocate(capacity: 1)
            inPlaceTexture.initialize(to: texture)
            let myFallbackAllocator = { ( filter: MPSKernel, commandBuffer: MTLCommandBuffer, sourceTexture: MTLTexture) -> MTLTexture in
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: sourceTexture.pixelFormat, width: sourceTexture.width, height: sourceTexture.height, mipmapped: false)
                let result = commandBuffer.device.makeTexture(descriptor: descriptor)
                return result
            }
            
            unwrappedKernel.encode(commandBuffer: commandBuffer, inPlaceTexture: inPlaceTexture, fallbackCopyAllocator: myFallbackAllocator)
        }
    }
    
    func cachedPipelineStateFor(_ shaderName:String) -> MTLRenderPipelineState? {
        guard let pipeline = _shaderPipelineStates[shaderName] else {
            
            var fragment:String! = shaderName
            var vertex:String? = nil
            
            if let s = _shaderDictionary?.object(forKey: shaderName) as? NSDictionary {
                vertex = s.object(forKey: "vertex") as? String
                if let frag:String = s.object(forKey: "fragment") as? String {
                    fragment = frag
                }
            }
            
            let (state, reflector) = pipelineStateFor(label:shaderName, fragmentShader: fragment, vertexShader: vertex)
            if let pipelineState = state
            {
                _shaderPipelineStates[shaderName] = pipelineState
                _shaderArguments[shaderName] = reflector
            } else {
                print("Fatal error trying to load pipeline state for \(shaderName)")
            }
            return state
            
        }
        return pipeline
    }

}

// MARK: - CameraCaptureDelegate

extension FilterRenderer: CameraCaptureDelegate {
    
    func setResolution(width: Int, height: Int) {
        
        guard let device = device else {
            return
        }
        
        objc_sync_enter(self)
        defer {
            objc_sync_exit(self)
        }
        
        threadsPerGroup = MTLSizeMake(16, 16, 1)
        numThreadgroups = MTLSizeMake(width / threadsPerGroup.width, height / threadsPerGroup.height, 1)
        
        let scale = UIScreen.main.nativeScale
        
        var textureWidth = Int(_controller.view.bounds.width * scale)
        var textureHeight = Int(_controller.view.bounds.height * scale)
        
        if (textureHeight > textureWidth) {
            let temp = textureHeight
            textureHeight = textureWidth
            textureWidth = temp
        }
        
        if ((textureHeight > height) || (textureWidth > width)) {
            textureHeight = height
            textureWidth = width
        }
        
        print("Setting offscreen texure resolution to \(textureWidth)x\(textureHeight)")
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: textureWidth, height: textureHeight, mipmapped: false)
        descriptor.resourceOptions = .storageModePrivate
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]
        
        _intermediateTextures = [descriptor,descriptor].map { device.makeTexture(descriptor: $0) }
        _intermediateRenderPassDescriptor = _intermediateTextures.map {
            let renderDescriptor = MTLRenderPassDescriptor()
            renderDescriptor.colorAttachments[0].texture = $0
            renderDescriptor.colorAttachments[0].loadAction = .dontCare
            renderDescriptor.colorAttachments[0].storeAction = .store
            return renderDescriptor
        }
        
        _rgbTexture = device.makeTexture(descriptor: descriptor)
        let rgbDescriptor = MTLRenderPassDescriptor()
        rgbDescriptor.colorAttachments[0].texture = _rgbTexture
        rgbDescriptor.colorAttachments[0].loadAction = .dontCare
        rgbDescriptor.colorAttachments[0].storeAction = .store
        _rgbDescriptor = rgbDescriptor
        
    }
    
    
    func captureBuffer(_ sampleBuffer: CMSampleBuffer!) {
        
        if _rgbDescriptor != nil,
            let textureCache = _textureCache,
            let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
            let commandQueue = _commandQueue,
            let currentColorFilter = _currentColorFilter,
            let colorArgs = _colorArgs,
            let rgbDescriptor = _rgbDescriptor
        {
            
            let commandBuffer = commandQueue.makeCommandBuffer()
            commandBuffer.enqueue()
            defer {
                commandBuffer.commit()
            }
            
            var y_texture: CVMetalTexture?
            let y_width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            let y_height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, .r8Unorm, y_width, y_height, 0, &y_texture)
            
            var uv_texture: CVMetalTexture?
            let uv_width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
            let uv_height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
            CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, .rg8Unorm, uv_width, uv_height, 1, &uv_texture)
            
            guard let yTexture = y_texture, let uvTexture = uv_texture else {
                    return
            }
            
            let luma = CVMetalTextureGetTexture(y_texture!)!
            let chroma = CVMetalTextureGetTexture(uv_texture!)!
            
            let yuvTextures:[MTLTexture] = [ luma, chroma ]
            
            // create the YUV->RGB pass
            createRenderPass(commandBuffer,
                             pipeline: currentColorFilter,
                             vertexIndex: 0,
                             fragmentBuffers: [colorArgs.bufferAndOffsetForElement(_currentColorBuffer)],
                             sourceTextures: yuvTextures,
                             descriptor: rgbDescriptor,
                             viewport: nil)
            
            CVMetalTextureCacheFlush(textureCache, 0)
            
        }
    }
    
}

// MARK: - MTKViewDelegate

extension FilterRenderer: MTKViewDelegate {
    
    @objc func draw(in view: MTKView) {
        
        let currentOrientation:UIInterfaceOrientation = _isiPad ? UIApplication.shared.statusBarOrientation : .portrait
        
        guard let commandQueue = _commandQueue,
              let renderSemaphore = _renderSemaphore,
              let currentDrawable = view.currentDrawable else {
            return
        }
        
        let commandBuffer = commandQueue.makeCommandBuffer()
        
        let _ = renderSemaphore.wait(timeout: DispatchTime.distantFuture)
        // get the command buffer
        commandBuffer.enqueue()
        defer {
            // commit buffers to GPU
            commandBuffer.addCompletedHandler() {
                (cmdb:MTLCommandBuffer!) in
                renderSemaphore.signal()
                return
            }
            
            commandBuffer.present(currentDrawable)
            commandBuffer.commit()
        }
        
        guard let rgbTexture = _rgbTexture,
              let currentOffset = _vertexStart[currentOrientation], _rgbTexture != nil else {
            return
        }
        
        var sourceTexture:MTLTexture = rgbTexture
        var destDescriptor:MTLRenderPassDescriptor = _intermediateRenderPassDescriptor[_currentDestTexture]
        
        func swapTextures() {
            self._currentSourceTexture += 1
            sourceTexture = self._intermediateTextures[self._currentSourceTexture]
            destDescriptor = self._intermediateRenderPassDescriptor[self._currentDestTexture]
        }
        
        let secondaryTexture = rgbTexture
        
        // apply all render passes in the current filter
        if  let filterArgs = _filterArgs,
            let screenDescriptor = view.currentRenderPassDescriptor {
            
            let filterParameters = [filterArgs.bufferAndOffsetForElement(_currentFilterBuffer)]
            for filter in _currentVideoFilter {
                
                if let renderState = filter as? MTLRenderPipelineState {
                    
                    createRenderPass(commandBuffer,
                                     pipeline: renderState,
                                     vertexIndex: 0,
                                     fragmentBuffers: filterParameters,
                                     sourceTextures: [sourceTexture, secondaryTexture, rgbTexture],
                                     descriptor: destDescriptor,
                                     viewport: nil)
                    
                    swapTextures()
                    
                } else if let computeState = filter as? MTLComputePipelineState {
                    
                    createComputePass(commandBuffer,
                                     pipeline: computeState,
                                     textures: [sourceTexture, secondaryTexture, rgbTexture],
                                     descriptor: destDescriptor,
                                     viewport: nil,
                                     name: nil)
                    
                } else if let mpsType = filter as? MPSFilerType {
                    
                    createMPSPass(commandBuffer,
                                  texture: sourceTexture,
                                  type: mpsType,
                                  sigma: nil,
                                  diameter: nil)
                    
                }
                
            }
            
            if let piplineState = invertScreen ? _screenInvertState : _screenBlitState {
            
                createRenderPass(commandBuffer,
                                 pipeline: piplineState,
                                 vertexIndex: currentOffset,
                                 fragmentBuffers: filterParameters,
                                 sourceTextures: [sourceTexture, secondaryTexture, rgbTexture],
                                 descriptor: screenDescriptor,
                                 viewport: _viewport)
                
                swapTextures()
                
            }
            
        }
        
    }
    
    @objc func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
        if let rgbTexture = _rgbTexture {
            
            let iWidth = Double(rgbTexture.width)
            let iHeight = Double(rgbTexture.height)
            let aspect = iHeight / iWidth
            
            
            if size.width > size.height {
                let newHeight = Double(size.width) * aspect
                let diff = (Double(size.height) - newHeight) * 0.5
                _viewport = MTLViewport(originX: 0.0, originY: diff, width: Double(size.width), height: newHeight, znear: 0.0, zfar: 1.0)
            } else {
                let newHeight = Double(size.height) * aspect
                let diff = (Double(size.width) - newHeight) * 0.5
                _viewport = MTLViewport(originX: diff, originY: 0.0, width: newHeight, height: Double(size.height), znear: 0.0, zfar: 1.0)
            }
            
            if _viewport.originX < 0.0 {
                _viewport.originX = 0.0
            }
            if _viewport.originY < 0.0 {
                _viewport.originY = 0.0
            }
            
            if _viewport.width > Double(size.width) {
                _viewport.width = Double(size.width)
            }
            
            if _viewport.height > Double(size.height) {
                _viewport.height = Double(size.height)
            }
            
        }
        
    }
    
}
