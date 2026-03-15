import SwiftUI

struct HomeScreen: View {
    @EnvironmentObject var appViewModel: AppViewModel

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

                    Text("语音输入，让表达更自然")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    Text("按住快捷键即可开始录音，松开后自动转写，结果直接输入到当前聚焦的文本框中。")
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
                        title: "多模态转写",
                        description: "音频直接发送到云端多模态大模型，一步完成转写与增强"
                    )
                    FeatureCard(
                        icon: "keyboard",
                        title: "全局快捷键",
                        description: "在任意应用中按住快捷键即可录音，松开自动插入文字"
                    )
                    FeatureCard(
                        icon: "brain.head.profile",
                        title: "上下文感知",
                        description: "自动学习你的用词习惯和常用术语，转写越用越准确"
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
                        title: "辅助功能",
                        isOK: appViewModel.isAccessibilityGranted
                    )

                    Divider()
                        .frame(height: 32)

                    statusItem(
                        icon: "cursorarrow.click.badge.clock",
                        title: "输入监控",
                        isOK: appViewModel.permissionManager.isInputMonitoringGranted
                    )

                    Divider()
                        .frame(height: 32)

                    statusItem(
                        icon: "network",
                        title: "API 配置",
                        isOK: MultimodalConfigStore.shared.isConfigured
                    )

                    Divider()
                        .frame(height: 32)

                    statusItem(
                        icon: "keyboard",
                        title: "快捷键",
                        isOK: true
                    )
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label("系统状态", systemImage: "checkmark.shield")
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
                Text(isOK ? "已就绪" : "需配置")
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
