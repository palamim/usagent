import Foundation
import Security

struct ClaudeCredentials {
    let accessToken: String
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
    static func read() -> Result<ClaudeCredentials, CredentialsError> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
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
                let expiresAt: Double
            }
            let claudeAiOauth: OAuth
        }

        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return .failure(.malformed)
        }

        let expiresAt = Date(timeIntervalSince1970: payload.claudeAiOauth.expiresAt / 1000)
        return .success(ClaudeCredentials(accessToken: payload.claudeAiOauth.accessToken, expiresAt: expiresAt))
    }
}
