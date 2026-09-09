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
    // Max-only: a separate weekly sub-cap on Opus specifically, tighter
    // than the general weekly cap. Null on Pro.
    let sevenDayOpus: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
    }
}

enum UsageFetchError: Error {
    case noCredentials
    case tokenExpired
    case unauthorized
    case network(String)
    case decoding
}

protocol UsageFetching: Sendable {
    func fetch() async -> Result<UsageSnapshot, UsageFetchError>
}

struct UsageClient: UsageFetching {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    // Refresh proactively this far ahead of expiry, so a 60s-cadence poller
    // doesn't race the token expiring mid-request.
    private static let refreshBuffer: TimeInterval = 60

    private let tokenRefresher: TokenRefreshing

    init(tokenRefresher: TokenRefreshing = TokenRefresher()) {
        self.tokenRefresher = tokenRefresher
    }

    private static let dateDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = formatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date: \(string)")
            }
            return date
        }
        return decoder
    }()

    func fetch() async -> Result<UsageSnapshot, UsageFetchError> {
        var credentials: ClaudeCredentials
        switch CredentialsStore.read() {
        case .failure:
            return .failure(.noCredentials)
        case .success(let creds):
            credentials = creds
        }

        if credentials.expiresAt < Date().addingTimeInterval(Self.refreshBuffer) {
            switch await tokenRefresher.refresh(refreshToken: credentials.refreshToken) {
            case .success(let refreshed):
                credentials = ClaudeCredentials(
                    accessToken: refreshed.accessToken,
                    refreshToken: refreshed.refreshToken,
                    expiresAt: refreshed.expiresAt
                )
                CredentialsStore.write(
                    accessToken: refreshed.accessToken,
                    refreshToken: refreshed.refreshToken,
                    expiresAt: refreshed.expiresAt
                )
            case .failure:
                // Refresh failed — only fatal if the token we already have
                // is actually expired; otherwise fall through and use it,
                // since it's still good for up to refreshBuffer longer.
                if credentials.expiresAt < Date() {
                    return .failure(.tokenExpired)
                }
            }
        }

        let result = await performRequest(accessToken: credentials.accessToken)

        // The proactive refresh above should make this rare, but the server
        // is the final authority: if it says the token is bad despite our
        // bookkeeping, try one refresh-and-retry before giving up.
        guard case .failure(.unauthorized) = result else {
            return result
        }
        guard case .success(let refreshed) = await tokenRefresher.refresh(refreshToken: credentials.refreshToken) else {
            return result
        }
        CredentialsStore.write(
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken,
            expiresAt: refreshed.expiresAt
        )
        return await performRequest(accessToken: refreshed.accessToken)
    }

    private func performRequest(accessToken: String) async -> Result<UsageSnapshot, UsageFetchError> {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("claude-code/2.0.15", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
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
            guard let snapshot = try? Self.dateDecoder.decode(UsageSnapshot.self, from: data) else {
                return .failure(.decoding)
            }
            return .success(snapshot)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }
}
