//
//  MotionManager.swift
//  AugmentKit2
//
//  Created by Jamie Scanlon on 7/9/17.
//  Copyright © 2017 TenthLetterMade. All rights reserved.
//

import Foundation
import CoreMotion
import GLKit

// MARK: - ViewPort

struct ViewPort {
    var width: Double = 0
    var height: Double = 0
    func aspectRatio() -> Double {
        return width/height
    }
}

// MARK: - MotionManager

protocol MotionManager {
    var cmMotionManager: CMMotionManager { get }
    var operationQueue: OperationQueue { get }
    var viewPort: ViewPort { get }
}

extension MotionManager {
    
    func startTrackingCompasDirection() {
        cmMotionManager.startDeviceMotionUpdates(using: .xTrueNorthZVertical, to: operationQueue) { (deviceMotion, error) in
            if let error = error {
                // TODO: Log errors
            } else if let motion = deviceMotion {
                let heading = self.headingCorrectedForTilt(withMotion: motion, viewPort: self.viewPort)
                print(heading)
            }
        }
    }
    func stopTrackingCompasDirection() {
        cmMotionManager.stopMagnetometerUpdates()
    }
    
    func headingCorrectedForTilt(withMotion motion: CMDeviceMotion, viewPort: ViewPort) -> Float?{
        
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

