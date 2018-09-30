//
//  AKWorldDistance.swift
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
//  SOFTWARE..
//

import Foundation

// MARK: - AKWorldDistance

/**
 Represents the distance in meters between two points in the AR world.
 */
public struct AKWorldDistance {
    /**
     Meters in the X direcrion
     */
    public var metersX: Double
    /**
     Meters in the Y direcrion
     */
    public var metersY: Double
    /**
     Meters in the Z direcrion
     */
    public var metersZ: Double
    /**
     The distance in the X/Z directrion in meters
     */
    public private(set) var distance2D: Double
    /**
     The distance in meters
     */
    public private(set) var distance3D: Double
    
    /**
     Initializes a new structure with meters X, Y, and Z
     - Parameters:
        - metersX: X value in meters
        - metersY: Y value in meters
        - metersZ: Z value in meters
     */
    public init(metersX: Double = 0, metersY: Double = 0, metersZ: Double = 0) {
        self.metersX = metersX
        self.metersY = metersY
        self.metersZ = metersZ
        let planarDistance = sqrt(metersX * metersX + metersZ * metersZ)
        self.distance2D = planarDistance
        self.distance3D = sqrt(planarDistance * planarDistance + metersY * metersY)
    }
}
