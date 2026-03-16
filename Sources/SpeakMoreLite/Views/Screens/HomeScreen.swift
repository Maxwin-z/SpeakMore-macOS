import SwiftUI
import CoreData

// MARK: - Time Range

enum DashboardTimeRange: String, CaseIterable, Identifiable {
    case week = "7d"
    case month = "30d"
    case all = "all"

    var id: String { rawValue }

    @MainActor func displayName(_ lang: LanguageManager) -> String {
        switch self {
        case .week: return lang.s("dashboard.7days")
        case .month: return lang.s("dashboard.30days")
        case .all: return lang.s("dashboard.all_time")
        }
    }

    var startDate: Date? {
        switch self {
        case .week: return Calendar.current.date(byAdding: .day, value: -7, to: Date())
        case .month: return Calendar.current.date(byAdding: .day, value: -30, to: Date())
        case .all: return nil
        }
    }
}

// MARK: - Usage Stats

struct UsageStats {
    let recordingCount: Int
    let totalDurationSeconds: Double
    let totalCharacters: Int
    /// Estimated time saved vs typing (in seconds)
    let timeSavedSeconds: Double
    /// Efficiency multiplier (typing time / voice time)
    let efficiencyMultiplier: Double

    static let empty = UsageStats(
        recordingCount: 0,
        totalDurationSeconds: 0,
        totalCharacters: 0,
        timeSavedSeconds: 0,
        efficiencyMultiplier: 1.0
    )

    /// Excellent typist speed: ~80 Chinese characters per minute
    private static let typingCharsPerSecond: Double = 80.0 / 60.0

    static func compute(from recordings: [Recording]) -> UsageStats {
        guard !recordings.isEmpty else { return .empty }

        var totalDuration: Double = 0
        var totalChars = 0

        for recording in recordings {
            totalDuration += recording.durationSeconds
            let text = recording.userEditedText ?? recording.enhancedText ?? recording.originalText ?? ""
            totalChars += text.count
        }

        let typingTimeSeconds = Double(totalChars) / typingCharsPerSecond
        let saved = max(0, typingTimeSeconds - totalDuration)
        let multiplier = totalDuration > 0 ? typingTimeSeconds / totalDuration : 1.0

        return UsageStats(
            recordingCount: recordings.count,
            totalDurationSeconds: totalDuration,
            totalCharacters: totalChars,
            timeSavedSeconds: saved,
            efficiencyMultiplier: multiplier
        )
    }
}

// MARK: - Home Screen

struct HomeScreen: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @ObservedObject private var lang = LanguageManager.shared
    @ObservedObject private var historyStore = HistoryStore.shared
    @State private var selectedRange: DashboardTimeRange = .week

    private var stats: UsageStats {
        let filtered: [Recording]
        if let start = selectedRange.startDate {
            filtered = historyStore.recordings.filter { ($0.createdAt ?? .distantPast) >= start }
        } else {
            filtered = historyStore.recordings
        }
        return UsageStats.compute(from: filtered)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 20)

                // Hero
                VStack(spacing: 6) {
                    Image(systemName: "mic.badge.plus")
                        .font(.system(size: 36))
                        .foregroundStyle(.tint)
                        .symbolRenderingMode(.hierarchical)

                    Text("SpeakMore Lite")
                        .font(.title.bold())

                    Text(lang.s("home.subtitle"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Dashboard
                dashboardSection

                // Status card
                statusCard

                // Feature cards
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    FeatureCard(
                        icon: "waveform.badge.magnifyingglass",
                        title: lang.s("home.multimodal_title"),
                        description: lang.s("home.multimodal_desc")
                    )
                    FeatureCard(
                        icon: "keyboard",
                        title: lang.s("home.hotkey_title"),
                        description: lang.s("home.hotkey_desc")
                    )
                    FeatureCard(
                        icon: "brain.head.profile",
                        title: lang.s("home.context_title"),
                        description: lang.s("home.context_desc")
                    )
                }
                .padding(.horizontal, 40)

                Spacer(minLength: 20)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Dashboard Section

    private var dashboardSection: some View {
        VStack(spacing: 10) {
            // Header with time range picker
            HStack {
                Label(lang.s("dashboard.title"), systemImage: "chart.bar.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Picker("", selection: $selectedRange) {
                    ForEach(DashboardTimeRange.allCases) { range in
                        Text(range.displayName(lang)).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            // Stats grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                StatCard(
                    icon: "mic.fill",
                    value: "\(stats.recordingCount)",
                    label: lang.s("dashboard.recordings"),
                    color: .blue
                )

                StatCard(
                    icon: "waveform",
                    value: formatDuration(stats.totalDurationSeconds),
                    label: lang.s("dashboard.voice_duration"),
                    color: .purple
                )

                StatCard(
                    icon: "character.cursor.ibeam",
                    value: formatCharCount(stats.totalCharacters),
                    label: lang.s("dashboard.chars_recognized"),
                    color: .orange
                )

                StatCard(
                    icon: "clock.arrow.circlepath",
                    value: formatTimeSaved(stats.timeSavedSeconds),
                    label: lang.s("dashboard.time_saved"),
                    color: .green
                )
            }

            // Efficiency bar
            if stats.recordingCount > 0 {
                efficiencyBar
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Efficiency Bar

    private var efficiencyBar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text(lang.s("dashboard.efficiency"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1fx", stats.efficiencyMultiplier))
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }

            GeometryReader { geo in
                let fraction = min(stats.efficiencyMultiplier / 10.0, 1.0)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 6)

            HStack {
                Text(lang.s("dashboard.efficiency_desc"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Formatting Helpers

    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%ds", Int(seconds))
        } else if seconds < 3600 {
            let m = Int(seconds) / 60
            let s = Int(seconds) % 60
            return String(format: "%dm%ds", m, s)
        } else {
            let h = Int(seconds) / 3600
            let m = (Int(seconds) % 3600) / 60
            return String(format: "%dh%dm", h, m)
        }
    }

    private func formatCharCount(_ count: Int) -> String {
        if count < 1000 {
            return "\(count)"
        } else if count < 10000 {
            return String(format: "%.1fk", Double(count) / 1000.0)
        } else {
            return String(format: "%.0fk", Double(count) / 1000.0)
        }
    }

    private func formatTimeSaved(_ seconds: Double) -> String {
        if seconds < 60 {
            return String(format: "%ds", Int(seconds))
        } else if seconds < 3600 {
            return String(format: "%dm", Int(seconds) / 60)
        } else {
            let h = Int(seconds) / 3600
            let m = (Int(seconds) % 3600) / 60
            return m > 0 ? String(format: "%dh%dm", h, m) : String(format: "%dh", h)
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        GroupBox {
            HStack(spacing: 0) {
                permissionItem(
                    icon: "hand.raised.fill",
                    title: lang.s("home.accessibility"),
                    isGranted: appViewModel.isAccessibilityGranted,
                    action: {
                        appViewModel.permissionManager.requestAccessibilityPermission()
                    }
                )

                Divider()
                    .frame(height: 40)

                permissionItem(
                    icon: "cursorarrow.click.badge.clock",
                    title: lang.s("home.input_monitoring"),
                    isGranted: appViewModel.permissionManager.isInputMonitoringGranted,
                    action: {
                        appViewModel.permissionManager.requestInputMonitoringPermission()
                        if !appViewModel.permissionManager.isInputMonitoringGranted {
                            appViewModel.permissionManager.openInputMonitoringSettings()
                        }
                    }
                )
            }
            .padding(.vertical, 4)
        } label: {
            HStack {
                Label(lang.s("home.system_status"), systemImage: "checkmark.shield")
                Spacer()
                Button {
                    appViewModel.permissionManager.checkAllPermissions()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help(lang.s("home.refresh_status"))
            }
        }
        .padding(.horizontal, 40)
        .onAppear {
            appViewModel.permissionManager.checkAllPermissions()
        }
    }

    private func permissionItem(icon: String, title: String, isGranted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(isGranted ? .green : .orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(isGranted ? lang.s("home.ready") : lang.s("home.setup_needed"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !isGranted {
                Button(lang.s("settings.authorize")) {
                    action()
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(color)
                .frame(width: 22, height: 22)

            Text(value)
                .font(.system(.title3, design: .rounded).bold())
                .foregroundStyle(.primary)
                .contentTransition(.numericText())

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.06))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(color.opacity(0.12), lineWidth: 0.5)
        }
    }
}

// MARK: - Feature Card

private struct FeatureCard: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 24, height: 24)

            Text(title)
                .font(.subheadline.weight(.semibold))

            Text(description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
