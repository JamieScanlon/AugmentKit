//
//  AKMeshProvider.swift
//  AugmentKit
//
//  Created by Jamie Scanlon on 11/27/17.
//  Copyright © 2017 TenthLetterMade. All rights reserved.
//

import Foundation
import ModelIO

class AKMeshProvider: MeshProvider {
    
    static let sharedInstance = AKMeshProvider()
    
    public func registerMesh(_ mdlAsset: MDLAsset, forObjectType type: String) {
        meshesByType[type] = mdlAsset
    }
    
    public func loadMesh(forObjectType type: String, completion: (MDLAsset?) -> Void) {
        
        if let anchorAsset = meshesByType[AKObject.type] {
            completion(anchorAsset)
        } else {
            print("Warning - Failed to find an MDLAsset for type: \(type).")
            completion(nil)
        }
        
    }
    
    // MARK: - Private
    
    private var meshesByType = [String: MDLAsset]()
    
}
