//
//  MotionManager.swift
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
import CoreMotion
import GLKit

// MARK: - ViewPort

public struct ViewPort {
    public var width: Double = 0
    public var height: Double = 0
    public func aspectRatio() -> Double {
        return width/height
    }
}

// MARK: - MotionManager

public protocol MotionManager {
    var cmMotionManager: CMMotionManager { get }
    var operationQueue: OperationQueue { get }
    var viewPort: ViewPort { get }
}

public extension MotionManager {
    
    public func startTrackingCompasDirection() {
        cmMotionManager.startDeviceMotionUpdates(using: .xTrueNorthZVertical, to: operationQueue) { (deviceMotion, error) in
//            if let error = error {
//                // TODO: Log errors
//            } else if let motion = deviceMotion {
//                let heading = self.headingCorrectedForTilt(withMotion: motion, viewPort: self.viewPort)
//            }
        }
    }
    public func stopTrackingCompasDirection() {
        cmMotionManager.stopMagnetometerUpdates()
    }
    
    public func headingCorrectedForTilt(withMotion motion: CMDeviceMotion, viewPort: ViewPort) -> Float?{
        
        let aspect = fabsf(Float(viewPort.width / viewPort.height))
        let projectionMatrix = GLKMatrix4MakePerspective(GLKMathDegreesToRadians(45.0), aspect, 0.1, 100)
        
        
        let r = motion.attitude.rotationMatrix
        let camFromIMU = GLKMatrix4Make(Float(r.m11), Float(r.m12), Float(r.m13), 0,
                                        Float(r.m21), Float(r.m22), Float(r.m23), 0,
                                        Float(r.m31), Float(r.m32), Float(r.m33), 0,
                                        0,     0,     0,     1)
        
        let viewFromCam = GLKMatrix4Translate(GLKMatrix4Identity, 0, 0, 0);
        let imuFromModel = GLKMatrix4Identity
        let viewModel = GLKMatrix4Multiply(imuFromModel, GLKMatrix4Multiply(camFromIMU, viewFromCam))
        var isInvertible : Bool = false
        let modelView = GLKMatrix4Invert(viewModel, &isInvertible);
        var viewport = [Int32](repeating: 0,count:4)
        
        viewport[0] = 0;
        viewport[1] = 0;
        viewport[2] = Int32(viewPort.width);
        viewport[3] = Int32(viewPort.height);
        
        var success: Bool = false
        let vector3 = GLKVector3Make(Float(viewPort.width)/2, Float(viewPort.height)/2, 1.0)
        let calculatedPoint = GLKMathUnproject(vector3, modelView, projectionMatrix, &viewport, &success)
        
        return success ? atan2f(-calculatedPoint.y, calculatedPoint.x) : nil
    }
    
}

