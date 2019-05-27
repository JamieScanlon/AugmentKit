//
//  DeviceManager.swift
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
/**
 Provides methods for geting information about the users device
 */
open class DeviceManager {
    /**
     Singleton instance
     */
    public static var shared = DeviceManager()
    /**
     Gets the screen size in pixels
     - Returns: A `CGSize` object containing the screen size in pixels
     */
    public  func screenSizeInPixels() -> CGSize {
        let screen = UIScreen.main
        let height = screen.nativeBounds.size.height
        let width = screen.nativeBounds.size.width
        return CGSize(width: width, height: height)
    }
    /**
     Gets the screen size in points
     - Returns: A `CGSize` object containing the screen size in points
     */
    public func screenSizeInPoints() -> CGSize {
        let screen = UIScreen.main
        let height = screen.bounds.size.height
        let width = screen.bounds.size.width
        return CGSize(width: width, height: height)
    }
    
}
