import Foundation

struct PromptConfiguration: Codable, Equatable {
    var generalPrompt: String
    var appPrompts: [AppPrompt]
    var glossaryTerms: [String]

    static let `default` = PromptConfiguration(
        generalPrompt: "",
        appPrompts: [],
        glossaryTerms: []
    )
}

struct AppPrompt: Codable, Equatable, Identifiable {
    let id: UUID
    var appName: String
    var appBundleId: String?
    var prompt: String

    init(id: UUID = UUID(), appName: String, appBundleId: String? = nil, prompt: String) {
        self.id = id
        self.appName = appName
        self.appBundleId = appBundleId
        self.prompt = prompt
    }
}
