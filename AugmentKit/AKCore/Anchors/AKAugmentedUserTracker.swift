//
//  AKAugmentedUserTracker.swift
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
import simd

class UserPosition: AKRelativePosition {
    public init() {
        super.init(withTransform: matrix_identity_float4x4)
    }
}

//  An AR tracking object that follows the users position.
protocol AKAugmentedUserTracker: AKAugmentedTracker {
    var position: AKRelativePosition { get }
    func userPosition() -> AKRelativePosition?
}

public class UserTracker: AKAugmentedUserTracker {
    
    public static var type: String {
        return "userTracker"
    }
    public var model: AKModel
    public var identifier: UUID?
    public var position: AKRelativePosition
    
    public init(withModel model: AKModel, withUserRelativeTransform relativeTransform: matrix_float4x4) {
        self.model = model
        let myPosition = AKRelativePosition(withTransform: relativeTransform, relativeTo: UserPosition())
        self.position = myPosition
    }
    
    func userPosition() -> AKRelativePosition? {
        return position.parentPosition
    }
    
}
