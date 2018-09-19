//
//  AKWorldMap.swift
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
//  Extends ARKit's ARWorldMap to add a world location properties which ties the
//  World Map to a specific location in the real world.

import ARKit
import UIKit
import simd

public class AKWorldMap: NSObject, NSCopying, NSSecureCoding {
    
    public var latitude: Double?
    public var longitude: Double?
    public var elevation: Double?
    public var transform: matrix_float4x4?
    public var arWorldMap: ARWorldMap
    
    public init(withARWorldMap arWorldMap: ARWorldMap , worldLocation: AKWorldLocation? = nil) {
        self.arWorldMap = arWorldMap
        if let worldLocation = worldLocation {
            self.latitude = worldLocation.latitude
            self.longitude = worldLocation.longitude
            self.elevation = worldLocation.elevation
        }
        super.init()
    }
    
    // MARK: NSCopying
    
    public func copy(with zone: NSZone? = nil) -> Any {
        let aCopy = super.copy()
        if aCopy is AKWorldMap {
            (aCopy as! AKWorldMap).latitude = latitude
            (aCopy as! AKWorldMap).longitude = longitude
            (aCopy as! AKWorldMap).elevation = elevation
            (aCopy as! AKWorldMap).transform = transform
            (aCopy as! AKWorldMap).arWorldMap = arWorldMap.copy() as! ARWorldMap
        }
        return aCopy
    }
    
    // MARK: NSSecureCoding
    
    public required init?(coder aDecoder: NSCoder) {
        guard let worldMap = ARWorldMap(coder: aDecoder) else {
            return nil
        }
        self.latitude = aDecoder.decodeDouble(forKey: "latitude")
        self.longitude = aDecoder.decodeDouble(forKey: "longitude")
        self.elevation = aDecoder.decodeDouble(forKey: "elevation")
        self.transform = aDecoder.decodeMatrixFloat4x4(forKey: "transform")
        self.arWorldMap = worldMap
    }
    
    public func encode(with aCoder: NSCoder) {
        aCoder.encode(latitude, forKey: "latitude")
        aCoder.encode(longitude, forKey: "longitude")
        aCoder.encode(elevation, forKey: "elevation")
        if let transform = transform {
            aCoder.encodeMatrixFloat4x4(transform, forKey: "transform")
        }
        arWorldMap.encode(with: aCoder)
    }
    
    public static var supportsSecureCoding: Bool = true
    
}

extension NSCoder {
    func decodeMatrixFloat4x4(forKey key:String) -> matrix_float4x4? {
        guard let array = decodeObject(forKey: key) as? [Float] else {
            return nil
        }
        guard array.count == 16 else {
            return nil
        }
        return matrix_float4x4(
            [array[0], array[1], array[2], array[3]],
            [array[4], array[5], array[6], array[7]],
            [array[8], array[9], array[10], array[11]],
            [array[12], array[13], array[14], array[15]]
        )
    }
    
    func encodeMatrixFloat4x4(_ value: matrix_float4x4, forKey key: String) {
        let array: [Float] = value.columns.0.map({$0}) + value.columns.1.map({$0}) + value.columns.2.map({$0}) + value.columns.3.map({$0})
        encode(array, forKey: key)
    }
}
