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

/**
 Effect type
 */
public enum AKEffectType {
    /**
     An affect that applies to the alpha value
     */
    case alpha
    /**
     An affect that applies a glow
     */
    case glow
    /**
     An affect that applies a tint color
     */
    case tint
    /**
     An affect that applies a uniform scale factor
     */
    case scale
}

/**
 Describes an effect that can be applied to a model. `AKEffect`s are evalueated and applied by the shader and apply to the model as a whole. `AKEffect`s are animatable
 */
public protocol AKEffect: AKAnimatable {
    /**
     The effect type
     */
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

/**
 A type erased `AKEffect`
 */
public final class AnyEffect<Value>: AKEffect {
    private let box: _AnyEffectBase<Value>
    
    /**
     Initializer takes a concrete implementation
     */
    public init<Concrete: AKEffect>(_ concrete: Concrete) where Concrete.Value == Value {
        box = _AnyEffectBox(concrete)
    }
    /**
     Calls the boxed `AKEffect` implementation of `value(forTime:)`
     */
    public func value(forTime time: TimeInterval) -> Value {
        return box.value(forTime: time)
    }
    /**
     Returns the boxed `AKEffect` implementation of `effectType`
     */
    public var effectType: AKEffectType {
        return box.effectType
    }
}

//
// Default Implementations
//

// MARK: - ConstantScaleEffect

/**
 Effect that applies a one-time scale factor.
 */
public struct ConstantScaleEffect: AKEffect {
    /**
     Returns `AKEffectType.scale`
     */
    public var effectType: AKEffectType {
        return .scale
    }
    private var scaleValue: Float
    /**
     Initialize the object with a scale value.
     - Parameters:
        - scaleValue: A scale factor that will be applied to all dinensions.
     */
    public init(scaleValue: Float) {
        self.scaleValue = scaleValue
    }
    /**
     Retrieve a the scale value.
     - Parameters:
        - forTime: The current `TimeInterval`
     - Returns: The scale value passed in during initialization
     */
    public func value(forTime: TimeInterval) -> Any {
        return scaleValue
    }
}

// MARK: - ConstantAlphaEffect

/**
 Effect that applies a one-time alpha value.
 */
public struct ConstantAlphaEffect: AKEffect {
    /**
     Returns `AKEffectType.alpha`
     */
    public var effectType: AKEffectType {
        return .alpha
    }
    private var alphaValue: Float
    /**
     Initialize the object with an alpha value.
     - Parameters:
        - alphaValue: A alpha value that will be applied to the model.
     */
    public init(alphaValue: Float) {
        self.alphaValue = alphaValue
    }
    /**
     Retrieve a the alpha value.
     - Parameters:
        - forTime: The current `TimeInterval`
     - Returns: The alpha value passed in during initialization
     */
    public func value(forTime: TimeInterval) -> Any {
        return alphaValue
    }
}

// MARK: - ConstantTintEffect

/**
 Effect that applies a one-time tint color.
 */
public struct ConstantTintEffect: AKEffect {
    /**
     Returns `AKEffectType.tint`
     */
    public var effectType: AKEffectType {
        return .tint
    }
    private var tintValue: simd_float3
    /**
     Initialize the object with an tint color.
     - Parameters:
        - tintValue: A color value that will be applied to the model.
     */
    public init(tintValue: simd_float3) {
        self.tintValue = tintValue
    }
    /**
     Retrieve a the tint value.
     - Parameters:
        - forTime: The current `TimeInterval`
     - Returns: The tint value passed in during initialization
     */
    public func value(forTime: TimeInterval) -> Any {
        return tintValue
    }
}

// MARK: - ConstantGlowEffect

/**
 Effect that applies a one-time glow value.
 */
public struct ConstantGlowEffect: AKEffect {
    /**
     Returns `AKEffectType.glow`
     */
    public var effectType: AKEffectType {
        return .glow
    }
    private var glowValue: Float
    /**
     Initialize the object with an glow value.
     - Parameters:
        - glowValue: A glow value between 0 and 1 that will be applied to the model.
     */
    public init(glowValue: Float) {
        self.glowValue = glowValue
    }
    /**
     Retrieve a the glow value.
     - Parameters:
        - forTime: The current `TimeInterval`
     - Returns: The glow value passed in during initialization
     */
    public func value(forTime: TimeInterval) -> Any {
        return glowValue
    }
}

// MARK: - PulsingScaleEffect

/**
 Effect that pulses the scale.
 */
public struct PulsingScaleEffect: AKEffect, AKPulsingAnimatable {
    public typealias Value = Any
    /**
     The minumum value.
     */
    public var minValue: Any
    /**
     The maximum value.
     */
    public var maxValue: Any
    /**
     The period.
     */
    public var period: TimeInterval
    /**
     The offset to apply to the animation.
     */
    public var periodOffset: TimeInterval = 0
    /**
     Returns `AKEffectType.scale`
     */
    public var effectType: AKEffectType {
        return .scale
    }
    /**
     Initialize the effect with a `minValue`, `maxValue`, `period`, and `periodOffset`
     */
    public init(minValue: Float, maxValue: Float, period: TimeInterval = 2, periodOffset: TimeInterval = 0) {
        self.minValue = minValue
        self.maxValue = maxValue
        self.period = period
        self.periodOffset = periodOffset
    }
}

// MARK: - PulsingGlowEffect

/**
 Effect that pulses the glow.
 */
public struct PulsingGlowEffect: AKEffect, AKPulsingAnimatable {
    public typealias Value = Any
    /**
     The minumum value.
     */
    public var minValue: Any
    /**
     The maximum value.
     */
    public var maxValue: Any
    /**
     The period.
     */
    public var period: TimeInterval
    /**
     The offset to apply to the animation.
     */
    public var periodOffset: TimeInterval = 0
    /**
     The effect type
     */
    public var effectType: AKEffectType = .glow
    /**
     Initialize the effect with a `minValue`, `maxValue`, `period`, and `periodOffset`
     */
    public init(minValue: Float, maxValue: Float, period: TimeInterval = 2, periodOffset: TimeInterval = 0) {
        self.minValue = minValue
        self.maxValue = maxValue
        self.period = period
        self.periodOffset = periodOffset
    }
}

// MARK: - PulsingAlphaEffect

/**
 Effect that pulses the alpha.
 */
public struct PulsingAlphaEffect: AKEffect, AKPulsingAnimatable {
    public typealias Value = Any
    /**
     The minumum value.
     */
    public var minValue: Any
    /**
     The maximum value.
     */
    public var maxValue: Any
    /**
     The period.
     */
    public var period: TimeInterval
    /**
     The offset to apply to the animation.
     */
    public var periodOffset: TimeInterval = 0
    /**
     The effect type
     */
    public var effectType: AKEffectType = .alpha
    /**
     Initialize the effect with a `minValue`, `maxValue`, `period`, and `periodOffset`
     */
    public init(minValue: Float, maxValue: Float, period: TimeInterval = 2, periodOffset: TimeInterval = 0) {
        self.minValue = minValue
        self.maxValue = maxValue
        self.period = period
        self.periodOffset = periodOffset
    }
}
