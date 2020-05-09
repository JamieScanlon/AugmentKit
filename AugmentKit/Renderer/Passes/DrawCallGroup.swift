//
//  DrawCallGroup.swift
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

import Foundation

// MARK: - DrawCallGroup

/// An abstraction for a collection of `DrawCall`'s. A `DrawCallGroup` helps organize a sequence of `DrawCall`'s into a logical group. Multiple `DrawCallGroup`'s can then be rendered, in order, in a single pass. A `DrawCallGroup` can be thought of as a model level abstraction where a model contains one or more mesh and each mesh is a `DrawCall`
class DrawCallGroup {
    
    /// The `uuid` is usually set to match the `identifier` property of the corresponding `AKGeometricEntity`
    var uuid: UUID
    var moduleIdentifier: String?
    var numDrawCalls: Int {
        return drawCalls.count
    }
    /// The value of this property is set automatically when initializing with an array of draw calls and is `true` if any `DrawCall` has a non-null `skeleton` prorperty set. When this is false the renderer can skip steps for calculating skinned skeleton animations resulting in some efficiency gain.
    var useSkeleton = false
    /// If `false` the renderer will not generate a shadow for this `DrawCallGroup`
    var generatesShadows: Bool
    
    /// The order of `drawCalls` is usually taken directly from the order in which the meshes are parsed from the MDLAsset.
    /// see: `ModelIOTools.meshGPUData(from asset: MDLAsset, device: MTLDevice, textureBundle: Bundle, vertexDescriptor: MDLVertexDescriptor?, frameRate: Double = 60, shaderPreference: ShaderPreference = .pbr)`
    var drawCalls = [DrawCall]()
    
    init(drawCalls: [DrawCall] = [], uuid: UUID = UUID(), generatesShadows: Bool = true) {
        self.uuid = uuid
        self.drawCalls = drawCalls
        self.generatesShadows = generatesShadows
        if drawCalls.first(where: {$0.usesSkeleton}) != nil {
            self.useSkeleton = true
        }
    }
    
    func markTexturesAsVolitile() {
        drawCalls.forEach{ $0.markTexturesAsVolitile() }
    }
    
    func markTexturesAsNonVolitile() {
        drawCalls.forEach{ $0.markTexturesAsNonVolitile() }
    }
}

extension DrawCallGroup: CustomDebugStringConvertible, CustomStringConvertible {
    
    /// :nodoc:
    var description: String {
        return debugDescription
    }
    /// :nodoc:
    var debugDescription: String {
        let myDescription = "<DrawCallGroup: \(Unmanaged.passUnretained(self).toOpaque())> uuid: \(uuid), moduleIdentifier:\(moduleIdentifier?.debugDescription ?? "None"), numDrawCalls: \(numDrawCalls), useSkeleton: \(useSkeleton)"
        return myDescription
    }
}
