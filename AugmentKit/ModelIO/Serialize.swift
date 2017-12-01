//
//  Serialize.swift
//  AugmentKit2
//
//  MIT License
//
//  Copyright (c) 2017 JamieScanlon
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
//
//  This class ads NSCoding extensions for serializing and deserializing Models.
//
//  Based heavily on "From Art to Engine with Model I/O" WWDC 2017 talk.
//  https://developer.apple.com/videos/play/wwdc2017/610/
//  Sample Code: https://developer.apple.com/sample-code/wwdc/2017/ModelIO-from-MDLAsset-to-Game-Engine.zip
//

import Foundation
import ModelIO

// MARK: - ModelSerializer

extension ModelParser {
    
    func serialize(toFilePath filePath: String) {
        
        // Serialize data.
        NSKeyedArchiver.archiveRootObject(ModelParser.CodingWrapper(scene: self), toFile: filePath)
        
    }
    
    static func deserialize(fromFilePath filePath: String) -> ModelParser? {
        
        let url = URL(fileURLWithPath: filePath)
        
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        
        return NSKeyedUnarchiver.unarchiveObject(with: data) as? ModelParser
        
    }
    
}

// MARK: - NSCoder Extensions

extension MDLVertexAttribute {
    
    //  Adds NSCoding support to MDLVertexAttribute
    @objc(MDLVertexAttributeCodingWrapper)
    class CodingWrapper: NSObject, NSCoding {
        var data: MDLVertexAttribute?

        init(_ vertexAttribute: MDLVertexAttribute) {
            self.data = vertexAttribute
        }

        required init?(coder aDecoder: NSCoder) {
            data = MDLVertexAttribute()

            let name = aDecoder.decodeObject(forKey: "name") as? String ?? ""
            let format = aDecoder.decodeObject(forKey: "format") as? UInt ?? 0
            let offset = aDecoder.decodeObject(forKey: "offset") as? UInt ?? 0
            let bufferIndex = aDecoder.decodeObject(forKey: "bufferIndex") as? UInt ?? 0

            data = MDLVertexAttribute(name: name,
                                      format: MDLVertexFormat(rawValue:format)!,
                                      offset: Int(offset),
                                      bufferIndex: Int(bufferIndex))
        }

        func encode(with aCoder: NSCoder) {
            aCoder.encode(NSString(string: data!.name), forKey: "name")
            aCoder.encode(NSNumber(value: data!.format.rawValue), forKey: "format")
            aCoder.encode(NSNumber(value: data!.offset), forKey: "offset")
            aCoder.encode(NSNumber(value: data!.bufferIndex), forKey: "bufferIndex")
        }
    }
}

extension MDLVertexDescriptor {
    
    //  Adds NSCoding support to MDLVertexDescriptor
    @objc(MDLVertexDescriptorCodingWrapper)
    class CodingWrapper: NSObject, NSCoding {
        var data: MDLVertexDescriptor?

        init(_ vertexDescriptor: MDLVertexDescriptor) {
            self.data = vertexDescriptor
        }

        required init?(coder aDecoder: NSCoder) {
            data = MDLVertexDescriptor()

            let decodedAttributeWrappers = aDecoder.decodeObject(forKey: "attributes")
                as? [MDLVertexAttribute.CodingWrapper]
            let decodedAttributeDatas = (decodedAttributeWrappers ?? []).map { $0.data! }
            data!.attributes = NSMutableArray(array: decodedAttributeDatas)

            let layoutStrides: [UInt] = aDecoder.decodePODArray(forKey: "layouts")
            let layouts = layoutStrides.map { MDLVertexBufferLayout(stride: Int($0)) }
            data!.layouts = NSMutableArray(array: layouts)
        }

        func encode(with aCoder: NSCoder) {
            let attributes = data!.attributes.map { MDLVertexAttribute.CodingWrapper($0 as! MDLVertexAttribute) }
            aCoder.encode(attributes, forKey: "attributes")

            let layouts = data!.layouts.map { ($0 as! MDLVertexBufferLayout).stride }
            aCoder.encodePODArray(layouts, forKey: "layouts")
        }
    }
}

extension MeshData {
    
    //  Adds NSCoding support to MeshData
    @objc(MeshDataCodingWrapper)
    class CodingWrapper: NSObject, NSCoding {
        var data: MeshData?

        init(_ meshData: MeshData) {
            self.data = meshData
        }

        required init?(coder aDecoder: NSCoder) {
            data = MeshData()

            data!.vbCount = aDecoder.decodeObject(forKey: "vbCount") as? Int ?? 0
            data!.vbStartIdx = aDecoder.decodeObject(forKey: "vbStartIdx") as? Int ?? 0
            data!.ibStartIdx = aDecoder.decodeObject(forKey: "ibStartIdx") as? Int ?? 0
            data!.idxCounts = aDecoder.decodePODArray(forKey: "idxCounts")
            data!.idxTypes = aDecoder.decodePODArray(forKey: "idxTypes")
            data!.materials = aDecoder.decodePODArray(forKey: "materials")
        }

        func encode(with aCoder: NSCoder) {
            aCoder.encode(NSNumber(value: data!.vbCount), forKey: "vbCount")
            aCoder.encode(NSNumber(value: data!.vbStartIdx), forKey: "vbStartIdx")
            aCoder.encode(NSNumber(value: data!.ibStartIdx), forKey: "ibStartIdx")
            aCoder.encodePODArray(data!.idxCounts, forKey: "idxCounts")
            aCoder.encodePODArray(data!.idxTypes, forKey: "idxTypes")
            aCoder.encodePODArray(data!.materials, forKey: "materials")
        }
    }
}

extension AnimatedSkeleton {
    
    //  Adds NSCoding support to AnimatedSkeleton
    @objc(AnimatedSkeletonCodingWrapper)
    class CodingWrapper: NSObject, NSCoding {
        var data: AnimatedSkeleton?

        init(_ animatedSkeleton: AnimatedSkeleton) {
            self.data = animatedSkeleton
        }

        required init?(coder aDecoder: NSCoder) {
            data = AnimatedSkeleton()

            data!.jointPaths = aDecoder.decodeObject(forKey: "jointPaths") as? [String] ?? []
            data!.parentIndices = aDecoder.decodePODArray(forKey: "parentIndices")
            data!.keyTimes = aDecoder.decodePODArray(forKey: "keyTimes")
            data!.translations = aDecoder.decodePODArray(forKey: "translations")
            data!.rotations = aDecoder.decodePODArray(forKey: "rotations")
        }

        func encode(with aCoder: NSCoder) {
            aCoder.encode(data!.jointPaths, forKey: "jointPaths")
            aCoder.encodePODArray(data!.parentIndices, forKey: "parentIndices")
            aCoder.encodePODArray(data!.keyTimes, forKey: "keyTimes")
            aCoder.encodePODArray(data!.translations, forKey: "translations")
            aCoder.encodePODArray(data!.rotations, forKey: "rotations")
        }
    }
}

extension SkinData {
    
    //  Adds NSCoding support to SkinData
    @objc(SkinDataCodingWrapper)
    class CodingWrapper: NSObject, NSCoding {
        var data: SkinData?

        init(_ skinData: SkinData) {
            self.data = skinData
        }

        var jointPaths = [String]()
        var skinToSkeletonMap = [Int]()
        var inverseBindTransforms = [matrix_float4x4]()
        var animationIndex: Int?

        required init?(coder aDecoder: NSCoder) {
            data = SkinData()

            data!.jointPaths = aDecoder.decodeObject(forKey: "jointPaths") as? [String] ?? []
            data!.skinToSkeletonMap = aDecoder.decodePODArray(forKey: "skinToSkeletonMap")
            data!.inverseBindTransforms = aDecoder.decodePODArray(forKey: "inverseBindTransforms")

            data!.animationIndex = aDecoder.decodeObject(forKey: "animationIndex") as? Int ?? -1
            if data!.animationIndex! < 0 {
                data!.animationIndex = nil
            }
        }

        func encode(with aCoder: NSCoder) {
            aCoder.encode(data!.jointPaths, forKey: "jointPaths")
            aCoder.encodePODArray(data!.skinToSkeletonMap, forKey: "skinToSkeletonMap")
            aCoder.encodePODArray(data!.inverseBindTransforms, forKey: "inverseBindTransforms")
            aCoder.encode(NSNumber(value:data!.animationIndex ?? -1), forKey: "animationIndex")
        }
    }
}

extension ModelParser {
    
    //  Adds NSCoding support to Baker
    @objc(BakerCodingWrapper)
    class CodingWrapper: NSObject, NSCoding {

        var scene: ModelParser?

        init(scene: ModelParser) {
            self.scene = scene
            self.scene?.nodeNames = scene.nodeNames
            self.scene?.localTransforms = scene.localTransforms
            self.scene?.worldTransforms = scene.worldTransforms
            self.scene?.parentIndices = scene.parentIndices
            self.scene?.meshNodeIndices = scene.meshNodeIndices
            self.scene?.vertexDescriptors = scene.vertexDescriptors
            self.scene?.vertexBuffers = scene.vertexBuffers
            self.scene?.indexBuffers = scene.indexBuffers
            self.scene?.meshes = scene.meshes
            self.scene?.texturePaths = scene.texturePaths
            self.scene?.instanceCount = scene.instanceCount
            self.scene?.sampleTimes = scene.sampleTimes
            self.scene?.localTransformAnimations = scene.localTransformAnimations
            self.scene?.worldTransformAnimations = scene.worldTransformAnimations
            self.scene?.localTransformAnimationIndices = scene.localTransformAnimationIndices
            self.scene?.worldTransformAnimationIndices = scene.worldTransformAnimationIndices
            // -- add skinning
            self.scene?.meshSkinIndices = scene.meshSkinIndices
            self.scene?.skins = scene.skins
            self.scene?.skeletonAnimations = scene.skeletonAnimations
        }

        required init?(coder aDecoder: NSCoder) {
            let scene = ModelParser()

            scene.texturePaths = aDecoder.decodeObject(forKey: "texturePaths") as? [String] ?? []
            scene.nodeNames = aDecoder.decodeObject(forKey: "nodeNames") as? [String] ?? []
            scene.localTransforms = aDecoder.decodePODArray(forKey: "localTransforms")
            scene.worldTransforms = aDecoder.decodePODArray(forKey: "worldTransforms")
            scene.parentIndices = aDecoder.decodePODArray(forKey: "parentIndices")
            scene.meshNodeIndices = aDecoder.decodePODArray(forKey: "meshNodeIndices")
            scene.meshSkinIndices = aDecoder.decodePODArray(forKey: "meshSkinIndices")
            scene.instanceCount = aDecoder.decodePODArray(forKey: "instanceCount")
            scene.sampleTimes = aDecoder.decodePODArray(forKey: "sampleTimes")
            scene.localTransformAnimations = aDecoder.decodeArrayOfPODArrays(forKey: "localTransformAnimations")
            scene.worldTransformAnimations = aDecoder.decodeArrayOfPODArrays(forKey: "worldTransformAnimations")
            scene.localTransformAnimationIndices = aDecoder.decodePODArray(forKey: "localTransformAnimationIndices")
            scene.worldTransformAnimationIndices = aDecoder.decodePODArray(forKey: "worldTransformAnimationIndices")

            let skeletonAnimationWrappers = aDecoder.decodeObject(forKey: "skeletonAnimations")
                as? [AnimatedSkeleton.CodingWrapper] ?? []
            scene.skeletonAnimations = skeletonAnimationWrappers.map { $0.data! }

            let skinWrappers = aDecoder.decodeObject(forKey: "skins") as? [SkinData.CodingWrapper] ?? []
            scene.skins = skinWrappers.map { $0.data! }

            let vertexDescriptorWrappers = aDecoder.decodeObject(forKey: "vertexDescriptors")
                as? [MDLVertexDescriptor.CodingWrapper] ?? []
            scene.vertexDescriptors = vertexDescriptorWrappers.map { $0.data! }

            scene.vertexBuffers = aDecoder.decodeObject(forKey: "vertexBuffers") as? [Data] ?? []
            scene.indexBuffers = aDecoder.decodeObject(forKey: "indexBuffers") as? [Data] ?? []

            let meshWrappers = aDecoder.decodeObject(forKey: "meshes") as? [MeshData.CodingWrapper] ?? []
            scene.meshes = meshWrappers.map { $0.data! }

            self.scene = scene
        }

        func encode(with aCoder: NSCoder) {
            aCoder.encode(scene!.texturePaths, forKey: "texturePaths")
            aCoder.encode(scene!.nodeNames, forKey: "nodeNames")
            aCoder.encodePODArray(scene!.localTransforms, forKey: "localTransforms")
            aCoder.encodePODArray(scene!.worldTransforms, forKey: "worldTransforms")
            aCoder.encodePODArray(scene!.parentIndices, forKey: "parentIndices")
            aCoder.encodePODArray(scene!.meshNodeIndices, forKey: "meshNodeIndices")
            aCoder.encodePODArray(scene!.meshSkinIndices, forKey: "meshSkinIndices")
            aCoder.encodePODArray(scene!.instanceCount, forKey: "instanceCount")
            aCoder.encodePODArray(scene!.sampleTimes, forKey: "sampleTimes")
            aCoder.encodeArrayOfPODArrays(scene!.localTransformAnimations, forKey: "localTransformAnimations")
            aCoder.encodeArrayOfPODArrays(scene!.worldTransformAnimations, forKey: "worldTransformAnimations")
            aCoder.encodePODArray(scene!.localTransformAnimationIndices, forKey: "localTransformAnimationIndices")
            aCoder.encodePODArray(scene!.worldTransformAnimationIndices, forKey: "worldTransformAnimationIndices")
            aCoder.encode(scene!.skeletonAnimations.map(AnimatedSkeleton.CodingWrapper.init), forKey: "skeletonAnimations")
            aCoder.encode(scene!.skins.map { SkinData.CodingWrapper($0) }, forKey: "skins")
            aCoder.encode(scene!.vertexDescriptors.map(MDLVertexDescriptor.CodingWrapper.init), forKey: "vertexDescriptors")
            aCoder.encode(scene!.vertexBuffers, forKey: "vertexBuffers")
            aCoder.encode(scene!.indexBuffers, forKey: "indexBuffers")
            aCoder.encode(scene!.meshes.map(MeshData.CodingWrapper.init), forKey: "meshes")
        }
    }
}

// Convenience methods for working with plain old data types.
extension NSCoder {
    func data<T>(for array: [T]) -> Data {
        return array.withUnsafeBufferPointer { buffer in
            return Data(buffer: buffer)
        }
    }

    func array<T>(for data: Data) -> [T] {
        return data.withUnsafeBytes { (bytes: UnsafePointer<T>) -> [T] in
            let buffer = UnsafeBufferPointer(start: bytes, count: data.count / MemoryLayout<T>.stride)
            return Array(buffer)
        }
    }

    func encodePODArray<T>(_ immutableArray: [T], forKey key: String) {
        encode(data(for: immutableArray), forKey: key)
    }

    func decodePODArray<T>(forKey key: String) -> [T] {
        return array(for: decodeObject(forKey: key) as? Data ?? Data())
    }

    func encodeArrayOfPODArrays<T>(_ arrayOfArrays: [[T]], forKey key: String) {
        let datas = arrayOfArrays.map { array in
            return data(for: array)
        }

        encode(datas, forKey: key)
    }

    func decodeArrayOfPODArrays<T>(forKey key: String) -> [[T]] {
        guard let datas = decodeObject(forKey: key) as? [Data] else {
            return []
        }

        return datas.map { data in
            return array(for: data)
        }
    }
}
