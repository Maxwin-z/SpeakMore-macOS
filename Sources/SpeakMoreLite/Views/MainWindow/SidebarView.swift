import SwiftUI

struct SidebarView: View {
    @ObservedObject var navigation: NavigationViewModel
    @ObservedObject private var lang = LanguageManager.shared

    var body: some View {
        List(SidebarTab.allCases, selection: $navigation.selectedTab) { tab in
            Label(tab.title, systemImage: tab.icon)
                .tag(tab)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("v1.0")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
}
