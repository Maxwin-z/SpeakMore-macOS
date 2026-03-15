import Foundation
import CoreData
import Combine

@MainActor
class ContextProfileService: ObservableObject {

    static let shared = ContextProfileService()

    @Published var latestSnapshot: ContextSnapshotData?
    @Published var activeProfile: UserProfileData?
    @Published var latestSnapshotDate: Date?
    @Published var activeProfileDate: Date?
    @Published var isSnapshotProcessing = false
    @Published var isProfileProcessing = false

    private let multimodalService = MultimodalService()

    private static let utteranceThreshold = 10
    private static let charThreshold = 500

    private static let utteranceCountKey = "contextProfile.utteranceCount"
    private static let charCountKey = "contextProfile.charCount"
    private static let lastSnapshotDateKey = "contextProfile.lastSnapshotDate"
    private static let lastProfileDateKey = "contextProfile.lastProfileDate"

    private var utteranceCount: Int {
        get { UserDefaults.standard.integer(forKey: Self.utteranceCountKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.utteranceCountKey) }
    }
    private var charCount: Int {
        get { UserDefaults.standard.integer(forKey: Self.charCountKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.charCountKey) }
    }
    private var lastSnapshotDate: Date? {
        get { UserDefaults.standard.object(forKey: Self.lastSnapshotDateKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastSnapshotDateKey) }
    }
    private var lastProfileDate: Date? {
        get { UserDefaults.standard.object(forKey: Self.lastProfileDateKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastProfileDateKey) }
    }

    private init() {
        loadLatestFromCoreData()
    }

    // MARK: - Public API

    func recordUtterance(text: String, sourceApp: String?, bundleId: String?) {
        guard MultimodalConfigStore.shared.isConfigured else { return }

        utteranceCount += 1
        charCount += text.count
        log("Utterance recorded: count=\(utteranceCount), chars=\(charCount)")

        if utteranceCount >= Self.utteranceThreshold || charCount >= Self.charThreshold {
            Task { await generateShortTermSnapshot() }
        }

        if lastProfileDate == nil || Date().timeIntervalSince(lastProfileDate!) > 86400 {
            Task { await generateLongTermProfile() }
        }
    }

    func refreshSnapshot() async {
        await generateShortTermSnapshot()
    }

    func refreshProfile() async {
        await generateLongTermProfile()
    }

    // MARK: - Manual Tag Editing

    func updateSnapshotVocabulary(_ vocab: [String]) {
        latestSnapshot?.recentVocabulary = vocab
        persistSnapshotChanges()
    }

    func updateSnapshotEntityCloud(_ entities: [String]) {
        latestSnapshot?.entityCloud = entities
        persistSnapshotChanges()
    }

    func updateProfileDomains(_ domains: [String]) {
        activeProfile?.primaryDomains = domains
        persistProfileChanges()
    }

    func updateProfileEntities(_ entities: [String]) {
        activeProfile?.fixedEntities = entities
        persistProfileChanges()
    }

    /// Build system prompt with a specific context level for re-recognition.
    func buildSystemPrompt(
        baseInstruction: String,
        contextLevel: ContextLevel,
        sourceApp: String?,
        glossaryTerms: [String] = []
    ) -> String {
        var sections: [String] = []

        sections.append(baseInstruction)

        var contextSections: [String] = []

        if !glossaryTerms.isEmpty {
            contextSections.append("【术语表（最高优先级）】\n以下术语在转写时优先使用：\n\(glossaryTerms.joined(separator: "、"))")
        }

        if contextLevel.rawValue >= ContextLevel.longTerm.rawValue, let profile = activeProfile {
            var profileParts: [String] = []
            if let id = profile.identity { profileParts.append("用户身份: \(id)") }
            if let domains = profile.primaryDomains, !domains.isEmpty {
                profileParts.append("主要领域: \(domains.joined(separator: "、"))")
            }
            if let habits = profile.languageHabits { profileParts.append("语言习惯: \(habits)") }
            if let entities = profile.fixedEntities, !entities.isEmpty {
                profileParts.append("常用实体: \(entities.joined(separator: "、"))")
            }
            if !profileParts.isEmpty {
                contextSections.append("【用户画像】\n\(profileParts.joined(separator: "\n"))")
            }
        }

        if contextLevel.rawValue >= ContextLevel.shortTerm.rawValue, let snapshot = latestSnapshot {
            var snapParts: [String] = []
            if let topic = snapshot.topic { snapParts.append("当前话题: \(topic)") }
            if let intent = snapshot.currentIntent { snapParts.append("当前意图: \(intent)") }
            if let domain = snapshot.domainFocus { snapParts.append("领域聚焦: \(domain)") }
            if let vocab = snapshot.recentVocabulary, !vocab.isEmpty {
                snapParts.append("近期词汇: \(vocab.joined(separator: "、"))")
            }
            if let entities = snapshot.entityCloud, !entities.isEmpty {
                snapParts.append("实体词云: \(entities.joined(separator: "、"))")
            }
            if !snapParts.isEmpty {
                contextSections.append("【近期上下文】\n\(snapParts.joined(separator: "\n"))")
            }
        }

        if contextLevel.rawValue >= ContextLevel.realtime.rawValue, let app = sourceApp, !app.isEmpty {
            contextSections.append("【当前环境】\n应用: \(app)")
        }

        if !contextSections.isEmpty {
            sections.append("以下为优先级从高到低的上下文环境，供转写过程参考：")
            sections.append(contentsOf: contextSections)
        }

        return sections.joined(separator: "\n\n")
    }

    /// Determine context level automatically based on recording duration.
    static func contextLevel(forDuration duration: TimeInterval) -> ContextLevel {
        if duration >= 45 {
            return .longTerm   // base + realtime + short-term + long-term
        } else if duration >= 15 {
            return .shortTerm  // base + realtime + short-term
        } else {
            return .realtime   // base + realtime only
        }
    }

    /// Build the enhanced system prompt combining context layers based on level.
    func buildEnhancedSystemPrompt(
        baseInstruction: String,
        appPrompt: String?,
        realtimeContext: RealtimeContext,
        glossaryTerms: [String] = [],
        contextLevel level: ContextLevel = .longTerm
    ) -> String {
        var sections: [String] = []

        // Base instruction (user-configured) — always included
        sections.append(baseInstruction)

        // Build context sections by priority (high → low)
        var contextSections: [String] = []

        // Glossary terms (highest priority) — always included
        if !glossaryTerms.isEmpty {
            contextSections.append("【术语表（最高优先级）】\n以下术语在转写时优先使用：\n\(glossaryTerms.joined(separator: "、"))")
        }

        // Long-term profile — only for longTerm level (≥45s)
        if level.rawValue >= ContextLevel.longTerm.rawValue, let profile = activeProfile {
            var profileParts: [String] = []
            if let id = profile.identity { profileParts.append("用户身份: \(id)") }
            if let domains = profile.primaryDomains, !domains.isEmpty {
                profileParts.append("主要领域: \(domains.joined(separator: "、"))")
            }
            if let habits = profile.languageHabits { profileParts.append("语言习惯: \(habits)") }
            if let entities = profile.fixedEntities, !entities.isEmpty {
                profileParts.append("常用实体: \(entities.joined(separator: "、"))")
            }
            if !profileParts.isEmpty {
                contextSections.append("【用户画像】\n\(profileParts.joined(separator: "\n"))")
            }
        }

        // Short-term snapshot — for shortTerm+ level (≥15s)
        if level.rawValue >= ContextLevel.shortTerm.rawValue, let snapshot = latestSnapshot {
            var snapParts: [String] = []
            if let topic = snapshot.topic { snapParts.append("当前话题: \(topic)") }
            if let intent = snapshot.currentIntent { snapParts.append("当前意图: \(intent)") }
            if let domain = snapshot.domainFocus { snapParts.append("领域聚焦: \(domain)") }
            if let vocab = snapshot.recentVocabulary, !vocab.isEmpty {
                snapParts.append("近期词汇: \(vocab.joined(separator: "、"))")
            }
            if let entities = snapshot.entityCloud, !entities.isEmpty {
                snapParts.append("实体词云: \(entities.joined(separator: "、"))")
            }
            if !snapParts.isEmpty {
                contextSections.append("【近期上下文】\n\(snapParts.joined(separator: "\n"))")
            }
        }

        // Real-time environment — for realtime+ level (always, since minimum is realtime)
        if level.rawValue >= ContextLevel.realtime.rawValue {
            let envSummary = realtimeContext.summary
            if envSummary != "无" {
                contextSections.append("【当前环境】\n\(envSummary)")
            }
        }

        // App-specific prompt override — always included
        if let appPrompt = appPrompt, !appPrompt.isEmpty {
            contextSections.append("【应用专属指令】\n\(appPrompt)")
        }

        if !contextSections.isEmpty {
            sections.append("以下为优先级从高到低的上下文环境，供转写过程参考：")
            sections.append(contentsOf: contextSections)
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Snapshot Generation

    private func generateShortTermSnapshot() async {
        guard !isSnapshotProcessing else { return }
        isSnapshotProcessing = true
        defer { isSnapshotProcessing = false }

        log("Generating short-term snapshot...")

        let context = PersistenceController.shared.container.viewContext
        let fetchRequest: NSFetchRequest<Recording> = Recording.fetchRequest()
        let oneHourAgo = Date().addingTimeInterval(-3600)
        fetchRequest.predicate = NSPredicate(format: "createdAt >= %@", oneHourAgo as NSDate)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Recording.createdAt, ascending: true)]

        do {
            let recordings = try context.fetch(fetchRequest)
            guard !recordings.isEmpty else {
                resetCounters()
                return
            }

            let texts = recordings.compactMap { r -> String? in
                let text = r.userEditedText ?? r.originalText
                return text?.isEmpty == false ? text : nil
            }
            guard !texts.isEmpty else {
                resetCounters()
                return
            }

            let correctionDiffs = buildCorrectionDiffs(from: recordings)
            var inputText = sanitizeText(texts.joined(separator: "\n"))

            if !correctionDiffs.isEmpty {
                inputText += "\n\n---用户纠正记录（高置信度信息）---\n" + correctionDiffs
            }

            let prompt = snapshotGenerationPrompt()
            let config = MultimodalConfigStore.shared.config

            let response = try await multimodalService.completeText(
                message: inputText,
                systemPrompt: prompt,
                config: config
            )

            if let data = parseSnapshotJSON(response) {
                saveSnapshotToCoreData(data: data, rawJSON: response)
                latestSnapshot = data
                latestSnapshotDate = Date()
                lastSnapshotDate = Date()
                resetCounters()
                log("Snapshot generated: topic=\(data.topic ?? "nil")")
            }
        } catch {
            log("Snapshot generation error: \(error)")
        }
    }

    // MARK: - Profile Generation

    private func generateLongTermProfile() async {
        guard !isProfileProcessing else { return }
        isProfileProcessing = true
        defer { isProfileProcessing = false }

        log("Generating long-term profile...")

        let context = PersistenceController.shared.container.viewContext
        let fetchRequest: NSFetchRequest<ContextSnapshot> = ContextSnapshot.fetchRequest()
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 86400)
        fetchRequest.predicate = NSPredicate(format: "createdAt >= %@", sevenDaysAgo as NSDate)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \ContextSnapshot.createdAt, ascending: true)]

        do {
            let snapshots = try context.fetch(fetchRequest)
            guard !snapshots.isEmpty else { return }

            let summaries = snapshots.compactMap { $0.rawJSON }
            guard !summaries.isEmpty else { return }

            var inputText = "近期上下文快照:\n" + summaries.joined(separator: "\n---\n")

            let recordingFetch: NSFetchRequest<Recording> = Recording.fetchRequest()
            recordingFetch.predicate = NSPredicate(format: "createdAt >= %@ AND userEditedText != nil", sevenDaysAgo as NSDate)
            recordingFetch.sortDescriptors = [NSSortDescriptor(keyPath: \Recording.createdAt, ascending: true)]
            if let editedRecordings = try? context.fetch(recordingFetch), !editedRecordings.isEmpty {
                let correctionDiffs = buildCorrectionDiffs(from: editedRecordings)
                if !correctionDiffs.isEmpty {
                    inputText += "\n\n---用户纠正记录（高置信度）---\n" + correctionDiffs
                }
            }

            if let current = activeProfile {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                if let currentJSON = try? encoder.encode(current),
                   let jsonStr = String(data: currentJSON, encoding: .utf8) {
                    inputText += "\n\n当前用户画像:\n\(jsonStr)"
                }
            }

            let prompt = profileGenerationPrompt()
            let config = MultimodalConfigStore.shared.config

            let response = try await multimodalService.completeText(
                message: inputText,
                systemPrompt: prompt,
                config: config
            )

            if let data = parseProfileJSON(response) {
                saveProfileToCoreData(data: data, rawJSON: response)
                activeProfile = data
                activeProfileDate = Date()
                lastProfileDate = Date()
                log("Profile generated: identity=\(data.identity ?? "nil")")
            }
        } catch {
            log("Profile generation error: \(error)")
        }
    }

    // MARK: - Correction Diff Building

    private func buildCorrectionDiffs(from recordings: [Recording]) -> String {
        var diffs: [String] = []

        for r in recordings {
            guard let edited = r.userEditedText, !edited.isEmpty,
                  let original = r.originalText, !original.isEmpty,
                  edited != original else { continue }

            let originalWords = original.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            let editedWords = edited.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

            let originalSet = Set(originalWords)
            let editedSet = Set(editedWords)

            let removed = originalSet.subtracting(editedSet)
            let added = editedSet.subtracting(originalSet)

            if !removed.isEmpty || !added.isEmpty {
                var diffLine = "纠正: "
                if !removed.isEmpty {
                    diffLine += "「\(removed.joined(separator: "、"))」→"
                }
                if !added.isEmpty {
                    diffLine += "「\(added.joined(separator: "、"))」"
                }
                diffs.append(diffLine)
            }
        }

        return sanitizeText(diffs.joined(separator: "\n"))
    }

    // MARK: - Sensitive Data Filtering

    private func sanitizeText(_ text: String) -> String {
        var result = text

        result = result.replacingOccurrences(
            of: "1[3-9]\\d{9}",
            with: "[手机号]",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: "\\d{17}[\\dXx]",
            with: "[身份证号]",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}",
            with: "[邮箱]",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: "(?:sk|ak|key|token|secret|password)[_-]?[a-zA-Z0-9]{16,}",
            with: "[密钥]",
            options: [.regularExpression, .caseInsensitive]
        )

        return result
    }

    // MARK: - Prompts

    private func snapshotGenerationPrompt() -> String {
        """
        你是一个上下文分析助手。分析以下语音转写文本，提取结构化信息。

        输入可能包含两部分：
        1. 语音转写文本（用户最近的语音输入）
        2. 用户纠正记录（用户手动修改了转写文本的部分，这是高置信度信息）

        特别注意：用户纠正记录中的"添加"词汇是用户确认的正确用词，应当优先收录到实体词云和近期词汇中。

        分析维度：
        1. 当前活动场景（如"代码调试"、"文档撰写"）
        2. 领域聚焦（技术栈、学科等）
        3. 实体词云（项目名、变量名、人名等专有名词，优先从用户纠正中提取）
        4. 近期高频词汇（优先从用户纠正中提取正确用词）
        5. 当前意图

        输出严格JSON格式（不要包含其他内容）：
        {"topic":"...","currentIntent":"...","domainFocus":"...","recentVocabulary":["..."],"entityCloud":["..."]}
        """
    }

    private func profileGenerationPrompt() -> String {
        """
        你是一个用户画像分析师。根据以下近期上下文快照，生成/更新用户长期画像。

        输入包含上下文快照的JSON摘要。快照中的实体词云和近期词汇可能来自用户手动纠正，这些是高置信度信息，应当优先纳入画像。

        分析维度：
        1. 职业身份推断
        2. 主要技术领域/知识领域
        3. 语言习惯（中英混用程度、口语特征）
        4. 固定实体（常提到的人名、项目名、工具名——特别关注跨多个快照重复出现的实体）

        输出严格JSON格式（不要包含其他内容）：
        {"identity":"...","primaryDomains":["..."],"languageHabits":"...","fixedEntities":["..."]}
        """
    }

    // MARK: - JSON Parsing

    private func parseSnapshotJSON(_ response: String) -> ContextSnapshotData? {
        guard let jsonStr = extractJSON(from: response),
              let data = jsonStr.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ContextSnapshotData.self, from: data)
    }

    private func parseProfileJSON(_ response: String) -> UserProfileData? {
        guard let jsonStr = extractJSON(from: response),
              let data = jsonStr.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(UserProfileData.self, from: data)
    }

    private func extractJSON(from text: String) -> String? {
        if let range = text.range(of: "\\{[^{}]*(?:\\{[^{}]*\\}[^{}]*)*\\}", options: .regularExpression) {
            return String(text[range])
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
            return trimmed
        }
        return nil
    }

    // MARK: - CoreData Operations

    private func loadLatestFromCoreData() {
        let context = PersistenceController.shared.container.viewContext

        let snapshotFetch: NSFetchRequest<ContextSnapshot> = ContextSnapshot.fetchRequest()
        snapshotFetch.sortDescriptors = [NSSortDescriptor(keyPath: \ContextSnapshot.createdAt, ascending: false)]
        snapshotFetch.fetchLimit = 1
        if let snapshot = try? context.fetch(snapshotFetch).first {
            latestSnapshotDate = snapshot.createdAt
            if let raw = snapshot.rawJSON {
                latestSnapshot = parseSnapshotJSON(raw)
            }
        }

        let profileFetch: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
        profileFetch.predicate = NSPredicate(format: "isActive == YES")
        profileFetch.sortDescriptors = [NSSortDescriptor(keyPath: \UserProfile.createdAt, ascending: false)]
        profileFetch.fetchLimit = 1
        if let profile = try? context.fetch(profileFetch).first {
            activeProfileDate = profile.createdAt
            if let raw = profile.rawJSON {
                activeProfile = parseProfileJSON(raw)
            }
        }
    }

    private func saveSnapshotToCoreData(data: ContextSnapshotData, rawJSON: String) {
        let context = PersistenceController.shared.container.viewContext
        let entity = ContextSnapshot(context: context)
        entity.id = UUID()
        entity.createdAt = Date()
        entity.topic = data.topic
        entity.currentIntent = data.currentIntent
        entity.domainFocus = data.domainFocus
        if let vocab = data.recentVocabulary, let json = try? JSONEncoder().encode(vocab) {
            entity.recentVocabulary = String(data: json, encoding: .utf8)
        }
        if let entities = data.entityCloud, let json = try? JSONEncoder().encode(entities) {
            entity.entityCloud = String(data: json, encoding: .utf8)
        }
        entity.rawJSON = rawJSON

        do {
            try context.save()
        } catch {
            log("Failed to save snapshot: \(error)")
        }
    }

    private func saveProfileToCoreData(data: UserProfileData, rawJSON: String) {
        let context = PersistenceController.shared.container.viewContext

        let fetchRequest: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "isActive == YES")
        if let existing = try? context.fetch(fetchRequest) {
            for profile in existing {
                profile.isActive = false
            }
        }

        let entity = UserProfile(context: context)
        entity.id = UUID()
        entity.createdAt = Date()
        entity.identity = data.identity
        if let domains = data.primaryDomains, let json = try? JSONEncoder().encode(domains) {
            entity.primaryDomains = String(data: json, encoding: .utf8)
        }
        entity.languageHabits = data.languageHabits
        if let entities = data.fixedEntities, let json = try? JSONEncoder().encode(entities) {
            entity.fixedEntities = String(data: json, encoding: .utf8)
        }
        entity.rawJSON = rawJSON
        entity.isActive = true

        do {
            try context.save()
        } catch {
            log("Failed to save profile: \(error)")
        }
    }

    // MARK: - Persist Manual Edits

    private func persistSnapshotChanges() {
        guard let snapshot = latestSnapshot else { return }
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest: NSFetchRequest<ContextSnapshot> = ContextSnapshot.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \ContextSnapshot.createdAt, ascending: false)]
        fetchRequest.fetchLimit = 1

        do {
            if let entity = try context.fetch(fetchRequest).first {
                if let vocab = snapshot.recentVocabulary, let json = try? JSONEncoder().encode(vocab) {
                    entity.recentVocabulary = String(data: json, encoding: .utf8)
                }
                if let entities = snapshot.entityCloud, let json = try? JSONEncoder().encode(entities) {
                    entity.entityCloud = String(data: json, encoding: .utf8)
                }
                if let rawData = try? JSONEncoder().encode(snapshot) {
                    entity.rawJSON = String(data: rawData, encoding: .utf8)
                }
                try context.save()
            }
        } catch {
            log("Failed to persist snapshot changes: \(error)")
        }
    }

    private func persistProfileChanges() {
        guard let profile = activeProfile else { return }
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest: NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "isActive == YES")
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \UserProfile.createdAt, ascending: false)]
        fetchRequest.fetchLimit = 1

        do {
            if let entity = try context.fetch(fetchRequest).first {
                if let domains = profile.primaryDomains, let json = try? JSONEncoder().encode(domains) {
                    entity.primaryDomains = String(data: json, encoding: .utf8)
                }
                if let entities = profile.fixedEntities, let json = try? JSONEncoder().encode(entities) {
                    entity.fixedEntities = String(data: json, encoding: .utf8)
                }
                if let rawData = try? JSONEncoder().encode(profile) {
                    entity.rawJSON = String(data: rawData, encoding: .utf8)
                }
                try context.save()
            }
        } catch {
            log("Failed to persist profile changes: \(error)")
        }
    }

    // MARK: - Helpers

    private func resetCounters() {
        utteranceCount = 0
        charCount = 0
    }

    private func log(_ msg: String) {
        let message = "[ContextProfile] \(msg)"
        NSLog("%@", message)
        DebugLogger.shared.log(message)
    }
}
