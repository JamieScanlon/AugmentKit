//
//  AugmentedObject.swift
//  AugmentKit
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
//  A generic AR object that can be placed in the AR world. These can be created
//  and given to the AR engine to render in the AR world.
//

import Foundation
import ModelIO

public struct AugmentedObject: AKAugmentedAnchor {
    
    public static var type: String {
        return "AugmentedObject"
    }
    public var worldLocation: AKWorldLocation
    public var model: AKModel
    public var identifier: UUID?
    
    public init(withAKModel model: AKModel, at location: AKWorldLocation) {
        self.model = model
        self.worldLocation = location
    }
    
    public mutating func setIdentifier(_ uuid: UUID) {
        identifier = uuid
    }
    
}
