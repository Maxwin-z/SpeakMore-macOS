import Foundation
import CoreData

@MainActor
class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published var recordings: [Recording] = []

    private let context = PersistenceController.shared.container.viewContext

    private init() {
        fetchRecordings()
    }

    func fetchRecordings() {
        let request = NSFetchRequest<Recording>(entityName: "Recording")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        do {
            recordings = try context.fetch(request)
        } catch {
            NSLog("[HistoryStore] Fetch error: \(error)")
        }
    }

    func saveRecording(
        originalText: String,
        enhancedText: String?,
        duration: TimeInterval,
        audioSamples: [Float]?,
        sourceApp: String?,
        sttModelName: String? = nil,
        llmModelName: String? = nil
    ) {
        let recording = Recording(context: context)
        recording.id = UUID()
        recording.createdAt = Date()
        recording.originalText = originalText
        recording.enhancedText = enhancedText
        recording.durationSeconds = duration
        recording.sourceApp = sourceApp
        recording.sttModelName = sttModelName
        recording.llmModelName = llmModelName

        let displayText = enhancedText ?? originalText
        recording.title = String(displayText.prefix(50))

        if let samples = audioSamples, !samples.isEmpty {
            let filePath = saveAudioToFile(samples: samples, id: recording.id!)
            recording.audioFilePath = filePath
        }

        do {
            try context.save()
            fetchRecordings()
            NSLog("[HistoryStore] Saved recording: \(recording.id?.uuidString ?? "?")")
        } catch {
            NSLog("[HistoryStore] Save error: \(error)")
        }
    }

    func deleteRecording(_ recording: Recording) {
        if let path = recording.audioFilePath {
            try? FileManager.default.removeItem(atPath: path)
        }
        context.delete(recording)
        do {
            try context.save()
            fetchRecordings()
        } catch {
            NSLog("[HistoryStore] Delete error: \(error)")
        }
    }

    func recording(for id: UUID) -> Recording? {
        recordings.first { $0.id == id }
    }

    func updateUserEditedText(_ recording: Recording, text: String) {
        recording.objectWillChange.send()
        recording.userEditedText = text
        recording.title = String(text.prefix(50))
        do {
            try context.save()
            fetchRecordings()
        } catch {
            NSLog("[HistoryStore] Update userEditedText error: \(error)")
        }
    }

    // MARK: - Audio File Saving

    private func saveAudioToFile(samples: [Float], id: UUID) -> String? {
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let recordingsDir = appSupportURL
            .appendingPathComponent("cn.byutech.SpeakMore", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

        let fileURL = recordingsDir.appendingPathComponent("\(id.uuidString).wav")

        let sampleRate: Double = 16000
        let bitsPerSample: UInt16 = 16
        let numChannels: UInt16 = 1
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count * Int(bitsPerSample / 8))

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        var chunkSize = UInt32(36 + dataSize)
        data.append(Data(bytes: &chunkSize, count: 4))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        var subchunk1Size: UInt32 = 16
        data.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat: UInt16 = 1
        data.append(Data(bytes: &audioFormat, count: 2))
        var channels = numChannels
        data.append(Data(bytes: &channels, count: 2))
        var sRate = UInt32(sampleRate)
        data.append(Data(bytes: &sRate, count: 4))
        var bRate = byteRate
        data.append(Data(bytes: &bRate, count: 4))
        var bAlign = blockAlign
        data.append(Data(bytes: &bAlign, count: 2))
        var bps = bitsPerSample
        data.append(Data(bytes: &bps, count: 2))
        data.append(contentsOf: "data".utf8)
        var dSize = dataSize
        data.append(Data(bytes: &dSize, count: 4))
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            var int16Sample = Int16(clamped * 32767.0)
            data.append(Data(bytes: &int16Sample, count: 2))
        }

        do {
            try data.write(to: fileURL)
            return fileURL.path
        } catch {
            NSLog("[HistoryStore] Failed to write WAV: \(error)")
            return nil
        }
    }
}
