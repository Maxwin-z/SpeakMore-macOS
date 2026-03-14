import SwiftUI

@main
struct SpeakMoreLiteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appViewModel = AppViewModel()

    var body: some Scene {
        Window("SpeakMore Lite", id: "main-window") {
            MainWindowView()
                .environmentObject(appViewModel)
        }
        .defaultSize(width: 900, height: 600)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(appViewModel)
        } label: {
            Image(systemName: menuBarIconName)
        }
    }

    private var menuBarIconName: String {
        switch appViewModel.state {
        case .recording:
            return "mic.fill"
        case .transcribing:
            return "ellipsis.circle"
        case .inserting:
            return "text.cursor"
        default:
            return "mic.badge.plus"
        }
    }
}
