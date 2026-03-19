//
//  Models.swift
//  WOWSQL
//
//  Created by WOWSQL Team
//  Copyright © 2024 WOWSQL. All rights reserved.
//

import Foundation

// MARK: - Query Models

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

// MARK: - Filter / Query Builder Models

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
    case `in` = "in"
    case notIn = "not_in"
    case between = "between"
    case notBetween = "not_between"
    case isNot = "is_not"
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
    public let logicalOp: String?
    
    public init(column: String, operator op: FilterOperator, value: AnyCodable?, logicalOp: String? = "AND") {
        self.column = column
        self.`operator` = op
        self.value = value
        self.logicalOp = logicalOp
    }
}

/// HAVING clause filter for aggregated results
public struct HavingFilter: Codable {
    public let column: String
    public let `operator`: String
    public let value: AnyCodable
    
    public init(column: String, operator op: String, value: AnyCodable) {
        self.column = column
        self.`operator` = op
        self.value = value
    }
}

/// Order by item for multiple column sorting
public struct OrderByItem: Codable {
    public let column: String
    public let direction: SortDirection
    
    public init(column: String, direction: SortDirection) {
        self.column = column
        self.direction = direction
    }
}

// MARK: - Auth Models

/// Token storage protocol for persisting auth tokens
public protocol TokenStorage: AnyObject {
    func getAccessToken() -> String?
    func setAccessToken(_ token: String?)
    func getRefreshToken() -> String?
    func setRefreshToken(_ token: String?)
}

/// Default in-memory token storage
public class MemoryTokenStorage: TokenStorage {
    private var accessToken: String?
    private var refreshToken: String?
    
    public init() {}
    
    public func getAccessToken() -> String? { accessToken }
    public func setAccessToken(_ token: String?) { accessToken = token }
    public func getRefreshToken() -> String? { refreshToken }
    public func setRefreshToken(_ token: String?) { refreshToken = token }
}

/// Authenticated user
public struct AuthUser: Codable {
    public let id: String
    public let email: String
    public let fullName: String?
    public let avatarUrl: String?
    public let emailVerified: Bool
    public let userMetadata: [String: AnyCodable]?
    public let appMetadata: [String: AnyCodable]?
    public let createdAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, email
        case fullName = "full_name"
        case avatarUrl = "avatar_url"
        case emailVerified = "email_verified"
        case userMetadata = "user_metadata"
        case appMetadata = "app_metadata"
        case createdAt = "created_at"
    }
    
    public init(
        id: String,
        email: String,
        fullName: String? = nil,
        avatarUrl: String? = nil,
        emailVerified: Bool = false,
        userMetadata: [String: AnyCodable]? = nil,
        appMetadata: [String: AnyCodable]? = nil,
        createdAt: String? = nil
    ) {
        self.id = id
        self.email = email
        self.fullName = fullName
        self.avatarUrl = avatarUrl
        self.emailVerified = emailVerified
        self.userMetadata = userMetadata
        self.appMetadata = appMetadata
        self.createdAt = createdAt
    }
}

/// Authentication session tokens
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
    
    public init(accessToken: String, refreshToken: String, tokenType: String = "bearer", expiresIn: Int = 0) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
    }
}

/// Authentication response (session + optional user)
public struct AuthResponse {
    public let session: AuthSession
    public let user: AuthUser?
    
    public init(session: AuthSession, user: AuthUser? = nil) {
        self.session = session
        self.user = user
    }
}

/// Backward-compatible alias
public typealias AuthResult = AuthResponse

// MARK: - Storage Models

/// Storage bucket information
public struct StorageBucket {
    public let id: String
    public let name: String
    public let isPublic: Bool
    public let fileSizeLimit: Int?
    public let allowedMimeTypes: [String]?
    public let createdAt: String?
    public let objectCount: Int
    public let totalSize: Int
    
    public init(data: [String: Any]) {
        self.id = data["id"] as? String ?? ""
        self.name = data["name"] as? String ?? ""
        self.isPublic = data["public"] as? Bool ?? false
        self.fileSizeLimit = data["file_size_limit"] as? Int
        self.allowedMimeTypes = data["allowed_mime_types"] as? [String]
        self.createdAt = data["created_at"] as? String
        self.objectCount = data["object_count"] as? Int ?? 0
        self.totalSize = data["total_size"] as? Int ?? 0
    }
}

/// Storage file/object information
public struct StorageFile {
    public let id: String
    public let bucketId: String
    public let name: String
    public let path: String
    public let mimeType: String?
    public let size: Int
    public let metadata: [String: Any]
    public let createdAt: String?
    public let publicUrl: String?
    
    public var sizeMb: Double { Double(size) / (1024.0 * 1024.0) }
    public var sizeGb: Double { Double(size) / (1024.0 * 1024.0 * 1024.0) }
    
    public init(data: [String: Any]) {
        self.id = data["id"] as? String ?? ""
        self.bucketId = data["bucket_id"] as? String ?? ""
        self.name = data["name"] as? String ?? ""
        self.path = data["path"] as? String ?? ""
        self.mimeType = data["mime_type"] as? String
        self.size = data["size"] as? Int ?? 0
        self.metadata = data["metadata"] as? [String: Any] ?? [:]
        self.createdAt = data["created_at"] as? String
        self.publicUrl = data["public_url"] as? String
    }
}

/// Storage quota / statistics information
public struct StorageQuota {
    public let totalFiles: Int
    public let totalSizeBytes: Int
    public let totalSizeGb: Double
    public let fileTypes: [String: Any]
    
    public init(data: [String: Any]) {
        self.totalFiles = data["total_files"] as? Int ?? 0
        self.totalSizeBytes = data["total_size_bytes"] as? Int ?? 0
        self.totalSizeGb = data["total_size_gb"] as? Double ?? 0.0
        self.fileTypes = data["file_types"] as? [String: Any] ?? [:]
    }
}

// MARK: - Legacy Auth Config (backward compatibility)

/// Project authentication configuration (deprecated - use direct params)
public struct ProjectAuthConfig {
    public let projectUrl: String
    public let baseDomain: String
    public let secure: Bool
    public let timeoutSeconds: TimeInterval
    public let apiKey: String?
    public let publicApiKey: String?
    
    public init(
        projectUrl: String,
        baseDomain: String = "wowsql.com",
        secure: Bool = true,
        timeoutSeconds: TimeInterval = 30,
        apiKey: String? = nil,
        publicApiKey: String? = nil
    ) {
        self.projectUrl = projectUrl
        self.baseDomain = baseDomain
        self.secure = secure
        self.timeoutSeconds = timeoutSeconds
        self.apiKey = apiKey ?? publicApiKey
        self.publicApiKey = apiKey ?? publicApiKey
    }
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

// MARK: - AnyCodable

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
