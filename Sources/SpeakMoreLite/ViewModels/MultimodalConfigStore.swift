import Foundation

@MainActor
class MultimodalConfigStore: ObservableObject {
    static let shared = MultimodalConfigStore()

    @Published var config: MultimodalConfig {
        didSet { save() }
    }

    var isConfigured: Bool {
        !config.apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// All models from providers that have API keys configured
    var availableModels: [AvailableModel] {
        var models: [AvailableModel] = []
        for provider in MultimodalProvider.allCases {
            let key = config.apiKeys[provider.rawValue] ?? ""
            guard !key.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            for model in provider.defaultModels {
                models.append(AvailableModel(provider: provider, model: model))
            }
        }
        return models
    }

    /// The currently active model as an AvailableModel
    var currentAvailableModel: AvailableModel? {
        let modelId = config.effectiveModelId
        let provider = config.provider
        if let model = provider.defaultModels.first(where: { $0.id == modelId }) {
            return AvailableModel(provider: provider, model: model)
        }
        // Custom model
        let customModel = MultimodalModel(id: modelId, displayName: modelId, description: "自定义")
        return AvailableModel(provider: provider, model: customModel)
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: "multimodalConfig"),
           let decoded = try? JSONDecoder().decode(MultimodalConfig.self, from: data) {
            self.config = decoded
        } else {
            self.config = .default
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "multimodalConfig")
        }
    }
}
