import Foundation
import AppKit
import ApplicationServices
import Combine

/// Application state machine
enum AppState: Equatable {
    case idle
    case recording
    case transcribing
    case inserting
    case showingResult(String)

    static func == (lhs: AppState, rhs: AppState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.recording, .recording),
             (.transcribing, .transcribing), (.inserting, .inserting):
            return true
        case (.showingResult(let a), .showingResult(let b)):
            return a == b
        default:
            return false
        }
    }
}

@MainActor
class AppViewModel: ObservableObject {

    @Published var state: AppState = .idle
    @Published var recordingDuration: String = "00:00"

    let permissionManager = PermissionManager()

    private let hotkeyService = HotkeyService()
    private let textInsertionService = TextInsertionService()
    private let multimodalService = MultimodalService()
    private let contextProfileService = ContextProfileService.shared

    var currentHotkeyConfig: HotkeyConfig {
        hotkeyService.currentConfig
    }

    private lazy var recordingOverlay = RecordingOverlayPanel()
    private lazy var textEditorPanel = TextEditorPanel()
    private lazy var floatingWidgetPanel = FloatingWidgetPanel()
    private lazy var historyPopoverPanel = HistoryPopoverPanel()

    @Published var isWidgetVisible: Bool = UserDefaults.standard.bool(forKey: "SpeakMore.widgetVisible") {
        didSet {
            UserDefaults.standard.set(isWidgetVisible, forKey: "SpeakMore.widgetVisible")
            if isWidgetVisible {
                showFloatingWidget()
            } else {
                historyPopoverPanel.hideAnimated()
                floatingWidgetPanel.orderOut(nil)
            }
        }
    }

    private var audioRecorder: AudioRecorderService?
    private var audioBuffer: [Float] = []
    private let bufferLock = NSLock()
    private var recordingStartTime: Date?
    private var durationTimer: Timer?

    private var lastSavedRecordingId: UUID?
    private var currentFullResponse: String = ""
    private var lastRecordingSamples: [Float]?
    private var lastRecordingDuration: TimeInterval = 0

    // Buffered insertion: accumulate SSE chunks and flush in batches
    private var insertionBuffer = ""
    private var isFlushingBuffer = false
    private var streamingTask: Task<Void, Never>?

    init() {
        NSLog("[AppViewModel] init() called")
        setupHotkeyCallbacks()
        permissionManager.checkAllPermissions()
        if !permissionManager.isInputMonitoringGranted {
            permissionManager.requestInputMonitoringPermission()
        }
        hotkeyService.start()
        setupFloatingWidget()
    }

    // MARK: - Permission Checks (for UI)

    var isAccessibilityGranted: Bool {
        permissionManager.isAccessibilityGranted
    }

    var isFnKeyConfigured: Bool {
        permissionManager.isFnKeyConfiguredCorrectly
    }

    func checkPermissions() {
        permissionManager.checkAllPermissions()
    }

    func requestAccessibilityPermission() {
        permissionManager.requestAccessibilityPermission()
    }

    func openKeyboardSettings() {
        permissionManager.openKeyboardSettings()
    }

    // MARK: - Hotkey Callbacks

    private func setupHotkeyCallbacks() {
        hotkeyService.onHotkeyDown = { [weak self] in
            self?.textInsertionService.captureFocusedElement()
            Task { @MainActor in
                self?.handleHotkeyDown()
            }
        }
        hotkeyService.onHotkeyUp = { [weak self] in
            Task { @MainActor in
                self?.handleHotkeyUp()
            }
        }
    }

    func updateHotkey(_ config: HotkeyConfig) {
        hotkeyService.updateHotkey(config)
        objectWillChange.send()
    }

    private func handleHotkeyDown() {
        DebugLogger.shared.log("[App] Hotkey DOWN: state=\(state)")

        if case .showingResult = state {
            textEditorPanel.hideAnimated()
            recordingOverlay.hideAnimated()
            state = .idle
        }

        guard state == .idle else { return }

        historyPopoverPanel.hideAnimated()

        if !MultimodalConfigStore.shared.isConfigured {
            recordingOverlay.showLoadingHint(L("error.configure_api"))
            return
        }

        startRecording()
    }

    private func handleHotkeyUp() {
        DebugLogger.shared.log("[App] Hotkey UP: state=\(state)")
        guard state == .recording else { return }
        stopRecordingAndTranscribe()
    }

    // MARK: - Recording

    private func startRecording() {
        audioBuffer.removeAll()

        let recorder = AudioRecorderService()
        recorder.onAudioSamples = { [weak self] samples in
            guard let self = self else { return }
            self.bufferLock.lock()
            self.audioBuffer.append(contentsOf: samples)
            self.bufferLock.unlock()
        }
        recorder.onAudioLevel = { [weak self] level in
            Task { @MainActor in
                self?.recordingOverlay.updateAudioLevel(level)
            }
        }

        do {
            try recorder.startRecording()
            audioRecorder = recorder
            state = .recording
            recordingStartTime = Date()
            startDurationTimer()
            recordingOverlay.showCentered()
            DebugLogger.shared.log("[App] Recording started")
        } catch {
            DebugLogger.shared.log("[App] Recording failed: \(error)")
            state = .idle
        }
    }

    private func stopRecordingAndTranscribe() {
        audioRecorder?.stopRecording()
        audioRecorder = nil
        durationTimer?.invalidate()
        durationTimer = nil

        lastRecordingDuration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0

        bufferLock.lock()
        let samples = audioBuffer
        audioBuffer.removeAll()
        bufferLock.unlock()

        lastRecordingSamples = samples

        guard !samples.isEmpty else {
            recordingOverlay.hideAnimated()
            state = .idle
            return
        }

        state = .transcribing
        recordingOverlay.showTranscribing(duration: lastRecordingDuration, onCancel: { [weak self] in
            Task { @MainActor in self?.cancelTranscription() }
        })

        DebugLogger.shared.log("[App] Using multimodal transcription for \(samples.count) samples...")
        streamingTask = Task {
            await streamMultimodalResponse(samples: samples)
        }
    }

    private func cancelTranscription() {
        DebugLogger.shared.log("[App] User cancelled transcription")
        streamingTask?.cancel()
        streamingTask = nil
        recordingOverlay.hideAnimated()
        textEditorPanel.hideAnimated()
        textInsertionService.clearCapturedElement()
        state = .idle
    }

    // MARK: - Buffered Insertion

    private func flushInsertionBuffer() async {
        guard !insertionBuffer.isEmpty, !isFlushingBuffer else { return }
        isFlushingBuffer = true

        var text = insertionBuffer
        var remaining = ""

        // Hold back potential partial closing </transcription> tag
        let closeTag = "</transcription>"
        if text.contains(closeTag) {
            text = text.replacingOccurrences(of: closeTag, with: "")
        } else if let ltIdx = text.lastIndex(of: "<") {
            let suffix = String(text[ltIdx...])
            if closeTag.hasPrefix(suffix) {
                remaining = suffix
                text = String(text[..<ltIdx])
            }
        }

        insertionBuffer = remaining

        if !text.isEmpty {
            let result = await textInsertionService.insertText(text, allowClipboard: false)
            DebugLogger.shared.log("[App] Buffered insertion (\(text.count) chars): \(result)")
            if case .failed = result {
                // Re-enqueue for retry; final drain will use clipboard as last resort
                insertionBuffer = text + insertionBuffer
                DebugLogger.shared.log("[App] Re-enqueued failed chunk for final drain")
            }
        }

        isFlushingBuffer = false
    }

    // MARK: - Multimodal Transcription

    private func streamMultimodalResponse(samples: [Float]) async {
        guard !Task.isCancelled else { return }
        state = .inserting
        currentFullResponse = ""
        DebugLogger.shared.log("[App] State → inserting (multimodal streaming)")

        textInsertionService.captureFocusedElement()

        let hasTextInput = textInsertionService.hasCapturedTextInput()
        let usePanel = !hasTextInput

        if usePanel {
            DebugLogger.shared.log("[App] No text field focused, using streaming editor panel")
            textEditorPanel.showStreaming(
                onClose: { [weak self] in
                    Task { @MainActor in self?.handleEditorClose() }
                },
                onCopy: { [weak self] editedText in
                    Task { @MainActor in self?.handleEditorCopy(editedText: editedText) }
                },
                onApply: { [weak self] editedText in
                    Task { @MainActor in self?.handleEditorApply(editedText: editedText) }
                }
            )
        }

        // Build system prompt using context layers
        let sourceApp = textInsertionService.capturedAppBundleId
        let realtimeContext = RealtimeContext(
            appName: textInsertionService.capturedAppName,
            bundleId: sourceApp,
            windowTitle: textInsertionService.capturedWindowTitle,
            documentPath: textInsertionService.capturedDocumentPath
        )

        let baseInstruction = PromptStore.shared.config.baseInstruction
        let appPrompt = PromptStore.shared.resolveAppPrompt(forApp: sourceApp)
        let glossaryTerms = PromptStore.shared.config.glossaryTerms
        let contextLevel = ContextProfileService.contextLevel(forDuration: lastRecordingDuration)
        DebugLogger.shared.log("[App] Recording duration: \(String(format: "%.1f", lastRecordingDuration))s → context level: \(contextLevel.displayName)")
        let systemPrompt = contextProfileService.buildEnhancedSystemPrompt(
            baseInstruction: baseInstruction,
            appPrompt: appPrompt,
            realtimeContext: realtimeContext,
            glossaryTerms: glossaryTerms,
            contextLevel: contextLevel
        )

        DebugLogger.shared.log("[App] === 多模态完整提示词 ===")
        DebugLogger.shared.log("[App] [System Prompt]\n\(systemPrompt)")
        DebugLogger.shared.log("[App] === 提示词结束 ===")

        if !usePanel {
            textInsertionService.captureInsertionStart()
        }

        var fullResponse = ""
        var streamFailed = false
        var isFirstChunk = true

        // Tag stripping state for streaming
        var tagBuffer = ""
        var isOpenTagStripped = false
        let openTag = "<transcription>"
        let closeTag = "</transcription>"

        // Reset insertion buffer
        insertionBuffer = ""
        isFlushingBuffer = false

        // Start a concurrent flush task for buffered insertion (non-panel mode only)
        let flushTask: Task<Void, Never>? = usePanel ? nil : Task { @MainActor [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000) // 30ms flush interval
                await self.flushInsertionBuffer()
            }
        }

        do {
            let multimodalConfig = MultimodalConfigStore.shared.config
            for try await chunk in multimodalService.stream(audioSamples: samples, systemPrompt: systemPrompt, config: multimodalConfig) {
                if isFirstChunk {
                    recordingOverlay.onStreamingStarted()
                    isFirstChunk = false
                }

                fullResponse += chunk
                recordingOverlay.bumpStreamingProgress()

                // Strip opening <transcription> tag from stream
                var processedChunk: String
                if isOpenTagStripped {
                    processedChunk = chunk
                } else {
                    tagBuffer += chunk
                    if tagBuffer.hasPrefix(openTag) && tagBuffer.count >= openTag.count {
                        isOpenTagStripped = true
                        processedChunk = String(tagBuffer.dropFirst(openTag.count))
                        if processedChunk.hasPrefix("\n") { processedChunk = String(processedChunk.dropFirst()) }
                        tagBuffer = ""
                    } else if openTag.hasPrefix(tagBuffer) {
                        continue // Still buffering, could be partial tag
                    } else {
                        // Not a tag, flush buffer as-is
                        isOpenTagStripped = true
                        processedChunk = tagBuffer
                        tagBuffer = ""
                    }
                }

                if !processedChunk.isEmpty {
                    if usePanel {
                        textEditorPanel.appendStreamingText(processedChunk)
                    } else {
                        insertionBuffer += processedChunk
                    }
                }
            }

            // Flush any remaining tag buffer
            if !tagBuffer.isEmpty {
                if usePanel {
                    textEditorPanel.appendStreamingText(tagBuffer)
                } else {
                    insertionBuffer += tagBuffer
                }
            }

            DebugLogger.shared.log("[App] Multimodal stream completed, total: \"\(fullResponse.prefix(100))\"")
        } catch {
            DebugLogger.shared.log("[App] Multimodal API error: \(error)")
            streamFailed = true
        }

        // Stop flush task and wait for in-flight flush to complete
        flushTask?.cancel()
        await flushTask?.value
        isFlushingBuffer = false

        // Drain remaining buffer (clipboard allowed as one-shot fallback)
        if !insertionBuffer.isEmpty {
            var remaining = insertionBuffer
            insertionBuffer = ""
            // Strip closing transcription tag from final buffer
            if remaining.contains(closeTag) {
                remaining = remaining.replacingOccurrences(of: closeTag, with: "")
            }
            remaining = remaining.trimmingCharacters(in: .newlines)
            if !remaining.isEmpty {
                let result = await textInsertionService.insertText(remaining)
                DebugLogger.shared.log("[App] Final buffer flush (\(remaining.count) chars): \(result)")
            }
        }

        // Strip transcription tags from full response
        fullResponse = MultimodalService.stripTranscriptionTags(fullResponse)
        currentFullResponse = fullResponse

        // Update panel text with cleaned content (strip any closing tag)
        if usePanel {
            textEditorPanel.textProvider.editableText = fullResponse
        }

        recordingOverlay.finishProgress()
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Early exit if cancelled by user
        guard !Task.isCancelled else {
            flushTask?.cancel()
            if usePanel { textEditorPanel.hideAnimated() }
            textInsertionService.clearCapturedElement()
            return
        }

        // Record utterance for context profiling
        if !fullResponse.isEmpty {
            contextProfileService.recordUtterance(
                text: fullResponse,
                sourceApp: textInsertionService.capturedAppName,
                bundleId: sourceApp
            )
        }

        // Save to history
        let multimodalModelId = MultimodalConfigStore.shared.config.effectiveModelId
        let capturedApp = textInsertionService.capturedAppName
        HistoryStore.shared.saveRecording(
            originalText: fullResponse,
            enhancedText: nil,
            duration: lastRecordingDuration,
            audioSamples: lastRecordingSamples,
            sourceApp: capturedApp,
            sttModelName: "multimodal:\(multimodalModelId)",
            llmModelName: nil,
            contextLevel: contextLevel,
            systemPrompt: systemPrompt
        )
        lastSavedRecordingId = HistoryStore.shared.recordings.first?.id
        lastRecordingSamples = nil

        if streamFailed || fullResponse.isEmpty {
            if usePanel { textEditorPanel.hideAnimated() }
            textInsertionService.clearCapturedElement()

            if lastRecordingDuration > 3 {
                // Show failure capsule with retry hint
                recordingOverlay.showTranscriptionFailed(onClicked: { [weak self] in
                    Task { @MainActor in
                        self?.openHistoryInMainWindow()
                    }
                })
            } else {
                recordingOverlay.hideAnimated()
            }
            state = .idle
            return
        }

        if usePanel {
            textInsertionService.clearCapturedElement()
        }

        // Show completed capsule
        recordingOverlay.showCompleted(onClicked: { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                if case .showingResult = self.state { return }
                self.showTextEditorForResult(text: fullResponse)
            }
        })

        if usePanel {
            textEditorPanel.finishStreaming()
            state = .showingResult(fullResponse)
        } else {
            state = .idle
        }
    }

    // MARK: - Text Editor Actions

    private func showTextEditorForResult(text: String) {
        currentFullResponse = text
        textEditorPanel.show(
            text: text,
            onClose: { [weak self] in
                Task { @MainActor in self?.handleEditorClose() }
            },
            onCopy: { [weak self] editedText in
                Task { @MainActor in self?.handleEditorCopy(editedText: editedText) }
            },
            onApply: { [weak self] editedText in
                Task { @MainActor in self?.handleEditorApply(editedText: editedText) }
            }
        )
        state = .showingResult(text)
    }

    private func handleEditorClose() {
        recordingOverlay.hideAnimated()
        textInsertionService.clearCapturedElement()
        state = .idle
    }

    private func handleEditorCopy(editedText: String) {
        recordingOverlay.hideAnimated()
        saveUserEditIfChanged(editedText: editedText)
        textInsertionService.clearCapturedElement()
        state = .idle
    }

    private func handleEditorApply(editedText: String) {
        recordingOverlay.hideAnimated()
        textEditorPanel.hideAnimated()
        saveUserEditIfChanged(editedText: editedText)
        state = .idle

        let selected = textInsertionService.hasInsertionTracking &&
                       textInsertionService.selectInsertedText()
        let charCount = textInsertionService.insertedCharacterCount
        textInsertionService.clearCapturedElement()

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(editedText, forType: .string)
        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)

            if !selected && charCount > 0 {
                let backspaceKeyCode: CGKeyCode = 0x33
                for _ in 0..<charCount {
                    if let kd = CGEvent(keyboardEventSource: nil, virtualKey: backspaceKeyCode, keyDown: true),
                       let ku = CGEvent(keyboardEventSource: nil, virtualKey: backspaceKeyCode, keyDown: false) {
                        kd.post(tap: .cgAnnotatedSessionEventTap)
                        ku.post(tap: .cgAnnotatedSessionEventTap)
                    }
                    usleep(5_000)
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }

            let source = CGEventSource(stateID: .hidSystemState)
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else { return }
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private func saveUserEditIfChanged(editedText: String) {
        guard editedText != currentFullResponse, !editedText.isEmpty else { return }
        guard let id = lastSavedRecordingId,
              let recording = HistoryStore.shared.recording(for: id) else { return }
        HistoryStore.shared.updateUserEditedText(recording, text: editedText)
        DebugLogger.shared.log("[App] Saved user edit for learning")
        Task { await ContextProfileService.shared.refreshSnapshot() }
    }

    // MARK: - Duration Timer

    private func startDurationTimer() {
        let startTime = recordingStartTime ?? Date()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            let elapsed = Int(Date().timeIntervalSince(startTime))
            let minutes = elapsed / 60
            let seconds = elapsed % 60
            Task { @MainActor in
                self?.recordingDuration = String(format: "%02d:%02d", minutes, seconds)
            }
        }
    }

    // MARK: - Floating Widget

    private func setupFloatingWidget() {
        floatingWidgetPanel.onClicked = { [weak self] in
            Task { @MainActor in self?.toggleHistoryPopover() }
        }
        floatingWidgetPanel.onPositionChanged = { origin in
            Task { @MainActor in
                UserDefaults.standard.set(Double(origin.x), forKey: "SpeakMore.widgetPositionX")
                UserDefaults.standard.set(Double(origin.y), forKey: "SpeakMore.widgetPositionY")
            }
        }

        if UserDefaults.standard.object(forKey: "SpeakMore.widgetVisible") == nil {
            UserDefaults.standard.set(true, forKey: "SpeakMore.widgetVisible")
            isWidgetVisible = true
        }

        if isWidgetVisible {
            showFloatingWidget()
        }
    }

    private func showFloatingWidget() {
        let defaults = UserDefaults.standard
        let hasPosition = defaults.object(forKey: "SpeakMore.widgetPositionX") != nil

        if hasPosition {
            let x = defaults.double(forKey: "SpeakMore.widgetPositionX")
            let y = defaults.double(forKey: "SpeakMore.widgetPositionY")
            floatingWidgetPanel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            if let screen = NSScreen.main {
                let visible = screen.visibleFrame
                let x = visible.maxX - 40 - 60
                let y = visible.minY + 60
                floatingWidgetPanel.setFrameOrigin(NSPoint(x: x, y: y))
            }
        }
        floatingWidgetPanel.orderFront(nil)
    }

    private func toggleHistoryPopover() {
        if historyPopoverPanel.isVisible {
            historyPopoverPanel.hideAnimated()
        } else {
            let recordings = HistoryStore.shared.recordings
            historyPopoverPanel.showRelativeTo(
                widgetFrame: floatingWidgetPanel.frame,
                recordings: Array(recordings.prefix(5)),
                onCopy: { [weak self] recording in
                    self?.handlePopoverCopy(recording: recording)
                },
                onEdit: { [weak self] recording in
                    self?.handlePopoverEdit(recording: recording)
                },
                onViewAll: { [weak self] in
                    self?.historyPopoverPanel.hideAnimated()
                    self?.openHistoryInMainWindow()
                }
            )
        }
    }

    private func handlePopoverCopy(recording: Recording) {
        let text = recording.userEditedText ?? recording.originalText ?? ""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        historyPopoverPanel.hideAnimated()
    }

    private func handlePopoverEdit(recording: Recording) {
        historyPopoverPanel.hideAnimated()
        showTextEditorForHistory(recording: recording)
    }

    private func openHistoryInMainWindow() {
        recordingOverlay.hideAnimated()
        // Bring main window to front
        for window in NSApp.windows {
            if window.identifier?.rawValue == "main-window" || window.title == "SpeakMore Lite" {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                break
            }
        }
        // Switch to history tab
        NotificationCenter.default.post(name: .openHistoryTab, object: nil)
    }

    private func showTextEditorForHistory(recording: Recording) {
        let text = recording.userEditedText ?? recording.originalText ?? ""
        lastSavedRecordingId = recording.id
        currentFullResponse = text
        textEditorPanel.show(
            text: text,
            onClose: { [weak self] in
                Task { @MainActor in self?.handleEditorClose() }
            },
            onCopy: { [weak self] editedText in
                Task { @MainActor in self?.handleEditorCopy(editedText: editedText) }
            },
            onApply: { [weak self] editedText in
                Task { @MainActor in self?.handleEditorApply(editedText: editedText) }
            }
        )
        state = .showingResult(text)
    }
}
