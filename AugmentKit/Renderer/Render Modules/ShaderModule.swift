//
//  RenderModule.swift
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
import Metal
import MetalKit

// MARK: - ShaderModuleState

enum ShaderModuleState {
    case uninitialized
    case initializing
    case ready
}

// MARK: - ShaderModule protocol

protocol ShaderModule {
    
    //
    // State
    //
    
    var moduleIdentifier: String { get }
    var state: ShaderModuleState { get }
    /// Lower layer modules are executed first. By convention, modules that to not participate directly in rendering have negavive values. Also by convention, the camera plane is layer 0, 1 - 9 and Int.max are reseved for the renderer.
    var renderLayer: Int { get }
    var errors: [AKError] { get set }
    /// An array of shared module identifiers that it this module will rely on in the draw phase.
    var sharedModuleIdentifiers: [String]? { get }
    
    //
    // Bootstrap
    //
    
    /// Initialize the buffers that will me managed and updated in this module.
    /// - parameters:
    ///   - withDevice: An `MTLDevice`.
    ///   - maxInFlightFrames: The number of in flight render frames.
    ///   - maxInstances: The maximum number of model instances. Must be a power of 2.
    func initializeBuffers(withDevice: MTLDevice, maxInFlightFrames: Int, maxInstances: Int)
    
    //
    // Per Frame Updates
    //
    
    /// The buffer index is the index into the ring on in flight buffers
    func updateBufferState(withBufferIndex: Int)
    
    /// Called when Metal and the GPU has fully finished proccssing the commands we're encoding this frame. This indicates when the dynamic buffers, that we're writing to this frame, will no longer be needed by Metal and the GPU. This gets called per frame.
    func frameEncodingComplete(renderPasses: [RenderPass])
    
    //
    // Util
    //
    
    func recordNewError(_ akError: AKError)
    
}



// MARK: - SkinningModule

protocol SkinningModule {
    
}

extension SkinningModule {
    
    //  Find the largest index of time stamp <= key
    func lowerBoundKeyframeIndex(_ keyTimes: [Double], key: Double) -> Int? {
        
        guard !keyTimes.isEmpty else {
            return nil
        }
        
        guard let first = keyTimes.first else {
            return nil
        }
        
        guard let last = keyTimes.last else {
            return nil
        }
        
        if key < first {
            return 0
        }
        if key > last {
            return keyTimes.count - 1
        }
        
        var range = 0..<keyTimes.count
        
        while range.endIndex - range.startIndex > 1 {
            let midIndex = range.startIndex + (range.endIndex - range.startIndex) / 2
            
            if keyTimes[midIndex] == key {
                return midIndex
            } else if keyTimes[midIndex] < key {
                range = midIndex..<range.endIndex
            } else {
                range = range.startIndex..<midIndex
            }
        }
        return range.startIndex
    }
    
    //  Evaluate the skeleton animation at a particular time
    func evaluateAnimation(_ skeleton: SkeletonData, keyframeIndex: Int) -> [matrix_float4x4] {
        
        let parentIndices = skeleton.parentIndices
        
        // get the translations and rotations
        let poseTranslations: [SIMD3<Float>] = {
            if keyframeIndex < skeleton.animations.count {
                return skeleton.animations[keyframeIndex].translations
            } else {
                return Array(repeating: SIMD3<Float>(0, 0, 0), count: skeleton.jointCount)
            }
        }()
        let poseRotations: [simd_quatf] = {
            if keyframeIndex < skeleton.animations.count {
                return skeleton.animations[keyframeIndex].rotations
            } else {
                return Array(repeating: simd_quatf(), count: skeleton.jointCount)
            }
        }()
        
        var keyframeTransforms = [matrix_float4x4]()
        keyframeTransforms.reserveCapacity(parentIndices.count)
        
        // using the parent indices create the worldspace transformations and store
        for index in 0..<parentIndices.count {
            let parentIndex = parentIndices[index]
            
            var localMatrix = simd_matrix4x4(poseRotations[index])
            let translation = poseTranslations[index]
            localMatrix.columns.3 = SIMD4<Float>(translation.x, translation.y, translation.z, 1.0)
            if let index = parentIndex {
                keyframeTransforms.append(keyframeTransforms[index] * localMatrix)
            } else {
                keyframeTransforms.append(localMatrix)
            }
        }
        
        return keyframeTransforms
    }
    
    //  Using the the skeletonData and a keyframe animation transform, compute the joint transform
    func evaluateJointTransforms(animationTransforms: [matrix_float4x4], skeletonData: SkeletonData) -> [matrix_float4x4] {
        let jointCount = skeletonData.jointCount
        let inverseBindTransforms = skeletonData.inverseBindTransforms
        let restTransforms = skeletonData.restTransforms
        
        var jointTransforms = [matrix_float4x4]()
        jointTransforms.reserveCapacity(jointCount)
        for index in 0..<skeletonData.jointCount {
            jointTransforms.append(animationTransforms[index] * restTransforms[index] * inverseBindTransforms[index])
        }
        
        return jointTransforms
    }
    
}

