//
//  AKEffect.swift
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
import simd

public enum AKEffectType {
    case alpha
    case glow
    case tint
    case scale
}

public protocol AKEffect: AKAnimatable {
    var effectType: AKEffectType { get }
}

//
// Type Erasure
//

private class _AnyEffectBase<Value>: AKEffect {
    init() {
        guard type(of: self) != _AnyEffectBase.self else {
            fatalError("_AnyEffectBase<Value> instances can not be created; create a subclass instance instead")
        }
    }
    
    func value(forTime: TimeInterval) -> Value {
        fatalError("Must override")
    }
    
    var effectType: AKEffectType {
        fatalError("Must override")
    }
}

private final class _AnyEffectBox<Concrete: AKEffect>: _AnyEffectBase<Concrete.Value> {
    // variable used since we're calling mutating functions
    var concrete: Concrete
    
    init(_ concrete: Concrete) {
        self.concrete = concrete
    }
    
    // Trampoline functions forward along to base
    override func value(forTime time: TimeInterval) -> Concrete.Value {
        return concrete.value(forTime: time)
    }
    
    // Trampoline property accessors along to base
    override var effectType: AKEffectType {
        return concrete.effectType
    }
}

public final class AnyEffect<Value>: AKEffect {
    private let box: _AnyEffectBase<Value>
    
    // Initializer takes a concrete implementation
    public init<Concrete: AKEffect>(_ concrete: Concrete) where Concrete.Value == Value {
        box = _AnyEffectBox(concrete)
    }
    
    public func value(forTime time: TimeInterval) -> Value {
        return box.value(forTime: time)
    }
    
    public var effectType: AKEffectType {
        return box.effectType
    }
}

//
// Default Implementations
//

// MARK: - ConstantScaleEffect

public struct ConstantScaleEffect: AKEffect {
    public var effectType: AKEffectType = .scale
    private var scaleValue: Float
    public init(scaleValue: Float) {
        self.scaleValue = scaleValue
    }
    public func value(forTime: TimeInterval) -> Any {
        return scaleValue
    }
}

// MARK: - ConstantAlphaEffect

public struct ConstantAlphaEffect: AKEffect {
    public var effectType: AKEffectType = .alpha
    private var alphaValue: Float
    public init(alphaValue: Float) {
        self.alphaValue = alphaValue
    }
    public func value(forTime: TimeInterval) -> Any {
        return alphaValue
    }
}

// MARK: - ConstantTintEffect

public struct ConstantTintEffect: AKEffect {
    public var effectType: AKEffectType = .tint
    private var tintValue: simd_float3
    public init(tintValue: simd_float3) {
        self.tintValue = tintValue
    }
    public func value(forTime: TimeInterval) -> Any {
        return tintValue
    }
}

// MARK: - ConstantGlowEffect

public struct ConstantGlowEffect: AKEffect {
    public var effectType: AKEffectType = .glow
    private var glowValue: Float
    public init(glowValue: Float) {
        self.glowValue = glowValue
    }
    public func value(forTime: TimeInterval) -> Any {
        return glowValue
    }
}
