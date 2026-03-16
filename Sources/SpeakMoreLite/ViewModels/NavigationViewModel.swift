import Foundation

extension Notification.Name {
    static let openHistoryTab = Notification.Name("SpeakMore.openHistoryTab")
}

enum SidebarTab: String, CaseIterable, Identifiable {
    case home
    case history
    case prompts
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return L("nav.home")
        case .history: return L("nav.history")
        case .prompts: return L("nav.ai_enhance")
        case .settings: return L("nav.settings")
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
