import AppKit
import SwiftUI

class FloatingWidgetPanel: NSPanel {

    var onClicked: (() -> Void)?
    var onPositionChanged: ((NSPoint) -> Void)?

    private var isDragging = false
    private var dragStartPoint: NSPoint = .zero
    private var windowStartOrigin: NSPoint = .zero

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 40, height: 40),
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
        ignoresMouseEvents = false
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        let rootView = FloatingWidgetContent()
        let hostingView = TransparentHostingView(rootView: rootView)
        contentView = hostingView
    }

    override var canBecomeKey: Bool { false }

    override func mouseDown(with event: NSEvent) {
        isDragging = false
        dragStartPoint = NSEvent.mouseLocation
        windowStartOrigin = frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        let current = NSEvent.mouseLocation
        let dx = current.x - dragStartPoint.x
        let dy = current.y - dragStartPoint.y

        if !isDragging && (dx * dx + dy * dy) < 9 { return }
        isDragging = true

        var newOrigin = NSPoint(
            x: windowStartOrigin.x + dx,
            y: windowStartOrigin.y + dy
        )
        clampToScreen(&newOrigin)
        setFrameOrigin(newOrigin)
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            onPositionChanged?(frame.origin)
        } else {
            onClicked?()
        }
        isDragging = false
    }

    private func clampToScreen(_ origin: inout NSPoint) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = frame.size
        origin.x = max(visible.minX, min(origin.x, visible.maxX - size.width))
        origin.y = max(visible.minY, min(origin.y, visible.maxY - size.height))
    }
}

struct FloatingWidgetContent: View {
    @State private var isHovered = false

    var body: some View {
        Group {
            if let nsImage = NSApp.applicationIconImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 36, height: 36)
            } else {
                Circle()
                    .fill(Color(white: 0.12).opacity(0.9))
                    .overlay(
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.8))
                    )
                    .frame(width: 36, height: 36)
            }
        }
        .scaleEffect(isHovered ? 1.08 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .frame(width: 40, height: 40)
    }
}
