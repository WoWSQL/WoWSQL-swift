//
//  Storage.swift
//  WOWSQL
//
//  Created by WOWSQL Team
//  Copyright © 2024 WOWSQL. All rights reserved.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// PostgreSQL-native storage client for WOWSQL.
///
/// Files are stored as BYTEA inside each project's `storage` schema.
///
/// Example:
/// ```swift
/// let storage = WOWSQLStorage(
///     projectUrl: "https://myproject.wowsql.com",
///     apiKey: "wowsql_anon_..."
/// )
/// let bucket = try await storage.createBucket("avatars", public: true)
/// let files = try await storage.listFiles(bucketName: "avatars")
/// ```
public class WOWSQLStorage {
    internal let baseUrl: String
    internal let projectSlug: String
    private let apiKey: String
    private let timeout: TimeInterval
    private let session: URLSession
    
    /// Initialize the storage client.
    ///
    /// - Parameters:
    ///   - projectUrl: Project subdomain or full URL
    ///   - apiKey: API key for authentication
    ///   - projectSlug: Explicit slug (used with `baseUrl`)
    ///   - baseUrl: Explicit base URL (used with `projectSlug`)
    ///   - baseDomain: Base domain (default: `"wowsql.com"`)
    ///   - secure: Use HTTPS (default: `true`)
    ///   - timeout: Request timeout in seconds (default: 60)
    ///   - verifySsl: Verify SSL (default: `true`)
    public init(
        projectUrl: String = "",
        apiKey: String = "",
        projectSlug: String? = nil,
        baseUrl: String? = nil,
        baseDomain: String = "wowsql.com",
        secure: Bool = true,
        timeout: TimeInterval = 60,
        verifySsl: Bool = true
    ) {
        if let slug = projectSlug, let base = baseUrl {
            self.baseUrl = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            self.projectSlug = slug
        } else {
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
            self.projectSlug = url
                .components(separatedBy: ".").first?
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "") ?? url
        }
        
        self.apiKey = apiKey
        self.timeout = timeout
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Buckets
    
    /// Create a new storage bucket.
    public func createBucket(
        _ name: String,
        public isPublic: Bool = false,
        fileSizeLimit: Int? = nil,
        allowedMimeTypes: [String]? = nil
    ) async throws -> StorageBucket {
        var body: [String: AnyCodable] = [
            "name": AnyCodable(name),
            "public": AnyCodable(isPublic)
        ]
        if let limit = fileSizeLimit { body["file_size_limit"] = AnyCodable(limit) }
        if let types = allowedMimeTypes { body["allowed_mime_types"] = AnyCodable(types) }
        
        let data = try await executeJsonRequest(
            path: "/api/v1/storage/projects/\(projectSlug)/buckets",
            method: "POST",
            body: body
        )
        return StorageBucket(data: data)
    }
    
    /// List all buckets in the project.
    public func listBuckets() async throws -> [StorageBucket] {
        let url = self.buildUrl("/api/v1/storage/projects/\(projectSlug)/buckets")
        let request = try buildRequest(url: url, method: "GET")
        let (data, response) = try await session.data(for: request)
        try checkResponse(response: response, data: data)
        
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return array.map { StorageBucket(data: $0) }
    }
    
    /// Get a specific bucket by name.
    public func getBucket(_ name: String) async throws -> StorageBucket {
        let data = try await executeJsonRequest(
            path: "/api/v1/storage/projects/\(projectSlug)/buckets/\(name)",
            method: "GET"
        )
        return StorageBucket(data: data)
    }
    
    /// Update bucket settings.
    public func updateBucket(_ name: String, settings: [String: Any]) async throws -> StorageBucket {
        let body = settings.mapValues { AnyCodable($0) }
        let data = try await executeJsonRequest(
            path: "/api/v1/storage/projects/\(projectSlug)/buckets/\(name)",
            method: "PATCH",
            body: body
        )
        return StorageBucket(data: data)
    }
    
    /// Delete a bucket and all its files.
    public func deleteBucket(_ name: String) async throws -> [String: Any] {
        return try await executeJsonRequest(
            path: "/api/v1/storage/projects/\(projectSlug)/buckets/\(name)",
            method: "DELETE"
        )
    }
    
    // MARK: - Files
    
    /// Upload file data to a bucket.
    public func upload(
        bucketName: String,
        fileData: Data,
        path filePath: String? = nil,
        fileName: String? = nil
    ) async throws -> StorageFile {
        let name = fileName ?? filePath?.components(separatedBy: "/").last ?? "file"
        var folder = ""
        if let filePath = filePath, filePath.contains("/") {
            folder = filePath.components(separatedBy: "/").dropLast().joined(separator: "/")
        }
        
        var urlString = "\(baseUrl)/api/v1/storage/projects/\(projectSlug)/buckets/\(bucketName)/files"
        if !folder.isEmpty {
            let encoded = folder.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? folder
            urlString += "?folder=\(encoded)"
        }
        
        let url = URL(string: urlString)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await session.data(for: request)
        try checkResponse(response: response, data: data)
        
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StorageError("Invalid upload response")
        }
        return StorageFile(data: dict)
    }
    
    /// Upload a file from a local filesystem path.
    public func uploadFromPath(
        filePath: String,
        bucketName: String = "default",
        path remotePath: String? = nil
    ) async throws -> StorageFile {
        let fileUrl = URL(fileURLWithPath: filePath)
        guard let fileData = try? Data(contentsOf: fileUrl) else {
            throw StorageError("File not found: \(filePath)")
        }
        let fileName = fileUrl.lastPathComponent
        return try await upload(
            bucketName: bucketName,
            fileData: fileData,
            path: remotePath ?? fileName,
            fileName: fileName
        )
    }
    
    /// List files in a bucket.
    public func listFiles(
        bucketName: String,
        prefix: String? = nil,
        limit: Int = 100,
        offset: Int = 0
    ) async throws -> [StorageFile] {
        var urlString = "\(baseUrl)/api/v1/storage/projects/\(projectSlug)/buckets/\(bucketName)/files?limit=\(limit)&offset=\(offset)"
        if let prefix = prefix {
            let encoded = prefix.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? prefix
            urlString += "&prefix=\(encoded)"
        }
        
        let url = URL(string: urlString)!
        let request = try buildRequest(url: url, method: "GET")
        let (data, response) = try await session.data(for: request)
        try checkResponse(response: response, data: data)
        
        let parsed = try JSONSerialization.jsonObject(with: data)
        let items: [[String: Any]]
        if let array = parsed as? [[String: Any]] {
            items = array
        } else if let dict = parsed as? [String: Any] {
            items = dict["files"] as? [[String: Any]] ?? dict["data"] as? [[String: Any]] ?? []
        } else {
            items = []
        }
        return items.map { StorageFile(data: $0) }
    }
    
    /// Download a file and return its binary contents.
    public func download(bucketName: String, filePath: String) async throws -> Data {
        let url = buildUrl("/api/v1/storage/projects/\(projectSlug)/files/\(bucketName)/\(filePath)")
        let request = try buildRequest(url: url, method: "GET")
        let (data, response) = try await session.data(for: request)
        try checkResponse(response: response, data: data)
        return data
    }
    
    /// Download a file and save it to a local path.
    public func downloadToFile(bucketName: String, filePath: String, localPath: String) async throws -> String {
        let data = try await download(bucketName: bucketName, filePath: filePath)
        let localUrl = URL(fileURLWithPath: localPath)
        let dir = localUrl.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: localUrl)
        return localPath
    }
    
    /// Delete a file from a bucket.
    public func deleteFile(bucketName: String, filePath: String) async throws -> [String: Any] {
        return try await executeJsonRequest(
            path: "/api/v1/storage/projects/\(projectSlug)/files/\(bucketName)/\(filePath)",
            method: "DELETE"
        )
    }
    
    // MARK: - Utilities
    
    /// Get the public URL for a file in a public bucket.
    public func getPublicUrl(bucketName: String, filePath: String) -> String {
        return "\(baseUrl)/api/v1/storage/projects/\(projectSlug)/files/\(bucketName)/\(filePath)"
    }
    
    /// Get storage statistics for the project.
    public func getStats() async throws -> StorageQuota {
        let data = try await executeJsonRequest(
            path: "/api/v1/storage/projects/\(projectSlug)/stats",
            method: "GET"
        )
        return StorageQuota(data: data)
    }
    
    /// Get storage quota (alias for getStats).
    public func getQuota(forceRefresh: Bool = false) async throws -> StorageQuota {
        return try await getStats()
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
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }
    
    private func executeJsonRequest(
        path: String,
        method: String,
        body: [String: AnyCodable]? = nil
    ) async throws -> [String: Any] {
        let url = buildUrl(path)
        var request = try buildRequest(url: url, method: method)
        
        if let body = body {
            let jsonData = try JSONEncoder().encode(body)
            request.httpBody = jsonData
        }
        
        let (data, response) = try await session.data(for: request)
        try checkResponse(response: response, data: data)
        
        if data.isEmpty { return [:] }
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }
    
    private func checkResponse(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError("Invalid response type")
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = errorDict?["detail"] as? String
                ?? errorDict?["error"] as? String
                ?? errorDict?["message"] as? String
                ?? "Request failed with status \(httpResponse.statusCode)"
            
            switch httpResponse.statusCode {
            case 401, 403:
                throw AuthenticationError(message, statusCode: httpResponse.statusCode, response: errorDict)
            case 404:
                throw NotFoundError(message, response: errorDict)
            case 413:
                throw StorageLimitExceededError(message, response: errorDict)
            case 429:
                throw RateLimitError(message, response: errorDict)
            default:
                throw StorageError(message, statusCode: httpResponse.statusCode, response: errorDict)
            }
        }
    }
}
