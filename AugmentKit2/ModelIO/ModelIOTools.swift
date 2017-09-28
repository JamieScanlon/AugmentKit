/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Contains utility functions
*/

import Foundation
import ModelIO

extension MDLAsset {
    /// Pretty-print MDLAsset's scene graph
    func printAsset() {
        func printSubgraph(object: MDLObject, indent: Int = 0) {
            print(String(repeating: " ", count: indent), object.name, object)

            for childIndex in 0..<object.children.count {
                printSubgraph(object: object.children[childIndex], indent: indent + 2)
            }
        }

        for childIndex in 0..<self.count {
            printSubgraph(object: self[childIndex]!)
        }
    }

    /// Find an MDLObject by its path from MDLAsset level
    func objectAtPath(_ path: String) -> MDLObject? {
        // pathArray[] is always ""
        let pathArray = path.components(separatedBy: "/")
        guard !pathArray.isEmpty else {
            return nil
        }

        for childIndex in 0..<self.count {
            guard let child = self[childIndex] else {
                continue
            }

            // since pathArray[0] == "" we ignore it and grab the substring if
            // the path count is greater than 2 otherwise return the child itself
            if child.name == pathArray[1] {
                if pathArray.count > 2 {
                    return child.atPath(path.substring(from: path.index(pathArray[1].endIndex, offsetBy: 3)))
                } else {
                    return child
                }
            }
        }

        return nil
    }
}

/// Protocol for remapping joint paths (e.g. between a skeleton's complete joint list
/// and the the subset bound to a particular mesh)
protocol JointPathRemappable {
    var jointPaths: [String] { get }
}

class ModelIOTools {

    /// Compute an index map from all elements of A.jointPaths to the corresponding paths in B.jointPaths
    static func mapJoints<A: JointPathRemappable, B: JointPathRemappable>(from src: A, to dst: B) -> [Int] {
        let dstJointPaths = dst.jointPaths
        return src.jointPaths.flatMap { srcJointPath in
            if let index = dstJointPaths.index(of: srcJointPath) {
                return index
            }
            print("Warning! animated joint \(srcJointPath) does not exist in skeleton")
            return nil
        }
    }

    /// Count the element count of the subgraph rooted at object.
    static func subGraphCount(_ object: MDLObject) -> Int {
        var elementCount: Int = 1 // counting us ...
        let childCount = object.children.count
        for childIndex in 0..<childCount {
             //... and subtree count of each child
            elementCount += subGraphCount(object.children[childIndex])
        }
        return elementCount
    }

    /// Traverse an MDLAsset's scene graph and run a closure on each element,
    /// passing on each element's flattened node index as well as its parent's index
    static func walkSceneGraph(in asset: MDLAsset, perNodeBody: (MDLObject, Int, Int?) -> Void) {
        func walkGraph(in object: MDLObject, currentIndex: inout Int, parentIndex: Int?, perNodeBody: (MDLObject, Int, Int?) -> Void) {
            perNodeBody(object, currentIndex, parentIndex)

            let ourIndex = currentIndex
            currentIndex += 1
            for childIndex in 0..<object.children.count {
                walkGraph(
                    in: object.children[childIndex],
                    currentIndex: &currentIndex,
                    parentIndex: ourIndex,
                    perNodeBody: perNodeBody
                )
            }
        }

        var currentIndex = 0
        for childIndex in 0..<asset.count {
            walkGraph(in: asset[childIndex]!, currentIndex: &currentIndex, parentIndex: nil, perNodeBody: perNodeBody)
        }
    }

    /// Traverse thescene graph rooted at object and run a closure on each element,
    /// passing on each element's flattened node index as well as its parent's index
    static func walkSceneGraph(rootAt object: MDLObject, perNodeBody: (MDLObject, Int, Int?) -> Void) {
        var currentIndex = 0

        func walkGraph(object: MDLObject, currentIndex: inout Int, parentIndex: Int?, perNodeBody: (MDLObject, Int, Int?) -> Void) {
            perNodeBody(object, currentIndex, parentIndex)

            let ourIndex = currentIndex
            currentIndex += 1
            for childIndex in 0..<object.children.count {
                walkGraph(
                    object: object.children[childIndex],
                    currentIndex: &currentIndex,
                    parentIndex: ourIndex,
                    perNodeBody: perNodeBody
                )
            }
        }

        walkGraph(object: object, currentIndex: &currentIndex, parentIndex: nil, perNodeBody: perNodeBody)
    }

    // Traverse an MDLAsset's masters list and run a closure on each element
    // Model I/O supports instancing. These are the master objects that the instances refer to.
    static func walkMasters(in asset: MDLAsset, perNodeBody: (MDLObject) -> Void) {
        func walkGraph(in object: MDLObject, perNodeBody: (MDLObject) -> Void) {
            perNodeBody(object)

            for childIndex in 0..<object.children.count {
                walkGraph(in: object.children[childIndex], perNodeBody: perNodeBody)
            }
        }

        for childIndex in 0..<asset.masters.count {
            walkGraph(in: asset.masters[childIndex], perNodeBody: perNodeBody)
        }
    }

    /// Return the number of active vertex buffers in an MDLMesh
    static func getVertexBufferCount(_ mdlMesh: MDLMesh) -> Int {
        var vbCount = 0
        for layout in mdlMesh.vertexDescriptor.layouts {
            if let stride = (layout as? MDLVertexBufferLayout)?.stride {
                if stride == 0 {
                    return vbCount
                }
                vbCount += 1
            }
        }
        return vbCount
    }

    /// Find the index of the (first) MDLMesh in MDLAsset.masters that an MDLObject.instance points to
    static func findMasterIndex(_ masterMeshes: [MDLMesh], _ instance: MDLObject) -> Int? {
        /// find first MDLMesh in MDLObject hierarchy
        func findFirstMesh(_ object: MDLObject) -> MDLMesh? {
            if let object = object as? MDLMesh {
                return object
            }
            for childIndex in 0..<object.children.count {
                return findFirstMesh(object.children[childIndex])
            }
            return nil
        }

        if let mesh = findFirstMesh(instance) {
            return masterMeshes.index(of: mesh)
        }

        return nil
    }

    /// Sort all mesh instances by mesh index, and return a permutation which groups together
    /// all instances of all particular mesh
    static func sortedMeshIndexPermutation(_ instanceMeshIndices: [Int]) -> ([Int], [Int]) {
        let permutation = (0..<instanceMeshIndices.count).sorted { instanceMeshIndices[$0] < instanceMeshIndices[$1] }

        var instanceCounts = [Int](repeating: 0, count: instanceMeshIndices.max()! + 1)
        for instanceMeshIndex in instanceMeshIndices {
            instanceCounts[instanceMeshIndex] += 1
        }

        return (permutation, instanceCounts)
    }

    /// Append the asset url to all texture paths
    static func fixupPaths(_ asset: MDLAsset, _ texturePaths: inout [String]) {
        guard let assetURL = asset.url else { return }

        let assetRelativeURL = assetURL.deletingLastPathComponent()
        texturePaths = texturePaths.map { assetRelativeURL.appendingPathComponent($0).absoluteString }
    }

    /// Find the shortest subpath containing a rootIdentifier (used to find a e.g. skeleton's root path)
    static func findShortestPath(in path: String, containing rootIdentifier: String) -> String? {
        var result = ""
        let pathArray = path.components(separatedBy: "/")
        for name in pathArray {
            result += name
            if name.range(of: rootIdentifier) != nil {
                return result
            }
            result += "/"
        }
        return nil
    }

    /// Get a float3 property from an MDLMaterialProperty
    static func getMaterialFloat3Value(_ materialProperty: MDLMaterialProperty) -> float3 {
        return materialProperty.float3Value
    }

    /// Get a float property from an MDLMaterialProperty
    static func getMaterialFloatValue(_ materialProperty: MDLMaterialProperty) -> Float {
        return materialProperty.floatValue
    }

    /// Uniformly sample a time interval
    static func sampleTimeInterval(start startTime: TimeInterval, end endTime: TimeInterval,
                            frameInterval: TimeInterval) -> [TimeInterval] {
        let count = Int( (endTime - startTime) / frameInterval )
        return (0..<count).map { startTime + TimeInterval($0) * frameInterval }
    }
    
    // Find the largest index of time stamp <= key
    static func lowerBoundKeyframeIndex(_ lhs: [Double], key: Double) -> Int? {
        if lhs.isEmpty {
            return nil
        }
        
        if key < lhs.first! { return 0 }
        if key > lhs.last! { return lhs.count - 1 }
        
        var range = 0..<lhs.count
        
        while range.endIndex - range.startIndex > 1 {
            let midIndex = range.startIndex + (range.endIndex - range.startIndex) / 2
            
            if lhs[midIndex] == key {
                return midIndex
            } else if lhs[midIndex] < key {
                range = midIndex..<range.endIndex
            } else {
                range = range.startIndex..<midIndex
            }
        }
        return range.startIndex
    }

}
