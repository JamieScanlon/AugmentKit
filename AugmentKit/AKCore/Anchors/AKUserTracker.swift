//
//  AKUserTracker.swift
//  AugmentKit
//
//  Created by Jamie Scanlon on 12/24/17.
//  Copyright © 2017 TenthLetterMade. All rights reserved.
//

import Foundation
import simd

class UserPosition: AKRelativePosition {
    
    init() {
        let transform = matrix_identity_float4x4
        super.init(withTransform: transform.translate(x: 0, y: -3, z: 0))
    }
}

public struct AKUserTracker: AKAugmentedTracker {
    
    public static var type: String {
        return "userTracker"
    }
    public var model: AKModel
    public var identifier: UUID?
    public var position: AKRelativePosition
    
    public init(withModel model: AKModel) {
        self.model = model
        self.position = UserPosition()
    }
    
}
