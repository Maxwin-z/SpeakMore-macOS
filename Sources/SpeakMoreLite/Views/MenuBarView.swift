import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var lang = LanguageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                openWindow(id: "main-window")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label(lang.s("menu.open_window"), systemImage: "macwindow")
            }

            Toggle(lang.s("menu.show_widget"), isOn: $appViewModel.isWidgetVisible)

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text(lang.s("menu.quit"))
            }
            .keyboardShortcut("q")
        }
    }
}
