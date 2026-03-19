# WowSQL Swift SDK

Official Swift package for [WowSQL](https://wowsql.com) — PostgreSQL backend-as-a-service with project auth, object storage, and schema management.

**Product module:** `WOWSQL` · **Swift:** 5.9+ · **Platforms:** iOS 13+, macOS 10.15+, watchOS 6+, tvOS 13+

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---

## Table of contents

1. [Installation](#installation)
2. [Quick start](#quick-start)
3. [Concepts & API keys](#concepts--api-keys)
4. [Database: `WOWSQLClient`](#database-wowsqlclient)
5. [Table & `QueryBuilder`](#table--querybuilder)
6. [Authentication: `ProjectAuthClient`](#authentication-projectauthclient)
7. [Storage: `WOWSQLStorage`](#storage-wowsqlstorage)
8. [Schema: `WOWSQLSchema`](#schema-wowsqlschema)
9. [Models](#models)
10. [Errors](#errors)
11. [Examples](#examples)
12. [Links](#links)

---

## Installation

### Swift Package Manager

`Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/wowsql/wowsql-swift.git", from: "1.0.0")
],
targets: [
    .target(name: "MyApp", dependencies: ["WOWSQL"])
]
```

Xcode: **File → Add Package Dependencies…** and enter the repository URL.

---

## Quick start

```swift
import WOWSQL

let client = WOWSQLClient(
    projectUrl: "https://your-project.wowsql.com",
    apiKey: ProcessInfo.processInfo.environment["WOWSQL_SERVICE_KEY"]!,
    baseDomain: "wowsql.com",
    secure: true,
    timeout: 30,
    verifySsl: true
)

let response = try await client.table("posts")
    .select("id", "title")
    .eq("published", AnyCodable(true))
    .limit(10)
    .execute() as QueryResponse<[String: AnyCodable]>

print("count:", response.count)
```

---

## Concepts & API keys

| Key | Prefix | Use |
|-----|--------|-----|
| Anonymous | `wowsql_anon_…` | Client apps — auth + limited data |
| Service role | `wowsql_service_…` | **Server only** — privileged DB, storage, schema |

- Use **service role** for `WOWSQLSchema` and trusted backends.
- JWTs from `ProjectAuthClient` are for **your** session handling; data/storage clients typically use **API keys** from the dashboard (see platform docs).

---

## Database: `WOWSQLClient`

```swift
public init(
    projectUrl: String,
    apiKey: String,
    baseDomain: String = "wowsql.com",
    secure: Bool = true,
    timeout: TimeInterval = 30,
    verifySsl: Bool = true
)
```

| Method | Description |
|--------|-------------|
| `table(_ name: String) -> Table` | Entry point for CRUD / queries. |
| `listTables() async throws -> [String]` | |
| `getTableSchema(_ name: String) async throws -> TableSchema` | |
| `close()` | Release resources. |

---

## Table & `QueryBuilder`

### `Table`

| Method | Returns |
|--------|---------|
| `select(_ columns: String...) -> QueryBuilder` | Also `select([String])`. |
| `filter(_ column:, _ op:, _ value:, _ logicalOp:) -> QueryBuilder` | |
| `get<T: Codable>() async throws -> QueryResponse<T>` | |
| `getById(_ id: AnyCodable) async throws -> [String: AnyCodable]` | |
| `create` / `insert` | `CreateResponse` |
| `bulkInsert` | `[CreateResponse]` |
| `upsert(_:onConflict:)` | `[String: AnyCodable]` |
| `update(_:data:)` | `UpdateResponse` |
| `delete(_:)` | `DeleteResponse` |
| `eq`, `neq`, `gt`, `gte`, `lt`, `lte` | `QueryBuilder` |
| `orderBy(_:_)` | `QueryBuilder` |
| `count() async throws -> Int` | |
| `paginate(page:perPage:) async throws -> PaginatedResponse` | |

### `QueryBuilder`

Chain: `select`, `filter`, `eq`, …, `like`, `isNull`, `isNotNull`, `inList`, `notIn`, `between`, `notBetween`, `orFilter`, `groupBy`, `having`, `orderBy`, `order`, `orderByMultiple`, `limit`, `offset`.

**Terminal:** `execute<T>()`, `get<T>()`, `first<T>()`, `single<T>()`, `count()`, `paginate`.

**Mutations:** `insert`, `create`, `update`, `delete` (see source for filter-based updates/deletes).

### `FilterOperator` / `SortDirection`

Enums mirroring the REST API (`eq`, `neq`, …, `asc`, `desc`).

---

## Authentication: `ProjectAuthClient`

```swift
public init(
    projectUrl: String,
    apiKey: String?,
    baseDomain: String = "wowsql.com",
    secure: Bool = true,
    timeout: TimeInterval = 30,
    verifySsl: Bool = true,
    tokenStorage: TokenStorage? = nil
)
```

### `TokenStorage` protocol

`getAccessToken`, `setAccessToken`, `getRefreshToken`, `setRefreshToken`.

`MemoryTokenStorage` is provided for demos.

### Methods (async / throws)

| Method | Purpose |
|--------|---------|
| `signUp`, `signIn` | Email/password. |
| `getUser(accessToken:)` | Load profile. |
| `getOAuthAuthorizationUrl`, `exchangeOAuthCallback` | OAuth. |
| `forgotPassword`, `resetPassword`, `changePassword` | Password flows. |
| `sendOtp`, `verifyOtp`, `sendMagicLink` | OTP / magic link. |
| `verifyEmail`, `resendVerification` | Email verification. |
| `logout`, `refreshToken` | Session lifecycle. |
| `updateUser` | Profile updates. |
| `getSession`, `setSession`, `clearSession` | Local session. |

---

## Storage: `WOWSQLStorage`

```swift
public init(
    projectUrl: String,
    apiKey: String,
    projectSlug: String? = nil,
    baseUrl: String? = nil,
    baseDomain: String = "wowsql.com",
    secure: Bool = true,
    timeout: TimeInterval = 60,
    verifySsl: Bool = true
)
```

| Method | Purpose |
|--------|---------|
| `createBucket`, `listBuckets`, `getBucket`, `updateBucket`, `deleteBucket` | Bucket CRUD. |
| `upload`, `uploadFromPath` | File upload. |
| `listFiles`, `download`, `downloadToFile`, `deleteFile` | Object operations. |
| `getPublicUrl` | Public URL helper. |
| `getStats`, `getQuota` | Usage. |
| `close()` | |

---

## Schema: `WOWSQLSchema`

**Requires service role key.**

| Method | Purpose |
|--------|---------|
| `createTable`, `alterTable`, `dropTable` | DDL. |
| `executeSql` | Raw SQL (where permitted). |
| `addColumn`, `dropColumn`, `renameColumn`, `modifyColumn` | Column ops. |
| `createIndex` | Indexes. |
| `listTables`, `getTableSchema` | Introspection. |

Typed helpers: `ColumnDefinition`, `CreateTableRequest`, `AlterTableRequest`, `SchemaResponse`, etc.

---

## Models

`QueryResponse`, `CreateResponse`, `UpdateResponse`, `DeleteResponse`, `TableSchema`, `ColumnInfo`, `PaginatedResponse`, `AuthUser`, `AuthSession`, `AuthResponse`, `StorageBucket`, `StorageFile`, `StorageQuota`, `FilterExpression`, `HavingFilter`, `OrderByItem`, `AnyCodable`, …

---

## Errors

Throwing APIs surface `Error` types from the package (see `Models.swift` / client files). Map HTTP failures to user-visible messages in your UI.

---

## Examples

### iOS: load rows in a view model

```swift
@MainActor
final class PostsVM: ObservableObject {
    @Published var items: [[String: AnyCodable]] = []

    func load() async {
        do {
            let client = WOWSQLClient(projectUrl: url, apiKey: key)
            let res = try await client.table("posts")
                .select("id", "title")
                .orderBy("created_at", .desc)
                .limit(50)
                .execute() as QueryResponse<[String: AnyCodable]>
            items = res.data
        } catch {
            print(error)
        }
    }
}
```

---

## Links

- [WowSQL Docs](https://wowsql.com/docs)
- [Dashboard](https://wowsql.com)

**License:** MIT
