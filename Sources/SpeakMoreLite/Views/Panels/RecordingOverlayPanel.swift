import AppKit
import SwiftUI

class TransparentHostingView<Content: View>: NSHostingView<Content> {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.isOpaque = false
        window?.backgroundColor = .clear
        clearAllBackgrounds(self)
    }

    override func layout() {
        super.layout()
        clearAllBackgrounds(self)
    }

    private func clearAllBackgrounds(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        view.layer?.borderWidth = 0
        view.layer?.borderColor = .clear
        view.compositingFilter = nil
        for subview in view.subviews {
            clearAllBackgrounds(subview)
        }
    }
}

class AudioLevelProvider: ObservableObject {
    @Published var level: Float = 0
}

enum OverlayMode: Equatable {
    case recording
    case transcribing
    case loadingHint(String)
    case completed
    case transcriptionFailed
}

class OverlayStateProvider: ObservableObject {
    @Published var mode: OverlayMode = .recording
    @Published var transcriptionProgress: Double = 0
    @Published var audioDuration: TimeInterval = 0
    var onCompletedTapped: (() -> Void)?
    var onCancelTapped: (() -> Void)?
    var onFailedTapped: (() -> Void)?
}

class RecordingOverlayPanel: NSPanel {

    let audioLevelProvider = AudioLevelProvider()
    let overlayState = OverlayStateProvider()
    private var progressTimer: Timer?
    private var hintDismissWorkItem: DispatchWorkItem?

    private let capsuleWidth: CGFloat = 120
    private let capsuleHeight: CGFloat = 36

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        let rootView = RecordingOverlayContent(
            audioLevel: audioLevelProvider,
            overlayState: overlayState
        )
        let hostingView = TransparentHostingView(rootView: rootView)
        contentView = hostingView
    }

    func updateAudioLevel(_ value: Float) {
        audioLevelProvider.level = value
    }

    func showCentered() {
        hintDismissWorkItem?.cancel()
        overlayState.mode = .recording
        overlayState.transcriptionProgress = 0
        overlayState.onCompletedTapped = nil
        ignoresMouseEvents = true
        stopProgressTimer()

        setContentSize(NSSize(width: capsuleWidth, height: capsuleHeight))

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - capsuleWidth / 2
        let y = screenFrame.origin.y + 48
        setFrameOrigin(NSPoint(x: x, y: y))
        alphaValue = 0
        orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    func showTranscribing(duration: TimeInterval, onCancel: @escaping () -> Void) {
        overlayState.mode = .transcribing
        overlayState.transcriptionProgress = 0
        overlayState.audioDuration = duration
        overlayState.onCancelTapped = onCancel
        audioLevelProvider.level = 0
        ignoresMouseEvents = false
        startProgressTimer(cap: 0.6, speed: 0.015)
    }

    func onStreamingStarted() {
        stopProgressTimer()
        if overlayState.transcriptionProgress < 0.6 {
            overlayState.transcriptionProgress = 0.6
        }
        startProgressTimer(cap: 0.95, speed: 0.04)
    }

    func bumpStreamingProgress() {
        let current = overlayState.transcriptionProgress
        let cap = 0.95
        if current < cap {
            overlayState.transcriptionProgress = current + (cap - current) * 0.06
        }
    }

    func finishProgress() {
        stopProgressTimer()
        overlayState.transcriptionProgress = 1.0
    }

    func showCompleted(onClicked: @escaping () -> Void) {
        stopProgressTimer()
        overlayState.mode = .completed
        overlayState.transcriptionProgress = 1.0
        overlayState.onCompletedTapped = onClicked
        ignoresMouseEvents = false

        hintDismissWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.hideAnimated()
        }
        hintDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
    }

    func showTranscriptionFailed(onClicked: @escaping () -> Void) {
        stopProgressTimer()
        overlayState.mode = .transcriptionFailed
        overlayState.transcriptionProgress = 0
        overlayState.onFailedTapped = onClicked
        ignoresMouseEvents = false

        let failedWidth: CGFloat = 260
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let newX = screenFrame.midX - failedWidth / 2
        let y = screenFrame.origin.y + 48
        setContentSize(NSSize(width: failedWidth, height: capsuleHeight))
        setFrameOrigin(NSPoint(x: newX, y: y))

        hintDismissWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.hideAnimated()
        }
        hintDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: workItem)
    }

    func showLoadingHint(_ message: String) {
        stopProgressTimer()
        overlayState.mode = .loadingHint(message)
        overlayState.transcriptionProgress = 0
        audioLevelProvider.level = 0

        let hintWidth: CGFloat = 200
        setContentSize(NSSize(width: hintWidth, height: capsuleHeight))

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - hintWidth / 2
        let y = screenFrame.origin.y + 48
        setFrameOrigin(NSPoint(x: x, y: y))
        alphaValue = 0
        orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }

        hintDismissWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.hideAnimated()
        }
        hintDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }

    func hideAnimated() {
        hintDismissWorkItem?.cancel()
        stopProgressTimer()
        ignoresMouseEvents = true
        overlayState.onCompletedTapped = nil
        overlayState.onCancelTapped = nil
        overlayState.onFailedTapped = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.audioLevelProvider.level = 0
            self?.overlayState.transcriptionProgress = 0
            self?.overlayState.audioDuration = 0
            self?.overlayState.mode = .recording
        })
    }

    private func startProgressTimer(cap: Double, speed: Double) {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                let current = self.overlayState.transcriptionProgress
                if current < cap {
                    let remaining = cap - current
                    self.overlayState.transcriptionProgress = current + remaining * speed
                }
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}

// MARK: - SwiftUI Content

struct RecordingOverlayContent: View {
    @ObservedObject var audioLevel: AudioLevelProvider
    @ObservedObject var overlayState: OverlayStateProvider
    @State private var isTranscribingHovered = false

    private let defaultWidth: CGFloat = 120
    private let capsuleHeight: CGFloat = 36

    private var capsuleWidth: CGFloat {
        switch overlayState.mode {
        case .loadingHint: return 200
        case .transcriptionFailed: return 260
        default: return defaultWidth
        }
    }

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(Color(white: 0.12).opacity(0.9))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                )

            switch overlayState.mode {
            case .recording:
                WaveformView(level: CGFloat(audioLevel.level))
            case .transcribing:
                TranscribingView(
                    progress: overlayState.transcriptionProgress,
                    audioDuration: overlayState.audioDuration,
                    isHovering: $isTranscribingHovered
                )
            case .loadingHint(let message):
                LoadingHintView(message: message)
            case .completed:
                CompletedView()
            case .transcriptionFailed:
                TranscriptionFailedView()
            }
        }
        .frame(width: capsuleWidth, height: capsuleHeight)
        .contentShape(Capsule(style: .continuous))
        .onTapGesture {
            switch overlayState.mode {
            case .completed:
                overlayState.onCompletedTapped?()
            case .transcriptionFailed:
                overlayState.onFailedTapped?()
            case .transcribing:
                if isTranscribingHovered {
                    overlayState.onCancelTapped?()
                }
            default:
                break
            }
        }
        .animation(.easeInOut(duration: 0.25), value: capsuleWidth)
    }
}

struct WaveformView: View {
    let level: CGFloat

    @State private var displayLevel: CGFloat = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            Canvas { ctx, size in
                drawWaveform(in: ctx, size: size, time: time)
            }
            .onChange(of: timeline.date) { _, _ in
                let normalizedTarget = min(max(level / 0.02, 0), 1)
                let factor: CGFloat = normalizedTarget > displayLevel ? 0.3 : 0.12
                displayLevel += (normalizedTarget - displayLevel) * factor
            }
        }
    }

    private func drawWaveform(in ctx: GraphicsContext, size: CGSize, time: Double) {
        let midY = size.height / 2
        let width = size.width
        let maxAmplitude = midY * 0.85

        // Subtle idle breathing so the waveform is never fully static
        let idleBreath = 0.03 + 0.02 * sin(time * 1.5)
        let effectiveLevel = max(Double(displayLevel), idleBreath)

        // Wave layers: (speed, frequency, amplitude scale, opacity)
        let layers: [(Double, Double, Double, Double)] = [
            (1.8, 1.2, 1.0, 0.5),
            (2.5, 1.7, 0.7, 0.35),
            (3.2, 2.3, 0.45, 0.2),
        ]

        // Glow layer behind the main wave
        if let first = layers.first {
            let (speed, freq, ampScale, _) = first
            let path = wavePath(width: width, midY: midY,
                                amplitude: effectiveLevel * maxAmplitude * ampScale,
                                frequency: freq, phase: time * speed)
            ctx.drawLayer { glowCtx in
                glowCtx.addFilter(.blur(radius: 4))
                glowCtx.fill(path, with: .color(.white.opacity(0.25 * effectiveLevel)))
            }
        }

        // Draw each wave layer
        for (speed, freq, ampScale, opacity) in layers {
            let amp = effectiveLevel * maxAmplitude * ampScale
            let path = wavePath(width: width, midY: midY,
                                amplitude: amp, frequency: freq, phase: time * speed)
            ctx.fill(path, with: .color(.white.opacity(opacity)))
        }
    }

    private func wavePath(width: CGFloat, midY: CGFloat,
                          amplitude: CGFloat, frequency: Double, phase: Double) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: midY))

        // Upper contour
        for x in stride(from: CGFloat(0), through: width, by: 1) {
            let t = Double(x / width)
            let envelope = pow(sin(t * .pi), 1.5)
            let s1 = sin(t * frequency * .pi * 2 + phase)
            let s2 = sin(t * frequency * 1.6 * .pi * 2 + phase * 1.3) * 0.35
            let s3 = sin(t * frequency * 0.6 * .pi * 2 + phase * 0.7) * 0.15
            let composite = abs(s1 + s2 + s3) / 1.5
            let y = midY - composite * amplitude * envelope
            path.addLine(to: CGPoint(x: x, y: y))
        }

        // Lower contour (symmetric mirror)
        for x in stride(from: width, through: CGFloat(0), by: -1) {
            let t = Double(x / width)
            let envelope = pow(sin(t * .pi), 1.5)
            let s1 = sin(t * frequency * .pi * 2 + phase)
            let s2 = sin(t * frequency * 1.6 * .pi * 2 + phase * 1.3) * 0.35
            let s3 = sin(t * frequency * 0.6 * .pi * 2 + phase * 0.7) * 0.15
            let composite = abs(s1 + s2 + s3) / 1.5
            let y = midY + composite * amplitude * envelope
            path.addLine(to: CGPoint(x: x, y: y))
        }

        path.closeSubpath()
        return path
    }
}

struct TranscribingView: View {
    let progress: Double
    let audioDuration: TimeInterval
    @Binding var isHovering: Bool
    @State private var carouselIndex = 0

    private var durationText: String {
        let seconds = Int(audioDuration)
        if seconds >= 60 {
            return String(format: L("duration.min_sec_fmt"), seconds / 60, seconds % 60)
        }
        return String(format: L("duration.sec_fmt"), seconds)
    }

    private var carouselTexts: [String] {
        [
            L("overlay.transcribing"),
            String(format: L("overlay.transcribing_duration_fmt"), durationText),
            L("overlay.hover_to_cancel")
        ]
    }

    var body: some View {
        ZStack {
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: geo.size.width * CGFloat(progress))
                    .animation(.easeOut(duration: 0.3), value: progress)
            }

            if isHovering {
                HStack(spacing: 4) {
                    Text(L("overlay.cancel_transcription"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .transition(.opacity)
            } else {
                Text(carouselTexts[carouselIndex])
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .id(carouselIndex)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
        }
        .clipShape(Capsule(style: .continuous))
        .contentShape(Capsule(style: .continuous))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                let count = carouselTexts.count
                withAnimation(.easeInOut(duration: 0.3)) {
                    carouselIndex = (carouselIndex + 1) % count
                }
            }
        }
    }
}

struct LoadingHintView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .lineLimit(1)
            .padding(.horizontal, 8)
    }
}

struct CompletedView: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.green)
            Text(L("overlay.click_edit"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

struct TranscriptionFailedView: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text(L("overlay.transcription_failed"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
    }
}
