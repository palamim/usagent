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

private func iconName(for clockID: String) -> String {
    switch clockID {
    case "5h": return "clock"
    case "7d-opus": return "sparkles"
    default: return "calendar"
    }
}

// Each severity tier gets a background/border in the same hue as its
// fill, at the same saturation/brightness relationship as the default
// blue tier — not just a colored fill on a fixed blue background.
private struct BarPalette {
    let background: Color
    let border: Color
    let fill: Color
}

private func barPalette(for percent: Double) -> BarPalette {
    if percent >= 90 {
        return BarPalette(
            background: Color(red: 0x42 / 255, green: 0x09 / 255, blue: 0x03 / 255),
            border: Color(red: 0x4D / 255, green: 0x15 / 255, blue: 0x10 / 255),
            fill: .red
        )
    }
    if percent >= 70 {
        return BarPalette(
            background: Color(red: 0x42 / 255, green: 0x36 / 255, blue: 0x03 / 255),
            border: Color(red: 0x4D / 255, green: 0x40 / 255, blue: 0x10 / 255),
            fill: .yellow
        )
    }
    return BarPalette(
        background: Color(red: 0x03 / 255, green: 0x20 / 255, blue: 0x42 / 255),
        border: Color(red: 0x10 / 255, green: 0x2B / 255, blue: 0x4C / 255),
        fill: Color(red: 0x2A / 255, green: 0x78 / 255, blue: 0xD7 / 255)
    )
}

private struct UsageBar: View {
    let percent: Double

    var body: some View {
        let palette = barPalette(for: percent)
        let fraction = min(percent, 100) / 100
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(palette.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(palette.border, lineWidth: 1)
                    )
                RoundedRectangle(cornerRadius: 3)
                    .fill(palette.fill)
                    .frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 8)
    }
}

struct MenuBarLabelView: View {
    @ObservedObject var store: UsageStore
    @AppStorage("displayMode") private var displayModeRaw: String = DisplayMode.closest.rawValue

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            switch store.state {
            case .noCredentials, .tokenExpired, .unauthorized:
                Image(systemName: "exclamationmark.triangle")
            case .error where store.lastGood == nil:
                Image(systemName: "wifi.exclamationmark")
            default:
                let mode = DisplayMode(rawValue: displayModeRaw) ?? .closest
                if let clock = store.displayedClock(for: mode) {
                    Image(systemName: iconName(for: clock.id))
                    Text("\(Int(clock.utilization.rounded()))%")
                        .foregroundStyle(severityColor(clock.utilization))
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
    @AppStorage("displayMode") private var displayModeRaw: String = DisplayMode.closest.rawValue

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

            VStack(alignment: .leading, spacing: 4) {
                Text("Menu bar shows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Menu bar shows", selection: $displayModeRaw) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
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
            }
            .font(.subheadline)

            UsageBar(percent: clock.utilization)

            Text("Resets in \(timeRemaining(until: clock.resetsAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
