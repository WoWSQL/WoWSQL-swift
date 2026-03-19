//
//  Exceptions.swift
//  WOWSQL
//
//  Created by WOWSQL Team
//  Copyright © 2024 WOWSQL. All rights reserved.
//

import Foundation

/// Base error for WOWSQL SDK
public class WOWSQLError: Error, LocalizedError {
    public let message: String
    public let statusCode: Int?
    public let response: [String: Any]?
    
    public var errorDescription: String? {
        message
    }
    
    public init(_ message: String, statusCode: Int? = nil, response: [String: Any]? = nil) {
        self.message = message
        self.statusCode = statusCode
        self.response = response
    }
}

/// Backward-compatible alias
public typealias WOWSQLException = WOWSQLError

/// Authentication error (401/403)
public class AuthenticationError: WOWSQLError {
    public override init(_ message: String, statusCode: Int? = nil, response: [String: Any]? = nil) {
        super.init(message, statusCode: statusCode, response: response)
    }
}

public typealias AuthenticationException = AuthenticationError

/// Not found error (404)
public class NotFoundError: WOWSQLError {
    public init(_ message: String, response: [String: Any]? = nil) {
        super.init(message, statusCode: 404, response: response)
    }
}

public typealias NotFoundException = NotFoundError

/// Rate limit error (429)
public class RateLimitError: WOWSQLError {
    public init(_ message: String, response: [String: Any]? = nil) {
        super.init(message, statusCode: 429, response: response)
    }
}

public typealias RateLimitException = RateLimitError

/// Network error
public class NetworkError: WOWSQLError {
    public init(_ message: String, underlyingError: Error? = nil) {
        super.init(message)
    }
}

public typealias NetworkException = NetworkError

/// Storage error
public class StorageError: WOWSQLError {
    public override init(_ message: String, statusCode: Int? = nil, response: [String: Any]? = nil) {
        super.init(message, statusCode: statusCode, response: response)
    }
}

public typealias StorageException = StorageError

/// Storage limit exceeded error (413)
public class StorageLimitExceededError: StorageError {
    public let requiredBytes: Int64
    public let availableBytes: Int64
    
    public init(_ message: String, requiredBytes: Int64 = 0, availableBytes: Int64 = 0, response: [String: Any]? = nil) {
        self.requiredBytes = requiredBytes
        self.availableBytes = availableBytes
        super.init(message, statusCode: 413, response: response)
    }
}

public typealias StorageLimitExceededException = StorageLimitExceededError

/// Schema permission error (403) - requires service role key
public class SchemaPermissionError: WOWSQLError {
    public init(_ message: String = "Schema operations require a SERVICE ROLE key.", response: [String: Any]? = nil) {
        super.init(message, statusCode: 403, response: response)
    }
}
