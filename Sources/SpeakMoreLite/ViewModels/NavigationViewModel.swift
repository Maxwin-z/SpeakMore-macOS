import Foundation

enum SidebarTab: String, CaseIterable, Identifiable {
    case home
    case history
    case prompts
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "首页"
        case .history: return "历史记录"
        case .prompts: return "AI增强"
        case .settings: return "设置"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .history: return "clock.arrow.circlepath"
        case .prompts: return "text.quote"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
class NavigationViewModel: ObservableObject {
    @Published var selectedTab: SidebarTab = .home
}
