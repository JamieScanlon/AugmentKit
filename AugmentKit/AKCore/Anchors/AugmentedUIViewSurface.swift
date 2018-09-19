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

public class AugmentedUIViewSurface: AugmentedSurfaceAnchor {
    
    public var view: UIView
    public fileprivate(set) var bytesPerRow: Int
    public fileprivate(set) var totalBytes: Int
    
    public init(withView view: UIView, at location: AKWorldLocation, heading: AKHeading? = nil) {
        
        self.view = view
        
        let width = view.bounds.width
        let height = view.bounds.height
        let maxDimension = max(width, height)
        let normalizedWidth = width / maxDimension
        let normalizedHeight = height / maxDimension
        let extent = vector_float3(Float(normalizedWidth), Float(normalizedHeight), 0)
        
        var buffer: Data
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let numChannels = 4
        self.bytesPerRow = numChannels * Int(width)
        self.totalBytes = self.bytesPerRow * Int(height)
        if let context = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: self.bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) {
        
            // draw the view to the buffer
            view.layer.render(in: context)
            
            // get pixel data
            buffer = Data(bytes: context.data!, count: self.totalBytes)
            
        } else {
            buffer = Data()
        }
        
        let texture = MDLTexture(data: buffer, topLeftOrigin: false, name: "UIView texture", dimensions: vector2(Int32(width), Int32(height)), rowStride: self.bytesPerRow, channelCount: numChannels, channelEncoding: .uInt8, isCube: false)
        
        super.init(withTexture: texture, extent: extent, at: location, heading: heading, withAllocator: nil)
        
        self.shaderPreference = .simple
        
    }
    
    private func updatedViewTextureData() -> Data {
        
        // Generate a new texture
        
        let width = view.bounds.width
        let height = view.bounds.height
        
        var buffer: Data
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let numChannels = 4
        let bytesPerRow = numChannels * Int(width)
        if let context = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) {
            
            // draw the view to the buffer
            view.layer.render(in: context)
            
            // get pixel data
            buffer = Data(bytes: context.data!, count: bytesPerRow * Int(height))
            
        } else {
            buffer = Data()
        }
        
        return buffer
        
    }
    
}
