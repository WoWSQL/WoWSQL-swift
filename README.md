# 🚀 WOWSQL Swift SDK

Official Swift SDK for [WOWSQL](https://wowsql.com) - MySQL Backend-as-a-Service with S3 Storage.

[![Swift Package Manager](https://img.shields.io/badge/SPM-supported-DE5C43.svg?logo=swift)](https://swift.org/package-manager/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## ✨ Features

### Database Features
- 🗄️ Full CRUD operations (Create, Read, Update, Delete)
- 🔍 Advanced filtering (eq, neq, gt, gte, lt, lte, like, isNull)
- 📄 Pagination (limit, offset)
- 📊 Sorting (orderBy)
- 🎯 Fluent query builder API
- 🔒 Type-safe queries with Codable
- ⚡ async/await support
- 📝 Raw SQL queries
- 📋 Table schema introspection

### Storage Features
- 📦 S3-compatible storage for file management
- ⬆️ File upload with automatic quota validation
- ⬇️ File download (presigned URLs)
- 📂 File listing with metadata
- 🗑️ File deletion (single and batch)
- 📊 Storage quota management

## 📦 Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/wowsql/wowsql-swift.git", from: "1.0.0")
]
```

Or add it via Xcode:
1. File → Add Packages...
2. Enter: `https://github.com/wowsql/wowsql-swift.git`
3. Select version: `1.0.0`

## 🚀 Quick Start

### Database Operations

```swift
import WOWSQL

let client = WOWSQLClient(
    projectUrl: "https://your-project.wowsql.com",
    apiKey: "your-api-key"
)

// Query data
let response = try await client.table("users")
    .select("id", "name", "email")
    .eq("status", AnyCodable("active"))
    .limit(10)
    .execute() as QueryResponse<[String: AnyCodable]>

print("Found \(response.count) users")
for user in response.data {
    print("\(user["name"]?.value ?? "Unknown") - \(user["email"]?.value ?? "")")
}
```

### Storage Operations

```swift
let storage = WOWSQLStorage(
    projectUrl: "https://your-project.wowsql.com",
    apiKey: "your-api-key"
)

// Upload file
let fileData = try Data(contentsOf: URL(fileURLWithPath: "document.pdf"))
let result = try await storage.uploadBytes(
    fileData,
    key: "uploads/document.pdf",
    contentType: "application/pdf"
)
print("Uploaded: \(result.url)")

// Check quota
let quota = try await storage.getQuota()
print("Storage used: \(quota.storageUsedGb)GB / \(quota.storageQuotaGb)GB")
```

## 🔧 Schema Management

Programmatically manage your database schema with the `WOWSQLSchema` client.

> **⚠️ IMPORTANT**: Schema operations require a **Service Role Key** (`service_*`). Anonymous keys will return a 403 Forbidden error.

### Quick Start

```swift
import WOWSQL

// Initialize schema client with SERVICE ROLE KEY
let schema = WOWSQLSchema(
    projectURL: "https://your-project.wowsql.com",
    serviceKey: "service_xyz789..."  // ⚠️ Backend only! Never expose!
)
```

### Create Table

```swift
// Create a new table
try await schema.createTable(CreateTableRequest(
    tableName: "products",
    columns: [
        ColumnDefinition(name: "id", type: "INT", autoIncrement: true),
        ColumnDefinition(name: "name", type: "VARCHAR(255)", notNull: true),
        ColumnDefinition(name: "price", type: "DECIMAL(10,2)", notNull: true),
        ColumnDefinition(name: "category", type: "VARCHAR(100)"),
        ColumnDefinition(name: "created_at", type: "TIMESTAMP", defaultValue: "CURRENT_TIMESTAMP")
    ],
    primaryKey: "id",
    indexes: [
        IndexDefinition(name: "idx_category", columns: ["category"]),
        IndexDefinition(name: "idx_price", columns: ["price"])
    ]
))

print("Table created successfully!")
```

### Alter Table

```swift
// Add a new column
try await schema.alterTable(AlterTableRequest(
    tableName: "products",
    addColumns: [
        ColumnDefinition(name: "stock_quantity", type: "INT", defaultValue: "0")
    ]
))

// Modify an existing column
try await schema.alterTable(AlterTableRequest(
    tableName: "products",
    modifyColumns: [
        ColumnDefinition(name: "price", type: "DECIMAL(12,2)")  // Increase precision
    ]
))

// Drop a column
try await schema.alterTable(AlterTableRequest(
    tableName: "products",
    dropColumns: ["category"]
))

// Rename a column
try await schema.alterTable(AlterTableRequest(
    tableName: "products",
    renameColumns: [
        RenameColumn(oldName: "name", newName: "product_name")
    ]
))
```

### Drop Table

```swift
// Drop a table
try await schema.dropTable("old_table")

// Drop with CASCADE (removes dependent objects)
try await schema.dropTable("products", cascade: true)
```

### Execute Raw SQL

```swift
// Execute custom schema SQL
try await schema.executeSQL("""
    CREATE INDEX idx_product_name 
    ON products(product_name);
""")

// Add a foreign key constraint
try await schema.executeSQL("""
    ALTER TABLE orders 
    ADD CONSTRAINT fk_product 
    FOREIGN KEY (product_id) 
    REFERENCES products(id);
""")
```

### Security & Best Practices

#### ✅ DO:
- Use service role keys **only in backend/server code** (never in iOS/macOS apps)
- Store service keys in environment variables or secure configuration
- Use anonymous keys for client-side data operations
- Test schema changes in development first

#### ❌ DON'T:
- Never expose service role keys in iOS/macOS app code
- Never commit service keys to version control
- Don't use anonymous keys for schema operations (will fail)

### Example: Backend Migration Script

```swift
import WOWSQL
import Foundation

func runMigration() async throws {
    let schema = WOWSQLSchema(
        projectURL: ProcessInfo.processInfo.environment["WOWSQL_PROJECT_URL"]!,
        serviceKey: ProcessInfo.processInfo.environment["WOWSQL_SERVICE_KEY"]!  // From env var
    )
    
    // Create users table
    try await schema.createTable(CreateTableRequest(
        tableName: "users",
        columns: [
            ColumnDefinition(name: "id", type: "INT", autoIncrement: true),
            ColumnDefinition(name: "email", type: "VARCHAR(255)", unique: true, notNull: true),
            ColumnDefinition(name: "name", type: "VARCHAR(255)", notNull: true),
            ColumnDefinition(name: "created_at", type: "TIMESTAMP", defaultValue: "CURRENT_TIMESTAMP")
        ],
        primaryKey: "id",
        indexes: [
            IndexDefinition(name: "idx_email", columns: ["email"])
        ]
    ))
    
    print("Migration completed!")
}

// Run migration
Task {
    try await runMigration()
}
```

### Error Handling

```swift
import WOWSQL

do {
    let schema = WOWSQLSchema(
        projectURL: "https://your-project.wowsql.com",
        serviceKey: "service_xyz..."
    )
    
    try await schema.createTable(CreateTableRequest(
        tableName: "test",
        columns: [ColumnDefinition(name: "id", type: "INT")]
    ))
} catch let error as PermissionError {
    print("Permission denied: \(error.message)")
    print("Make sure you're using a SERVICE ROLE KEY, not an anonymous key!")
} catch {
    print("Error: \(error)")
}
```

---

## 📚 Documentation

Full documentation available at: https://wowsql.com/docs/swift

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

---

Made with ❤️ by the WOWSQL Team

