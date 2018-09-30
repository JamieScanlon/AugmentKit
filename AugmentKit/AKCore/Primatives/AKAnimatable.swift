//
//  AKAnimatable.swift
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

// MARK: - AKAnimatable

/**
 Describes a animatable value. That is, a value that changes over time.
 */
public protocol AKAnimatable {
    associatedtype Value
    /**
     Retrieve a value.
     - Parameters:
        - forTime: The current `TimeInterval`
     - Returns: The value
     */
    func value(forTime: TimeInterval) -> Value
}

// MARK: - AKPulsingAnimatable

/**
 Describes an `AKAnimatable` that oscillates between a `minValue` and `maxValue` over a time `period`
 */
public protocol AKPulsingAnimatable: AKAnimatable {
    /**
     The minumum value.
     */
    var minValue: Value { get }
    /**
     The maximum value.
     */
    var maxValue: Value { get }
    /**
     The period.
     */
    var period: TimeInterval { get }
    /**
     The offset to apply to the animation.
     */
    var periodOffset: TimeInterval { get }
}

extension AKPulsingAnimatable where Value == Double {
    /**
     Retrieve a value.
     
     Implementation of the `value(forTime:)` function when `AKAnimatable.Value` is a `Double`
     
     - Parameters:
        - forTime: The current `TimeInterval`
     - Returns: The value
     */
    public func value(forTime time: TimeInterval) -> Value {
        let delta = maxValue - minValue
        let progress = ((periodOffset + time).truncatingRemainder(dividingBy: period)) / period
        return minValue + delta * (0.5 + 0.5 * cos(2 * Double.pi * progress))
    }
}

extension AKPulsingAnimatable where Value == Float {
    /**
     Retrieve a value.
     
     Implementation of the `value(forTime:)` function when `AKAnimatable.Value` is a `Float`
     
     - Parameters:
        - forTime: The current `TimeInterval`
     - Returns: The value
     */
    public func value(forTime time: TimeInterval) -> Value {
        let delta = Double(maxValue - minValue)
        let progress = ((periodOffset + time).truncatingRemainder(dividingBy: period)) / period
        return minValue + Float(delta * (0.5 + 0.5 * cos(2 * Double.pi * progress)))
    }
}

extension AKPulsingAnimatable where Value == Int {
    /**
     Retrieve a value.
     
     Implementation of the `value(forTime:)` function when `AKAnimatable.Value` is an `Int`
     
     - Parameters:
        - forTime: The current `TimeInterval`
     - Returns: The value
     */
    public func value(forTime time: TimeInterval) -> Value {
        let delta = Double(maxValue - minValue)
        let progress = ((periodOffset + time).truncatingRemainder(dividingBy: period)) / period
        return minValue + Int(delta * (0.5 + 0.5 * cos(2 * Double.pi * progress)))
    }
}

extension AKPulsingAnimatable where Value == UInt {
    /**
     Retrieve a value.
     
     Implementation of the `value(forTime:)` function when `AKAnimatable.Value` is a `UInt`
     
     - Parameters:
        - forTime: The current `TimeInterval`
     - Returns: The value
     */
    public func value(forTime time: TimeInterval) -> Value {
        let delta = Double(maxValue - minValue)
        let progress = ((periodOffset + time).truncatingRemainder(dividingBy: period)) / period
        return minValue + UInt(delta * (0.5 + 0.5 * cos(2 * Double.pi * progress)))
    }
}

extension AKPulsingAnimatable where Value == Any {
    /**
     Retrieve a value.
     
     Implementation of the `value(forTime:)` function when `AKAnimatable.Value` is a `Any`.
     
     This implementation checks if `Any` can be downcast to `double`, `Float`, `Int`, or `UInt` and performs the calculations, returning `minValue` otherwise
     
     - Parameters:
        - forTime: The current `TimeInterval`
     - Returns: The value
     */
    public func value(forTime time: TimeInterval) -> Value {
        if let aMinValue = minValue as? Double, let aMaxValue = maxValue as? Double {
            let delta = aMaxValue - aMinValue
            let progress = ((periodOffset + time).truncatingRemainder(dividingBy: period)) / period
            return aMinValue + delta * (0.5 + 0.5 * cos(2 * Double.pi * progress))
        } else if let aMinValue = minValue as? Float, let aMaxValue = maxValue as? Float {
            let delta = Double(aMaxValue - aMinValue)
            let progress = ((periodOffset + time).truncatingRemainder(dividingBy: period)) / period
            return aMinValue + Float(delta * (0.5 + 0.5 * cos(2 * Double.pi * progress)))
        } else if let aMinValue = minValue as? Int, let aMaxValue = maxValue as? Int {
            let delta = Double(aMaxValue - aMinValue)
            let progress = ((periodOffset + time).truncatingRemainder(dividingBy: period)) / period
            return aMinValue + Int(delta * (0.5 + 0.5 * cos(2 * Double.pi * progress)))
        } else if let aMinValue = minValue as? UInt, let aMaxValue = maxValue as? UInt {
            let delta = Double(aMaxValue - aMinValue)
            let progress = ((periodOffset + time).truncatingRemainder(dividingBy: period)) / period
            return aMinValue + UInt(delta * (0.5 + 0.5 * cos(2 * Double.pi * progress)))
        } else {
            return minValue
        }
    }
}
