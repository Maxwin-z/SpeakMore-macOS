import Foundation

struct ContextSnapshotData: Codable {
    var topic: String?
    var currentIntent: String?
    var domainFocus: String?
    var recentVocabulary: [String]?
    var entityCloud: [String]?
}

struct UserProfileData: Codable {
    var identity: String?
    var primaryDomains: [String]?
    var languageHabits: String?
    var fixedEntities: [String]?
}

struct RealtimeContext {
    var appName: String?
    var bundleId: String?
    var windowTitle: String?
    var documentPath: String?

    var summary: String {
        var parts: [String] = []
        if let app = appName { parts.append("\(L("prompt.env_app")): \(app)") }
        if let title = windowTitle { parts.append("\(L("prompt.env_window")): \(title)") }
        if let path = documentPath { parts.append("\(L("prompt.env_document")): \(path)") }
        return parts.isEmpty ? L("prompt.env_none") : parts.joined(separator: L("prompt.separator"))
    }
}
