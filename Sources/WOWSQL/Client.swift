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

/// Main client for interacting with WOWSQL API
public class WOWSQLClient {
    internal let baseUrl: String
    private let apiKey: String
    private let timeout: TimeInterval
    private let session: URLSession
    
    /// Initialize the client
    /// - Parameters:
    ///   - projectUrl: Your project URL (e.g., "https://your-project.wowsql.com")
    ///   - apiKey: Your API key
    ///   - timeout: Request timeout in seconds (default: 30)
    public init(projectUrl: String, apiKey: String, timeout: TimeInterval = 30) {
        var url = projectUrl.trimmingCharacters(in: .whitespaces)
        if url.hasSuffix("/") {
            url = String(url.dropLast())
        }
        self.baseUrl = url
        self.apiKey = apiKey
        self.timeout = timeout
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: config)
    }
    
    /// Get a table interface for operations
    /// - Parameter tableName: Name of the table
    /// - Returns: Table instance
    public func table(_ tableName: String) -> Table {
        return Table(client: self, tableName: tableName)
    }
    
    /// List all tables in the database
    /// - Returns: Array of table names
    public func listTables() async throws -> [String] {
        let url = URL(string: "\(baseUrl)/api/v2/tables")!
        let response: [String: AnyCodable] = try await executeRequest(url: url, method: "GET")
        
        if let tables = response["tables"]?.value as? [String] {
            return tables
        } else if let tablesArray = response["tables"]?.value as? [Any] {
            return tablesArray.compactMap { $0 as? String }
        }
        return []
    }
    
    /// Get table schema information
    /// - Parameter tableName: Name of the table
    /// - Returns: Table schema
    public func getTableSchema(_ tableName: String) async throws -> TableSchema {
        let url = URL(string: "\(baseUrl)/api/v2/tables/\(tableName)/schema")!
        return try await executeRequest(url: url, method: "GET")
    }
    
    /// Execute a raw SQL query (read-only)
    /// - Parameter sql: SQL query string
    /// - Returns: Query results
    public func query<T: Codable>(_ sql: String) async throws -> [T] {
        let url = URL(string: "\(baseUrl)/api/v2/query")!
        let body: [String: AnyCodable] = ["sql": AnyCodable(sql)]
        let response: [String: AnyCodable] = try await executeRequest(url: url, method: "POST", body: body)
        
        if let data = response["data"]?.value as? [[String: Any]] {
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            return try JSONDecoder().decode([T].self, from: jsonData)
        }
        return []
    }
    
    /// Check API health
    /// - Returns: Health status information
    public func health() async throws -> [String: AnyCodable] {
        let url = URL(string: "\(baseUrl)/api/v2/health")!
        return try await executeRequest(url: url, method: "GET")
    }
    
    /// Build a request with common headers
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
    
    /// Execute a request and handle response
    internal func executeRequest<T: Codable>(url: URL, method: String, body: [String: AnyCodable]? = nil) async throws -> T {
        let request = try buildRequest(url: url, method: method, body: body)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkException("Invalid response type")
            }
            
            if !(200...299).contains(httpResponse.statusCode) {
                try handleError(statusCode: httpResponse.statusCode, data: data)
            }
            
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as WOWSQLException {
            throw error
        } catch {
            throw NetworkException("Network error: \(error.localizedDescription)", underlyingError: error)
        }
    }
    
    /// Handle HTTP errors
    private func handleError(statusCode: Int, data: Data) throws -> Never {
        let errorResponse = try? JSONDecoder().decode([String: AnyCodable].self, from: data)
        
        let message = errorResponse?["error"]?.value as? String
            ?? errorResponse?["message"]?.value as? String
            ?? errorResponse?["detail"]?.value as? String
            ?? "Request failed with status \(statusCode)"
        
        let errorDict = errorResponse?.mapValues { $0.value } as? [String: Any]
        
        switch statusCode {
        case 401, 403:
            throw AuthenticationException(message, statusCode: statusCode, errorResponse: errorDict)
        case 404:
            throw NotFoundException(message, errorResponse: errorDict)
        case 429:
            throw RateLimitException(message, errorResponse: errorDict)
        default:
            throw WOWSQLException(message, statusCode: statusCode, errorResponse: errorDict)
        }
    }
}

/// Represents a database table with fluent API for operations
public class Table {
    private let client: WOWSQLClient
    private let tableName: String
    
    internal init(client: WOWSQLClient, tableName: String) {
        self.client = client
        self.tableName = tableName
    }
    
    /// Start a select query
    /// - Parameter columns: Columns to select (use "*" for all)
    /// - Returns: QueryBuilder instance
    public func select(_ columns: String...) -> QueryBuilder {
        return QueryBuilder(client: client, tableName: tableName).select(columns)
    }
    
    /// Start a select query
    /// - Parameter columns: Columns to select
    /// - Returns: QueryBuilder instance
    public func select(_ columns: [String]) -> QueryBuilder {
        return QueryBuilder(client: client, tableName: tableName).select(columns)
    }
    
    /// Get all records (shorthand for select("*"))
    /// - Returns: QueryBuilder instance
    public func get() -> QueryBuilder {
        return QueryBuilder(client: client, tableName: tableName).select(["*"])
    }
    
    /// Get a single record by ID
    /// - Parameter id: Record ID
    /// - Returns: Record data
    public func getById(_ id: AnyCodable) async throws -> [String: AnyCodable] {
        let url = URL(string: "\(client.baseUrl)/api/v2/\(tableName)/\(id)")!
        return try await client.executeRequest(url: url, method: "GET", body: nil)
    }
    
    /// Create a new record
    /// - Parameter data: Data to insert
    /// - Returns: Create response
    public func create(_ data: [String: AnyCodable]) async throws -> CreateResponse {
        return try await QueryBuilder(client: client, tableName: tableName).create(data)
    }
    
    /// Insert a new record (alias for create)
    /// - Parameter data: Data to insert
    /// - Returns: Create response
    public func insert(_ data: [String: AnyCodable]) async throws -> CreateResponse {
        return try await create(data)
    }
    
    /// Update a record by ID
    /// - Parameters:
    ///   - id: Record ID
    ///   - data: Data to update
    /// - Returns: Update response
    public func update(_ id: AnyCodable, data: [String: AnyCodable]) async throws -> UpdateResponse {
        let url = URL(string: "\(client.baseUrl)/api/v2/\(tableName)/\(id)")!
        return try await client.executeRequest(url: url, method: "PATCH", body: data)
    }
    
    /// Update a record by ID (alias)
    public func updateById(_ id: AnyCodable, data: [String: AnyCodable]) async throws -> UpdateResponse {
        return try await update(id, data: data)
    }
    
    /// Delete a record by ID
    /// - Parameter id: Record ID
    /// - Returns: Delete response
    public func delete(_ id: AnyCodable) async throws -> DeleteResponse {
        let url = URL(string: "\(client.baseUrl)/api/v2/\(tableName)/\(id)")!
        return try await client.executeRequest(url: url, method: "DELETE", body: nil)
    }
    
    /// Delete a record by ID (alias)
    public func deleteById(_ id: AnyCodable) async throws -> DeleteResponse {
        return try await delete(id)
    }
    
    /// Start a query with filters
    /// - Returns: QueryBuilder instance
    public func `where`() -> QueryBuilder {
        return QueryBuilder(client: client, tableName: tableName)
    }
}

