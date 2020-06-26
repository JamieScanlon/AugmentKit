//
//  AKCapabilities.swift
//  AugmentKit
//
//  Created by Marvin Scanlon on 3/25/20.
//  Copyright © 2020 TenthLetterMade. All rights reserved.
//

import Foundation

/// For managing code paths that are under development. These development featues are turned off by default because they can affect performance.
public struct AKCapabilities {
    public static let ImageBasedLighting = false
    public static let SubsurfaceMap = false
    public static let AmbientOcclusionMap = true
    public static let EmissionMap = true
    public static let NormalMap = true
    public static let RoughnessMap = true
    public static let MetallicMap = true
    public static let SpecularMap = true
    public static let SpecularTintMap = true
    public static let AnisotropicMap = false
    public static let SheenMap = false
    public static let SheenTintMap = false
    public static let ClearcoatMap = false
    public static let ClearcoatGlossMap = false
    public static let EnvironmentMap = true
    public static let LevelOfDetail = true
}
