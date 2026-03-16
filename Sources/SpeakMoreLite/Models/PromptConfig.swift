import Foundation

// MARK: - Base Instruction Templates

enum BaseInstructionTemplate: String, Codable, CaseIterable, Identifiable, Equatable {
    case faithful
    case moderate
    case structured

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .faithful: return L("template.faithful")
        case .moderate: return L("template.moderate")
        case .structured: return L("template.structured")
        }
    }

    var description: String {
        switch self {
        case .faithful: return L("template.faithful_desc")
        case .moderate: return L("template.moderate_desc")
        case .structured: return L("template.structured_desc")
        }
    }

    var prompt: String {
        switch self {
        case .faithful: return L("template.faithful_prompt")
        case .moderate: return L("template.moderate_prompt")
        case .structured: return L("template.structured_prompt")
        }
    }
}

// MARK: - Prompt Configuration

struct PromptConfiguration: Codable, Equatable {
    var baseInstruction: String
    var baseInstructionTemplate: BaseInstructionTemplate?
    var appPrompts: [AppPrompt]
    var glossaryTerms: [String]

    enum CodingKeys: String, CodingKey {
        case baseInstruction = "generalPrompt"
        case baseInstructionTemplate
        case appPrompts
        case glossaryTerms
    }

    static let `default` = PromptConfiguration(
        baseInstruction: BaseInstructionTemplate.faithful.prompt,
        baseInstructionTemplate: .faithful,
        appPrompts: [],
        glossaryTerms: []
    )

    init(
        baseInstruction: String,
        baseInstructionTemplate: BaseInstructionTemplate? = nil,
        appPrompts: [AppPrompt],
        glossaryTerms: [String]
    ) {
        self.baseInstruction = baseInstruction
        self.baseInstructionTemplate = baseInstructionTemplate
        self.appPrompts = appPrompts
        self.glossaryTerms = glossaryTerms
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseInstruction = try container.decode(String.self, forKey: .baseInstruction)
        baseInstructionTemplate = try container.decodeIfPresent(BaseInstructionTemplate.self, forKey: .baseInstructionTemplate)
        appPrompts = try container.decode([AppPrompt].self, forKey: .appPrompts)
        glossaryTerms = try container.decode([String].self, forKey: .glossaryTerms)

        // Migration: old data had empty generalPrompt and no template
        if baseInstruction.isEmpty && baseInstructionTemplate == nil {
            baseInstruction = BaseInstructionTemplate.faithful.prompt
            baseInstructionTemplate = .faithful
        }

        // Migration: sync baseInstruction with current template text.
        // This picks up localization changes (e.g., role/constraints moved to system prompt).
        if let template = baseInstructionTemplate {
            baseInstruction = template.prompt
        }
    }
}

struct AppPrompt: Codable, Equatable, Identifiable {
    let id: UUID
    var appName: String
    var appBundleId: String?
    var prompts: [String]

    /// Joined text used as the actual prompt sent to the model.
    var promptText: String {
        prompts.joined(separator: "；")
    }

    init(id: UUID = UUID(), appName: String, appBundleId: String? = nil, prompts: [String]) {
        self.id = id
        self.appName = appName
        self.appBundleId = appBundleId
        self.prompts = prompts
    }

    // Migration: decode legacy single "prompt" string into [String] array
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        appName = try container.decode(String.self, forKey: .appName)
        appBundleId = try container.decodeIfPresent(String.self, forKey: .appBundleId)
        if let array = try? container.decode([String].self, forKey: .prompts) {
            prompts = array
        } else if let legacy = try? container.decode(String.self, forKey: .legacyPrompt) {
            prompts = legacy.isEmpty ? [] : [legacy]
        } else {
            prompts = []
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, appName, appBundleId, prompts
        case legacyPrompt = "prompt"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(appName, forKey: .appName)
        try container.encodeIfPresent(appBundleId, forKey: .appBundleId)
        try container.encode(prompts, forKey: .prompts)
    }
}
