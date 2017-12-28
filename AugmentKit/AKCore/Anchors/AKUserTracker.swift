//
//  AKUserTracker.swift
//  AugmentKit
//
//  Created by Jamie Scanlon on 12/24/17.
//  Copyright © 2017 TenthLetterMade. All rights reserved.
//

import Foundation
import simd

public class UserPosition: AKRelativePosition {
    public init() {
        super.init(withTransform: matrix_identity_float4x4)
    }
}

public struct AKUserTracker: AKAugmentedTracker {
    
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
    
}
