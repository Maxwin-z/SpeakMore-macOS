import AppKit
import SwiftUI

class EditableTextProvider: ObservableObject {
    @Published var editableText: String = ""
    @Published var isStreaming: Bool = false
}

class TextEditorPanel: NSPanel {

    let textProvider = EditableTextProvider()

    override var canBecomeKey: Bool { true }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 240),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    func show(text: String, onClose: @escaping () -> Void, onCopy: @escaping (String) -> Void, onApply: @escaping (String) -> Void) {
        textProvider.editableText = text
        textProvider.isStreaming = false
        setupContent(onClose: onClose, onCopy: onCopy, onApply: onApply)
        showPositioned()
    }

    func showStreaming(onClose: @escaping () -> Void, onCopy: @escaping (String) -> Void, onApply: @escaping (String) -> Void) {
        textProvider.editableText = ""
        textProvider.isStreaming = true
        setupContent(onClose: onClose, onCopy: onCopy, onApply: onApply)
        showPositioned()
    }

    func appendStreamingText(_ chunk: String) {
        textProvider.editableText += chunk
    }

    func finishStreaming() {
        textProvider.isStreaming = false
    }

    private func setupContent(onClose: @escaping () -> Void, onCopy: @escaping (String) -> Void, onApply: @escaping (String) -> Void) {
        let content = TextEditorContent(
            provider: textProvider,
            onClose: { [weak self] in
                onClose()
                self?.hideAnimated()
            },
            onCopy: { [weak self] in
                guard let self = self else { return }
                let text = self.textProvider.editableText
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                onCopy(text)
                self.hideAnimated()
            },
            onApply: { [weak self] in
                guard let self = self else { return }
                let text = self.textProvider.editableText
                onApply(text)
                self.hideAnimated()
            }
        )
        let hostingView = TransparentHostingView(rootView: content)
        contentView = hostingView
    }

    private func showPositioned() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelWidth: CGFloat = 400
        let panelHeight: CGFloat = 240

        setContentSize(NSSize(width: panelWidth, height: panelHeight))

        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.origin.y + 48 + 36 + 8
        setFrameOrigin(NSPoint(x: x, y: y))

        alphaValue = 0
        makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    func hideAnimated() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
        })
    }
}

struct TextEditorContent: View {
    @ObservedObject var provider: EditableTextProvider
    let onClose: () -> Void
    let onCopy: () -> Void
    let onApply: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if provider.isStreaming {
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(provider.editableText.isEmpty ? " " : provider.editableText)
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id("streamText")
                        }
                        .onChange(of: provider.editableText) {
                            proxy.scrollTo("streamText", anchor: .bottom)
                        }
                    }
                } else {
                    TextEditor(text: $provider.editableText)
                        .font(.system(size: 14))
                        .scrollContentBackground(.hidden)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)
                .padding(.horizontal, 12)

            HStack {
                if provider.isStreaming {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                    Text(L("panel.receiving"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                HStack(spacing: 16) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])

                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)

                    Button(action: onApply) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.blue))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 400, height: 240)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.12).opacity(0.95))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}
