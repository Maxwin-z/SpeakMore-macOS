import Foundation

@MainActor
class PromptStore: ObservableObject {
    static let shared = PromptStore()

    @Published var config: PromptConfiguration {
        didSet { save() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: "promptConfiguration"),
           let decoded = try? JSONDecoder().decode(PromptConfiguration.self, from: data) {
            self.config = decoded
        } else {
            self.config = .default
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "promptConfiguration")
        }
    }

    func addAppPrompt(_ prompt: AppPrompt) {
        config.appPrompts.append(prompt)
    }

    func removeAppPrompt(at offsets: IndexSet) {
        config.appPrompts.remove(atOffsets: offsets)
    }

    func addGlossaryTerm(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !config.glossaryTerms.contains(trimmed) else { return }
        config.glossaryTerms.append(trimmed)
    }

    func removeGlossaryTerm(_ term: String) {
        config.glossaryTerms.removeAll { $0 == term }
    }

    /// Returns app-specific prompt if matched, otherwise nil.
    /// The base instruction is used separately as the system prompt foundation.
    func resolveAppPrompt(forApp bundleId: String?) -> String? {
        if let bundleId = bundleId,
           let appPrompt = config.appPrompts.first(where: { $0.appBundleId == bundleId }),
           !appPrompt.prompt.isEmpty {
            return appPrompt.prompt
        }
        return nil
    }

    func applyTemplate(_ template: BaseInstructionTemplate) {
        config.baseInstructionTemplate = template
        config.baseInstruction = template.prompt
    }
}
