import SwiftUI

struct HomeScreen: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @ObservedObject private var lang = LanguageManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer(minLength: 40)

                // Hero
                VStack(spacing: 12) {
                    Image(systemName: "mic.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                        .symbolRenderingMode(.hierarchical)

                    Text("SpeakMore Lite")
                        .font(.largeTitle.bold())

                    Text(lang.s("home.subtitle"))
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    Text(lang.s("home.description"))
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }

                // Status card
                statusCard

                // Feature cards
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ], spacing: 16) {
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

                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    statusItem(
                        icon: "hand.raised.fill",
                        title: lang.s("home.accessibility"),
                        isOK: appViewModel.isAccessibilityGranted
                    )

                    Divider()
                        .frame(height: 32)

                    statusItem(
                        icon: "cursorarrow.click.badge.clock",
                        title: lang.s("home.input_monitoring"),
                        isOK: appViewModel.permissionManager.isInputMonitoringGranted
                    )

                    Divider()
                        .frame(height: 32)

                    statusItem(
                        icon: "network",
                        title: lang.s("home.api_config"),
                        isOK: MultimodalConfigStore.shared.isConfigured
                    )

                    Divider()
                        .frame(height: 32)

                    statusItem(
                        icon: "keyboard",
                        title: lang.s("home.hotkey"),
                        isOK: true
                    )
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label(lang.s("home.system_status"), systemImage: "checkmark.shield")
        }
        .padding(.horizontal, 40)
    }

    private func statusItem(icon: String, title: String, isOK: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isOK ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(isOK ? .green : .orange)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(isOK ? lang.s("home.ready") : lang.s("home.setup_needed"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Feature Card

private struct FeatureCard: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 32, height: 32)

            Text(title)
                .font(.headline)

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
