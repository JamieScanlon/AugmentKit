//
//  DefaultComputeModule.swift
//  AugmentKit
//
//  Created by Marvin Scanlon on 7/13/19.
//  Copyright © 2019 TenthLetterMade. All rights reserved.
//

import Foundation

class DefaultComputeModule: ComputeModule {
    
    var moduleIdentifier: String {
        return "DefaultComputeModule"
    }
    var state: ShaderModuleState = .uninitialized
    var renderLayer: Int {
        return -2
    }
    
    var errors = [AKError]()
    
    func initializeBuffers(withDevice device: MTLDevice, maxInFlightFrames: Int, maxInstances: Int, computePass: ComputePass) {
        
        if computePass.usesGeometry {
            computePass.geometryBuffer.initialize(withDevice: device, options: .storageModeShared)
        }
    }
}
