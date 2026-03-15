import Foundation

// MARK: - Base Instruction Templates

enum BaseInstructionTemplate: String, Codable, CaseIterable, Identifiable, Equatable {
    case faithful
    case moderate
    case structured

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .faithful: return "忠实转写"
        case .moderate: return "轻度优化"
        case .structured: return "深度优化"
        }
    }

    var description: String {
        switch self {
        case .faithful: return "完全保留原意，仅去除重复、语气词及错别字"
        case .moderate: return "保持原意，轻度调整语序与分段，使文本更易阅读"
        case .structured: return "保持核心语义，深度整理逻辑结构，输出接近正式书面语"
        }
    }

    var prompt: String {
        switch self {
        case .faithful:
            return "你是一个语音转写助手。请将用户的语音内容准确转写为文字，完全保留原意和表达方式，仅去除重复内容、语气词（如 嗯、啊、那个）及明显的口误错别字。直接输出转写结果，不要添加任何解释。"
        case .moderate:
            return "你是一个语音转写助手。请将用户的语音内容转写为文字，保持原意，修正口语错误和语气词，进行轻度结构化调整（如理顺语序、补充必要标点、合理分段），使文本自然流畅且易于阅读。直接输出转写结果，不要添加任何解释。"
        case .structured:
            return "你是一个语音转写助手。请将用户的语音内容转写为结构清晰的书面文本，保持核心语义不变，深度优化：整理逻辑结构、消除冗余、改善表达、合理分段，使输出接近正式书面语水平。直接输出转写结果，不要添加任何解释。"
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
    }
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
