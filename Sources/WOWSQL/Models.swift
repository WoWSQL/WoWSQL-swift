//
//  Models.swift
//  WOWSQL
//
//  Created by WOWSQL Team
//  Copyright © 2024 WOWSQL. All rights reserved.
//

import Foundation

/// Response from a query operation
public struct QueryResponse<T: Codable>: Codable {
    public let data: [T]
    public let count: Int
    public let total: Int?
    public let error: String?
    
    public init(data: [T], count: Int, total: Int? = nil, error: String? = nil) {
        self.data = data
        self.count = count
        self.total = total
        self.error = error
    }
}

/// Response from a create operation
public struct CreateResponse: Codable {
    public let id: AnyCodable
    public let affectedRows: Int
    public let success: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case affectedRows = "affected_rows"
        case success
    }
    
    public init(id: AnyCodable, affectedRows: Int = 1, success: Bool = true) {
        self.id = id
        self.affectedRows = affectedRows
        self.success = success
    }
}

/// Response from an update operation
public struct UpdateResponse: Codable {
    public let affectedRows: Int
    public let success: Bool
    
    enum CodingKeys: String, CodingKey {
        case affectedRows = "affected_rows"
        case success
    }
    
    public init(affectedRows: Int, success: Bool = true) {
        self.affectedRows = affectedRows
        self.success = success
    }
}

/// Response from a delete operation
public struct DeleteResponse: Codable {
    public let affectedRows: Int
    public let success: Bool
    
    enum CodingKeys: String, CodingKey {
        case affectedRows = "affected_rows"
        case success
    }
    
    public init(affectedRows: Int, success: Bool = true) {
        self.affectedRows = affectedRows
        self.success = success
    }
}

/// Table schema information
public struct TableSchema: Codable {
    public let name: String
    public let columns: [ColumnInfo]
    public let primaryKey: String?
    public let rowCount: Int?
    
    enum CodingKeys: String, CodingKey {
        case name
        case columns
        case primaryKey = "primary_key"
        case rowCount = "row_count"
    }
}

/// Column information
public struct ColumnInfo: Codable {
    public let name: String
    public let type: String
    public let nullable: Bool
    public let `default`: AnyCodable?
    
    public init(name: String, type: String, nullable: Bool = true, default: AnyCodable? = nil) {
        self.name = name
        self.type = type
        self.nullable = nullable
        self.default = `default`
    }
}

/// Storage quota information
public struct StorageQuota: Codable {
    public let storageQuotaGb: Double
    public let storageUsedGb: Double
    public let storageExpansionGb: Double
    public let storageAvailableGb: Double
    public let usagePercentage: Double
    public let canExpandStorage: Bool
    public let isEnterprise: Bool
    public let planName: String
    
    enum CodingKeys: String, CodingKey {
        case storageQuotaGb = "storage_quota_gb"
        case storageUsedGb = "storage_used_gb"
        case storageExpansionGb = "storage_expansion_gb"
        case storageAvailableGb = "storage_available_gb"
        case usagePercentage = "usage_percentage"
        case canExpandStorage = "can_expand_storage"
        case isEnterprise = "is_enterprise"
        case planName = "plan_name"
    }
    
    public var storageQuotaBytes: Int64 {
        Int64(storageQuotaGb * 1024 * 1024 * 1024)
    }
    
    public var storageUsedBytes: Int64 {
        Int64(storageUsedGb * 1024 * 1024 * 1024)
    }
    
    public var storageAvailableBytes: Int64 {
        Int64(storageAvailableGb * 1024 * 1024 * 1024)
    }
}

/// Storage file information
public struct StorageFile: Codable {
    public let key: String
    public let size: Int64
    public let lastModified: String
    public let contentType: String?
    public let etag: String?
    
    enum CodingKeys: String, CodingKey {
        case key
        case size
        case lastModified = "last_modified"
        case contentType = "content_type"
        case etag
    }
}

/// File upload result
public struct FileUploadResult: Codable {
    public let key: String
    public let size: Int64
    public let url: String
    public let success: Bool
    
    public init(key: String, size: Int64, url: String, success: Bool = true) {
        self.key = key
        self.size = size
        self.url = url
        self.success = success
    }
}

/// Filter operators for queries
public enum FilterOperator: String, Codable {
    case eq = "eq"
    case neq = "neq"
    case gt = "gt"
    case gte = "gte"
    case lt = "lt"
    case lte = "lte"
    case like = "like"
    case isNull = "is"
}

/// Sort direction
public enum SortDirection: String, Codable {
    case asc = "asc"
    case desc = "desc"
}

/// Filter expression for queries
public struct FilterExpression: Codable {
    public let column: String
    public let `operator`: FilterOperator
    public let value: AnyCodable?
    
    public init(column: String, operator op: FilterOperator, value: AnyCodable?) {
        self.column = column
        self.`operator` = op
        self.value = value
    }
}

/// Type-erased Codable value
public struct AnyCodable: Codable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodable value cannot be decoded"
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "AnyCodable value cannot be encoded"
                )
            )
        }
    }
}

// MARK: - Auth Models

/// Project authentication configuration
public struct ProjectAuthConfig {
    public let projectUrl: String
    public let baseDomain: String
    public let secure: Bool
    public let timeoutSeconds: TimeInterval
    public let publicApiKey: String?
    
    public init(
        projectUrl: String,
        baseDomain: String = "wowsql.com",
        secure: Bool = true,
        timeoutSeconds: TimeInterval = 30,
        publicApiKey: String? = nil
    ) {
        self.projectUrl = projectUrl
        self.baseDomain = baseDomain
        self.secure = secure
        self.timeoutSeconds = timeoutSeconds
        self.publicApiKey = publicApiKey
    }
}

/// Authenticated user
public struct AuthUser: Codable {
    public let id: String
    public let email: String
    public let fullName: String?
    public let avatarUrl: String?
    public let emailVerified: Bool
    public let userMetadata: [String: AnyCodable]
    public let appMetadata: [String: AnyCodable]
    public let createdAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case fullName = "full_name"
        case avatarUrl = "avatar_url"
        case emailVerified = "email_verified"
        case userMetadata = "user_metadata"
        case appMetadata = "app_metadata"
        case createdAt = "created_at"
    }
}

/// Authentication session
public struct AuthSession: Codable {
    public let accessToken: String
    public let refreshToken: String
    public let tokenType: String
    public let expiresIn: Int
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

/// Authentication result
public struct AuthResult {
    public let user: AuthUser?
    public let session: AuthSession
}

/// OAuth authorization response
public struct OAuthAuthorizationResponse: Codable {
    public let authorizationUrl: String
    public let provider: String
    public let redirectUri: String
    public let backendCallbackUrl: String?
    public let frontendRedirectUri: String?
    
    enum CodingKeys: String, CodingKey {
        case authorizationUrl = "authorization_url"
        case provider
        case redirectUri = "redirect_uri"
        case backendCallbackUrl = "backend_callback_url"
        case frontendRedirectUri = "frontend_redirect_uri"
    }
}

/// Sign up request
public struct SignUpRequest {
    public let email: String
    public let password: String
    public let fullName: String?
    public let userMetadata: [String: AnyCodable]?
    
    public init(email: String, password: String, fullName: String? = nil, userMetadata: [String: AnyCodable]? = nil) {
        self.email = email
        self.password = password
        self.fullName = fullName
        self.userMetadata = userMetadata
    }
}

/// Sign in request
public struct SignInRequest {
    public let email: String
    public let password: String
    
    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}

