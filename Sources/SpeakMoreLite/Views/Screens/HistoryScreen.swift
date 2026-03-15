import SwiftUI
import CoreData

struct HistoryScreen: View {
    @StateObject private var historyStore = HistoryStore.shared
    @State private var selectedId: NSManagedObjectID?

    var body: some View {
        HSplitView {
            historyList
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

            if let id = selectedId,
               let recording = historyStore.recordings.first(where: { $0.objectID == id }) {
                HistoryDetailView(recording: recording, historyStore: historyStore, selectedId: $selectedId)
            } else {
                emptyDetail
            }
        }
        .onAppear {
            historyStore.fetchRecordings()
        }
    }

    // MARK: - List

    private var historyList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("录音记录")
                    .font(.headline)
                Spacer()
                Text("\(historyStore.recordings.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if historyStore.recordings.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "waveform.slash")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                    Text("暂无录音记录")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    Text("按住快捷键开始录音")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(historyStore.recordings, id: \.objectID, selection: $selectedId) { recording in
                    RecordingRow(recording: recording, isSelected: selectedId == recording.objectID, historyStore: historyStore)
                        .tag(recording.objectID)
                        .contextMenu {
                            Button {
                                let text = recording.userEditedText ?? recording.originalText ?? ""
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(text, forType: .string)
                            } label: {
                                Label("复制文本", systemImage: "doc.on.doc")
                            }

                            Divider()

                            Button(role: .destructive) {
                                if selectedId == recording.objectID {
                                    selectedId = nil
                                }
                                historyStore.deleteRecording(recording)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var emptyDetail: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("选择一条记录查看详情")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Detail View

private struct HistoryDetailView: View {
    let recording: Recording
    @ObservedObject var historyStore: HistoryStore
    @Binding var selectedId: NSManagedObjectID?

    @StateObject private var multimodalStore = MultimodalConfigStore.shared
    @State private var selectedModel: AvailableModel?
    @State private var contextLevel: ContextLevel = .none

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection

                // Audio player
                if recording.audioFilePath != nil {
                    audioPlayerSection
                }

                // Model & context level info
                HStack(spacing: 8) {
                    if let model = recording.sttModelName {
                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                                .font(.caption2)
                            Text(model)
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }

                    let level = ContextLevel(rawValue: Int(recording.contextLevelUsed)) ?? .none
                    HStack(spacing: 4) {
                        Image(systemName: "brain")
                            .font(.caption2)
                        Text(level.displayName)
                            .font(.caption)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(contextLevelColor(level), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                // Context layers debug section
                contextLayersSection

                Divider()

                // Original transcription
                originalTranscriptionSection

                // Re-recognition results
                reRecognitionResultsSection

                Divider()

                // Re-recognition controls
                if recording.audioFilePath != nil {
                    reRecognitionSection
                }

                // Actions
                actionsSection
            }
            .padding(24)
        }
        .onAppear {
            if selectedModel == nil {
                selectedModel = multimodalStore.currentAvailableModel
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recording.title ?? "无标题")
                .font(.title2.weight(.semibold))
                .lineLimit(2)

            HStack(spacing: 12) {
                if let date = recording.createdAt {
                    Label(formatDate(date), systemImage: "calendar")
                }
                Label(formatDuration(recording.durationSeconds), systemImage: "clock")
                if let app = recording.sourceApp, !app.isEmpty {
                    Label(app, systemImage: "app")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Audio Player

    private var audioPlayerSection: some View {
        let isThisPlaying = historyStore.playingRecordingId == recording.id

        return HStack(spacing: 12) {
            Button {
                if isThisPlaying {
                    historyStore.stopAudio()
                } else {
                    historyStore.playAudio(for: recording)
                }
            } label: {
                Image(systemName: isThisPlaying ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isThisPlaying ? .red : .accentColor)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.1))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(isThisPlaying ? Color.accentColor : Color.clear)
                            .frame(width: geo.size.width * (isThisPlaying ? historyStore.playbackProgress : 0), height: 4)
                    }
                }
                .frame(height: 4)

                Text(formatDuration(recording.durationSeconds))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Original Transcription

    private var originalTranscriptionSection: some View {
        let displayText = recording.userEditedText ?? recording.originalText ?? ""

        return VStack(alignment: .leading, spacing: 8) {
            GroupBox {
                VStack(alignment: .leading) {
                    Text(displayText)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(4)
            } label: {
                HStack {
                    Text("转写内容")
                    Spacer()
                    if let model = recording.sttModelName {
                        Text(model)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if let userEdited = recording.userEditedText, !userEdited.isEmpty,
               let original = recording.originalText, !original.isEmpty,
               userEdited != original {
                GroupBox("原始转写") {
                    VStack(alignment: .leading) {
                        Text(original)
                            .font(.body)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(4)
                }
            }
        }
    }

    // MARK: - Re-recognition Results

    private var reRecognitionResultsSection: some View {
        let results = historyStore.fetchTranscriptionResults(for: recording)

        return Group {
            if !results.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("重新识别记录")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    ForEach(results, id: \.objectID) { result in
                        TranscriptionResultCard(result: result, onDelete: {
                            historyStore.deleteTranscriptionResult(result)
                        })
                    }
                }
            }

            if historyStore.isReRecognizing {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在识别...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !historyStore.reRecognizingText.isEmpty {
                            Text(historyStore.reRecognizingText)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(4)
                } label: {
                    Text("识别中...")
                }
            }
        }
    }

    // MARK: - Re-recognition Controls

    private var reRecognitionSection: some View {
        let models = multimodalStore.availableModels

        return GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                // Model picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("选择模型")
                        .font(.subheadline.weight(.medium))

                    if models.isEmpty {
                        Text("请先在设置中配置 API Key")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Picker("模型", selection: $selectedModel) {
                            ForEach(models) { model in
                                Text(model.displayName)
                                    .tag(Optional(model))
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }

                // Context level slider
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("上下文级别")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(contextLevel.displayName)
                            .font(.caption.weight(.medium))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.1), in: Capsule())
                    }

                    Slider(
                        value: Binding(
                            get: { Double(contextLevel.rawValue) },
                            set: { contextLevel = ContextLevel(rawValue: Int($0)) ?? .none }
                        ),
                        in: 0...3,
                        step: 1
                    )

                    HStack {
                        ForEach(ContextLevel.allCases) { level in
                            VStack(spacing: 2) {
                                Circle()
                                    .fill(contextLevel.rawValue >= level.rawValue ? Color.accentColor : Color.primary.opacity(0.15))
                                    .frame(width: 6, height: 6)
                                Text(level.displayName)
                                    .font(.system(size: 9))
                                    .foregroundStyle(contextLevel == level ? .primary : .tertiary)
                            }
                            if level != ContextLevel.allCases.last {
                                Spacer()
                            }
                        }
                    }

                    Text(contextLevel.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Re-recognize button
                Button {
                    guard let model = selectedModel else { return }
                    Task {
                        await historyStore.reRecognize(
                            recording: recording,
                            model: model,
                            contextLevel: contextLevel
                        )
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("重新识别")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(selectedModel == nil || historyStore.isReRecognizing || models.isEmpty)
            }
        } label: {
            Label("重新识别", systemImage: "arrow.triangle.2.circlepath")
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        let displayText = recording.userEditedText ?? recording.originalText ?? ""

        return HStack(spacing: 12) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(displayText, forType: .string)
            } label: {
                Label("复制文本", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(role: .destructive) {
                selectedId = nil
                historyStore.deleteRecording(recording)
            } label: {
                Label("删除", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Context Layers Debug

    @State private var isSystemPromptExpanded = false

    private var contextLayersSection: some View {
        let level = ContextLevel(rawValue: Int(recording.contextLevelUsed)) ?? .none

        return GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                // Context level breakdown
                HStack(spacing: 0) {
                    ForEach(ContextLevel.allCases) { l in
                        if l != .none {
                            contextLayerChip(l, active: level.rawValue >= l.rawValue)
                            if l != .longTerm { Spacer() }
                        }
                    }
                }

                // Duration → level explanation
                let durationStr = String(format: "%.1f", recording.durationSeconds)
                let rule: String = {
                    if recording.durationSeconds >= 45 {
                        return "\(durationStr)s ≥ 45s → 全部上下文"
                    } else if recording.durationSeconds >= 15 {
                        return "\(durationStr)s ≥ 15s → 基础 + 近期上下文"
                    } else {
                        return "\(durationStr)s < 15s → 仅基础上下文"
                    }
                }()
                Text(rule)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // System prompt (collapsible)
                if let prompt = recording.systemPromptUsed, !prompt.isEmpty {
                    Divider()

                    DisclosureGroup("System Prompt", isExpanded: $isSystemPromptExpanded) {
                        Text(prompt)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .font(.caption.weight(.medium))
                }
            }
            .padding(4)
        } label: {
            Label("上下文层级", systemImage: "square.3.layers.3d")
        }
    }

    private func contextLayerChip(_ level: ContextLevel, active: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: active ? "checkmark.circle.fill" : "circle")
                .font(.caption2)
            Text(level.displayName)
                .font(.caption)
        }
        .foregroundStyle(active ? .primary : .tertiary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            active ? contextLevelColor(level).opacity(0.15) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }

    private func contextLevelColor(_ level: ContextLevel) -> Color {
        switch level {
        case .none: return .gray
        case .realtime: return .blue
        case .shortTerm: return .orange
        case .longTerm: return .purple
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else if calendar.isDateInYesterday(date) {
            return "昨天"
        } else {
            formatter.dateFormat = "MM/dd"
        }
        return formatter.string(from: date)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Transcription Result Card

private struct TranscriptionResultCard: View {
    let result: TranscriptionResult
    let onDelete: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text(result.text ?? "")
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    Button {
                        let text = result.text ?? ""
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(4)
        } label: {
            HStack(spacing: 8) {
                if let provider = result.providerName, let model = result.modelName {
                    Text("\(provider) - \(model)")
                        .font(.caption2.weight(.medium))
                } else if let model = result.modelName {
                    Text(model)
                        .font(.caption2.weight(.medium))
                }

                let level = ContextLevel(rawValue: Int(result.contextLevel)) ?? .none
                Text(level.displayName)
                    .font(.caption2)
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.1), in: Capsule())

                Spacer()

                if let date = result.createdAt {
                    Text(formatResultDate(date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func formatResultDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Recording Row

private struct RecordingRow: View {
    let recording: Recording
    let isSelected: Bool
    @ObservedObject var historyStore: HistoryStore

    private var displayText: String {
        recording.userEditedText ?? recording.originalText ?? ""
    }

    private var hasAudio: Bool {
        recording.audioFilePath != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if hasAudio {
                    Image(systemName: "waveform")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }
                Text(recording.title ?? String(displayText.prefix(50)))
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(formatDuration(recording.durationSeconds))
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)

                if let app = recording.sourceApp, !app.isEmpty {
                    Text(app)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Show re-recognition count
                let resultCount = historyStore.fetchTranscriptionResults(for: recording).count
                if resultCount > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 8))
                        Text("\(resultCount)")
                            .font(.caption2)
                    }
                    .foregroundColor(.accentColor)
                }

                Spacer()

                if let date = recording.createdAt {
                    Text(formatDate(date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else if calendar.isDateInYesterday(date) {
            return "昨天"
        } else {
            formatter.dateFormat = "MM/dd"
        }
        return formatter.string(from: date)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
