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

enum OverlayMode {
    case recording
    case transcribing
    case loadingHint(String)
    case completed
}

class OverlayStateProvider: ObservableObject {
    @Published var mode: OverlayMode = .recording
    @Published var transcriptionProgress: Double = 0
    var onCompletedTapped: (() -> Void)?
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

    func showTranscribing() {
        overlayState.mode = .transcribing
        overlayState.transcriptionProgress = 0
        audioLevelProvider.level = 0
        startProgressTimer(cap: 0.8)
    }

    func showChatStreaming() {
        stopProgressTimer()
        overlayState.transcriptionProgress = 0.8
        startProgressTimer(cap: 0.95)
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
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.audioLevelProvider.level = 0
            self?.overlayState.transcriptionProgress = 0
            self?.overlayState.mode = .recording
        })
    }

    private func startProgressTimer(cap: Double) {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                let current = self.overlayState.transcriptionProgress
                if current < cap {
                    let remaining = cap - current
                    self.overlayState.transcriptionProgress = current + remaining * 0.06
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

    private let defaultWidth: CGFloat = 120
    private let capsuleHeight: CGFloat = 36

    private var capsuleWidth: CGFloat {
        if case .loadingHint = overlayState.mode { return 200 }
        return defaultWidth
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
                EqualizerView(level: CGFloat(audioLevel.level))
            case .transcribing:
                TranscribingView(progress: overlayState.transcriptionProgress)
            case .loadingHint(let message):
                LoadingHintView(message: message)
            case .completed:
                CompletedView()
            }
        }
        .frame(width: capsuleWidth, height: capsuleHeight)
        .contentShape(Capsule(style: .continuous))
        .onTapGesture {
            if case .completed = overlayState.mode {
                overlayState.onCompletedTapped?()
            }
        }
        .animation(.easeInOut(duration: 0.15), value: capsuleWidth)
    }
}

struct EqualizerView: View {
    let level: CGFloat

    private let barCount = 15
    private let barWidth: CGFloat = 2
    private let barSpacing: CGFloat = 2
    private let maxBarHeight: CGFloat = 30
    private let minBarHeight: CGFloat = 3

    @State private var randomFactors: [CGFloat] = (0..<15).map { _ in
        let raw = CGFloat.random(in: 0...1)
        return 0.15 + pow(raw, 2.5) * 0.85
    }

    private let timer = Timer.publish(every: 0.12, on: .main, in: .common).autoconnect()

    private static func nextRandomFactor() -> CGFloat {
        let raw = CGFloat.random(in: 0...1)
        return 0.15 + pow(raw, 2.5) * 0.85
    }

    var body: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                EqualizerBar(
                    level: level,
                    weight: randomFactors[index],
                    minHeight: minBarHeight,
                    maxHeight: maxBarHeight
                )
                .frame(width: barWidth)
            }
        }
        .onReceive(timer) { _ in
            for i in 0..<barCount {
                randomFactors[i] = Self.nextRandomFactor()
            }
        }
    }
}

struct EqualizerBar: View {
    let level: CGFloat
    let weight: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat

    private var normalizedLevel: CGFloat {
        min(max(level / 0.02, 0), 1)
    }

    private var barHeight: CGFloat {
        let target = minHeight + (maxHeight - minHeight) * normalizedLevel * weight
        return max(target, minHeight)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(.white)
            .frame(height: barHeight)
            .animation(.easeInOut(duration: 0.12), value: barHeight)
    }
}

struct TranscribingView: View {
    let progress: Double

    var body: some View {
        ZStack {
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: geo.size.width * CGFloat(progress))
                    .animation(.easeOut(duration: 0.3), value: progress)
            }

            Text("正在转译...")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
        }
        .clipShape(Capsule(style: .continuous))
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
            Text("点击编辑")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}
