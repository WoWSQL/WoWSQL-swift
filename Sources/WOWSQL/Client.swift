//
//  Client.swift
//  WOWSQL
//
//  Created by WOWSQL Team
//  Copyright © 2024 WOWSQL. All rights reserved.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Main client for interacting with WOWSQL API (database operations).
///
/// Use Service Role Key or Anonymous Key for authentication.
///
/// Example:
/// ```swift
/// let client = WOWSQLClient(
///     projectUrl: "myproject",
///     apiKey: "wowbase_service_..."
/// )
/// let users = try await client.table("users").select("*").get()
/// ```
public class WOWSQLClient {
    internal let baseUrl: String
    internal let apiUrl: String
    private let apiKey: String
    private let timeout: TimeInterval
    private let session: URLSession
    
    /// Initialize the client for DATABASE OPERATIONS.
    ///
    /// All requests are sent directly to the PostgREST endpoint (`/rest/v1`).
    ///
    /// - Parameters:
    ///   - projectUrl: Project subdomain or full URL
    ///     (e.g., `"myproject"`, `"https://myproject.wowsqlconnect.com"`)
    ///   - apiKey: API key (Service Role or Anonymous)
    ///   - baseDomain: Base domain (default: `"wowsqlconnect.com"`)
    ///   - secure: Use HTTPS (default: `true`)
    ///   - timeout: Request timeout in seconds (default: 30)
    ///   - verifySsl: Verify SSL certificates (default: `true`)
    public init(
        projectUrl: String,
        apiKey: String,
        baseDomain: String = "wowsqlconnect.com",
        secure: Bool = true,
        timeout: TimeInterval = 30,
        verifySsl: Bool = true
    ) {
        let url = projectUrl.trimmingCharacters(in: .whitespaces)
        let apiPath = "/rest/v1"

        if url.hasPrefix("http://") || url.hasPrefix("https://") {
            var base = url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if base.contains("/api") {
                base = base.components(separatedBy: "/api").first ?? base
            }
            self.baseUrl = base
            self.apiUrl = "\(base)\(apiPath)"
        } else {
            let proto = secure ? "https" : "http"
            let base: String
            if url.contains(".\(baseDomain)") || url.hasSuffix(baseDomain) {
                base = "\(proto)://\(url)"
            } else {
                base = "\(proto)://\(url).\(baseDomain)"
            }
            self.baseUrl = base
            self.apiUrl = "\(base)\(apiPath)"
        }
        
        self.apiKey = apiKey
        self.timeout = timeout
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: config)
    }
    
    /// Get a table interface for operations.
    public func table(_ tableName: String) -> Table {
        return Table(client: self, tableName: tableName)
    }
    
    /// List all tables in the database.
    public func listTables() async throws -> [String] {
        let url = URL(string: "\(apiUrl)/tables")!
        let response: [String: AnyCodable] = try await executeRequest(url: url, method: "GET")
        
        if let tables = response["tables"]?.value as? [String] {
            return tables
        } else if let tablesArray = response["tables"]?.value as? [Any] {
            return tablesArray.compactMap { $0 as? String }
        }
        return []
    }
    
    /// Get table schema information.
    public func getTableSchema(_ tableName: String) async throws -> TableSchema {
        let url = URL(string: "\(apiUrl)/tables/\(tableName)/schema")!
        return try await executeRequest(url: url, method: "GET")
    }
    
    /// Close the client session (invalidates all outstanding tasks).
    public func close() {
        session.invalidateAndCancel()
    }
    
    // MARK: - Internal Request Methods
    
    internal func buildRequest(url: URL, method: String, body: [String: AnyCodable]? = nil) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        if let body = body {
            let jsonData = try JSONEncoder().encode(body)
            request.httpBody = jsonData
        }
        
        return request
    }
    
    internal func executeRequest<T: Codable>(url: URL, method: String, body: [String: AnyCodable]? = nil) async throws -> T {
        let request = try buildRequest(url: url, method: method, body: body)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError("Invalid response type")
            }
            
            if !(200...299).contains(httpResponse.statusCode) {
                try handleError(statusCode: httpResponse.statusCode, data: data)
            }
            
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as WOWSQLError {
            throw error
        } catch {
            throw NetworkError("Network error: \(error.localizedDescription)", underlyingError: error)
        }
    }
    
    private func handleError(statusCode: Int, data: Data) throws -> Never {
        let errorResponse = try? JSONDecoder().decode([String: AnyCodable].self, from: data)
        
        let message = errorResponse?["detail"]?.value as? String
            ?? errorResponse?["error"]?.value as? String
            ?? errorResponse?["message"]?.value as? String
            ?? "Request failed with status \(statusCode)"
        
        let errorDict = errorResponse?.mapValues { $0.value } as? [String: Any]
        
        switch statusCode {
        case 401, 403:
            throw AuthenticationError(message, statusCode: statusCode, response: errorDict)
        case 404:
            throw NotFoundError(message, response: errorDict)
        case 429:
            throw RateLimitError(message, response: errorDict)
        default:
            throw WOWSQLError(message, statusCode: statusCode, response: errorDict)
        }
    }
}

// MARK: - Table

/// Represents a database table with fluent API for operations.
public class Table {
    private let client: WOWSQLClient
    private let tableName: String
    
    internal init(client: WOWSQLClient, tableName: String) {
        self.client = client
        self.tableName = tableName
    }
    
    /// Start a select query.
    public func select(_ columns: String...) -> QueryBuilder {
        return QueryBuilder(client: client, tableName: tableName).select(columns)
    }
    
    /// Start a select query.
    public func select(_ columns: [String]) -> QueryBuilder {
        return QueryBuilder(client: client, tableName: tableName).select(columns)
    }
    
    /// Start a filtered query.
    public func filter(_ column: String, _ op: FilterOperator, _ value: AnyCodable, _ logicalOp: String = "AND") -> QueryBuilder {
        return QueryBuilder(client: client, tableName: tableName).filter(column, op, value, logicalOp)
    }
    
    /// Get all records.
    public func get<T: Codable>() async throws -> QueryResponse<T> {
        return try await QueryBuilder(client: client, tableName: tableName).select(["*"]).execute()
    }
    
    /// Get a single record by ID.
    public func getById(_ id: AnyCodable) async throws -> [String: AnyCodable] {
        let url = URL(string: "\(client.apiUrl)/\(tableName)/\(id)")!
        return try await client.executeRequest(url: url, method: "GET", body: nil)
    }
    
    /// Create a new record.
    public func create(_ data: [String: AnyCodable]) async throws -> CreateResponse {
        let url = URL(string: "\(client.apiUrl)/\(tableName)")!
        return try await client.executeRequest(url: url, method: "POST", body: data)
    }
    
    /// Insert a new record (alias for create).
    public func insert(_ data: [String: AnyCodable]) async throws -> CreateResponse {
        return try await create(data)
    }
    
    /// Insert multiple records.
    public func bulkInsert(_ records: [[String: AnyCodable]]) async throws -> [CreateResponse] {
        if records.isEmpty { return [] }
        var results: [CreateResponse] = []
        for record in records {
            let result = try await create(record)
            results.append(result)
        }
        return results
    }
    
    /// Insert or update based on conflict column.
    public func upsert(_ data: [String: AnyCodable], onConflict: String = "id") async throws -> [String: AnyCodable] {
        let conflictValue = data[onConflict]
        guard let conflictValue = conflictValue else {
            let createResult = try await create(data)
            return ["id": createResult.id, "affected_rows": AnyCodable(createResult.affectedRows)]
        }
        
        let existing: [String: AnyCodable]? = try await QueryBuilder(client: client, tableName: tableName)
            .eq(onConflict, conflictValue)
            .first()
        
        if existing != nil {
            var updateData = data
            updateData.removeValue(forKey: onConflict)
            if !updateData.isEmpty {
                let result = try await update(conflictValue, data: updateData)
                return ["affected_rows": AnyCodable(result.affectedRows), "success": AnyCodable(result.success)]
            }
            return ["message": AnyCodable("No changes"), "affected_rows": AnyCodable(0)]
        }
        let createResult = try await create(data)
        return ["id": createResult.id, "affected_rows": AnyCodable(createResult.affectedRows)]
    }
    
    /// Update a record by ID.
    public func update(_ id: AnyCodable, data: [String: AnyCodable]) async throws -> UpdateResponse {
        let url = URL(string: "\(client.apiUrl)/\(tableName)/\(id)")!
        return try await client.executeRequest(url: url, method: "PATCH", body: data)
    }
    
    /// Delete a record by ID.
    public func delete(_ id: AnyCodable) async throws -> DeleteResponse {
        let url = URL(string: "\(client.apiUrl)/\(tableName)/\(id)")!
        return try await client.executeRequest(url: url, method: "DELETE", body: nil)
    }
    
    // MARK: - Convenience Shortcuts
    
    public func eq(_ column: String, _ value: AnyCodable) -> QueryBuilder {
        return QueryBuilder(client: client, tableName: tableName).eq(column, value)
    }
    
    public func neq(_ column: String, _ value: AnyCodable) -> QueryBuilder {
        return QueryBuilder(client: client, tableName: tableName).neq(column, value)
    }
    
    public func gt(_ column: String, _ value: AnyCodable) -> QueryBuilder {
        return QueryBuilder(client: client, tableName: tableName).gt(column, value)
    }
    
    public func gte(_ column: String, _ value: AnyCodable) -> QueryBuilder {
        return QueryBuilder(client: client, tableName: tableName).gte(column, value)
    }
    
    public func lt(_ column: String, _ value: AnyCodable) -> QueryBuilder {
        return QueryBuilder(client: client, tableName: tableName).lt(column, value)
    }
    
    public func lte(_ column: String, _ value: AnyCodable) -> QueryBuilder {
        return QueryBuilder(client: client, tableName: tableName).lte(column, value)
    }
    
    public func orderBy(_ column: String, _ direction: SortDirection = .asc) -> QueryBuilder {
        return QueryBuilder(client: client, tableName: tableName).orderBy(column, direction)
    }
    
    public func count() async throws -> Int {
        return try await QueryBuilder(client: client, tableName: tableName).count()
    }
    
    public func paginate(page: Int = 1, perPage: Int = 20) async throws -> PaginatedResponse {
        return try await QueryBuilder(client: client, tableName: tableName).paginate(page: page, perPage: perPage)
    }
}
