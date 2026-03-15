import Foundation
import CoreData
import AVFoundation

@MainActor
class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published var recordings: [Recording] = []

    // Audio playback
    @Published var playingRecordingId: UUID?
    @Published var playbackProgress: Double = 0
    private var audioPlayer: AVAudioPlayer?
    private var playbackTimer: Timer?

    // Re-recognition state
    @Published var isReRecognizing = false
    @Published var reRecognizingText = ""

    private let context = PersistenceController.shared.container.viewContext
    private let multimodalService = MultimodalService()

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

    // MARK: - Audio Playback

    func playAudio(for recording: Recording) {
        guard let path = recording.audioFilePath else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            NSLog("[HistoryStore] Audio file not found: \(path)")
            return
        }

        stopAudio()

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.play()
            audioPlayer = player
            playingRecordingId = recording.id

            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self, let player = self.audioPlayer else { return }
                    if player.isPlaying {
                        self.playbackProgress = player.currentTime / max(player.duration, 0.01)
                    } else {
                        self.stopAudio()
                    }
                }
            }
        } catch {
            NSLog("[HistoryStore] Audio playback error: \(error)")
        }
    }

    func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        playbackTimer?.invalidate()
        playbackTimer = nil
        playingRecordingId = nil
        playbackProgress = 0
    }

    var isPlaying: Bool {
        audioPlayer?.isPlaying == true
    }

    // MARK: - Transcription Results

    func fetchTranscriptionResults(for recording: Recording) -> [TranscriptionResult] {
        guard let results = recording.transcriptionResults as? Set<TranscriptionResult> else {
            return []
        }
        return results.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
    }

    func reRecognize(
        recording: Recording,
        model: AvailableModel,
        contextLevel: ContextLevel
    ) async {
        guard let audioPath = recording.audioFilePath,
              FileManager.default.fileExists(atPath: audioPath) else {
            NSLog("[HistoryStore] No audio file for re-recognition")
            return
        }

        isReRecognizing = true
        reRecognizingText = ""

        defer {
            isReRecognizing = false
        }

        // Load audio samples from WAV file
        guard let samples = loadAudioSamples(from: audioPath) else {
            NSLog("[HistoryStore] Failed to load audio samples")
            return
        }

        // Build config for the selected model
        let baseConfig = MultimodalConfigStore.shared.config
        let config = model.buildConfig(from: baseConfig)

        // Build system prompt with context level
        let glossaryTerms = PromptStore.shared.config.glossaryTerms
        let systemPrompt = ContextProfileService.shared.buildSystemPrompt(
            contextLevel: contextLevel,
            sourceApp: recording.sourceApp,
            glossaryTerms: glossaryTerms
        )

        NSLog("[HistoryStore] Re-recognizing: model=\(model.displayName), contextLevel=\(contextLevel.displayName)")

        var fullText = ""
        do {
            for try await chunk in multimodalService.stream(audioSamples: samples, systemPrompt: systemPrompt, config: config) {
                fullText += chunk
                reRecognizingText = fullText
            }
        } catch {
            NSLog("[HistoryStore] Re-recognition error: \(error)")
            if fullText.isEmpty {
                reRecognizingText = "识别失败: \(error.localizedDescription)"
                return
            }
        }

        // Save as TranscriptionResult
        let result = TranscriptionResult(context: context)
        result.id = UUID()
        result.createdAt = Date()
        result.text = fullText
        result.modelName = model.model.displayName
        result.providerName = model.provider.displayName
        result.contextLevel = Int16(contextLevel.rawValue)
        result.recording = recording

        do {
            try context.save()
            objectWillChange.send()
            NSLog("[HistoryStore] Saved re-recognition result")
        } catch {
            NSLog("[HistoryStore] Save re-recognition error: \(error)")
        }
    }

    func deleteTranscriptionResult(_ result: TranscriptionResult) {
        context.delete(result)
        do {
            try context.save()
            objectWillChange.send()
        } catch {
            NSLog("[HistoryStore] Delete transcription result error: \(error)")
        }
    }

    // MARK: - Load Audio Samples from WAV

    private func loadAudioSamples(from path: String) -> [Float]? {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else { return nil }

        // Parse WAV header (44 bytes) and extract PCM samples
        guard data.count > 44 else { return nil }
        let audioData = data.subdata(in: 44..<data.count)
        let sampleCount = audioData.count / 2 // 16-bit samples

        var samples = [Float](repeating: 0, count: sampleCount)
        audioData.withUnsafeBytes { buffer in
            let int16Buffer = buffer.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                samples[i] = Float(int16Buffer[i]) / 32767.0
            }
        }
        return samples
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
