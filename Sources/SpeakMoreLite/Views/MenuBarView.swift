import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                openWindow(id: "main-window")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("打开主窗口", systemImage: "macwindow")
            }

            Toggle("显示悬浮按钮", isOn: $appViewModel.isWidgetVisible)

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("退出 SpeakMore Lite")
            }
            .keyboardShortcut("q")
        }
    }
}
