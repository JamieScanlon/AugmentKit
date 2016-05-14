//
//  MetalView.swift
//  AccessibleVideo
//
//  Created by Luke Groeninger on 10/5/14.
//  Copyright (c) 2014 Luke Groeninger. All rights reserved.
//

import Foundation
import UIKit
import Metal
import MetalKit
import QuartzCore

class MetalView:MTKView {
    
    override func didMoveToWindow() {
        if let win = window {
            contentScaleFactor = win.screen.nativeScale
        }
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        self.opaque = true
        self.backgroundColor = nil
        self.presentsWithTransaction = false
        self.colorPixelFormat = .BGRA8Unorm
        self.framebufferOnly = false
    }
    
    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        self.opaque = true
        self.backgroundColor = nil
        self.presentsWithTransaction = false
        self.colorPixelFormat = .BGRA8Unorm
        self.framebufferOnly = false
    }

    /*
    func display() {
        autoreleasepool {
            if self._layerSizeDidUpdate {
                var drawableSize = self.bounds.size
                drawableSize.width *= self.contentScaleFactor
                drawableSize.height *= self.contentScaleFactor
                self._metalLayer.drawableSize = drawableSize
                self.delegate.resize(drawableSize)
                self._layerSizeDidUpdate = false
            }
            self.delegate.render(self)
            self._currentDrawable = nil
        }
    }
    */
    override func layoutSubviews() {
        super.layoutSubviews()
        //_layerSizeDidUpdate = true
    }
    
}
