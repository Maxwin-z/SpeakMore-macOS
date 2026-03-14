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
                historyDetail(recording)
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
                    RecordingRow(recording: recording, isSelected: selectedId == recording.objectID)
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

    // MARK: - Detail

    private func historyDetail(_ recording: Recording) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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

                Divider()

                let displayText = recording.userEditedText ?? recording.originalText ?? ""

                GroupBox("转写内容") {
                    VStack(alignment: .leading) {
                        Text(displayText)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(4)
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

                HStack(spacing: 12) {
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
            .padding(24)
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

// MARK: - Recording Row

private struct RecordingRow: View {
    let recording: Recording
    let isSelected: Bool

    private var displayText: String {
        recording.userEditedText ?? recording.originalText ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recording.title ?? String(displayText.prefix(50)))
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .lineLimit(2)

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
