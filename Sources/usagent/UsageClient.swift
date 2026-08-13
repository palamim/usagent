import Foundation

struct UsageWindow: Decodable {
    let utilization: Double
    let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

struct UsageSnapshot: Decodable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

enum UsageFetchError: Error {
    case noCredentials
    case tokenExpired
    case unauthorized
    case network(String)
    case decoding
}

enum UsageClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private static let dateDecoder: JSONDecoder = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = formatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date: \(string)")
            }
            return date
        }
        return decoder
    }()

    static func fetch() async -> Result<UsageSnapshot, UsageFetchError> {
        let credentials: ClaudeCredentials
        switch CredentialsStore.read() {
        case .failure:
            return .failure(.noCredentials)
        case .success(let creds):
            credentials = creds
        }

        if credentials.expiresAt < Date() {
            return .failure(.tokenExpired)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("claude-code/2.0.15", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.network("no response"))
            }
            if http.statusCode == 401 {
                return .failure(.unauthorized)
            }
            guard http.statusCode == 200 else {
                return .failure(.network("HTTP \(http.statusCode)"))
            }
            guard let snapshot = try? dateDecoder.decode(UsageSnapshot.self, from: data) else {
                return .failure(.decoding)
            }
            return .success(snapshot)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }
}
