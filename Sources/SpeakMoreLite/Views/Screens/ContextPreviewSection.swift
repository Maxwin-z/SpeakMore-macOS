import SwiftUI

struct ContextPreviewSection: View {
    @ObservedObject var contextService: ContextProfileService
    @ObservedObject private var lang = LanguageManager.shared
    @State private var isExpanded = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                // User profile summary
                if let profile = contextService.activeProfile {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel(lang.s("context.user_profile"))

                        HStack(spacing: 12) {
                            if let identity = profile.identity {
                                infoTag(icon: "person.fill", text: identity, color: .green)
                            }
                            if let habits = profile.languageHabits {
                                infoTag(icon: "text.bubble", text: habits, color: .indigo)
                            }
                        }

                        if let domains = profile.primaryDomains, !domains.isEmpty {
                            TagFlowView(tags: domains, color: .green)
                        }
                    }
                }

                // Recent context summary
                if let snapshot = contextService.latestSnapshot {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel(lang.s("context.recent"))

                        HStack(spacing: 12) {
                            if let topic = snapshot.topic {
                                infoTag(icon: "bubble.left.fill", text: topic, color: .indigo)
                            }
                            if let domain = snapshot.domainFocus {
                                infoTag(icon: "scope", text: domain, color: .orange)
                            }
                        }

                        if let entities = snapshot.entityCloud, !entities.isEmpty {
                            TagFlowView(tags: Array(entities.prefix(5)), color: .orange)
                        }
                    }
                }

                if contextService.activeProfile == nil && contextService.latestSnapshot == nil {
                    Text(lang.s("context.no_data"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }

                Text(lang.s("context.auto_inject"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                // Expand/collapse
                Button(isExpanded
                       ? lang.s("context.collapse_full")
                       : lang.s("context.view_full")) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(.indigo)

                if isExpanded {
                    VStack(spacing: 12) {
                        ContextSnapshotCard(contextService: contextService)
                        UserProfileCard(contextService: contextService)
                    }
                }
            }
        } label: {
            Label(lang.s("context.dynamic"), systemImage: "brain.head.profile")
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func infoTag(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 11))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color.opacity(0.1))
        )
    }
}
