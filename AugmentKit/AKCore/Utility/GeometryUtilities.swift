//
//  GeometryUtilities.swift
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
import GLKit

// MARK: - float4x4

public extension float4x4 {
    /**
     Make a scale transform
     - Parameters:
        - x: The X component of the scale
        - y: The y component of the scale
        - z: The z component of the scale
     - Returns: A new scale transform
     */
    static func makeScale(x: Float, y: Float, z: Float) -> float4x4 {
        return unsafeBitCast(GLKMatrix4MakeScale(x, y, z), to: float4x4.self)
    }
    /**
     Make a rotation transform
     - Parameters:
        - radians: The rotation degrees
        - x: The X axis component of the rotation
        - y: The Y axis component of the rotation
        - z: The Z axis component of the rotation
     - Returns: A new rotation transform
     */
    static func makeRotate(radians: Float, x: Float, y: Float, z: Float) -> float4x4 {
        let q = simd_quatf(angle: radians, axis: float3(x, y, z))
        return q.toMatrix4()
    }
    /**
     Make a translation transform
     - Parameters:
        - x: The X component of the translation
        - y: The Y component of the translation
        - z: The Z component of the translation
     - Returns: A new translation transform
     */
    static func makeTranslation(x: Float, y: Float, z: Float) -> float4x4 {
        return float4x4(float4(1, 0, 0, 0), float4(0, 1, 0, 0), float4(0, 0, 1, 0), float4(x, y, z, 1))
    }
    /**
     Make a 4x4 perspective projection matrix.
     - Parameters:
        - fovyRadians: The angle of the vertical viewing area.
        - aspect: The ratio between the horizontal and the vertical viewing area.
        - nearZ: The near clipping distance. Must be positive.
        - farZ: The far clipping distance. Must be positive and greater than the near distance.
     - Returns: A new perspective projection matrix
     */
    static func makePerspective(fovyRadians: Float, aspect: Float, nearZ: Float, farZ: Float) -> float4x4 {
//        return unsafeBitCast(GLKMatrix4MakePerspective(fovyRadians, aspect, nearZ, farZ), to: float4x4.self)
        let h = 1 / tan(fovyRadians * Float.pi / 360)
        let negDepth = nearZ - farZ
        return float4x4(
            float4(h / aspect, 0, 0, 0),
            float4(0, h, 0, 0),
            float4(0, 0, (farZ + nearZ) / negDepth, 2 * (nearZ * farZ) / negDepth),
            float4(0, 0, -1, 0)
        )
    }
    /**
     Make a 4x4 perspective projection matrix.
     - Parameters:
        - left: The left clipping plane.
        - right: The right clipping plane.
        - bottom: The bottom clipping plane.
        - top: The top clipping plane.
        - nearZ: The near clipping distance. Must be positive.
        - farZ: The far clipping distance. Must be positive and greater than the near distance.
     - Returns: A projection matrix
     */
    static func makeFrustum(left: Float, right: Float, bottom: Float, top: Float, nearZ: Float, farZ: Float) -> float4x4 {
        return unsafeBitCast(GLKMatrix4MakeFrustum(left, right, bottom, top, nearZ, farZ), to: float4x4.self)
    }
    /**
     Make a 4x4 orthographic projection matrix.
     - Parameters:
        - left: The left coordinate of the projection volume in eye coordinates.
        - right: The right coordinate of the projection volume in eye coordinates.
        - bottom: The bottom coordinate of the projection volume in eye coordinates.
        - top: The top coordinate of the projection volume in eye coordinates.
        - nearZ: The near coordinate of the projection volume in eye coordinates.
        - farZ: The far coordinate of the projection volume in eye coordinates.
     - Returns: A projection matrix
     */
    static func makeOrtho(left: Float, right: Float, bottom: Float, top: Float, nearZ: Float, farZ: Float) -> float4x4 {
        return unsafeBitCast(GLKMatrix4MakeOrtho(left, right, bottom, top, nearZ, farZ), to: float4x4.self)
    }
    /**
     Make a 4x4 rotation matrix.
     - Parameters:
        - eyeX: The x coordinate of the eye position.
        - eyeY: The y coordinate of the eye position.
        - eyeZ: The z coordinate of the eye position.
        - centerX: The x coordinate of the point being looked at.
        - centerY: The y coordinate of the point being looked at.
        - centerZ: The z coordinate of the point being looked at.
        - upX: The x coordinate of the camera’s up vector.
        - upY: The y coordinate of the camera’s up vector.
        - upZ: The z coordinate of the camera’s up vector.
     - Returns: A rotation matrix
     */
    static func makeLookAt(eyeX: Float, eyeY: Float, eyeZ: Float, centerX: Float, centerY: Float, centerZ: Float, upX: Float, upY: Float, upZ: Float) -> float4x4 {
        let quaternion = simd_quatf(vector: float4(0, 0, 0, 1))
        let lookAtQ = quaternion.lookAt(eye: float3(eyeX, eyeY, eyeZ), center: float3(centerX, centerY, centerZ), up: float3(upX, upY, upZ))
        return lookAtQ.toMatrix4()
    }

    /**
     Creates a new `simd_quatf` from a 4x4 matrix.
     - Parameters:
        - from: A 4x4 matrix.
     - Returns: A new `simd_quatf`
     */
    static func makeQuaternion(from: float4x4) -> simd_quatf {
        return simd_quatf(from)
    }
    /**
     Make a new scale transform by scaling this transform by the specified values
     - Parameters:
        - x: The X component of the scale
        - y: The y component of the scale
        - z: The z component of the scale
     - Returns: A new scale transform
     */
    func scale(x: Float, y: Float, z: Float) -> float4x4 {
        return self * float4x4.makeScale(x: x, y: y, z: z)
    }
    /**
     Make a rotation transform by rotating this transform by the specified values
     - Parameters:
        - radians: The rotation degrees
        - x: The X axis component of the rotation
        - y: The Y axis component of the rotation
        - z: The Z axis component of the rotation
     - Returns: A new rotation transform
     */
    func rotate(radians: Float, x: Float, y: Float, z: Float) -> float4x4 {
        return self * float4x4.makeRotate(radians: radians, x: x, y: y, z: z)
    }
    /**
     Make a translation transform by translating this transform by the specified values
     - Parameters:
        - x: The X component of the translation
        - y: The Y component of the translation
        - z: The Z component of the translation
     - Returns: A new translation transform
     */
    func translate(x: Float, y: Float, z: Float) -> float4x4 {
        return self * float4x4.makeTranslation(x: x, y: y, z: z)
    }
    /**
     Creates a new `simd_quatf`.
     - Returns: A new `simd_quatf`
     */
    func quaternion() -> simd_quatf {
        return float4x4.makeQuaternion(from: self)
    }
    /**
     - Returns: `true` if all of the values in the matrix are less than 0.0001
     */
    func isZero() -> Bool {
        if self.columns.0.x > 0.0001 || self.columns.0.y > 0.0001 || self.columns.0.z > 0.0001 || self.columns.0.w > 0.0001 {
            return false
        }
        if self.columns.1.x > 0.0001 || self.columns.1.y > 0.0001 || self.columns.1.z > 0.0001 || self.columns.1.w > 0.0001 {
            return false
        }
        if self.columns.2.x > 0.0001 || self.columns.2.y > 0.0001 || self.columns.2.z > 0.0001 || self.columns.2.w > 0.0001 {
            return false
        }
        if self.columns.3.x > 0.0001 || self.columns.3.y > 0.0001 || self.columns.3.z > 0.0001 || self.columns.3.w > 0.0001 {
            return false
        }
        return true
    }
    
    /**
     Makes a new rotation transform for rotating this transfor to look at the specified point.
     - Parameters:
        - position: The point to look at
     - Returns: A `float4x4` which specifies how this transform should be rotated to look at the point.
     */
    func lookAtMatrix(position: float3) -> float4x4 {
        return lookAtQuaternion(position: position).toMatrix4()
    }
    /**
     Makes a new rotation quaternion for rotating this transfor to look at the specified point.
     - Parameters:
        - position: The point to look at
     - Returns: A `simd_quatf` which specifies how this transform should be rotated to look at the point.
     */
    func lookAtQuaternion(position: float3) -> simd_quatf {
        let quaternion = float4x4.makeLookAt(eyeX: columns.3.x, eyeY: columns.3.y, eyeZ: columns.3.z, centerX: position.x, centerY: position.y, centerZ: position.z, upX: 0, upY: 1, upZ: 0).quaternion()
        return quaternion
    }
    /**
     A normalized 3x3 matrix
     */
    var normalMatrix: float3x3 {
        let upperLeft = float3x3(self[0].xyz, self[1].xyz, self[2].xyz)
        return upperLeft.transpose.inverse
    }
    
}

// MARK: - float4x4

public extension double4x4 {
    /**
     Make a scale transform
     - Parameters:
         - x: The X component of the scale
         - y: The y component of the scale
         - z: The z component of the scale
     - Returns: A new scale transform
     */
    static func makeScale(x: Double, y: Double, z: Double) -> double4x4 {
        return double4x4(double4(x, 0, 0, 0), double4(0, y, 0, 0), double4(0, 0, z, 0), double4(0, 0, 0, 1))
    }
    /**
     Make a rotation transform
     - Parameters:
         - radians: The rotation degrees
         - x: The X axis component of the rotation
         - y: The Y axis component of the rotation
         - z: The Z axis component of the rotation
     - Returns: A new rotation transform
     */
    static func makeRotate(radians: Double, x: Double, y: Double, z: Double) -> double4x4 {
        let q = simd_quatd(angle: radians, axis: double3(x, y, z))
        return q.toMatrix4()
    }
    /**
     Make a translation transform
     - Parameters:
         - x: The X component of the translation
         - y: The Y component of the translation
         - z: The Z component of the translation
     - Returns: A new translation transform
     */
    static func makeTranslation(x: Double, y: Double, z: Double) -> double4x4 {
        return double4x4(double4(1, 0, 0, 0), double4(0, 1, 0, 0), double4(0, 0, 1, 0), double4(x, y, z, 1))
    }
    /**
     Make a 4x4 perspective projection matrix.
     - Parameters:
         - fovyRadians: The angle of the vertical viewing area.
         - aspect: The ratio between the horizontal and the vertical viewing area.
         - nearZ: The near clipping distance. Must be positive.
         - farZ: The far clipping distance. Must be positive and greater than the near distance.
     - Returns: A new perspective projection matrix
     */
    static func makePerspective(fovyRadians: Double, aspect: Double, nearZ: Double, farZ: Double) -> double4x4 {
        let scale = 1 / tan(fovyRadians * Double.pi / 360)
        let negDepth = nearZ - farZ
        return double4x4(
            double4(scale / aspect, 0, 0, 0),
            double4(0, scale, 0, 0),
            double4(0, 0, (farZ + nearZ) / negDepth, 2 * (nearZ * farZ) / negDepth),
            double4(0, 0, -1, 0)
        )
    }
    /**
     Make a 4x4 perspective projection matrix.
     - Parameters:
         - left: The left clipping plane.
         - right: The right clipping plane.
         - bottom: The bottom clipping plane.
         - top: The top clipping plane.
         - nearZ: The near clipping distance. Must be positive.
         - farZ: The far clipping distance. Must be positive and greater than the near distance.
     - Returns: A projection matrix
     */
//    static func makeFrustum(left: Float, right: Float, bottom: Float, top: Float, nearZ: Float, farZ: Float) -> double4x4 {
//        return unsafeBitCast(GLKMatrix4MakeFrustum(left, right, bottom, top, nearZ, farZ), to: float4x4.self)
//    }
    /**
     Make a 4x4 orthographic projection matrix.
     - Parameters:
         - left: The left coordinate of the projection volume in eye coordinates.
         - right: The right coordinate of the projection volume in eye coordinates.
         - bottom: The bottom coordinate of the projection volume in eye coordinates.
         - top: The top coordinate of the projection volume in eye coordinates.
         - nearZ: The near coordinate of the projection volume in eye coordinates.
         - farZ: The far coordinate of the projection volume in eye coordinates.
     - Returns: A projection matrix
     */
//    static func makeOrtho(left: Float, right: Float, bottom: Float, top: Float, nearZ: Float, farZ: Float) -> double4x4 {
//        return unsafeBitCast(GLKMatrix4MakeOrtho(left, right, bottom, top, nearZ, farZ), to: float4x4.self)
//    }
    /**
     Make a 4x4 rotation matrix.
     - Parameters:
         - eyeX: The x coordinate of the eye position.
         - eyeY: The y coordinate of the eye position.
         - eyeZ: The z coordinate of the eye position.
         - centerX: The x coordinate of the point being looked at.
         - centerY: The y coordinate of the point being looked at.
         - centerZ: The z coordinate of the point being looked at.
         - upX: The x coordinate of the camera’s up vector.
         - upY: The y coordinate of the camera’s up vector.
         - upZ: The z coordinate of the camera’s up vector.
     - Returns: A rotation matrix
     */
    static func makeLookAt(eyeX: Double, eyeY: Double, eyeZ: Double, centerX: Double, centerY: Double, centerZ: Double, upX: Double, upY: Double, upZ: Double) -> double4x4 {
        let quaternion = simd_quatd(vector: double4(0, 0, 0, 1))
        let lookAtQ = quaternion.lookAt(eye: double3(eyeX, eyeY, eyeZ), center: double3(centerX, centerY, centerZ), up: double3(upX, upY, upZ))
        return lookAtQ.toMatrix4()
    }
    
    /**
     Creates a new `simd_quatd` from a 4x4 matrix.
     - Parameters:
         - from: A 4x4 matrix.
     - Returns: A new `simd_quatd`
     */
    static func makeQuaternion(from: double4x4) -> simd_quatd {
        return simd_quatd(from)
    }
    /**
     Make a new scale transform by scaling this transform by the specified values
     - Parameters:
         - x: The X component of the scale
         - y: The y component of the scale
         - z: The z component of the scale
     - Returns: A new scale transform
     */
    func scale(x: Double, y: Double, z: Double) -> double4x4 {
        return self * double4x4.makeScale(x: x, y: y, z: z)
    }
    /**
     Make a rotation transform by rotating this transform by the specified values
     - Parameters:
         - radians: The rotation degrees
         - x: The X axis component of the rotation
         - y: The Y axis component of the rotation
         - z: The Z axis component of the rotation
     - Returns: A new rotation transform
     */
    func rotate(radians: Double, x: Double, y: Double, z: Double) -> double4x4 {
        return self * double4x4.makeRotate(radians: radians, x: x, y: y, z: z)
    }
    /**
     Make a translation transform by translating this transform by the specified values
     - Parameters:
         - x: The X component of the translation
         - y: The Y component of the translation
         - z: The Z component of the translation
     - Returns: A new translation transform
     */
    func translate(x: Double, y: Double, z: Double) -> double4x4 {
        return self * double4x4.makeTranslation(x: x, y: y, z: z)
    }
    /**
     Creates a new `simd_quatd`.
     - Returns: A new `simd_quatd`
     */
    func quaternion() -> simd_quatd {
        return double4x4.makeQuaternion(from: self)
    }
    /**
     - Returns: `true` if all of the values in the matrix are less than 0.0001
     */
    func isZero() -> Bool {
        if self.columns.0.x > 0.0001 || self.columns.0.y > 0.0001 || self.columns.0.z > 0.0001 || self.columns.0.w > 0.0001 {
            return false
        }
        if self.columns.1.x > 0.0001 || self.columns.1.y > 0.0001 || self.columns.1.z > 0.0001 || self.columns.1.w > 0.0001 {
            return false
        }
        if self.columns.2.x > 0.0001 || self.columns.2.y > 0.0001 || self.columns.2.z > 0.0001 || self.columns.2.w > 0.0001 {
            return false
        }
        if self.columns.3.x > 0.0001 || self.columns.3.y > 0.0001 || self.columns.3.z > 0.0001 || self.columns.3.w > 0.0001 {
            return false
        }
        return true
    }
    
    /**
     Makes a new rotation transform for rotating this transfor to look at the specified point.
     - Parameters:
         - position: The point to look at
     - Returns: A `float4x4` which specifies how this transform should be rotated to look at the point.
     */
    func lookAtMatrix(position: double3) -> double4x4 {
        return lookAtQuaternion(position: position).toMatrix4()
    }
    /**
     Makes a new rotation quaternion for rotating this transfor to look at the specified point.
     - Parameters:
         - position: The point to look at
     - Returns: A `simd_quatd` which specifies how this transform should be rotated to look at the point.
     */
    func lookAtQuaternion(position: double3) -> simd_quatd {
        let quaternion = double4x4.makeLookAt(eyeX: columns.3.x, eyeY: columns.3.y, eyeZ: columns.3.z, centerX: position.x, centerY: position.y, centerZ: position.z, upX: 0, upY: 1, upZ: 0).quaternion()
        return quaternion
    }
    /**
     A normalized 3x3 matrix
     */
    var normalMatrix: double3x3 {
        let upperLeft = double3x3(double3(columns.0.x, columns.0.y, columns.0.z), double3(columns.1.x, columns.1.y, columns.1.z), double3(columns.2.x, columns.2.y, columns.2.z))
        return upperLeft.transpose.inverse
    }
    
    /**
     Convert to a `float4x4`
     */
    func toFloat() -> float4x4 {
        return float4x4(
            columns.0.toFloat(),
            columns.1.toFloat(),
            columns.2.toFloat(),
            columns.3.toFloat()
        )
    }
    
}

// MARK: - float4

public extension float4 {
    /**
     A zero vector
     */
    static let zero = float4(0.0, 0.0, 0.0, 0.0)
    
    /**
     Equatable function
     */
    static func ==(left: float4, right: float4) -> int4 {
        return int4(left.x == right.x ? -1: 0, left.y == right.y ? -1: 0, left.z == right.z ? -1: 0, left.w == right.w ? -1: 0)
    }
    /**
     The first three elements of the vector
     */
    var xyz: float3 {
        get {
            return float3(x, y, z)
        }
        set {
            x = newValue.x
            y = newValue.y
            z = newValue.z
        }
    }
}

// MARK: - double4

public extension double4 {
    /**
     A zero vector
     */
    static let zero = double4(0.0, 0.0, 0.0, 0.0)
    
    /**
     Equatable function
     */
    static func ==(left: double4, right: double4) -> int4 {
        return int4(left.x == right.x ? -1: 0, left.y == right.y ? -1: 0, left.z == right.z ? -1: 0, left.w == right.w ? -1: 0)
    }
    /**
     The first three elements of the vector
     */
    var xyz: double3 {
        get {
            return double3(x, y, z)
        }
        set {
            x = newValue.x
            y = newValue.y
            z = newValue.z
        }
    }
    
    func toFloat() -> float4 {
        return float4(x: Float(x), y: Float(y), z: Float(z), w: Float(w))
    }
}

// MARK: - float3

public extension float3 {
    /**
     Inverse of the vector
     */
    func inverse() -> float3 {
        return float3(x: fabsf(self.x)>0 ? 1/self.x : 0, y: fabsf(self.y)>0 ? 1/self.y : 0, z: fabsf(self.z)>0 ? 1/self.z : 0)
    }
    /**
     Is another `float3` vector close to this one within an `epsilon`. `epsilon` defaults to 0.0001
     - Parameters:
        - _: The other vector
        - epsilon: the error tollerance
     - Returns: `true` if the other vector is close
     */
    func isClose(_ v: float3, epsilon: Float = 0.0001) -> Bool {
        let diff = self - v
        return Float.isClose(length_squared(diff), 0)
    }
}

// MARK: - Float

public extension FloatingPoint {
    /**
     Are two `Float`'s close within an `epsilon`. `epsilon` defaults to 0.0001
     - Parameters:
        - _: The first `Float`
        - _: The second `Float`
        - epsilon: the error tollerance
     - Returns: `true` if the two `Float`'s are close
     */
    static func isClose(_ a: Float, _ b: Float, epsilon: Float = 0.0001) -> Bool {
        return ( fabsf( a - b ) < epsilon )
    }
}

// MARK: - EulerAngles

/**
 A structure representing euler angles (roll, yaw, pitch)
 Parameters are ordered in the ARKit rotation order, ZYX:
 first roll (about Z axis), then yaw (about Y axis), then pitch (about X axis)
 */
public struct EulerAngles {
    var roll: Float
    var yaw: Float
    var pitch: Float
}

// MARK: - simd_quatf

extension simd_quatf {
    
    /**
     Converts a quaternion to a rotation matrix.
     - Returns: a rotation matrix (column major, p' = M * p)
     */
    public func toMatrix4() -> float4x4 {
        let normalizedQuaternion = normalized
        let w = normalizedQuaternion.real
        let v = normalizedQuaternion.imag
        let w2 = w * w
        let x2 = v.x * v.x
        let y2 = v.y * v.y
        let z2 = v.z * v.z
        var m = matrix_identity_float4x4
        
        m.columns.0.x = x2 - y2 - z2 + w2
        m.columns.1.y = -x2 + y2 - z2 + w2
        m.columns.2.z = -x2 - y2 + z2 + w2
        
        var tmp1 = v.x * v.y
        var tmp2 = v.z * w
        m.columns.1.x = 2.0 * (tmp1 + tmp2)
        m.columns.0.y = 2.0 * (tmp1 - tmp2)
        
        tmp1 = v.x * v.z
        tmp2 = v.y * w
        m.columns.2.x = 2.0 * (tmp1 - tmp2)
        m.columns.0.z = 2.0 * (tmp1 + tmp2)
        
        tmp1 = v.y * v.z
        tmp2 = v.x * w
        m.columns.2.y = 2.0 * (tmp1 + tmp2)
        m.columns.1.z = 2.0 * (tmp1 - tmp2)
        
        m = m.inverse
        
        return m
    }
    /**
     Look At algorythm
     - Parameters:
        - eye: The current transform of the thing that will be rotated, i.e. the 'eye'
        - center: The position of the center of the thing the eye will look at
        - up: The up direction
     - Returns: a `simd_quatf` rotation quaternion
     */
    public func lookAt(eye: float3, center: float3, up: float3) -> simd_quatf {
        
        // Normalized vector of the starting orientation. Assume that the starting orientation is
        // pointed alon the z axis
        let E = simd_normalize(float3(0, 0, 1) - eye)
        
        // Normalized vector of the target
        let zaxis = simd_normalize(center - eye)
        // Check for edge cases:
        // - No rotation
        if zaxis.x.isNaN || zaxis.y.isNaN || zaxis.z.isNaN {
            return simd_quatf(vector: float4(0, 0, 0, 1))
        }
        
        var xaxis = simd_normalize(cross(up, zaxis))
        // Check for edge cases:
        // - target is straigh up. In this case the math falls apart
        if xaxis.x.isNaN || xaxis.y.isNaN || xaxis.z.isNaN {
            xaxis = float3(repeating: 0)
        }
        
        var yaxis = cross(zaxis, xaxis)
        // Check for edge cases:
        // - target is straigh up. In this case the math falls apart
        if yaxis.x.isNaN || yaxis.y.isNaN || yaxis.z.isNaN {
            yaxis = float3(repeating: 0)
        }
        
        // Build the transform matrix
        var P = float4(repeating: 0)
        var Q = float4(repeating: 0)
        var R = float4(repeating: 0)
        var S = float4(repeating: 0)
        P.x = xaxis.x
        P.y = xaxis.y
        P.z = xaxis.z
        P.w = dot(xaxis, E)
        Q.x = yaxis.x
        Q.y = yaxis.y
        Q.z = yaxis.z
        Q.w = dot(yaxis, E)
        R.x = zaxis.x
        R.y = zaxis.y
        R.z = zaxis.z
        R.w = dot(zaxis, E)
        S.w = 1
        
        let matrix = float4x4(P, Q, R, S)
        return simd_quatf(matrix)
        
    }
    
}

// MARK: - simd_quatd

extension simd_quatd {
    
    /**
     Converts a quaternion to a rotation matrix.
     - Returns: a rotation matrix (column major, p' = M * p)
     */
    public func toMatrix4() -> double4x4 {
        let normalizedQuaternion = normalized
        let w = normalizedQuaternion.real
        let v = normalizedQuaternion.imag
        let w2 = w * w
        let x2 = v.x * v.x
        let y2 = v.y * v.y
        let z2 = v.z * v.z
        var m = matrix_identity_double4x4
        
        m.columns.0.x = x2 - y2 - z2 + w2
        m.columns.1.y = -x2 + y2 - z2 + w2
        m.columns.2.z = -x2 - y2 + z2 + w2
        
        var tmp1 = v.x * v.y
        var tmp2 = v.z * w
        m.columns.1.x = 2.0 * (tmp1 + tmp2)
        m.columns.0.y = 2.0 * (tmp1 - tmp2)
        
        tmp1 = v.x * v.z
        tmp2 = v.y * w
        m.columns.2.x = 2.0 * (tmp1 - tmp2)
        m.columns.0.z = 2.0 * (tmp1 + tmp2)
        
        tmp1 = v.y * v.z
        tmp2 = v.x * w
        m.columns.2.y = 2.0 * (tmp1 + tmp2)
        m.columns.1.z = 2.0 * (tmp1 - tmp2)
        
        m = m.inverse
        
        return m
    }
    /**
     Look At algorythm
     - Parameters:
     - eye: The current transform of the thing that will be rotated, i.e. the 'eye'
     - center: The position of the center of the thing the eye will look at
     - up: The up direction
     - Returns: a `simd_quatd` rotation quaternion
     */
    public func lookAt(eye: double3, center: double3, up: double3) -> simd_quatd {
        
        // Normalized vector of the starting orientation. Assume that the starting orientation is
        // pointed alon the z axis
        let E = simd_normalize(double3(0, 0, 1) - eye)
        
        // Normalized vector of the target
        let zaxis = simd_normalize(center - eye)
        // Check for edge cases:
        // - No rotation
        if zaxis.x.isNaN || zaxis.y.isNaN || zaxis.z.isNaN {
            return simd_quatd(vector: double4(0, 0, 0, 1))
        }
        
        var xaxis = simd_normalize(cross(up, zaxis))
        // Check for edge cases:
        // - target is straigh up. In this case the math falls apart
        if xaxis.x.isNaN || xaxis.y.isNaN || xaxis.z.isNaN {
            xaxis = double3(repeating: 0)
        }
        
        var yaxis = cross(zaxis, xaxis)
        // Check for edge cases:
        // - target is straigh up. In this case the math falls apart
        if yaxis.x.isNaN || yaxis.y.isNaN || yaxis.z.isNaN {
            yaxis = double3(repeating: 0)
        }
        
        // Build the transform matrix
        var P = double4(repeating: 0)
        var Q = double4(repeating: 0)
        var R = double4(repeating: 0)
        var S = double4(repeating: 0)
        P.x = xaxis.x
        P.y = xaxis.y
        P.z = xaxis.z
        P.w = dot(xaxis, E)
        Q.x = yaxis.x
        Q.y = yaxis.y
        Q.z = yaxis.z
        Q.w = dot(yaxis, E)
        R.x = zaxis.x
        R.y = zaxis.y
        R.z = zaxis.z
        R.w = dot(zaxis, E)
        S.w = 1
        
        let matrix = double4x4(P, Q, R, S)
        return simd_quatd(matrix)
        
    }
    
}

// MARK: Debugging

extension simd_quatf: CustomStringConvertible {
    /// :nodoc:
    public var description: String {
        return debugDescription
    }
}

extension simd_quatd: CustomStringConvertible {
    /// :nodoc:
    public var description: String {
        return debugDescription
    }
}


// MARK: - QuaternionUtilities
/**
 Tools for using quaternions. Augmentkit uses `simd_quatf` for all quaternions.
 */
open class QuaternionUtilities {
    
    /**
     Creates a quaternion from a set of `EulerAngles`
     - Parameters:
        - eulerAngles: A set of euler angles representing the rotation
     - Returns: a new `simd_quatf`
     */
    public static func quaternionFromEulerAngles(eulerAngles: EulerAngles) -> simd_quatf {
        
        // Follow the ZYX rotation order convention
        var q = simd_quatf(angle: eulerAngles.roll, axis: float3(0, 0, 1))
        q *= simd_quatf(angle: eulerAngles.yaw, axis: float3(0, 1, 0))
        q *= simd_quatf(angle: eulerAngles.pitch, axis: float3(1, 0, 0))
        return q
        
    }
    
}
