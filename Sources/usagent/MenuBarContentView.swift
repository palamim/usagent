import SwiftUI

private func timeRemaining(until date: Date?) -> String {
    guard let date else { return "—" }
    let seconds = date.timeIntervalSinceNow
    if seconds <= 0 { return "now" }
    let totalMinutes = Int(seconds) / 60
    let days = totalMinutes / (24 * 60)
    let hours = (totalMinutes % (24 * 60)) / 60
    let minutes = totalMinutes % 60
    if days > 0 { return "\(days)d \(hours)h" }
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(minutes)m"
}

private func severityColor(_ percent: Double) -> Color {
    if percent >= 90 { return .red }
    if percent >= 70 { return .orange }
    return .primary
}

struct MenuBarLabelView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            switch store.state {
            case .noCredentials, .tokenExpired, .unauthorized:
                Image(systemName: "exclamationmark.triangle")
            case .error where store.lastGood == nil:
                Image(systemName: "wifi.exclamationmark")
            default:
                if let binding = store.bindingClock {
                    Image(systemName: binding.id == "5h" ? "clock" : "calendar")
                    Text("\(Int(binding.utilization.rounded()))%")
                        .foregroundStyle(severityColor(binding.utilization))
                } else {
                    Text("…")
                }
            }
        }
        .task { store.startAutoRefresh() }
    }
}

struct MenuBarContentView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claude Usage")
                .font(.headline)

            statusBanner

            if store.clocks.isEmpty && store.lastGood == nil {
                Text("No data yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.clocks) { clock in
                    ClockRow(clock: clock)
                }
            }

            if let fetchedAt = store.lastGood?.fetchedAt {
                Text("Updated \(fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button("Refresh") { store.retry() }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 260)
        .onAppear { store.refreshOnReveal() }
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch store.state {
        case .noCredentials:
            Text("Not signed in. Run `claude` once in a terminal to sign in, then reopen this app.")
                .font(.caption)
                .foregroundStyle(.orange)
        case .tokenExpired, .unauthorized:
            Text("Session expired. Run `claude` in a terminal to sign in again.")
                .font(.caption)
                .foregroundStyle(.orange)
        case .error(let message):
            Text("Couldn't reach Claude: \(message)")
                .font(.caption)
                .foregroundStyle(.orange)
        case .loading where store.lastGood == nil:
            Text("Loading…")
                .font(.caption)
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }
}

private struct ClockRow: View {
    let clock: ClockReading

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(clock.label)
                Spacer()
                Text("\(Int(clock.utilization.rounded()))%")
                    .foregroundStyle(severityColor(clock.utilization))
            }
            .font(.subheadline)

            ProgressView(value: min(clock.utilization, 100), total: 100)
                .tint(severityColor(clock.utilization))

            Text("Resets in \(timeRemaining(until: clock.resetsAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
