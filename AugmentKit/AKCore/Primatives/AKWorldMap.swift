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


import ARKit
import UIKit
import simd

/**
 Wraps ARKit's `ARWorldMap` and adds world location properties which ties the World Map to a specific location in the real world. The `ARWorldMap` provides enough information to tie all of the anchors in `arWorldMap` to real world locations. The `transform`, a position in the coordinate space of the `arWorldMap` is mapped to the `latitude`, `longitude`, and `elevation`. From one knowd reference location,  the `latitude`, `longitude`, and `elevation` of every other point in the coordinate space of `arWorldMap` can be calculated.
 */
open class AKWorldMap: NSObject, NSCopying, NSSecureCoding {
    
    /**
     The latitude of a reference location given by the `transform`
     */
    public var latitude: Double?
    /**
     The longitude of a reference location given by the `transform`
     */
    public var longitude: Double?
    /**
     The elevation of a reference location given by the `transform`
     */
    public var elevation: Double?
    /**
     The position transform of a reference location in the coordinate space of the `arWordMap`
     */
    public var transform: matrix_float4x4?
    /**
     An `ARWorldMap` instance aquired from ARKit
     */
    public var arWorldMap: ARWorldMap
    /**
     Initialize a new object with an `ARWorldMap` and an `AKWorldLocation`
     - Parameters:
        - withARWorldMap: An `ARWorldMap` instance aquired from ARKit
        - worldLocation: An `AKWorldLocation` instance used as a reference location to populate the `latitude`, `longitude`, and `elevation`
     */
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
    
    /// :nodoc:
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
    
    /// :nodoc:
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
    
    /// :nodoc:
    public func encode(with aCoder: NSCoder) {
        aCoder.encode(latitude, forKey: "latitude")
        aCoder.encode(longitude, forKey: "longitude")
        aCoder.encode(elevation, forKey: "elevation")
        if let transform = transform {
            aCoder.encodeMatrixFloat4x4(transform, forKey: "transform")
        }
        arWorldMap.encode(with: aCoder)
    }
    
    /// :nodoc:
    public static var supportsSecureCoding: Bool = true
    
}

/// :nodoc:
extension NSCoder {
    
    /// :nodoc:
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
    
    /// :nodoc:
    func encodeMatrixFloat4x4(_ value: matrix_float4x4, forKey key: String) {
        let array: [Float] = [value.columns.0.x, value.columns.0.y, value.columns.0.z, value.columns.0.w, value.columns.1.x, value.columns.1.y, value.columns.1.z, value.columns.1.w, value.columns.2.x, value.columns.2.y, value.columns.2.z, value.columns.2.w, value.columns.3.x, value.columns.3.y, value.columns.3.z, value.columns.3.w]
        encode(array, forKey: key)
    }
}
