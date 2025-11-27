import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Column definition for table creation
public struct ColumnDefinition: Codable {
    public let name: String
    public let type: String
    public let autoIncrement: Bool?
    public let unique: Bool?
    public let notNull: Bool?
    public let defaultValue: String?
    
    enum CodingKeys: String, CodingKey {
        case name
        case type
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

/// Request for creating a table
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

/// Request for altering a table
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

/// Permission error for schema operations
public struct PermissionError: Error, LocalizedError {
    public let message: String
    
    public var errorDescription: String? {
        return message
    }
    
    public init(_ message: String) {
        self.message = message
    }
}

/// Schema management client for WOWSQL.
///
/// ⚠️ IMPORTANT: Requires SERVICE ROLE key, not anonymous key!
///
/// Example:
/// ```swift
/// let schema = WOWSQLSchema(
///     projectURL: "https://myproject.wowsql.com",
///     serviceKey: "service_xyz..."  // NOT anon key!
/// )
///
/// // Create table
/// try await schema.createTable(CreateTableRequest(
///     tableName: "users",
///     columns: [
///         ColumnDefinition(name: "id", type: "INT", autoIncrement: true),
///         ColumnDefinition(name: "email", type: "VARCHAR(255)", unique: true, notNull: true)
///     ],
///     primaryKey: "id"
/// ))
/// ```
public class WOWSQLSchema {
    private let baseURL: String
    private let serviceKey: String
    private let session: URLSession
    
    /// Initialize schema management client.
    ///
    /// ⚠️ IMPORTANT: Requires SERVICE ROLE key, not anonymous key!
    ///
    /// - Parameters:
    ///   - projectURL: Project URL (e.g., "https://myproject.wowsql.com")
    ///   - serviceKey: SERVICE ROLE key (not anonymous key!)
    public init(projectURL: String, serviceKey: String) {
        self.baseURL = projectURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.serviceKey = serviceKey
        self.session = URLSession.shared
    }
    
    /// Create a new table.
    ///
    /// - Parameter request: Table creation request
    /// - Returns: Schema operation response
    /// - Throws: `PermissionError` if using anonymous key instead of service key
    /// - Throws: `WOWSQLException` if table creation fails
    public func createTable(_ request: CreateTableRequest) async throws -> SchemaResponse {
        let url = URL(string: "\(baseURL)/api/v2/schema/tables")!
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(serviceKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)
        
        let (data, response) = try await session.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WOWSQLException("Invalid response")
        }
        
        if httpResponse.statusCode == 403 {
            throw PermissionError(
                "Schema operations require a SERVICE ROLE key. " +
                "You are using an anonymous key which cannot modify database schema. " +
                "Please use your service role key instead."
            )
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw WOWSQLException("Failed to create table: \(errorMessage)")
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(SchemaResponse.self, from: data)
    }
    
    /// Alter an existing table.
    ///
    /// - Parameter request: Table alteration request
    /// - Returns: Schema operation response
    /// - Throws: `PermissionError` if using anonymous key
    /// - Throws: `WOWSQLException` if alteration fails
    public func alterTable(_ request: AlterTableRequest) async throws -> SchemaResponse {
        let url = URL(string: "\(baseURL)/api/v2/schema/tables/\(request.tableName)")!
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "PATCH"
        urlRequest.setValue("Bearer \(serviceKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)
        
        let (data, response) = try await session.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WOWSQLException("Invalid response")
        }
        
        if httpResponse.statusCode == 403 {
            throw PermissionError("Schema operations require a SERVICE ROLE key.")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw WOWSQLException("Failed to alter table: \(errorMessage)")
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(SchemaResponse.self, from: data)
    }
    
    /// Drop a table.
    ///
    /// ⚠️ WARNING: This operation cannot be undone!
    ///
    /// - Parameters:
    ///   - tableName: Name of the table to drop
    ///   - cascade: Whether to drop with CASCADE
    /// - Returns: Schema operation response
    /// - Throws: `PermissionError` if using anonymous key
    /// - Throws: `WOWSQLException` if drop fails
    public func dropTable(_ tableName: String, cascade: Bool = false) async throws -> SchemaResponse {
        let url = URL(string: "\(baseURL)/api/v2/schema/tables/\(tableName)?cascade=\(cascade)")!
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "DELETE"
        urlRequest.setValue("Bearer \(serviceKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WOWSQLException("Invalid response")
        }
        
        if httpResponse.statusCode == 403 {
            throw PermissionError("Schema operations require a SERVICE ROLE key.")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw WOWSQLException("Failed to drop table: \(errorMessage)")
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(SchemaResponse.self, from: data)
    }
    
    /// Execute raw SQL for schema operations.
    ///
    /// ⚠️ Only schema operations allowed (CREATE TABLE, ALTER TABLE, etc.)
    ///
    /// - Parameter sql: SQL statement to execute
    /// - Returns: Schema operation response
    /// - Throws: `PermissionError` if using anonymous key
    /// - Throws: `WOWSQLException` if execution fails
    public func executeSQL(_ sql: String) async throws -> SchemaResponse {
        let url = URL(string: "\(baseURL)/api/v2/schema/execute")!
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(serviceKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = ["sql": sql]
        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(payload)
        
        let (data, response) = try await session.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WOWSQLException("Invalid response")
        }
        
        if httpResponse.statusCode == 403 {
            throw PermissionError("Schema operations require a SERVICE ROLE key.")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw WOWSQLException("Failed to execute SQL: \(errorMessage)")
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(SchemaResponse.self, from: data)
    }
}
