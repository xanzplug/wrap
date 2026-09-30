import Foundation
import Observation

/// The signed-in person.
struct WrapAccount: Equatable {
    let id: String
    let email: String
    let name: String
}

/// A message Supabase sent back, shown to the user as-is.
struct AuthError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Sign up, log in, reset password and sign out, using Supabase Auth.
/// Passwords go straight to Supabase; Wrap only keeps a session token in the Keychain.
@Observable
final class AuthService {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(WrapAccount)
    }

    enum SignUpResult {
        case signedIn
        case checkEmail
    }

    private(set) var state: State = .loading
    private var accessToken: String?
    private var accessExpiry: Date = .distantPast

    private static let refreshTokenKey = "refreshToken"

    var account: WrapAccount? {
        if case .signedIn(let account) = state { return account }
        return nil
    }

    var isConfigured: Bool { SupabaseConfig.isConfigured }

    // MARK: Session

    /// On launch: stay signed in if there's a saved session.
    func restoreSession() async {
        guard isConfigured, let refreshToken = Keychain.read(Self.refreshTokenKey) else {
            state = .signedOut
            return
        }
        do {
            let json = try await post("/auth/v1/token?grant_type=refresh_token",
                                      body: ["refresh_token": refreshToken])
            try handleSession(json)
        } catch {
            Keychain.delete(Self.refreshTokenKey)
            state = .signedOut
        }
    }

    // MARK: Actions

    func signUp(name: String, email: String, password: String) async throws -> SignUpResult {
        let json = try await post("/auth/v1/signup", body: [
            "email": email,
            "password": password,
            "data": ["name": name],
        ])
        if json["access_token"] != nil {
            try handleSession(json)
            return .signedIn
        }
        // Supabase is set to confirm emails first.
        return .checkEmail
    }

    func signIn(email: String, password: String) async throws {
        let json = try await post("/auth/v1/token?grant_type=password", body: [
            "email": email,
            "password": password,
        ])
        try handleSession(json)
    }

    func sendPasswordReset(email: String) async throws {
        _ = try await post("/auth/v1/recover", body: ["email": email])
    }

    func signOut() async {
        if let accessToken {
            _ = try? await post("/auth/v1/logout", body: [:], bearer: accessToken)
        }
        accessToken = nil
        accessExpiry = .distantPast
        Keychain.delete(Self.refreshTokenKey)
        state = .signedOut
    }

    /// A current access token for talking to the database, refreshed when it's about to expire.
    func validAccessToken() async throws -> String {
        if let accessToken, Date() < accessExpiry.addingTimeInterval(-60) {
            return accessToken
        }
        guard let refreshToken = Keychain.read(Self.refreshTokenKey) else {
            throw AuthError(message: "Please log in again.")
        }
        let json = try await post("/auth/v1/token?grant_type=refresh_token",
                                  body: ["refresh_token": refreshToken])
        try handleSession(json)
        guard let accessToken else { throw AuthError(message: "Please log in again.") }
        return accessToken
    }

    // MARK: Helpers

    private func handleSession(_ json: [String: Any]) throws {
        guard let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String,
              let user = json["user"] as? [String: Any],
              let id = user["id"] as? String
        else { throw AuthError(message: "Couldn't read the sign-in response. Try again.") }

        let email = user["email"] as? String ?? ""
        let metadata = user["user_metadata"] as? [String: Any]
        let name = (metadata?["name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""

        accessToken = access
        accessExpiry = Date().addingTimeInterval((json["expires_in"] as? Double) ?? 3600)
        Keychain.save(refresh, for: Self.refreshTokenKey)
        if !name.isEmpty {
            UserDefaults.standard.set(name, forKey: "displayName")   // used by the dashboard greeting
        }
        state = .signedIn(WrapAccount(id: id, email: email, name: name))
    }

    private func post(_ path: String, body: [String: Any], bearer: String? = nil) async throws -> [String: Any] {
        guard isConfigured, let url = URL(string: SupabaseConfig.projectURL + path) else {
            throw AuthError(message: "Accounts aren't connected yet. Add your Supabase details in SupabaseConfig.swift.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        if let bearer {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthError(message: "Can't reach the server. Check your internet connection.")
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = json["msg"] as? String
                ?? json["error_description"] as? String
                ?? json["message"] as? String
                ?? "Something went wrong (error \(status))."
            throw AuthError(message: message)
        }
        return json
    }
}
