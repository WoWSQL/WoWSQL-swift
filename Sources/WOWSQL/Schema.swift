//
//  Schema.swift
//  WOWSQL
//
//  Created by WOWSQL Team
//  Copyright © 2024 WOWSQL. All rights reserved.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Schema management client for WOWSQL (PostgreSQL).
///
/// Requires a SERVICE ROLE key (`wowsql_service_...`), not an anonymous key.
///
/// Example:
/// ```swift
/// let schema = WOWSQLSchema(
///     projectUrl: "myproject",
///     serviceKey: "wowsql_service_..."
/// )
///
/// try await schema.createTable("users", columns: [
///     ["name": "id", "type": "SERIAL", "auto_increment": true],
///     ["name": "email", "type": "VARCHAR(255)", "unique": true, "nullable": false],
/// ], primaryKey: "id", indexes: ["email"])
/// ```
public class WOWSQLSchema {
    private let baseUrl: String
    private let serviceKey: String
    private let timeout: TimeInterval
    private let session: URLSession
    
    /// Initialize schema management client.
    ///
    /// - Parameters:
    ///   - projectUrl: Project subdomain or full URL
    ///   - serviceKey: Service role key (`wowsql_service_...`)
    ///   - baseDomain: Base domain (default: `"wowsql.com"`)
    ///   - secure: Use HTTPS (default: `true`)
    ///   - timeout: Request timeout in seconds (default: 30)
    ///   - verifySsl: Verify SSL (default: `true`)
    public init(
        projectUrl: String,
        serviceKey: String,
        baseDomain: String = "wowsql.com",
        secure: Bool = true,
        timeout: TimeInterval = 30,
        verifySsl: Bool = true
    ) {
        let url = projectUrl.trimmingCharacters(in: .whitespaces)
        
        if url.hasPrefix("http://") || url.hasPrefix("https://") {
            var base = url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if base.contains("/api") {
                base = base.components(separatedBy: "/api").first ?? base
            }
            self.baseUrl = base
        } else {
            let proto = secure ? "https" : "http"
            if url.contains(".\(baseDomain)") || url.hasSuffix(baseDomain) {
                self.baseUrl = "\(proto)://\(url)"
            } else {
                self.baseUrl = "\(proto)://\(url).\(baseDomain)"
            }
        }
        
        self.serviceKey = serviceKey
        self.timeout = timeout
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: config)
    }
    
    /// Backward-compatible initializer.
    public convenience init(projectURL: String, serviceKey: String) {
        self.init(projectUrl: projectURL, serviceKey: serviceKey)
    }
    
    // MARK: - Table Operations
    
    /// Create a new table.
    ///
    /// Supported PostgreSQL types: SERIAL, BIGSERIAL, VARCHAR(n), TEXT, INT,
    /// BIGINT, BOOLEAN, NUMERIC(p,s), REAL, DOUBLE PRECISION, TIMESTAMPTZ,
    /// DATE, TIME, UUID, JSONB, TEXT[], INT[], BYTEA, etc.
    public func createTable(
        _ tableName: String,
        columns: [[String: Any]],
        primaryKey: String? = nil,
        indexes: [String]? = nil
    ) async throws -> [String: Any] {
        let body: [String: Any] = [
            "table_name": tableName,
            "columns": columns,
            "primary_key": primaryKey as Any,
            "indexes": indexes as Any
        ]
        return try await request("POST", path: "/api/v2/schema/tables", jsonBody: body)
    }
    
    /// Create a table using CreateTableRequest (backward compatibility).
    public func createTable(_ request: CreateTableRequest) async throws -> SchemaResponse {
        let url = buildUrl("/api/v2/schema/tables")
        var urlRequest = try buildRequest(url: url, method: "POST")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        
        let (data, response) = try await session.data(for: urlRequest)
        try checkResponse(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500, data: data)
        return try JSONDecoder().decode(SchemaResponse.self, from: data)
    }
    
    /// Alter an existing table.
    ///
    /// Operations: `add_column`, `drop_column`, `modify_column`, `rename_column`.
    public func alterTable(
        _ tableName: String,
        operation: String,
        columnName: String? = nil,
        columnType: String? = nil,
        newColumnName: String? = nil,
        nullable: Bool = true,
        default defaultValue: String? = nil
    ) async throws -> [String: Any] {
        var body: [String: Any] = [
            "table_name": tableName,
            "operation": operation
        ]
        if let columnName = columnName { body["column_name"] = columnName }
        if let columnType = columnType { body["column_type"] = columnType }
        if let newColumnName = newColumnName { body["new_column_name"] = newColumnName }
        body["nullable"] = nullable
        if let defaultValue = defaultValue { body["default"] = defaultValue }
        
        return try await request("PATCH", path: "/api/v2/schema/tables/\(tableName)", jsonBody: body)
    }
    
    /// Alter a table using AlterTableRequest (backward compatibility).
    public func alterTable(_ request: AlterTableRequest) async throws -> SchemaResponse {
        let url = buildUrl("/api/v2/schema/tables/\(request.tableName)")
        var urlRequest = try buildRequest(url: url, method: "PATCH")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        
        let (data, response) = try await session.data(for: urlRequest)
        try checkResponse(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500, data: data)
        return try JSONDecoder().decode(SchemaResponse.self, from: data)
    }
    
    /// Drop a table. WARNING: This cannot be undone!
    public func dropTable(_ tableName: String, cascade: Bool = false) async throws -> [String: Any] {
        return try await request(
            "DELETE",
            path: "/api/v2/schema/tables/\(tableName)?cascade=\(cascade)"
        )
    }
    
    /// Execute raw DDL SQL (CREATE TABLE, ALTER TABLE, etc.).
    public func executeSql(_ sql: String) async throws -> [String: Any] {
        return try await request("POST", path: "/api/v2/schema/execute", jsonBody: ["sql": sql])
    }
    
    /// Backward-compatible alias.
    public func executeSQL(_ sql: String) async throws -> SchemaResponse {
        let url = buildUrl("/api/v2/schema/execute")
        var urlRequest = try buildRequest(url: url, method: "POST")
        urlRequest.httpBody = try JSONEncoder().encode(["sql": sql])
        
        let (data, response) = try await session.data(for: urlRequest)
        try checkResponse(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500, data: data)
        return try JSONDecoder().decode(SchemaResponse.self, from: data)
    }
    
    // MARK: - Convenience Methods
    
    /// Add a column to an existing table.
    public func addColumn(
        _ tableName: String,
        columnName: String,
        columnType: String,
        nullable: Bool = true,
        default defaultValue: String? = nil
    ) async throws -> [String: Any] {
        return try await alterTable(
            tableName,
            operation: "add_column",
            columnName: columnName,
            columnType: columnType,
            nullable: nullable,
            default: defaultValue
        )
    }
    
    /// Drop a column from a table.
    public func dropColumn(_ tableName: String, columnName: String) async throws -> [String: Any] {
        return try await alterTable(tableName, operation: "drop_column", columnName: columnName)
    }
    
    /// Rename a column.
    public func renameColumn(_ tableName: String, oldName: String, newName: String) async throws -> [String: Any] {
        return try await alterTable(
            tableName,
            operation: "rename_column",
            columnName: oldName,
            newColumnName: newName
        )
    }
    
    /// Change column type, nullability, or default value.
    public func modifyColumn(
        _ tableName: String,
        columnName: String,
        columnType: String? = nil,
        nullable: Bool? = nil,
        default defaultValue: String? = nil
    ) async throws -> [String: Any] {
        var body: [String: Any] = [
            "table_name": tableName,
            "operation": "modify_column",
            "column_name": columnName
        ]
        if let columnType = columnType { body["column_type"] = columnType }
        if let nullable = nullable { body["nullable"] = nullable }
        if let defaultValue = defaultValue { body["default"] = defaultValue }
        
        return try await request("PATCH", path: "/api/v2/schema/tables/\(tableName)", jsonBody: body)
    }
    
    /// Create an index.
    ///
    /// - Parameters:
    ///   - table: Table to index
    ///   - columns: Column(s) to index
    ///   - unique: Create a UNIQUE index
    ///   - name: Custom index name
    ///   - using: Index method (btree, hash, gin, gist)
    public func createIndex(
        table: String,
        columns: [String],
        unique: Bool = false,
        name: String? = nil,
        using: String? = nil
    ) async throws -> [String: Any] {
        let idxName = name ?? "idx_\(table)_\(columns.joined(separator: "_"))"
        let uniqueKw = unique ? "UNIQUE " : ""
        let usingKw = using != nil ? " USING \(using!)" : ""
        let colList = columns.map { "\"\($0)\"" }.joined(separator: ", ")
        let sql = "CREATE \(uniqueKw)INDEX IF NOT EXISTS \"\(idxName)\" ON \"\(table)\"\(usingKw) (\(colList))"
        return try await executeSql(sql)
    }
    
    /// List all tables.
    public func listTables() async throws -> [String] {
        let result = try await request("GET", path: "/api/v2/tables")
        if let tables = result["tables"] as? [String] {
            return tables
        }
        return []
    }
    
    /// Get column-level schema information for a table.
    public func getTableSchema(_ tableName: String) async throws -> [String: Any] {
        return try await request("GET", path: "/api/v2/tables/\(tableName)/schema")
    }
    
    /// Close the HTTP session.
    public func close() {
        session.invalidateAndCancel()
    }
    
    // MARK: - Private Helpers
    
    private func buildUrl(_ path: String) -> URL {
        return URL(string: "\(baseUrl)\(path)")!
    }
    
    private func buildRequest(url: URL, method: String) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(serviceKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
    
    private func request(
        _ method: String,
        path: String,
        jsonBody: [String: Any]? = nil
    ) async throws -> [String: Any] {
        let url = buildUrl(path)
        var urlRequest = try buildRequest(url: url, method: method)
        
        if let jsonBody = jsonBody {
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        }
        
        let (data, response) = try await session.data(for: urlRequest)
        
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
        try checkResponse(statusCode: statusCode, data: data)
        
        if data.isEmpty { return [:] }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
    
    private func checkResponse(statusCode: Int, data: Data) throws {
        if statusCode == 403 {
            throw SchemaPermissionError(
                "Schema operations require a SERVICE ROLE key. "
                + "You are using an anonymous key which cannot modify database schema."
            )
        }
        
        if !(200...299).contains(statusCode) {
            let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = errorDict?["detail"] as? String
                ?? errorDict?["error"] as? String
                ?? errorDict?["message"] as? String
                ?? "Request failed with status \(statusCode)"
            throw WOWSQLError(message, statusCode: statusCode, response: errorDict)
        }
    }
}

// MARK: - Schema Request/Response Models

/// Column definition for table creation
public struct ColumnDefinition: Codable {
    public let name: String
    public let type: String
    public let autoIncrement: Bool?
    public let unique: Bool?
    public let notNull: Bool?
    public let defaultValue: String?
    
    enum CodingKeys: String, CodingKey {
        case name, type
        case autoIncrement = "auto_increment"
        case unique
        case notNull = "not_null"
        case defaultValue = "default"
    }
    
    public init(
        name: String,
        type: String,
        autoIncrement: Bool? = nil,
        unique: Bool? = nil,
        notNull: Bool? = nil,
        defaultValue: String? = nil
    ) {
        self.name = name
        self.type = type
        self.autoIncrement = autoIncrement
        self.unique = unique
        self.notNull = notNull
        self.defaultValue = defaultValue
    }
}

/// Index definition for table creation
public struct IndexDefinition: Codable {
    public let name: String
    public let columns: [String]
    
    public init(name: String, columns: [String]) {
        self.name = name
        self.columns = columns
    }
}

/// Request for creating a table (legacy struct)
public struct CreateTableRequest: Codable {
    public let tableName: String
    public let columns: [ColumnDefinition]
    public let primaryKey: String?
    public let indexes: [IndexDefinition]?
    
    enum CodingKeys: String, CodingKey {
        case tableName = "table_name"
        case columns
        case primaryKey = "primary_key"
        case indexes
    }
    
    public init(
        tableName: String,
        columns: [ColumnDefinition],
        primaryKey: String? = nil,
        indexes: [IndexDefinition]? = nil
    ) {
        self.tableName = tableName
        self.columns = columns
        self.primaryKey = primaryKey
        self.indexes = indexes
    }
}

/// Request for altering a table (legacy struct)
public struct AlterTableRequest: Codable {
    public let tableName: String
    public let addColumns: [ColumnDefinition]?
    public let modifyColumns: [ColumnDefinition]?
    public let dropColumns: [String]?
    public let renameColumns: [RenameColumn]?
    
    enum CodingKeys: String, CodingKey {
        case tableName = "table_name"
        case addColumns = "add_columns"
        case modifyColumns = "modify_columns"
        case dropColumns = "drop_columns"
        case renameColumns = "rename_columns"
    }
    
    public init(
        tableName: String,
        addColumns: [ColumnDefinition]? = nil,
        modifyColumns: [ColumnDefinition]? = nil,
        dropColumns: [String]? = nil,
        renameColumns: [RenameColumn]? = nil
    ) {
        self.tableName = tableName
        self.addColumns = addColumns
        self.modifyColumns = modifyColumns
        self.dropColumns = dropColumns
        self.renameColumns = renameColumns
    }
}

/// Column rename specification
public struct RenameColumn: Codable {
    public let oldName: String
    public let newName: String
    
    enum CodingKeys: String, CodingKey {
        case oldName = "old_name"
        case newName = "new_name"
    }
    
    public init(oldName: String, newName: String) {
        self.oldName = oldName
        self.newName = newName
    }
}

/// Schema operation response
public struct SchemaResponse: Codable {
    public let success: Bool?
    public let message: String?
    public let table: String?
    public let operation: String?
}

/// Permission error for schema operations (legacy, use SchemaPermissionError instead)
public struct PermissionError: Error, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}
