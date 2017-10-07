//
//  AKAnchor.swift
//  AugmentKit2
//
//  MIT License
//
//  Copyright (c) 2017 JamieScanlon
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
import ModelIO

// MARK: - AKAnchor

protocol AKAnchor {
    
    static var type: String { get }
    var transform: matrix_float4x4 { get set }
    var mdlAsset: MDLAsset { get }
    
}

// MARK: - AKAugmentedAnchor

//  Represents an anchor placed in the AR world. This anchor only exists in the AR world
//  as opposed to a real anchor like a detected horizontal / vertical plane which exists
//  in the physical world.
protocol AKAugmentedAnchor: AKAnchor {
    
}

extension AKAugmentedAnchor {
    
    // This function sets the transform of this anchor given an origin location.
    // The origin location is usually the location of the camera when the AR session starts.
    mutating func setLocation(_ location: AKWorldLocation, withOrigin originLocation: AKWorldLocation) {
        let worldDistoance = AKLocationUtility.worldDistance(atLocation: originLocation, to: location)
        let myTransform = matrix_identity_float4x4
        transform = myTransform.translate(x: Float(worldDistoance.metersX), y: Float(worldDistoance.metersY), z: Float(worldDistoance.metersZ))
    }
    
}

// MARK: - AKRealAnchor

//  Represents an anchor in the AR world that is tied to an object in the real world
//  for example a detected horizontal / vertical plane wich represents a table or wall
protocol AKRealAnchor: AKAnchor {
    
}
