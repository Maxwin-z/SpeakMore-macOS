import SwiftUI

// MARK: - Short-term Snapshot Card

struct ContextSnapshotCard: View {
    @ObservedObject var contextService: ContextProfileService
    @State private var showRawJSON = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.indigo)
                Text("近期上下文快照")
                    .font(.system(size: 14, weight: .bold))
                Spacer()

                if contextService.isSnapshotProcessing {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("刷新") {
                    Task { await contextService.refreshSnapshot() }
                }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(.indigo)
                .disabled(contextService.isSnapshotProcessing)
            }

            if let snapshot = contextService.latestSnapshot {
                VStack(alignment: .leading, spacing: 10) {
                    if let topic = snapshot.topic {
                        ContextInfoRow(label: "话题", value: topic)
                    }
                    if let intent = snapshot.currentIntent {
                        ContextInfoRow(label: "意图", value: intent)
                    }
                    if let domain = snapshot.domainFocus {
                        ContextInfoRow(label: "领域", value: domain)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("近期词汇")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        EditableTagFlowView(
                            tags: Binding(
                                get: { snapshot.recentVocabulary ?? [] },
                                set: { contextService.updateSnapshotVocabulary($0) }
                            ),
                            color: .indigo
                        )
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("实体词云")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        EditableTagFlowView(
                            tags: Binding(
                                get: { snapshot.entityCloud ?? [] },
                                set: { contextService.updateSnapshotEntityCloud($0) }
                            ),
                            color: .orange
                        )
                    }
                }

                if let date = contextService.latestSnapshotDate {
                    Text("更新于 \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Button(showRawJSON ? "收起原始数据" : "查看原始数据") {
                    withAnimation { showRawJSON.toggle() }
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)

                if showRawJSON {
                    let encoder = JSONEncoder()
                    let _ = encoder.outputFormatting = .prettyPrinted
                    let jsonText = (try? encoder.encode(snapshot)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                    Text(jsonText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.background.secondary)
                        )
                }
            } else {
                Text("暂无上下文快照。使用语音转写后将自动生成。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}

// MARK: - Long-term Profile Card

struct UserProfileCard: View {
    @ObservedObject var contextService: ContextProfileService
    @State private var showRawJSON = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.text.rectangle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                Text("用户画像")
                    .font(.system(size: 14, weight: .bold))
                Spacer()

                if contextService.isProfileProcessing {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("刷新") {
                    Task { await contextService.refreshProfile() }
                }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(.green)
                .disabled(contextService.isProfileProcessing)
            }

            if let profile = contextService.activeProfile {
                VStack(alignment: .leading, spacing: 10) {
                    if let identity = profile.identity {
                        ContextInfoRow(label: "身份", value: identity)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("主要领域")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        EditableTagFlowView(
                            tags: Binding(
                                get: { profile.primaryDomains ?? [] },
                                set: { contextService.updateProfileDomains($0) }
                            ),
                            color: .green
                        )
                    }
                    if let habits = profile.languageHabits {
                        ContextInfoRow(label: "语言习惯", value: habits)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("固定实体")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        EditableTagFlowView(
                            tags: Binding(
                                get: { profile.fixedEntities ?? [] },
                                set: { contextService.updateProfileEntities($0) }
                            ),
                            color: .orange
                        )
                    }
                }

                if let date = contextService.activeProfileDate {
                    Text("更新于 \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                Button(showRawJSON ? "收起原始数据" : "查看原始数据") {
                    withAnimation { showRawJSON.toggle() }
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)

                if showRawJSON {
                    let encoder = JSONEncoder()
                    let _ = encoder.outputFormatting = .prettyPrinted
                    let jsonText = (try? encoder.encode(profile)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                    Text(jsonText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.background.secondary)
                        )
                }
            } else {
                Text("暂无用户画像。积累足够的上下文快照后将自动生成。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}

// MARK: - Helper Views

struct ContextInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
            Text(value)
                .font(.system(size: 12))
                .textSelection(.enabled)
        }
    }
}

struct TagFlowView: View {
    let tags: [String]
    let color: Color

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 11))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(color.opacity(0.12))
                    )
            }
        }
    }
}

// MARK: - Editable Tag Flow View

struct EditableTagFlowView: View {
    @Binding var tags: [String]
    let color: Color

    @State private var editingIndex: Int? = nil
    @State private var editText = ""
    @State private var isAdding = false
    @State private var newTagText = ""

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(tags.enumerated()), id: \.offset) { index, tag in
                if editingIndex == index {
                    editTagField(index: index)
                } else {
                    tagChip(tag: tag, index: index)
                }
            }

            if isAdding {
                addTagField()
            } else {
                addButton()
            }
        }
    }

    private func tagChip(tag: String, index: Int) -> some View {
        HStack(spacing: 3) {
            Text(tag)
                .font(.system(size: 11))
                .foregroundStyle(color)

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    var updated = tags
                    updated.remove(at: index)
                    tags = updated
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(color.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 8)
        .padding(.trailing, 5)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color.opacity(0.12))
        )
        .onTapGesture(count: 2) {
            editText = tag
            editingIndex = index
        }
    }

    private func editTagField(index: Int) -> some View {
        TextField("", text: $editText, onCommit: {
            let trimmed = editText.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                tags[index] = trimmed
            }
            editingIndex = nil
            editText = ""
        })
        .font(.system(size: 11))
        .textFieldStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(minWidth: 50, maxWidth: 120)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(color.opacity(0.4), lineWidth: 1)
        )
        .onExitCommand {
            editingIndex = nil
            editText = ""
        }
    }

    private func addTagField() -> some View {
        TextField("输入词汇", text: $newTagText, onCommit: {
            let trimmed = newTagText.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                withAnimation(.easeInOut(duration: 0.15)) {
                    tags.append(trimmed)
                }
            }
            newTagText = ""
            isAdding = false
        })
        .font(.system(size: 11))
        .textFieldStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(minWidth: 60, maxWidth: 120)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(color.opacity(0.4), lineWidth: 1)
        )
        .onExitCommand {
            newTagText = ""
            isAdding = false
        }
    }

    private func addButton() -> some View {
        Button {
            isAdding = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color.opacity(0.7))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(color.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}
