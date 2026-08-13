import Foundation

enum UsageState {
    case loading
    case loaded
    case noCredentials
    case tokenExpired
    case unauthorized
    case error(String)
}

struct ClockReading: Identifiable {
    let id: String
    let label: String
    let utilization: Double
    let resetsAt: Date?
}

enum DisplayMode: String, CaseIterable, Identifiable {
    case closest
    case fiveHour
    case weekly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .closest: return "Closest"
        case .fiveHour: return "5h"
        case .weekly: return "Weekly"
        }
    }
}

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var state: UsageState = .loading
    @Published private(set) var lastGood: (snapshot: UsageSnapshot, fetchedAt: Date)?

    private var didStart = false
    private var lastFetchStarted: Date?
    private let minimumRefreshInterval: TimeInterval = 15
    private var timer: Timer?

    func startAutoRefresh() {
        guard !didStart else { return }
        didStart = true
        refresh(force: true)
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(force: false)
            }
        }
    }

    func refreshOnReveal() {
        refresh(force: false)
    }

    func retry() {
        refresh(force: true)
    }

    private func refresh(force: Bool) {
        if !force, let last = lastFetchStarted, Date().timeIntervalSince(last) < minimumRefreshInterval {
            return
        }
        lastFetchStarted = Date()
        state = .loading
        Task {
            let result = await UsageClient.fetch()
            switch result {
            case .success(let snapshot):
                lastGood = (snapshot, Date())
                state = .loaded
            case .failure(.noCredentials):
                state = .noCredentials
            case .failure(.tokenExpired):
                state = .tokenExpired
            case .failure(.unauthorized):
                state = .unauthorized
            case .failure(.network(let message)):
                state = .error(message)
            case .failure(.decoding):
                state = .error("Unexpected response from Claude")
            }
        }
    }

    var clocks: [ClockReading] {
        guard let snapshot = lastGood?.snapshot else { return [] }
        var result: [ClockReading] = []
        if let fiveHour = snapshot.fiveHour {
            result.append(ClockReading(id: "5h", label: "5-hour", utilization: fiveHour.utilization, resetsAt: fiveHour.resetsAt))
        }
        if let sevenDay = snapshot.sevenDay {
            result.append(ClockReading(id: "7d", label: "Weekly", utilization: sevenDay.utilization, resetsAt: sevenDay.resetsAt))
        }
        if let sevenDayOpus = snapshot.sevenDayOpus {
            result.append(ClockReading(id: "7d-opus", label: "Weekly Opus", utilization: sevenDayOpus.utilization, resetsAt: sevenDayOpus.resetsAt))
        }
        return result
    }

    var bindingClock: ClockReading? {
        clocks.max(by: { $0.utilization < $1.utilization })
    }

    func displayedClock(for mode: DisplayMode) -> ClockReading? {
        switch mode {
        case .closest: return bindingClock
        case .fiveHour: return clocks.first { $0.id == "5h" }
        case .weekly: return clocks.first { $0.id == "7d" }
        }
    }
}
