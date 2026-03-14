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
