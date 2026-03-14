import Foundation

/// Supported multimodal API providers
enum MultimodalProvider: String, Codable, CaseIterable, Identifiable {
    case gemini
    case dashscope
    case openrouter
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini: return "Google Gemini"
        case .dashscope: return "通义千问 (DashScope)"
        case .openrouter: return "OpenRouter"
        case .custom: return "自定义 (OpenAI 兼容)"
        }
    }

    var icon: String {
        switch self {
        case .gemini: return "globe.americas"
        case .dashscope: return "cloud.fill"
        case .openrouter: return "arrow.triangle.branch"
        case .custom: return "slider.horizontal.3"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta"
        case .dashscope: return "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .openrouter: return "https://openrouter.ai/api/v1"
        case .custom: return ""
        }
    }

    var defaultModels: [MultimodalModel] {
        switch self {
        case .gemini:
            return [
                MultimodalModel(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash", description: "高性价比，推荐使用"),
                MultimodalModel(id: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro", description: "最强性能"),
                MultimodalModel(id: "gemini-2.0-flash", displayName: "Gemini 2.0 Flash", description: "快速稳定"),
            ]
        case .dashscope:
            return [
                MultimodalModel(id: "qwen-omni-turbo", displayName: "Qwen Omni Turbo", description: "快速，支持中英文"),
                MultimodalModel(id: "qwen3-omni-flash", displayName: "Qwen3 Omni Flash", description: "最新一代，效果更好"),
                MultimodalModel(id: "qwen2.5-omni-7b", displayName: "Qwen2.5 Omni 7B", description: "开源模型"),
            ]
        case .openrouter:
            return [
                MultimodalModel(id: "google/gemini-2.5-flash", displayName: "Gemini 2.5 Flash", description: "通过 OpenRouter 使用"),
                MultimodalModel(id: "google/gemini-2.5-pro", displayName: "Gemini 2.5 Pro", description: "最强性能"),
                MultimodalModel(id: "google/gemini-2.0-flash-001", displayName: "Gemini 2.0 Flash", description: "快速稳定"),
            ]
        case .custom:
            return []
        }
    }

    /// Whether this provider uses the Gemini native API format (vs OpenAI-compatible)
    var usesGeminiFormat: Bool {
        self == .gemini
    }
}

/// A multimodal model option
struct MultimodalModel: Identifiable, Codable, Hashable {
    let id: String
    let displayName: String
    let description: String
}

/// Persisted multimodal API configuration
struct MultimodalConfig: Codable {
    var provider: MultimodalProvider
    var apiKey: String
    var endpoint: String
    var selectedModelId: String
    var customModelId: String

    static let `default` = MultimodalConfig(
        provider: .gemini,
        apiKey: "",
        endpoint: MultimodalProvider.gemini.defaultEndpoint,
        selectedModelId: "gemini-2.5-flash",
        customModelId: ""
    )

    init(provider: MultimodalProvider, apiKey: String,
         endpoint: String, selectedModelId: String, customModelId: String = "") {
        self.provider = provider
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.selectedModelId = selectedModelId
        self.customModelId = customModelId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decodeIfPresent(MultimodalProvider.self, forKey: .provider) ?? .gemini
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? provider.defaultEndpoint
        selectedModelId = try container.decodeIfPresent(String.self, forKey: .selectedModelId) ?? "gemini-2.5-flash"
        customModelId = try container.decodeIfPresent(String.self, forKey: .customModelId) ?? ""
    }

    /// The effective model ID to use
    var effectiveModelId: String {
        if !customModelId.trimmingCharacters(in: .whitespaces).isEmpty {
            return customModelId
        }
        return selectedModelId
    }
}
