//
//  AKSessionType.swift
//  AugmentKit
//
//  MIT License
//
//  Copyright (c) 2020 JamieScanlon
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

/**
 The type of AR session. The three main types of AR sessions are World Tracking, Face Tracking, and Body Tracking.
 */
public enum AKSessionType {
    /**
     Initializes the ARKit session with an `ARWorldTrackingConfiguration`
     */
    case worldTracking
    /**
     Initializes the ARKit session with an `ARFaceTrackingConfiguration`
     */
    case faceTracking
    /**
     Initializes the ARKit session with an `ARWorldTrackingConfiguration` with  `userFaceTrackingEnabled` set to `true`
     */
    case worldTrackingWithFaceDetection
    /**
     Initializes the ARKit session with an `ARFaceTrackingConfiguration` with  `supportsWorldTracking` set to `true`
     */
    case faceTrackingWithWorldTracking
    /**
     Initializes the ARKit session with an `ARBodyTrackingConfiguration`
     */
    case bodyTracking
}
