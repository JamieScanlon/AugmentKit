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
//  This class ads NSCoding extensions for serializing and deserializing AKModels.
//
//  Based heavily on "From Art to Engine with Model I/O" WWDC 2017 talk.
//  https://developer.apple.com/videos/play/wwdc2017/610/
//  Sample Code: https://developer.apple.com/sample-code/wwdc/2017/ModelIO-from-MDLAsset-to-Game-Engine.zip
//

import Foundation
import ModelIO

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

//  Adds NSCoding support to AKModel
class AKModelCodingWrapper: NSObject, NSCoding {
    
    var model: AKModel?
    
    init(model: AKModel) {
        self.model = model
        self.model?.nodeNames = model.nodeNames
        self.model?.localTransforms = model.localTransforms
        self.model?.worldTransforms = model.worldTransforms
        self.model?.parentIndices = model.parentIndices
        self.model?.meshNodeIndices = model.meshNodeIndices
        self.model?.vertexDescriptors = model.vertexDescriptors
        self.model?.vertexBuffers = model.vertexBuffers
        self.model?.indexBuffers = model.indexBuffers
        self.model?.meshes = model.meshes
        self.model?.texturePaths = model.texturePaths
        self.model?.instanceCount = model.instanceCount
        self.model?.sampleTimes = model.sampleTimes
        self.model?.localTransformAnimations = model.localTransformAnimations
        self.model?.worldTransformAnimations = model.worldTransformAnimations
        self.model?.localTransformAnimationIndices = model.localTransformAnimationIndices
        self.model?.worldTransformAnimationIndices = model.worldTransformAnimationIndices
        // -- add skinning
        self.model?.meshSkinIndices = model.meshSkinIndices
        self.model?.skins = model.skins
        self.model?.skeletonAnimations = model.skeletonAnimations
    }
    
    required init?(coder aDecoder: NSCoder) {
        let model = AKSimpleModel()
        
        model.texturePaths = aDecoder.decodeObject(forKey: "texturePaths") as? [String] ?? []
        model.nodeNames = aDecoder.decodeObject(forKey: "nodeNames") as? [String] ?? []
        model.localTransforms = aDecoder.decodePODArray(forKey: "localTransforms")
        model.worldTransforms = aDecoder.decodePODArray(forKey: "worldTransforms")
        model.parentIndices = aDecoder.decodePODArray(forKey: "parentIndices")
        model.meshNodeIndices = aDecoder.decodePODArray(forKey: "meshNodeIndices")
        model.meshSkinIndices = aDecoder.decodePODArray(forKey: "meshSkinIndices")
        model.instanceCount = aDecoder.decodePODArray(forKey: "instanceCount")
        model.sampleTimes = aDecoder.decodePODArray(forKey: "sampleTimes")
        model.localTransformAnimations = aDecoder.decodeArrayOfPODArrays(forKey: "localTransformAnimations")
        model.worldTransformAnimations = aDecoder.decodeArrayOfPODArrays(forKey: "worldTransformAnimations")
        model.localTransformAnimationIndices = aDecoder.decodePODArray(forKey: "localTransformAnimationIndices")
        model.worldTransformAnimationIndices = aDecoder.decodePODArray(forKey: "worldTransformAnimationIndices")
        
        let skeletonAnimationWrappers = aDecoder.decodeObject(forKey: "skeletonAnimations")
            as? [AnimatedSkeleton.CodingWrapper] ?? []
        model.skeletonAnimations = skeletonAnimationWrappers.map { $0.data! }
        
        let skinWrappers = aDecoder.decodeObject(forKey: "skins") as? [SkinData.CodingWrapper] ?? []
        model.skins = skinWrappers.map { $0.data! }
        
        let vertexDescriptorWrappers = aDecoder.decodeObject(forKey: "vertexDescriptors")
            as? [MDLVertexDescriptor.CodingWrapper] ?? []
        model.vertexDescriptors = vertexDescriptorWrappers.map { $0.data! }
        
        model.vertexBuffers = aDecoder.decodeObject(forKey: "vertexBuffers") as? [Data] ?? []
        model.indexBuffers = aDecoder.decodeObject(forKey: "indexBuffers") as? [Data] ?? []
        
        let meshWrappers = aDecoder.decodeObject(forKey: "meshes") as? [MeshData.CodingWrapper] ?? []
        model.meshes = meshWrappers.map { $0.data! }
        
        self.model = model
    }
    
    func encode(with aCoder: NSCoder) {
        aCoder.encode(model!.texturePaths, forKey: "texturePaths")
        aCoder.encode(model!.nodeNames, forKey: "nodeNames")
        aCoder.encodePODArray(model!.localTransforms, forKey: "localTransforms")
        aCoder.encodePODArray(model!.worldTransforms, forKey: "worldTransforms")
        aCoder.encodePODArray(model!.parentIndices, forKey: "parentIndices")
        aCoder.encodePODArray(model!.meshNodeIndices, forKey: "meshNodeIndices")
        aCoder.encodePODArray(model!.meshSkinIndices, forKey: "meshSkinIndices")
        aCoder.encodePODArray(model!.instanceCount, forKey: "instanceCount")
        aCoder.encodePODArray(model!.sampleTimes, forKey: "sampleTimes")
        aCoder.encodeArrayOfPODArrays(model!.localTransformAnimations, forKey: "localTransformAnimations")
        aCoder.encodeArrayOfPODArrays(model!.worldTransformAnimations, forKey: "worldTransformAnimations")
        aCoder.encodePODArray(model!.localTransformAnimationIndices, forKey: "localTransformAnimationIndices")
        aCoder.encodePODArray(model!.worldTransformAnimationIndices, forKey: "worldTransformAnimationIndices")
        aCoder.encode(model!.skeletonAnimations.map(AnimatedSkeleton.CodingWrapper.init), forKey: "skeletonAnimations")
        aCoder.encode(model!.skins.map { SkinData.CodingWrapper($0) }, forKey: "skins")
        aCoder.encode(model!.vertexDescriptors.map(MDLVertexDescriptor.CodingWrapper.init), forKey: "vertexDescriptors")
        aCoder.encode(model!.vertexBuffers, forKey: "vertexBuffers")
        aCoder.encode(model!.indexBuffers, forKey: "indexBuffers")
        aCoder.encode(model!.meshes.map(MeshData.CodingWrapper.init), forKey: "meshes")
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
