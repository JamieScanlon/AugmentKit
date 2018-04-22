//
//  AKWorldDistance.swift
//  AugmentKit
//
//  Created by Jamie Scanlon on 4/21/18.
//  Copyright © 2018 TenthLetterMade. All rights reserved.
//

import Foundation

// MARK: - AKWorldDistance

//  A data structure that represents the distance in meters between tow points in world space.
public struct AKWorldDistance {
    public var metersX: Double
    public var metersY: Double
    public var metersZ: Double
    public private(set) var distance2D: Double
    public private(set) var distance3D: Double
    
    public init(metersX: Double = 0, metersY: Double = 0, metersZ: Double = 0) {
        self.metersX = metersX
        self.metersY = metersY
        self.metersZ = metersZ
        let planarDistance = sqrt(metersX * metersX + metersZ * metersZ)
        self.distance2D = planarDistance
        self.distance3D = sqrt(planarDistance * planarDistance + metersY * metersY)
    }
}
