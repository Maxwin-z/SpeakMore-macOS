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
        if let app = appName { parts.append("应用: \(app)") }
        if let title = windowTitle { parts.append("窗口: \(title)") }
        if let path = documentPath { parts.append("文档: \(path)") }
        return parts.isEmpty ? "无" : parts.joined(separator: "，")
    }
}
