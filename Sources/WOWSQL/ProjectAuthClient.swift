//
//  ProjectAuthClient.swift
//  WOWSQL
//
//  Created by WOWSQL Team
//  Copyright © 2024 WOWSQL. All rights reserved.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Project authentication client for user management
public class ProjectAuthClient {
    private let config: ProjectAuthConfig
    private let session: URLSession
    private var accessToken: String?
    private var refreshToken: String?
    
    /// Initialize the auth client
    public init(config: ProjectAuthConfig) {
        self.config = config
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = config.timeoutSeconds
        sessionConfig.timeoutIntervalForResource = config.timeoutSeconds
        self.session = URLSession(configuration: sessionConfig)
    }
    
    /// Sign up a new user
    public func signUp(_ request: SignUpRequest) async throws -> AuthResult {
        let url = buildAuthUrl("/signup")
        var body: [String: AnyCodable] = [
            "email": AnyCodable(request.email),
            "password": AnyCodable(request.password)
        ]
        
        if let fullName = request.fullName {
            body["full_name"] = AnyCodable(fullName)
        }
        
        if let metadata = request.userMetadata {
            body["user_metadata"] = AnyCodable(metadata.mapValues { $0.value })
        }
        
        let response: [String: AnyCodable] = try await executeRequest(url: url, method: "POST", body: body)
        let session = try parseSession(from: response)
        persistSession(session)
        
        let user = try? parseUser(from: response["user"]?.value)
        return AuthResult(user: user, session: session)
    }
    
    /// Sign in an existing user
    public func signIn(_ request: SignInRequest) async throws -> AuthResult {
        let url = buildAuthUrl("/login")
        let body: [String: AnyCodable] = [
            "email": AnyCodable(request.email),
            "password": AnyCodable(request.password)
        ]
        
        let response: [String: AnyCodable] = try await executeRequest(url: url, method: "POST", body: body)
        let session = try parseSession(from: response)
        persistSession(session)
        
        return AuthResult(user: nil, session: session)
    }
    
    /// Get current user information
    public func getUser(tokenOverride: String? = nil) async throws -> AuthUser {
        guard let token = tokenOverride ?? accessToken else {
            throw AuthenticationException("Access token is required. Call signIn first.")
        }
        let url = buildAuthUrl("/me")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        // UNIFIED AUTHENTICATION: Use apiKey (new) or publicApiKey (deprecated) for backward compatibility
        let unifiedKey = config.apiKey ?? config.publicApiKey
        if let apiKey = unifiedKey {
            // UNIFIED AUTHENTICATION: Use Authorization header (same as database operations)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await session.data(for: request)
        try checkResponse(response: response, data: data)
        
        let userDict = try JSONDecoder().decode([String: AnyCodable].self, from: data)
        return try parseUser(from: userDict)
    }
    
    /// Get OAuth authorization URL
    public func getOAuthAuthorizationUrl(provider: String, redirectUri: String) async throws -> OAuthAuthorizationResponse {
        let encodedUri = redirectUri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectUri
        let url = buildAuthUrl("/oauth/\(provider)?frontend_redirect_uri=\(encodedUri)")
        
        let response: [String: AnyCodable] = try await executeRequest(url: url, method: "GET", body: nil)
        
        return OAuthAuthorizationResponse(
            authorizationUrl: response["authorization_url"]?.value as? String ?? "",
            provider: response["provider"]?.value as? String ?? provider,
            redirectUri: response["redirect_uri"]?.value as? String ?? response["backend_callback_url"]?.value as? String ?? "",
            backendCallbackUrl: response["backend_callback_url"]?.value as? String,
            frontendRedirectUri: response["frontend_redirect_uri"]?.value as? String
        )
    }
    
    /// Exchange OAuth callback code for access tokens
    public func exchangeOAuthCallback(provider: String, code: String, redirectUri: String? = nil) async throws -> AuthResult {
        let url = buildAuthUrl("/oauth/\(provider)/callback")
        var body: [String: AnyCodable] = ["code": AnyCodable(code)]
        
        if let redirectUri = redirectUri {
            body["redirect_uri"] = AnyCodable(redirectUri)
        }
        
        let response: [String: AnyCodable] = try await executeRequest(url: url, method: "POST", body: body)
        let session = try parseSession(from: response)
        persistSession(session)
        
        let user = try? parseUser(from: response["user"]?.value)
        return AuthResult(user: user, session: session)
    }
    
    /// Request password reset
    public func forgotPassword(email: String) async throws -> [String: AnyCodable] {
        let url = buildAuthUrl("/forgot-password")
        let body: [String: AnyCodable] = ["email": AnyCodable(email)]
        return try await executeRequest(url: url, method: "POST", body: body)
    }
    
    /// Reset password with token
    public func resetPassword(token: String, newPassword: String) async throws -> [String: AnyCodable] {
        let url = buildAuthUrl("/reset-password")
        let body: [String: AnyCodable] = [
            "token": AnyCodable(token),
            "new_password": AnyCodable(newPassword)
        ]
        return try await executeRequest(url: url, method: "POST", body: body)
    }
    
    /// Set session tokens
    public func setSession(accessToken: String, refreshToken: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
    
    /// Clear session tokens
    public func clearSession() {
        accessToken = nil
        refreshToken = nil
    }
    
    /// Get current session
    public func getSession() -> AuthSession? {
        guard let token = accessToken else { return nil }
        return AuthSession(
            accessToken: token,
            refreshToken: refreshToken ?? "",
            tokenType: "bearer",
            expiresIn: 0
        )
    }
    
    // MARK: - Private Methods
    
    private func buildAuthUrl(_ path: String) -> URL {
        var normalized = config.projectUrl.trimmingCharacters(in: .whitespaces)
        
        // If it's already a full URL, use it as-is
        if normalized.hasPrefix("http://") || normalized.hasPrefix("https://") {
            normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if normalized.hasSuffix("/api") {
                normalized = String(normalized.dropLast(4))
            }
            return URL(string: "\(normalized)/api/auth\(path)")!
        }
        
        // Build URL from project slug
        let `protocol` = config.secure ? "https" : "http"
        if normalized.contains(".\(config.baseDomain)") || normalized.hasSuffix(config.baseDomain) {
            normalized = "\(`protocol`)://\(normalized)"
        } else {
            normalized = "\(`protocol`)://\(normalized).\(config.baseDomain)"
        }
        
        normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalized.hasSuffix("/api") {
            normalized = String(normalized.dropLast(4))
        }
        
        return URL(string: "\(normalized)/api/auth\(path)")!
    }
    
    private func executeRequest(url: URL, method: String, body: [String: AnyCodable]?) async throws -> [String: AnyCodable] {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // UNIFIED AUTHENTICATION: Use apiKey (new) or publicApiKey (deprecated) for backward compatibility
        let unifiedKey = config.apiKey ?? config.publicApiKey
        if let apiKey = unifiedKey {
            // UNIFIED AUTHENTICATION: Use Authorization header (same as database operations)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        if let body = body {
            let jsonData = try JSONEncoder().encode(body)
            request.httpBody = jsonData
        }
        
        let (data, response) = try await session.data(for: request)
        try checkResponse(response: response, data: data)
        
        return try JSONDecoder().decode([String: AnyCodable].self, from: data)
    }
    
    private func checkResponse(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkException("Invalid response type")
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorResponse = try? JSONDecoder().decode([String: AnyCodable].self, from: data)
            let message = errorResponse?["detail"]?.value as? String
                ?? errorResponse?["message"]?.value as? String
                ?? errorResponse?["error"]?.value as? String
                ?? "Request failed with status \(httpResponse.statusCode)"
            
            let errorDict = errorResponse?.mapValues { $0.value } as? [String: Any]
            
            switch httpResponse.statusCode {
            case 401, 403:
                throw AuthenticationException(message, statusCode: httpResponse.statusCode, errorResponse: errorDict)
            case 404:
                throw NotFoundException(message, errorResponse: errorDict)
            case 429:
                throw RateLimitException(message, errorResponse: errorDict)
            default:
                throw WOWSQLException(message, statusCode: httpResponse.statusCode, errorResponse: errorDict)
            }
        }
    }
    
    private func parseSession(from response: [String: AnyCodable]) throws -> AuthSession {
        guard let accessToken = response["access_token"]?.value as? String,
              let refreshToken = response["refresh_token"]?.value as? String,
              let tokenType = response["token_type"]?.value as? String,
              let expiresIn = response["expires_in"]?.value as? Int else {
            throw AuthenticationException("Invalid session response")
        }
        
        return AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: tokenType,
            expiresIn: expiresIn
        )
    }
    
    private func parseUser(from value: Any?) throws -> AuthUser {
        guard let dict = value as? [String: Any] else {
            throw AuthenticationException("Invalid user data")
        }
        
        let userDict = dict.mapValues { AnyCodable($0) }
        
        guard let id = userDict["id"]?.value as? String,
              let email = userDict["email"]?.value as? String else {
            throw AuthenticationException("Missing required user fields")
        }
        
        let metadata = userDict["user_metadata"]?.value as? [String: Any] ?? [:]
        let appMetadata = userDict["app_metadata"]?.value as? [String: Any] ?? [:]
        
        return AuthUser(
            id: id,
            email: email,
            fullName: userDict["full_name"]?.value as? String,
            avatarUrl: userDict["avatar_url"]?.value as? String,
            emailVerified: userDict["email_verified"]?.value as? Bool ?? false,
            userMetadata: metadata.mapValues { AnyCodable($0) },
            appMetadata: appMetadata.mapValues { AnyCodable($0) },
            createdAt: userDict["created_at"]?.value as? String
        )
    }
    
    private func persistSession(_ session: AuthSession) {
        self.accessToken = session.accessToken
        self.refreshToken = session.refreshToken
    }
}

