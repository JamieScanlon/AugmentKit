//
//  AKMeshGeometry.swift
//  AugmentKit
//
//  MIT License
//
//  Copyright (c) 2020 JamieScanlon
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
import ARKit

/// This is a  thin protocol wrapper around `ARPlaneGeometry` and `ARFaceGeometry`
public protocol AKMeshGeometry {
    /// An array of vertex positions for each point in the plane mesh.
    var vertices: [vector_float3] { get }
    /// An array of texture coordinate values for each point in the plane mesh.
    var textureCoordinates: [vector_float2] { get }
    /// The number of triangles described by the `triangleIndices` buffer.
    var triangleCount: Int { get }
    /// An array of indices describing the triangle mesh formed by the plane geometry's vertex data.
    var triangleIndices: [Int16] { get }
}

extension ARPlaneGeometry: AKMeshGeometry {
    
}

extension ARFaceGeometry: AKMeshGeometry {
    
}
