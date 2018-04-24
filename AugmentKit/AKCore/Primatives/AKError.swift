//
//  AKError.swift
//  AugmentKit
//
//  Created by Jamie Scanlon on 4/21/18.
//  Copyright © 2018 TenthLetterMade. All rights reserved.
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
