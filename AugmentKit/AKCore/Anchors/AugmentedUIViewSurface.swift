//
//  AugmentedUIViewSurface.swift
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

import UIKit
import simd
import CoreGraphics.CGImage
import ModelIO

/**
 A `AugmentedSurfaceAnchor` subclass that is able to display the contents of a `UIView` as the texture for the surface.
 */
open class AugmentedUIViewSurface: AugmentedSurfaceAnchor {
    
    /**
     A view that will be used as a texture for the surface
     */
    public var view: UIView
    /**
     Initialize a new object with a `UIView` and a `AKHeading`
     - Parameters:
        - withView: A `UIView` that will be captured and rendered on the surface.
        - at: The location of the anchor
        - heading: The heading for the anchor
     */
    public init(withView view: UIView, at location: AKWorldLocation, heading: AKHeading? = nil) {
        
        self.view = view
        
        let textureSize = TextureSize(width: Int(view.bounds.width), height: Int(view.bounds.height))
        
        let width = view.bounds.width
        let height = view.bounds.height
        let maxDimension = max(width, height)
        let normalizedWidth = width / maxDimension
        let normalizedHeight = height / maxDimension
        let extent = SIMD3<Float>(Float(normalizedWidth), Float(normalizedHeight), 0)

        let buffer = AugmentedUIViewSurface.viewTextureData(with: textureSize, view: self.view)

        let texture = MDLTexture(data: buffer, topLeftOrigin: true, name: "UIView texture", dimensions: textureSize.dimensions, rowStride: textureSize.bytesPerRow, channelCount: TextureSize.numChannels, channelEncoding: .uInt8, isCube: false)

        super.init(withTexture: texture, extent: extent, at: location, heading: heading, withAllocator: nil)
        
        self.shaderPreference = .simple
        self.needsColorTextureUpdate = true
        
    }
    
    /// Must be called on the main thread
    public func updateTextureWithCurrentPixelData(_ texture: MTLTexture) {
        
        let textureSize = TextureSize(width: Int(view.bounds.width), height: Int(view.bounds.height))
        let region = MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0), size: MTLSize(width: textureSize.width, height: textureSize.height, depth: 1))
        var data = AugmentedUIViewSurface.viewTextureData(with: textureSize, view: view)
        data.withUnsafeMutableBytes { bytes in
            let buffer = bytes.baseAddress!
            texture.replace(region: region, mipmapLevel: 0, withBytes: buffer, bytesPerRow: textureSize.bytesPerRow)
        }
        
    }
    
    fileprivate struct TextureSize {
        static let numChannels: Int = 4
        var width: Int
        var height: Int
        var bytesPerRow: Int {
            return AugmentedUIViewSurface.TextureSize.numChannels * width
        }
        var dimensions: SIMD2<Int32> {
            return SIMD2<Int32>(Int32(width), Int32(height))
        }
    }
    
    fileprivate static let colorSpace = CGColorSpaceCreateDeviceRGB()
    fileprivate static func viewTextureData(with textureSize: TextureSize, view: UIView) -> Data {
        
        // Generate a new texture
        var buffer: Data
        
        if let context = CGContext(data: nil, width: textureSize.width, height: textureSize.height, bitsPerComponent: 8, bytesPerRow: textureSize.bytesPerRow, space: AugmentedUIViewSurface.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) {
            
            // Use a top left origin
            context.translateBy(x: 0, y: CGFloat(textureSize.height))
            context.scaleBy(x: 1, y: -1)
            
            // draw the view to the buffer
            view.layer.render(in: context)
            
            
            // get pixel data
            buffer = Data(bytes: context.data!, count: textureSize.bytesPerRow * textureSize.height)
            
        } else {
            buffer = Data()
        }
        
        return buffer
        
    }
    
}
