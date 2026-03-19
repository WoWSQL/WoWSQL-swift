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

/// Project authentication client for user management.
///
/// UNIFIED AUTHENTICATION: Uses the same API keys (anon/service) as database operations.
///
/// Example:
/// ```swift
/// let auth = ProjectAuthClient(
///     projectUrl: "myproject",
///     apiKey: "wowsql_anon_..."
/// )
/// let result = try await auth.signIn(email: "user@example.com", password: "secret")
/// ```
public class ProjectAuthClient {
    private let baseUrl: String
    private let apiKey: String?
    private let timeout: TimeInterval
    private let session: URLSession
    private let storage: TokenStorage
    private var _accessToken: String?
    private var _refreshToken: String?
    
    /// Initialize the auth client.
    ///
    /// - Parameters:
    ///   - projectUrl: Project subdomain or full URL
    ///   - apiKey: API key (Anonymous or Service Role)
    ///   - baseDomain: Base domain (default: `"wowsql.com"`)
    ///   - secure: Use HTTPS (default: `true`)
    ///   - timeout: Request timeout in seconds (default: 30)
    ///   - verifySsl: Verify SSL (default: `true`)
    ///   - tokenStorage: Custom token storage (default: `MemoryTokenStorage`)
    public init(
        projectUrl: String,
        apiKey: String? = nil,
        baseDomain: String = "wowsql.com",
        secure: Bool = true,
        timeout: TimeInterval = 30,
        verifySsl: Bool = true,
        tokenStorage: TokenStorage? = nil
    ) {
        self.baseUrl = ProjectAuthClient.buildAuthBaseUrl(
            projectUrl: projectUrl,
            baseDomain: baseDomain,
            secure: secure
        )
        self.apiKey = apiKey
        self.timeout = timeout
        self.storage = tokenStorage ?? MemoryTokenStorage()
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        self.session = URLSession(configuration: config)
        
        self._accessToken = storage.getAccessToken()
        self._refreshToken = storage.getRefreshToken()
    }
    
    /// Initialize from legacy config struct (backward compatibility).
    public convenience init(config: ProjectAuthConfig) {
        self.init(
            projectUrl: config.projectUrl,
            apiKey: config.apiKey,
            baseDomain: config.baseDomain,
            secure: config.secure,
            timeout: config.timeoutSeconds
        )
    }
    
    // MARK: - Sign Up / Sign In
    
    /// Sign up a new user.
    public func signUp(
        email: String,
        password: String,
        fullName: String? = nil,
        userMetadata: [String: Any]? = nil
    ) async throws -> AuthResponse {
        var body: [String: AnyCodable] = [
            "email": AnyCodable(email),
            "password": AnyCodable(password)
        ]
        if let fullName = fullName {
            body["full_name"] = AnyCodable(fullName)
        }
        if let metadata = userMetadata {
            body["user_metadata"] = AnyCodable(metadata)
        }
        
        let response = try await executeRequest(url: url("/signup"), method: "POST", body: body)
        let session = try persistSession(from: response)
        let user = parseUser(from: response["user"]?.value)
        return AuthResponse(session: session, user: user)
    }
    
    /// Sign up using a request struct (backward compatibility).
    public func signUp(_ request: SignUpRequest) async throws -> AuthResponse {
        return try await signUp(
            email: request.email,
            password: request.password,
            fullName: request.fullName,
            userMetadata: request.userMetadata?.mapValues { $0.value }
        )
    }
    
    /// Sign in an existing user.
    public func signIn(email: String, password: String) async throws -> AuthResponse {
        let body: [String: AnyCodable] = [
            "email": AnyCodable(email),
            "password": AnyCodable(password)
        ]
        let response = try await executeRequest(url: url("/login"), method: "POST", body: body)
        let session = try persistSession(from: response)
        return AuthResponse(session: session, user: nil)
    }
    
    /// Sign in using a request struct (backward compatibility).
    public func signIn(_ request: SignInRequest) async throws -> AuthResponse {
        return try await signIn(email: request.email, password: request.password)
    }
    
    // MARK: - User
    
    /// Get current user information.
    public func getUser(accessToken: String? = nil) async throws -> AuthUser {
        guard let token = accessToken ?? _accessToken ?? storage.getAccessToken() else {
            throw WOWSQLError("Access token is required. Call signIn first.")
        }
        let response = try await executeRequest(
            url: url("/me"),
            method: "GET",
            body: nil,
            extraHeaders: ["Authorization": "Bearer \(token)"]
        )
        return try parseUserRequired(from: response)
    }
    
    /// Update the authenticated user's profile.
    public func updateUser(
        fullName: String? = nil,
        avatarUrl: String? = nil,
        username: String? = nil,
        userMetadata: [String: Any]? = nil,
        accessToken: String? = nil
    ) async throws -> AuthUser {
        guard let token = accessToken ?? _accessToken ?? storage.getAccessToken() else {
            throw WOWSQLError("Access token is required. Call signIn first.")
        }
        
        var body: [String: AnyCodable] = [:]
        if let fullName = fullName { body["full_name"] = AnyCodable(fullName) }
        if let avatarUrl = avatarUrl { body["avatar_url"] = AnyCodable(avatarUrl) }
        if let username = username { body["username"] = AnyCodable(username) }
        if let userMetadata = userMetadata { body["user_metadata"] = AnyCodable(userMetadata) }
        
        if body.isEmpty {
            throw WOWSQLError("At least one field to update is required")
        }
        
        let response = try await executeRequest(
            url: url("/me"),
            method: "PATCH",
            body: body,
            extraHeaders: ["Authorization": "Bearer \(token)"]
        )
        return try parseUserRequired(from: response)
    }
    
    // MARK: - OAuth
    
    /// Get OAuth authorization URL for a provider.
    public func getOAuthAuthorizationUrl(
        provider: String,
        redirectUri: String? = nil
    ) async throws -> [String: String] {
        var urlString = "/oauth/\(provider)"
        if let redirectUri = redirectUri {
            let encoded = redirectUri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectUri
            urlString += "?frontend_redirect_uri=\(encoded)"
        }
        
        let response = try await executeRequest(url: url(urlString), method: "GET", body: nil)
        return [
            "authorization_url": response["authorization_url"]?.value as? String ?? "",
            "provider": response["provider"]?.value as? String ?? provider,
            "backend_callback_url": response["backend_callback_url"]?.value as? String ?? "",
            "frontend_redirect_uri": response["frontend_redirect_uri"]?.value as? String ?? redirectUri ?? ""
        ]
    }
    
    /// Exchange OAuth callback code for access tokens.
    public func exchangeOAuthCallback(
        provider: String,
        code: String,
        redirectUri: String? = nil
    ) async throws -> AuthResponse {
        var body: [String: AnyCodable] = ["code": AnyCodable(code)]
        if let redirectUri = redirectUri {
            body["redirect_uri"] = AnyCodable(redirectUri)
        }
        
        let response = try await executeRequest(url: url("/oauth/\(provider)/callback"), method: "POST", body: body)
        let session = try persistSession(from: response)
        let user = parseUser(from: response["user"]?.value)
        return AuthResponse(session: session, user: user)
    }
    
    // MARK: - Password
    
    /// Request password reset.
    public func forgotPassword(email: String) async throws -> [String: Any] {
        let body: [String: AnyCodable] = ["email": AnyCodable(email)]
        let response = try await executeRequest(url: url("/forgot-password"), method: "POST", body: body)
        return [
            "success": response["success"]?.value ?? true,
            "message": response["message"]?.value ?? "If that email exists, a password reset link has been sent"
        ]
    }
    
    /// Reset password with token.
    public func resetPassword(token: String, newPassword: String) async throws -> [String: Any] {
        let body: [String: AnyCodable] = [
            "token": AnyCodable(token),
            "new_password": AnyCodable(newPassword)
        ]
        let response = try await executeRequest(url: url("/reset-password"), method: "POST", body: body)
        return [
            "success": response["success"]?.value ?? true,
            "message": response["message"]?.value ?? "Password reset successfully!"
        ]
    }
    
    /// Change the authenticated user's password.
    public func changePassword(
        currentPassword: String,
        newPassword: String,
        accessToken: String? = nil
    ) async throws -> [String: Any] {
        guard let token = accessToken ?? _accessToken ?? storage.getAccessToken() else {
            throw WOWSQLError("Access token is required. Call signIn first.")
        }
        let body: [String: AnyCodable] = [
            "current_password": AnyCodable(currentPassword),
            "new_password": AnyCodable(newPassword)
        ]
        let response = try await executeRequest(
            url: url("/change-password"),
            method: "POST",
            body: body,
            extraHeaders: ["Authorization": "Bearer \(token)"]
        )
        return response.mapValues { $0.value }
    }
    
    // MARK: - OTP
    
    /// Send OTP code to user's email.
    /// Purpose: `"login"`, `"signup"`, or `"password_reset"`.
    public func sendOtp(email: String, purpose: String = "login") async throws -> [String: Any] {
        guard ["login", "signup", "password_reset"].contains(purpose) else {
            throw WOWSQLError("Purpose must be 'login', 'signup', or 'password_reset'")
        }
        let body: [String: AnyCodable] = [
            "email": AnyCodable(email),
            "purpose": AnyCodable(purpose)
        ]
        let response = try await executeRequest(url: url("/otp/send"), method: "POST", body: body)
        return [
            "success": response["success"]?.value ?? true,
            "message": response["message"]?.value ?? "If that email exists, an OTP code has been sent"
        ]
    }
    
    /// Verify OTP and complete authentication.
    /// Returns `AuthResponse` for login/signup, dict for password_reset.
    public func verifyOtp(
        email: String,
        otp: String,
        purpose: String = "login",
        newPassword: String? = nil
    ) async throws -> Any {
        guard ["login", "signup", "password_reset"].contains(purpose) else {
            throw WOWSQLError("Purpose must be 'login', 'signup', or 'password_reset'")
        }
        if purpose == "password_reset" && (newPassword == nil || newPassword!.isEmpty) {
            throw WOWSQLError("newPassword is required for password_reset purpose")
        }
        
        var body: [String: AnyCodable] = [
            "email": AnyCodable(email),
            "otp": AnyCodable(otp),
            "purpose": AnyCodable(purpose)
        ]
        if let newPassword = newPassword {
            body["new_password"] = AnyCodable(newPassword)
        }
        
        let response = try await executeRequest(url: url("/otp/verify"), method: "POST", body: body)
        
        if purpose == "password_reset" {
            return [
                "success": response["success"]?.value ?? true,
                "message": response["message"]?.value ?? "Password reset successfully!"
            ] as [String: Any]
        }
        
        let session = try persistSession(from: response)
        let user = parseUser(from: response["user"]?.value)
        return AuthResponse(session: session, user: user)
    }
    
    // MARK: - Magic Link
    
    /// Send magic link to user's email.
    /// Purpose: `"login"`, `"signup"`, or `"email_verification"`.
    public func sendMagicLink(email: String, purpose: String = "login") async throws -> [String: Any] {
        guard ["login", "signup", "email_verification"].contains(purpose) else {
            throw WOWSQLError("Purpose must be 'login', 'signup', or 'email_verification'")
        }
        let body: [String: AnyCodable] = [
            "email": AnyCodable(email),
            "purpose": AnyCodable(purpose)
        ]
        let response = try await executeRequest(url: url("/magic-link/send"), method: "POST", body: body)
        return [
            "success": response["success"]?.value ?? true,
            "message": response["message"]?.value ?? "If that email exists, a magic link has been sent"
        ]
    }
    
    // MARK: - Email Verification
    
    /// Verify email using token.
    public func verifyEmail(token: String) async throws -> [String: Any] {
        let body: [String: AnyCodable] = ["token": AnyCodable(token)]
        let response = try await executeRequest(url: url("/verify-email"), method: "POST", body: body)
        return [
            "success": response["success"]?.value ?? true,
            "message": response["message"]?.value ?? "Email verified successfully!"
        ]
    }
    
    /// Resend verification email.
    public func resendVerification(email: String) async throws -> [String: Any] {
        let body: [String: AnyCodable] = ["email": AnyCodable(email)]
        let response = try await executeRequest(url: url("/resend-verification"), method: "POST", body: body)
        return [
            "success": response["success"]?.value ?? true,
            "message": response["message"]?.value ?? "If that email exists, a verification email has been sent"
        ]
    }
    
    // MARK: - Session Management
    
    /// Logout the current user.
    public func logout(accessToken: String? = nil) async throws -> [String: Any] {
        guard let token = accessToken ?? _accessToken ?? storage.getAccessToken() else {
            throw WOWSQLError("Access token is required. Call signIn first.")
        }
        let response = try await executeRequest(
            url: url("/logout"),
            method: "POST",
            body: nil,
            extraHeaders: ["Authorization": "Bearer \(token)"]
        )
        clearSession()
        return response.mapValues { $0.value }
    }
    
    /// Exchange a refresh token for new access + refresh tokens.
    public func refreshToken(refreshToken: String? = nil) async throws -> AuthResponse {
        guard let token = refreshToken ?? _refreshToken ?? storage.getRefreshToken() else {
            throw WOWSQLError("Refresh token is required. Call signIn first.")
        }
        let body: [String: AnyCodable] = ["refresh_token": AnyCodable(token)]
        let response = try await executeRequest(url: url("/refresh-token"), method: "POST", body: body)
        let session = try persistSession(from: response)
        return AuthResponse(session: session, user: nil)
    }
    
    /// Get current session tokens.
    public func getSession() -> [String: String?] {
        return [
            "access_token": _accessToken ?? storage.getAccessToken(),
            "refresh_token": _refreshToken ?? storage.getRefreshToken()
        ]
    }
    
    /// Set session tokens manually.
    public func setSession(accessToken: String, refreshToken: String? = nil) {
        _accessToken = accessToken
        _refreshToken = refreshToken
        storage.setAccessToken(accessToken)
        storage.setRefreshToken(refreshToken)
    }
    
    /// Clear all session tokens.
    public func clearSession() {
        _accessToken = nil
        _refreshToken = nil
        storage.setAccessToken(nil)
        storage.setRefreshToken(nil)
    }
    
    /// Close the HTTP session.
    public func close() {
        session.invalidateAndCancel()
    }
    
    // MARK: - Private Helpers
    
    private func url(_ path: String) -> URL {
        return URL(string: "\(baseUrl)\(path)")!
    }
    
    private func executeRequest(
        url: URL,
        method: String,
        body: [String: AnyCodable]?,
        extraHeaders: [String: String]? = nil
    ) async throws -> [String: AnyCodable] {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let apiKey = apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        if let extraHeaders = extraHeaders {
            for (key, value) in extraHeaders {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        
        if let body = body {
            let jsonData = try JSONEncoder().encode(body)
            request.httpBody = jsonData
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError("Invalid response type")
            }
            
            if !(200...299).contains(httpResponse.statusCode) {
                try handleAuthError(statusCode: httpResponse.statusCode, data: data)
            }
            
            if data.isEmpty { return [:] }
            return try JSONDecoder().decode([String: AnyCodable].self, from: data)
        } catch let error as WOWSQLError {
            throw error
        } catch {
            throw NetworkError("Network error: \(error.localizedDescription)", underlyingError: error)
        }
    }
    
    private func handleAuthError(statusCode: Int, data: Data) throws -> Never {
        let errorResponse = try? JSONDecoder().decode([String: AnyCodable].self, from: data)
        let message = errorResponse?["detail"]?.value as? String
            ?? errorResponse?["message"]?.value as? String
            ?? errorResponse?["error"]?.value as? String
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
    
    private func persistSession(from response: [String: AnyCodable]) throws -> AuthSession {
        guard let accessToken = response["access_token"]?.value as? String,
              let refreshToken = response["refresh_token"]?.value as? String else {
            throw AuthenticationError("Invalid session response")
        }
        
        let tokenType = response["token_type"]?.value as? String ?? "bearer"
        let expiresIn = response["expires_in"]?.value as? Int ?? 0
        
        let session = AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: tokenType,
            expiresIn: expiresIn
        )
        
        _accessToken = session.accessToken
        _refreshToken = session.refreshToken
        storage.setAccessToken(session.accessToken)
        storage.setRefreshToken(session.refreshToken)
        
        return session
    }
    
    private func parseUser(from value: Any?) -> AuthUser? {
        guard let dict = value as? [String: Any] else { return nil }
        return AuthUser(
            id: dict["id"] as? String ?? "",
            email: dict["email"] as? String ?? "",
            fullName: dict["full_name"] as? String ?? dict["fullName"] as? String,
            avatarUrl: dict["avatar_url"] as? String ?? dict["avatarUrl"] as? String,
            emailVerified: dict["email_verified"] as? Bool ?? dict["emailVerified"] as? Bool ?? false,
            userMetadata: (dict["user_metadata"] as? [String: Any] ?? dict["userMetadata"] as? [String: Any])?.mapValues { AnyCodable($0) },
            appMetadata: (dict["app_metadata"] as? [String: Any] ?? dict["appMetadata"] as? [String: Any])?.mapValues { AnyCodable($0) },
            createdAt: dict["created_at"] as? String ?? dict["createdAt"] as? String
        )
    }
    
    private func parseUserRequired(from response: [String: AnyCodable]) throws -> AuthUser {
        let dict = response.mapValues { $0.value }
        guard let id = dict["id"] as? String, let email = dict["email"] as? String else {
            throw AuthenticationError("Invalid user data")
        }
        return AuthUser(
            id: id,
            email: email,
            fullName: dict["full_name"] as? String ?? dict["fullName"] as? String,
            avatarUrl: dict["avatar_url"] as? String ?? dict["avatarUrl"] as? String,
            emailVerified: dict["email_verified"] as? Bool ?? dict["emailVerified"] as? Bool ?? false,
            userMetadata: (dict["user_metadata"] as? [String: Any] ?? dict["userMetadata"] as? [String: Any])?.mapValues { AnyCodable($0) },
            appMetadata: (dict["app_metadata"] as? [String: Any] ?? dict["appMetadata"] as? [String: Any])?.mapValues { AnyCodable($0) },
            createdAt: dict["created_at"] as? String ?? dict["createdAt"] as? String
        )
    }
    
    private static func buildAuthBaseUrl(projectUrl: String, baseDomain: String, secure: Bool) -> String {
        var normalized = projectUrl.trimmingCharacters(in: .whitespaces)
        
        if normalized.hasPrefix("http://") || normalized.hasPrefix("https://") {
            normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if normalized.hasSuffix("/api") {
                normalized = String(normalized.dropLast(4))
            }
            return "\(normalized)/api/auth"
        }
        
        let proto = secure ? "https" : "http"
        if normalized.contains(".\(baseDomain)") || normalized.hasSuffix(baseDomain) {
            normalized = "\(proto)://\(normalized)"
        } else {
            normalized = "\(proto)://\(normalized).\(baseDomain)"
        }
        
        normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalized.hasSuffix("/api") {
            normalized = String(normalized.dropLast(4))
        }
        
        return "\(normalized)/api/auth"
    }
}
