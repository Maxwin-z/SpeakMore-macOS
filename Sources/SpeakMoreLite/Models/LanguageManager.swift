import Foundation
import SwiftUI

// MARK: - App Language

enum AppLanguage: String, CaseIterable, Identifiable {
    case zhHans = "zh-Hans"
    case en = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zhHans: return "简体中文"
        case .en: return "English"
        }
    }
}

// MARK: - Language Manager

@MainActor
class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "SpeakMore.language")
            loadBundle()
        }
    }

    private(set) var bundle: Bundle = .main

    private init() {
        let saved = UserDefaults.standard.string(forKey: "SpeakMore.language")
        self.language = AppLanguage(rawValue: saved ?? "") ?? .zhHans
        loadBundle()
    }

    private func loadBundle() {
        if let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
           let b = Bundle(path: path) {
            bundle = b
        } else {
            bundle = .main
        }
    }

    /// Localized string lookup using the current language bundle.
    func s(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}

// MARK: - Global convenience

/// Localized string lookup for non-view code. Thread-safe via UserDefaults.
func L(_ key: String) -> String {
    let saved = UserDefaults.standard.string(forKey: "SpeakMore.language") ?? "zh-Hans"
    let lang = saved == "en" ? "en" : "zh-Hans"
    guard let path = Bundle.main.path(forResource: lang, ofType: "lproj"),
          let bundle = Bundle(path: path) else {
        return Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }
    return bundle.localizedString(forKey: key, value: nil, table: nil)
}
