import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @StateObject private var navigation = NavigationViewModel()
    @StateObject private var promptStore = PromptStore.shared
    @StateObject private var multimodalStore = MultimodalConfigStore.shared

    var body: some View {
        NavigationSplitView {
            SidebarView(navigation: navigation)
        } detail: {
            Group {
                switch navigation.selectedTab {
                case .home:
                    HomeScreen()
                case .history:
                    HistoryScreen()
                case .prompts:
                    PromptsScreen()
                        .environmentObject(promptStore)
                case .settings:
                    SettingsScreen()
                        .environmentObject(multimodalStore)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .environmentObject(appViewModel)
    }
}
