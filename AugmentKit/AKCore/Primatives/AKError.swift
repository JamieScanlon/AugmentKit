//
//  AKError.swift
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

public let AKErrorDomain = "com.tenthlettermade.AugmentKit.errordomain"
public let AKErrorCodeMissingVertexDescriptors = 123
public let AKErrorCodeDeviceNotFound = 124
public let AKErrorCodeShaderInitializationFailed = 125
public let AKErrorCodeRenderPipelineInitializationFailed = 125
public let AKErrorCodeIntermediateMeshDataNotAvailable = 126
public let AKErrorCodeIntermediateMeshDataNotFound = 127
public let AKErrorCodeInvalidMeshData = 128
public let AKErrorCodeModelNotFound = 129
public let AKErrorCodeModelNotSupported = 130
public let AKErrorCodeModelProviderNotFound = 131

public enum AKError: Error {
    case warning(AKErrorType)
    case recoverableError(AKErrorType)
    case seriousError(AKErrorType)
}

public enum AKErrorType {
    case modelError(ModelErrorReason)
    case renderPipelineError(RenderPipelineErrorReason)
    case locationServicesError(UnderlyingErrorInfo)
    case arkitError(UnderlyingErrorInfo)
    case serializationError(SerializationErrorReason)
}

public enum ModelErrorReason {
    case unableToLoadTexture(AssetErrorInfo)
    case fileNotLoaded(AssetErrorInfo)
    case modelNotFound(ModelErrorInfo)
    case invalidModel(ModelErrorInfo)
}

public enum RenderPipelineErrorReason {
    case failedToInitialize(PipelineErrorInfo)
    case drawAborted(PipelineErrorInfo)
}

public enum SerializationErrorReason {
    case unableToSave(AssetErrorInfo)
    case fileNotFound(AssetErrorInfo)
    case invalidFile(AssetErrorInfo)
    case emptyFile(AssetErrorInfo)
}

public struct AssetErrorInfo {
    var path: String
    var underlyingError: Error?
    
    init(path: String, underlyingError: Error? = nil) {
        self.path = path
        self.underlyingError = underlyingError
    }
}

public struct ModelErrorInfo {
    var type: String
    var identifier: UUID?
    var underlyingError: Error?
    
    init(type: String, identifier: UUID? = nil, underlyingError: Error? = nil) {
        self.type = type
        self.identifier = identifier
        self.underlyingError = underlyingError
    }
    
}

public struct PipelineErrorInfo {
    var moduleIdentifier: String?
    var underlyingError: Error?
    
    init(moduleIdentifier: String? = nil, underlyingError: Error? = nil) {
        self.moduleIdentifier = moduleIdentifier
        self.underlyingError = underlyingError
    }
    
}

public struct UnderlyingErrorInfo {
    var underlyingError: Error?
    
    init() {}
    
    init(underlyingError: Error) {
        self.underlyingError = underlyingError
    }
    
}
