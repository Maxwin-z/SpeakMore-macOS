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

/// A fully resolved available model (provider + model + has API key)
struct AvailableModel: Identifiable, Hashable {
    let provider: MultimodalProvider
    let model: MultimodalModel

    var id: String { "\(provider.rawValue):\(model.id)" }

    var displayName: String {
        "\(provider.displayName) - \(model.displayName)"
    }

    /// Build a MultimodalConfig targeting this specific model
    func buildConfig(from base: MultimodalConfig) -> MultimodalConfig {
        MultimodalConfig(
            provider: provider,
            apiKeys: base.apiKeys,
            endpoint: provider.defaultEndpoint,
            selectedModelId: model.id,
            customModelId: ""
        )
    }
}

/// Context level for re-recognition
enum ContextLevel: Int, CaseIterable, Identifiable {
    case none = 0
    case realtime = 1
    case shortTerm = 2
    case longTerm = 3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .none: return "无上下文"
        case .realtime: return "ID 上下文"
        case .shortTerm: return "短期上下文"
        case .longTerm: return "长期上下文"
        }
    }

    var description: String {
        switch self {
        case .none: return "仅基础转写指令"
        case .realtime: return "加入来源应用信息"
        case .shortTerm: return "加入近期话题和词汇"
        case .longTerm: return "加入用户画像和长期偏好"
        }
    }
}

/// Persisted multimodal API configuration
struct MultimodalConfig: Codable {
    var provider: MultimodalProvider
    var apiKeys: [String: String]
    var endpoint: String
    var selectedModelId: String
    var customModelId: String

    /// Current provider's API key (read/write through apiKeys dictionary)
    var apiKey: String {
        get { apiKeys[provider.rawValue] ?? "" }
        set { apiKeys[provider.rawValue] = newValue }
    }

    static let `default` = MultimodalConfig(
        provider: .gemini,
        apiKeys: [:],
        endpoint: MultimodalProvider.gemini.defaultEndpoint,
        selectedModelId: "gemini-2.5-flash",
        customModelId: ""
    )

    init(provider: MultimodalProvider, apiKeys: [String: String],
         endpoint: String, selectedModelId: String, customModelId: String = "") {
        self.provider = provider
        self.apiKeys = apiKeys
        self.endpoint = endpoint
        self.selectedModelId = selectedModelId
        self.customModelId = customModelId
    }

    private enum CodingKeys: String, CodingKey {
        case provider, apiKeys, endpoint, selectedModelId, customModelId
        case apiKey // legacy single-key field
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decodeIfPresent(MultimodalProvider.self, forKey: .provider) ?? .gemini
        // Migrate from legacy single apiKey to per-provider apiKeys
        if let keys = try container.decodeIfPresent([String: String].self, forKey: .apiKeys) {
            apiKeys = keys
        } else if let legacyKey = try container.decodeIfPresent(String.self, forKey: .apiKey), !legacyKey.isEmpty {
            apiKeys = [provider.rawValue: legacyKey]
        } else {
            apiKeys = [:]
        }
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? provider.defaultEndpoint
        selectedModelId = try container.decodeIfPresent(String.self, forKey: .selectedModelId) ?? "gemini-2.5-flash"
        customModelId = try container.decodeIfPresent(String.self, forKey: .customModelId) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(apiKeys, forKey: .apiKeys)
        try container.encode(endpoint, forKey: .endpoint)
        try container.encode(selectedModelId, forKey: .selectedModelId)
        try container.encode(customModelId, forKey: .customModelId)
    }

    /// The effective model ID to use
    var effectiveModelId: String {
        if !customModelId.trimmingCharacters(in: .whitespaces).isEmpty {
            return customModelId
        }
        return selectedModelId
    }
}
