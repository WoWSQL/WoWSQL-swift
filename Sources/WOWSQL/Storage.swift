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

/// S3 Storage client for WOWSQL
public class WOWSQLStorage {
    private let baseUrl: String
    private let apiKey: String
    private let timeout: TimeInterval
    private let session: URLSession
    private let autoCheckQuota: Bool
    private let projectSlug: String
    
    /// Initialize the storage client
    /// - Parameters:
    ///   - projectUrl: Your project URL or slug
    ///   - apiKey: Your API key
    ///   - timeout: Request timeout in seconds (default: 60)
    ///   - autoCheckQuota: Automatically check quota before uploads (default: true)
    public init(
        projectUrl: String,
        apiKey: String,
        timeout: TimeInterval = 60,
        autoCheckQuota: Bool = true
    ) {
        var url = projectUrl.trimmingCharacters(in: .whitespaces)
        if url.hasSuffix("/") {
            url = String(url.dropLast())
        }
        
        // Extract project slug from URL
        var slug = url
        if let urlObj = URL(string: url) {
            slug = urlObj.host ?? url
            if slug.contains(".") {
                slug = String(slug.split(separator: ".").first ?? "")
            }
        }
        
        self.baseUrl = "https://api.wowsql.com" // Default API base
        self.projectSlug = slug
        self.apiKey = apiKey
        self.timeout = timeout
        self.autoCheckQuota = autoCheckQuota
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: config)
    }
    
    /// Get storage quota information
    public func getQuota(forceRefresh: Bool = false) async throws -> StorageQuota {
        let url = URL(string: "\(baseUrl)/api/v1/storage/s3/projects/\(projectSlug)/quota")!
        return try await executeRequest(url: url, method: "GET")
    }
    
    /// Check if upload is allowed based on quota
    public func checkUploadAllowed(fileSizeBytes: Int64) async throws -> (allowed: Bool, message: String) {
        let quota = try await getQuota(forceRefresh: true)
        let fileSizeGb = Double(fileSizeBytes) / (1024.0 * 1024.0 * 1024.0)
        
        if fileSizeGb > quota.storageAvailableGb {
            return (false, "Storage limit exceeded! File size: \(String(format: "%.4f", fileSizeGb)) GB, Available: \(String(format: "%.4f", quota.storageAvailableGb)) GB. Upgrade your plan to get more storage.")
        }
        
        return (true, "Upload allowed. \(String(format: "%.4f", quota.storageAvailableGb)) GB available.")
    }
    
    /// Upload file from file path
    public func uploadFromPath(
        filePath: String,
        fileKey: String? = nil,
        folder: String? = nil,
        contentType: String? = nil,
        checkQuota: Bool? = nil
    ) async throws -> FileUploadResult {
        guard let fileData = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
            throw StorageException("File not found: \(filePath)")
        }
        
        let key = fileKey ?? URL(fileURLWithPath: filePath).lastPathComponent
        return try await uploadBytes(fileData, key: key, folder: folder, contentType: contentType, checkQuota: checkQuota)
    }
    
    /// Upload bytes to storage
    public func uploadBytes(
        _ bytes: Data,
        key: String,
        folder: String? = nil,
        contentType: String? = nil,
        checkQuota: Bool? = nil
    ) async throws -> FileUploadResult {
        // Check quota if enabled
        let shouldCheck = checkQuota ?? autoCheckQuota
        if shouldCheck {
            let (allowed, message) = try await checkUploadAllowed(fileSizeBytes: Int64(bytes.count))
            if !allowed {
                let quota = try await getQuota()
                throw StorageLimitExceededException(
                    message,
                    requiredBytes: Int64(bytes.count),
                    availableBytes: quota.storageAvailableBytes
                )
            }
        }
        
        var urlString = "\(baseUrl)/api/v1/storage/s3/projects/\(projectSlug)/upload"
        if let folder = folder {
            urlString += "?folder=\(folder.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? folder)"
        }
        let url = URL(string: urlString)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"key\"\r\n\r\n".data(using: .utf8)!)
        body.append(key.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        
        if let contentType = contentType {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"content_type\"\r\n\r\n".data(using: .utf8)!)
            body.append(contentType.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(key.split(separator: "/").last ?? "file")\"\r\n".data(using: .utf8)!)
        if let contentType = contentType {
            body.append("Content-Type: \(contentType)\r\n".data(using: .utf8)!)
        }
        body.append("\r\n".data(using: .utf8)!)
        body.append(bytes)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await session.data(for: request)
        try checkResponse(response: response, data: data)
        
        return try JSONDecoder().decode(FileUploadResult.self, from: data)
    }
    
    /// List files with optional prefix
    public func listFiles(prefix: String? = nil, maxKeys: Int = 1000) async throws -> [StorageFile] {
        var urlString = "\(baseUrl)/api/v1/storage/s3/projects/\(projectSlug)/files?max_keys=\(maxKeys)"
        if let prefix = prefix {
            let encoded = prefix.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? prefix
            urlString += "&prefix=\(encoded)"
        }
        
        let url = URL(string: urlString)!
        let response: [String: AnyCodable] = try await executeRequest(url: url, method: "GET")
        
        if let filesArray = response["files"]?.value as? [[String: Any]] {
            let jsonData = try JSONSerialization.data(withJSONObject: filesArray)
            return try JSONDecoder().decode([StorageFile].self, from: jsonData)
        }
        
        return []
    }
    
    /// Get file URL (presigned URL)
    public func getFileUrl(key: String, expiresIn: Int64 = 3600) async throws -> [String: AnyCodable] {
        let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        let urlString = "\(baseUrl)/api/v1/storage/s3/projects/\(projectSlug)/files/\(encoded)/url?expires_in=\(expiresIn)"
        let url = URL(string: urlString)!
        return try await executeRequest(url: url, method: "GET")
    }
    
    /// Get presigned URL for file operations
    public func getPresignedUrl(key: String, expiresIn: Int64 = 3600, operation: String = "get_object") async throws -> String {
        let url = URL(string: "\(baseUrl)/api/v1/storage/s3/projects/\(projectSlug)/presigned-url")!
        let body: [String: AnyCodable] = [
            "file_key": AnyCodable(key),
            "expires_in": AnyCodable(expiresIn),
            "operation": AnyCodable(operation)
        ]
        
        let response: [String: AnyCodable] = try await executeRequest(url: url, method: "POST", body: body)
        
        guard let downloadUrl = response["url"]?.value as? String else {
            throw StorageException("Invalid presigned URL response")
        }
        
        return downloadUrl
    }
    
    /// Download file (alias for getPresignedUrl)
    public func download(key: String, expiresIn: Int64 = 3600) async throws -> String {
        return try await getPresignedUrl(key: key, expiresIn: expiresIn, operation: "get_object")
    }
    
    /// Get storage information
    public func getStorageInfo() async throws -> [String: AnyCodable] {
        let url = URL(string: "\(baseUrl)/api/v1/storage/s3/projects/\(projectSlug)/info")!
        return try await executeRequest(url: url, method: "GET")
    }
    
    /// Provision S3 storage for the project
    public func provisionStorage(region: String = "us-east-1") async throws -> [String: AnyCodable] {
        let url = URL(string: "\(baseUrl)/api/v1/storage/s3/projects/\(projectSlug)/provision")!
        let body: [String: AnyCodable] = ["region": AnyCodable(region)]
        return try await executeRequest(url: url, method: "POST", body: body)
    }
    
    /// Get available S3 regions
    public func getAvailableRegions() async throws -> [[String: AnyCodable]] {
        let url = URL(string: "\(baseUrl)/api/v1/storage/s3/regions")!
        let response: [String: AnyCodable] = try await executeRequest(url: url, method: "GET")
        
        if let regionsArray = response["regions"]?.value as? [[String: Any]] {
            return regionsArray.map { region in
                region.mapValues { AnyCodable($0) }
            }
        }
        
        return []
    }
    
    /// Delete a file
    public func deleteFile(key: String) async throws {
        let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        let url = URL(string: "\(baseUrl)/api/v1/storage/s3/projects/\(projectSlug)/files/\(encoded)")!
        let _: [String: AnyCodable] = try await executeRequest(url: url, method: "DELETE")
    }
    
    // MARK: - Private Methods
    
    private func executeRequest<T: Codable>(
        url: URL,
        method: String,
        body: [String: AnyCodable]? = nil
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        if let body = body {
            let jsonData = try JSONEncoder().encode(body)
            request.httpBody = jsonData
        }
        
        let (data, response) = try await session.data(for: request)
        try checkResponse(response: response, data: data)
        
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    private func checkResponse(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkException("Invalid response type")
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorResponse = try? JSONDecoder().decode([String: AnyCodable].self, from: data)
            let message = errorResponse?["error"]?.value as? String
                ?? errorResponse?["message"]?.value as? String
                ?? errorResponse?["detail"]?.value as? String
                ?? "Request failed with status \(httpResponse.statusCode)"
            
            let errorDict = errorResponse?.mapValues { $0.value } as? [String: Any]
            
            switch httpResponse.statusCode {
            case 401, 403:
                throw AuthenticationException(message, statusCode: httpResponse.statusCode, errorResponse: errorDict)
            case 404:
                throw NotFoundException(message, errorResponse: errorDict)
            case 413:
                throw StorageLimitExceededException(
                    message,
                    requiredBytes: 0,
                    availableBytes: 0
                )
            case 429:
                throw RateLimitException(message, errorResponse: errorDict)
            default:
                throw StorageException(message, statusCode: httpResponse.statusCode, errorResponse: errorDict)
            }
        }
    }
}

