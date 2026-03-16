import AppKit
import SwiftUI

class HistoryPopoverPanel: NSPanel {

    private let popoverWidth: CGFloat = 320
    private let popoverMaxHeight: CGFloat = 400
    private var globalMonitor: Any?
    private var localMonitor: Any?
    var widgetFrame: NSRect = .zero

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = false
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { false }

    func showRelativeTo(widgetFrame: NSRect, recordings: [Recording],
                        onCopy: @escaping (Recording) -> Void,
                        onEdit: @escaping (Recording) -> Void,
                        onViewAll: @escaping () -> Void) {
        self.widgetFrame = widgetFrame

        let recentRecordings = Array(recordings.prefix(5))

        let content = HistoryPopoverContent(
            recordings: recentRecordings,
            onCopy: onCopy,
            onEdit: onEdit,
            onViewAll: onViewAll
        )
        let hostingView = TransparentHostingView(rootView: content)
        contentView = hostingView

        let itemHeight: CGFloat = 68
        let footerHeight: CGFloat = recentRecordings.isEmpty ? 0 : 41 // button + divider
        let contentHeight: CGFloat = recentRecordings.isEmpty
            ? 80
            : CGFloat(recentRecordings.count) * itemHeight + 16 + footerHeight

        let panelHeight = min(contentHeight, popoverMaxHeight)
        setContentSize(NSSize(width: popoverWidth, height: panelHeight))

        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let margin: CGFloat = 8

        var x = widgetFrame.midX - popoverWidth / 2
        x = max(visible.minX + margin, min(x, visible.maxX - popoverWidth - margin))

        var y: CGFloat
        let spaceAbove = visible.maxY - widgetFrame.maxY
        if spaceAbove >= panelHeight + margin {
            y = widgetFrame.maxY + margin
        } else {
            y = widgetFrame.minY - panelHeight - margin
        }
        y = max(visible.minY + margin, min(y, visible.maxY - panelHeight - margin))

        setFrameOrigin(NSPoint(x: x, y: y))
        alphaValue = 0
        orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }

        installClickOutsideMonitors()
    }

    func hideAnimated() {
        removeMonitors()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }

    private func installClickOutsideMonitors() {
        removeMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handleOutsideClick(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handleOutsideClick(event)
            return event
        }
    }

    private func handleOutsideClick(_ event: NSEvent) {
        let clickLocation = NSEvent.mouseLocation
        if frame.contains(clickLocation) { return }
        if widgetFrame.contains(clickLocation) { return }
        hideAnimated()
    }

    private func removeMonitors() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    deinit {
        removeMonitors()
    }
}

// MARK: - SwiftUI Content

struct HistoryPopoverContent: View {
    let recordings: [Recording]
    let onCopy: (Recording) -> Void
    let onEdit: (Recording) -> Void
    let onViewAll: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if recordings.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(recordings, id: \.objectID) { recording in
                            HistoryPopoverRow(
                                recording: recording,
                                onCopy: { onCopy(recording) },
                                onEdit: { onEdit(recording) }
                            )
                            if recording.objectID != recordings.last?.objectID {
                                Divider()
                                    .background(Color.white.opacity(0.08))
                                    .padding(.horizontal, 12)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                Divider()
                    .background(Color.white.opacity(0.08))

                Button(action: onViewAll) {
                    HStack(spacing: 4) {
                        Text(L("popover.view_all"))
                            .font(.system(size: 12))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.12).opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.3))
            Text(L("popover.no_history"))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .padding(.vertical, 10)
    }
}

struct HistoryPopoverRow: View {
    let recording: Recording
    let onCopy: () -> Void
    let onEdit: () -> Void

    private var displayText: String {
        recording.userEditedText ?? recording.originalText ?? ""
    }

    private var metadataLine: String {
        var parts: [String] = []
        let seconds = Int(recording.durationSeconds)
        if seconds >= 60 {
            parts.append(String(format: L("duration.min_sec_fmt"), seconds / 60, seconds % 60))
        } else if seconds > 0 {
            parts.append(String(format: L("duration.sec_fmt"), seconds))
        }
        if let app = recording.sourceApp, !app.isEmpty {
            parts.append(app)
        }
        if let date = recording.createdAt {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            parts.append(formatter.string(from: date))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayText)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(metadataLine)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
            }

            HStack(spacing: 4) {
                Button(action: onCopy) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
