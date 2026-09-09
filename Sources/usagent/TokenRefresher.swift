import Foundation

struct RefreshedTokens {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

enum TokenRefreshError: Error {
    case network(String)
    case invalidResponse
}

protocol TokenRefreshing: Sendable {
    func refresh(refreshToken: String) async -> Result<RefreshedTokens, TokenRefreshError>
}

/// Refreshes an expired (or soon-to-expire) access token using the
/// refresh_token the Claude Code CLI already stores alongside it — the same
/// undocumented flow the CLI itself runs silently on every invocation.
/// client_id here is Claude Code's own public OAuth client identifier, not a
/// secret tied to any individual account.
struct TokenRefresher: TokenRefreshing {
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let endpoint = URL(string: "https://console.anthropic.com/v1/oauth/token")!

    func refresh(refreshToken: String) async -> Result<RefreshedTokens, TokenRefreshError> {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                return .failure(.network("HTTP \(code)"))
            }

            struct TokenResponse: Decodable {
                let accessToken: String
                let refreshToken: String
                let expiresIn: Double

                enum CodingKeys: String, CodingKey {
                    case accessToken = "access_token"
                    case refreshToken = "refresh_token"
                    case expiresIn = "expires_in"
                }
            }

            guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
                return .failure(.invalidResponse)
            }

            let expiresAt = Date().addingTimeInterval(decoded.expiresIn)
            return .success(RefreshedTokens(
                accessToken: decoded.accessToken,
                refreshToken: decoded.refreshToken,
                expiresAt: expiresAt
            ))
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }
}
