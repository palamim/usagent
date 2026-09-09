import Foundation
import Security

struct ClaudeCredentials {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

enum CredentialsError: Error {
    case notFound
    case malformed
}

/// Claude Code stores its OAuth token in the macOS Keychain (service
/// "Claude Code-credentials"), not in ~/.claude/.credentials.json — that
/// path is the Linux/Windows location.
enum CredentialsStore {
    private static let service = "Claude Code-credentials"

    static func read() -> Result<ClaudeCredentials, CredentialsError> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return .failure(.notFound)
        }

        struct Payload: Decodable {
            struct OAuth: Decodable {
                let accessToken: String
                let refreshToken: String
                let expiresAt: Double
            }
            let claudeAiOauth: OAuth
        }

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return .failure(.malformed)
        }

        let expiresAt = Date(timeIntervalSince1970: payload.claudeAiOauth.expiresAt / 1000)
        return .success(ClaudeCredentials(
            accessToken: payload.claudeAiOauth.accessToken,
            refreshToken: payload.claudeAiOauth.refreshToken,
            expiresAt: expiresAt
        ))
    }

    /// Patches accessToken/refreshToken/expiresAt in place, leaving every
    /// other field in the Keychain blob (scopes, subscriptionType, ...)
    /// untouched — this is a partial update, not a replacement, so it stays
    /// compatible with whatever the CLI itself expects to find there.
    @discardableResult
    static func write(accessToken: String, refreshToken: String, expiresAt: Date) -> Bool {
        let readQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(readQuery as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var oauth = root["claudeAiOauth"] as? [String: Any] else {
            return false
        }

        oauth["accessToken"] = accessToken
        oauth["refreshToken"] = refreshToken
        oauth["expiresAt"] = expiresAt.timeIntervalSince1970 * 1000
        root["claudeAiOauth"] = oauth

        guard let newData = try? JSONSerialization.data(withJSONObject: root) else {
            return false
        }

        let matchQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let update: [String: Any] = [kSecValueData as String: newData]
        return SecItemUpdate(matchQuery as CFDictionary, update as CFDictionary) == errSecSuccess
    }
}
