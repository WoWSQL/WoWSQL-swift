//
//  Exceptions.swift
//  WOWSQL
//
//  Created by WOWSQL Team
//  Copyright © 2024 WOWSQL. All rights reserved.
//

import Foundation

/// Base exception for WOWSQL SDK
public class WOWSQLException: Error, LocalizedError {
    public let message: String
    public let statusCode: Int?
    public let errorResponse: [String: Any]?
    
    public var errorDescription: String? {
        message
    }
    
    public init(_ message: String, statusCode: Int? = nil, errorResponse: [String: Any]? = nil) {
        self.message = message
        self.statusCode = statusCode
        self.errorResponse = errorResponse
    }
}

/// Authentication exception
public class AuthenticationException: WOWSQLException {
    public override init(_ message: String, statusCode: Int? = nil, errorResponse: [String: Any]? = nil) {
        super.init(message, statusCode: statusCode, errorResponse: errorResponse)
    }
}

/// Not found exception
public class NotFoundException: WOWSQLException {
    public init(_ message: String, errorResponse: [String: Any]? = nil) {
        super.init(message, statusCode: 404, errorResponse: errorResponse)
    }
}

/// Rate limit exception
public class RateLimitException: WOWSQLException {
    public init(_ message: String, errorResponse: [String: Any]? = nil) {
        super.init(message, statusCode: 429, errorResponse: errorResponse)
    }
}

/// Network exception
public class NetworkException: WOWSQLException {
    public init(_ message: String, underlyingError: Error? = nil) {
        super.init(message)
    }
}

/// Storage exception
public class StorageException: WOWSQLException {
    public override init(_ message: String, statusCode: Int? = nil, errorResponse: [String: Any]? = nil) {
        super.init(message, statusCode: statusCode, errorResponse: errorResponse)
    }
}

/// Storage limit exceeded exception
public class StorageLimitExceededException: StorageException {
    public let requiredBytes: Int64
    public let availableBytes: Int64
    
    public init(_ message: String, requiredBytes: Int64, availableBytes: Int64, errorResponse: [String: Any]? = nil) {
        self.requiredBytes = requiredBytes
        self.availableBytes = availableBytes
        super.init(message, statusCode: 413, errorResponse: errorResponse)
    }
}

