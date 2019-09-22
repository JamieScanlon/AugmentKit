//
//  GPUPassTexture.swift
//  AugmentKit
//
//  Created by Marvin Scanlon on 8/6/19.
//  Copyright © 2019 TenthLetterMade. All rights reserved.
//

import Foundation

class GPUPassTexture {
    
    var texture: MTLTexture?
    var label: String?
    var shaderAttributeIndex: Int = 0
    var mipLevels: Int = 1
    fileprivate(set) var mippedTextures = [MTLTexture]()
    fileprivate(set) var mippedSizes = [Int]()
    
    init(texture: MTLTexture? = nil, label: String?, shaderAttributeIndex: Int = 0, mipLevels: Int = 1) {
        self.texture = texture
        self.label = label
        self.shaderAttributeIndex = shaderAttributeIndex
        self.mipLevels = mipLevels
    }
    
    func roughness(for lod: Int) -> Float {
        guard mipLevels > 1 else {
            return 0
        }
        let roughness = Float(lod) / Float(mipLevels - 1)
        return roughness
    }
    
    func mipSize(for lod: Int) -> Int {
        guard let texture = texture else {
            return 0
        }
        let textureSize = max(texture.width, texture.height)
        guard mipLevels > 1 else {
            return textureSize
        }
        guard lod > 0 else {
            return textureSize
        }
        return textureSize / lod * 2
    }
    
    func generateMippedTextures() {
        
        guard let texture = texture else {
            mippedTextures = []
//            mippedThreadgroups = []
            mippedSizes = []
            return
        }
        
        var mipSize = max(texture.width, texture.height)
        
        guard mipLevels > 1 else {
            mippedTextures.append(texture)
//            let aThreadgroup = ThreadGroup(computePipelineState: threadGroup.computePipelineState, size: (width: mipSize, height: mipSize, depth: threadGroup.size.depth))
//            mippedThreadgroups.append(aThreadgroup)
            mippedSizes.append(mipSize)
            return
        }
        
        for lod in 0..<mipLevels {
            if let mippedTexture = texture.makeTextureView(pixelFormat: .rgba16Float, textureType: .typeCube, levels: lod..<(lod + 1), slices: 0..<6) {
                mippedTextures.append(mippedTexture)
//                let aThreadgroup = ThreadGroup(computePipelineState: threadGroup.computePipelineState, size: (width: mipSize, height: mipSize, depth: threadGroup.size.depth))
//                mippedThreadgroups.append(aThreadgroup)
                mippedSizes.append(mipSize)
            }
            mipSize = mipSize / 2
        }
    }
    
}
