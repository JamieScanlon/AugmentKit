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

/**
 AugmentKit error domain
 */
public let AKErrorDomain = "com.tenthlettermade.AugmentKit.errordomain"
/**
 Error code for missing vertex descriptors
 */
public let AKErrorCodeMissingVertexDescriptors = 123
/**
 Error code for the Metal device not being found
 */
public let AKErrorCodeDeviceNotFound = 124
/**
 Error code for failed shader initialization
 */
public let AKErrorCodeShaderInitializationFailed = 125
/**
 Error code for failed render pipeline initialization
 */
public let AKErrorCodeRenderPipelineInitializationFailed = 125
/**
 Error code for not being able to find the intermediate representation of the model data during a draw call.
 */
public let AKErrorCodeIntermediateMeshDataNotAvailable = 126
/**
 Error code for not being able to find the parse the model asset into an intermediate representation during initialization.
 */
public let AKErrorCodeIntermediateMeshDataNotFound = 127
/**
 Error code for invalid model asset data.
 */
public let AKErrorCodeInvalidMeshData = 128
/**
 Error code for missing model asset data.
 */
public let AKErrorCodeModelNotFound = 129
/**
 Error code for unsupported model asset data.
 */
public let AKErrorCodeModelNotSupported = 130
/**
 Error code for a missing model provider.
 */
public let AKErrorCodeModelProviderNotFound = 131
/**
 Error code for a missing render pass.
 */
public let AKErrorCodeRenderPassNotFound = 131

/**
 `AKError`'s are describe according to severity.
 - `warning`s may hint to a misconfiguration or a possible oversight. AugmentKit is still running properly but you should be aware of warnings and make sure that it is what you intended.
 - `recoverableError`s are errors that should be fixed but are not serious enough to terminate the session. The consequences of proceeding despite serious warnings might be that somw AR objects are not rendered or rendered improperly.
 - `seriousError`s are errors that cause AugmentKit to be in an unstable state. No recovery is possible.
 */
public enum AKError: Error {
    /**
     An error which may hint to a misconfiguration or a possible oversight. AugmentKit is still running properly but you should be aware of warnings and make sure that it is what you intended.
     */
    case warning(AKErrorType)
    /**
     An error which should be fixed but are not serious enough to terminate the session. The consequences of proceeding despite serious warnings might be that somw AR objects are not rendered or rendered improperly.
     */
    case recoverableError(AKErrorType)
    /**
     An error which cause AugmentKit to be in an unstable state. No recovery is possible.
     */
    case seriousError(AKErrorType)
}

/**
 `AKErrorType`s describe `AKError`s. All `AKErrorType`s have an Associated Value which provide more detail about the error.
 - `modelError`s are errors related to loading or parsing an `MDLAsset` model
 - `renderPipelineError` are errors related to the render pipeline
 - `locationServicesError` are errors related to location services
 - `arkitError` are errors bubbled up from `ARKit`
 */
public enum AKErrorType {
    /**
     An error related to misconfiguration of the renderer..
     */
    case configurationError(ConfigurationErrorReason)
    /**
     An error related to loading or parsing an `MDLAsset` model.
     */
    case modelError(ModelErrorReason)
    /**
     An error related to the render pipeline.
     */
    case renderPipelineError(RenderPipelineErrorReason)
    /**
     An error related to location services.
     */
    case locationServicesError(UnderlyingErrorInfo)
    /**
     An error bubbled up from `ARKit`.
     */
    case arkitError(UnderlyingErrorInfo)
}

/**
 `ModelErrorReason` is used as an Associted Value for a `AKErrorType.modelError` and provides the reason for the error. All `ModelErrorReason`s have an Associated Value that gives moer info about the specific error.
 */
public enum ModelErrorReason {
    /**
     A model texture could not be found or could not be loaded
     */
    case unableToLoadTexture(AssetErrorInfo)
    /**
     A model could not be loaded
     */
    case fileNotLoaded(AssetErrorInfo)
    /**
     A model could not be found
     */
    case modelNotFound(ModelErrorInfo)
    /**
     A model could not be be parsed by Model I/O
     */
    case invalidModel(ModelErrorInfo)
}

/**
 `RenderPipelineErrorReason` is used as an Associted Value for a `AKErrorType.renderPipelineError` and provides the reason for the error. All `RenderPipelineErrorReason`s have an Associated Value that gives more info about the specific error.
 */
public enum RenderPipelineErrorReason {
    /**
     The render pipline could not be initialized
     */
    case failedToInitialize(PipelineErrorInfo)
    /**
     The render pipline had to abort a draw call due to errors
     */
    case drawAborted(PipelineErrorInfo)
}

/**
 `ConfigurationErrorReason` is used as an Associted Value for a `AKErrorType.modelError` and provides the reason for the error. All `ConfigurationErrorReason`s relate to misconfiguration of the renderer.
 */
public enum ConfigurationErrorReason {
    /**
     The current `AKSessionType` is not capable of performing the requested action
     */
    case sessionTypeCapabilities
}

/**
 `AssetErrorInfo` is used as an Associted Value for a `ModelErrorReason` and provides the information about the `MDLAsset` which caused the `AKError`
 */
public struct AssetErrorInfo {
    /**
     The file path of the `MDLAsset`
     */
    var path: String
    /**
     An underlying error from Model I/O
     */
    var underlyingError: Error?
    
    /**
     Initialize a new structure with a `path` and `underlyingError`
     - Parameters:
        - path: The file path of the `MDLAsset`
        - underlyingError: An underlying error from Model I/O
     */
    init(path: String, underlyingError: Error? = nil) {
        self.path = path
        self.underlyingError = underlyingError
    }
}

/**
 `ModelErrorInfo` is used as an Associted Value for a `ModelErrorReason` and provides the information about the `AKGeometricEntity` which caused the `AKError`
 - SeeAlso: `AKGeometricEntity`
 */
public struct ModelErrorInfo {
    /**
     The `AKGeometricEntity.type` of the entity which triggered the `AKError`
     */
    var type: String
    /**
     The `AKGeometricEntity.identifier` of the entity which triggered the `AKError`
     */
    var identifier: UUID?
    /**
     An underlying error is one is available.
     */
    var underlyingError: Error?
    /**
     Initializes a new structure with a `type`, `identifier`, and `underlyingError`
     - Parameters:
        - type: The `AKGeometricEntity.type` of the entity which triggered the `AKError`
        - identifier: The `AKGeometricEntity.identifier` of the entity which triggered the `AKError`
        - underlyingError: An underlying error is one is available.
     */
    init(type: String, identifier: UUID? = nil, underlyingError: Error? = nil) {
        self.type = type
        self.identifier = identifier
        self.underlyingError = underlyingError
    }
    
}

/**
 `PipelineErrorInfo` is used as an Associted Value for a `RenderPipelineErrorReason` and provides the information about  `AKError`
 */
public struct PipelineErrorInfo {
    /**
     An identifier for the `RenderModule` which encountered the error
     */
    var moduleIdentifier: String?
    /**
     An underlying error is one is available.
     */
    var underlyingError: Error?
    /**
     Initializes a new structure with a `identifier`, and `underlyingError`
     - Parameters:
     - identifier: An identifier for the `RenderModule` which encountered the error
     - underlyingError: An underlying error is one is available.
     */
    init(moduleIdentifier: String? = nil, underlyingError: Error? = nil) {
        self.moduleIdentifier = moduleIdentifier
        self.underlyingError = underlyingError
    }
    
}

/**
 `UnderlyingErrorInfo` is used as an Associted Value for a `AKErrorType` and provides the underlying error which caused the `AKError`
 */
public struct UnderlyingErrorInfo {
    var underlyingError: Error?
    
    init() {}
    
    init(underlyingError: Error) {
        self.underlyingError = underlyingError
    }
    
}
