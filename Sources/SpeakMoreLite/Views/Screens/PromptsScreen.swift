import SwiftUI

struct PromptsScreen: View {
    @EnvironmentObject var promptStore: PromptStore
    @StateObject private var contextService = ContextProfileService.shared
    @ObservedObject private var lang = LanguageManager.shared
    @State private var newTerm = ""
    @State private var isAddingAppPrompt = false
    @State private var selectedApp: InstalledApp? = nil
    @State private var newAppPromptTags: [String] = []
    @State private var newAppTagInput = ""
    @State private var editingBaseInstruction = ""
    @State private var selectedTemplate: BaseInstructionTemplate? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title
                VStack(alignment: .leading, spacing: 4) {
                    Text(lang.s("prompts.title"))
                        .font(.largeTitle.bold())
                    Text(lang.s("prompts.subtitle"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                // MARK: - Context Preview
                ContextPreviewSection(contextService: contextService)

                // MARK: - Glossary
                glossarySection

                // MARK: - Base Instruction
                baseInstructionSection

                // MARK: - App-specific Prompts
                appPromptsSection
            }
            .padding(24)
        }
        .onAppear {
            editingBaseInstruction = promptStore.config.baseInstruction
            selectedTemplate = promptStore.config.baseInstructionTemplate
        }
    }

    // MARK: - Glossary Section

    private var glossarySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(lang.s("prompts.glossary_desc"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Input
                HStack(spacing: 8) {
                    TextField(lang.s("prompts.enter_term"), text: $newTerm)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addTerm() }

                    Button(lang.s("prompts.add")) { addTerm() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                // Tags
                if !promptStore.config.glossaryTerms.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(promptStore.config.glossaryTerms, id: \.self) { term in
                            GlossaryTag(term: term) {
                                promptStore.removeGlossaryTerm(term)
                            }
                        }
                    }
                } else {
                    Text(lang.s("prompts.no_terms"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            }
        } label: {
            Label(lang.s("prompts.glossary"), systemImage: "text.book.closed")
        }
    }

    // MARK: - Base Instruction Section

    private var baseInstructionHasChanges: Bool {
        editingBaseInstruction != promptStore.config.baseInstruction
    }

    private var baseInstructionSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(lang.s("prompts.base_instruction_desc"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Template picker
                HStack(spacing: 6) {
                    ForEach(BaseInstructionTemplate.allCases) { template in
                        Button {
                            selectedTemplate = template
                            editingBaseInstruction = template.prompt
                        } label: {
                            VStack(spacing: 4) {
                                Text(template.displayName)
                                    .font(.callout.weight(.medium))
                                Text(template.description)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2, reservesSpace: true)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 6)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(selectedTemplate == template ? Color.accentColor.opacity(0.12) : .clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(selectedTemplate == template ? Color.accentColor.opacity(1) : Color.gray.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                TextEditor(text: $editingBaseInstruction)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 80, maxHeight: 160)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.background.secondary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.quaternary, lineWidth: 1)
                    )
                    .onChange(of: editingBaseInstruction) {
                        // If user edits text to no longer match any template, clear selection
                        if let current = selectedTemplate, editingBaseInstruction != current.prompt {
                            selectedTemplate = nil
                        }
                        // If user edits text to match a template, select it
                        if selectedTemplate == nil {
                            for t in BaseInstructionTemplate.allCases where editingBaseInstruction == t.prompt {
                                selectedTemplate = t
                                break
                            }
                        }
                    }

                HStack(spacing: 8) {
                    if selectedTemplate == nil {
                        Text(lang.s("prompts.custom"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(.orange.opacity(0.12))
                            )
                    }

                    Spacer()

                    Button(lang.s("prompts.revert")) {
                        editingBaseInstruction = promptStore.config.baseInstruction
                        selectedTemplate = promptStore.config.baseInstructionTemplate
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!baseInstructionHasChanges)

                    Button(lang.s("prompts.save")) {
                        promptStore.config.baseInstruction = editingBaseInstruction
                        promptStore.config.baseInstructionTemplate = selectedTemplate
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!baseInstructionHasChanges)
                }
            }
        } label: {
            Label(lang.s("prompts.base_instruction"), systemImage: "text.alignleft")
        }
    }

    // MARK: - App-specific Prompts Section

    private var appPromptsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(lang.s("prompts.app_prompts_desc"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if promptStore.config.appPrompts.isEmpty {
                    Text(lang.s("prompts.no_app_prompts"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    ForEach($promptStore.config.appPrompts) { $appPrompt in
                        AppPromptRow(appPrompt: $appPrompt) {
                            if let idx = promptStore.config.appPrompts.firstIndex(where: { $0.id == appPrompt.id }) {
                                promptStore.config.appPrompts.remove(at: idx)
                            }
                        }
                    }
                }

                Divider()

                // Add new app prompt
                if isAddingAppPrompt, let app = selectedApp {
                    // Step 2: Enter prompt tags for selected app
                    VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(nsImage: app.icon)
                                    .resizable()
                                    .frame(width: 24, height: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(app.name)
                                        .font(.callout.weight(.medium))
                                    Text(app.bundleId)
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Button {
                                    selectedApp = nil
                                } label: {
                                    Text(lang.s("prompts.change_app"))
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            // Tags already added
                            if !newAppPromptTags.isEmpty {
                                FlowLayout(spacing: 6) {
                                    ForEach(newAppPromptTags, id: \.self) { tag in
                                        PromptTag(tag: tag) {
                                            newAppPromptTags.removeAll { $0 == tag }
                                        }
                                    }
                                }
                            }

                            // Input for new tag
                            HStack(spacing: 8) {
                                TextField(lang.s("prompts.enter_prompt_tag"), text: $newAppTagInput)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption)
                                    .onSubmit { addNewAppTag() }

                                Button(lang.s("prompts.add")) { addNewAppTag() }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(newAppTagInput.trimmingCharacters(in: .whitespaces).isEmpty)
                            }

                            HStack {
                                Button(lang.s("prompts.cancel")) {
                                    isAddingAppPrompt = false
                                    resetNewAppFields()
                                }
                                .buttonStyle(.bordered)

                                Button(lang.s("prompts.done")) {
                                    let prompt = AppPrompt(
                                        appName: app.name,
                                        appBundleId: app.bundleId,
                                        prompts: newAppPromptTags
                                    )
                                    promptStore.addAppPrompt(prompt)
                                    isAddingAppPrompt = false
                                    resetNewAppFields()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(newAppPromptTags.isEmpty)
                            }
                        }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.background.secondary)
                    )
                }

                if !isAddingAppPrompt || selectedApp == nil {
                    Button {
                        isAddingAppPrompt = true
                    } label: {
                        Label(lang.s("prompts.add_app_prompt"), systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .popover(isPresented: Binding(
                        get: { isAddingAppPrompt && selectedApp == nil },
                        set: { if !$0 { isAddingAppPrompt = false; resetNewAppFields() } }
                    ), arrowEdge: .bottom) {
                        AppPickerView(
                            existingBundleIds: Set(promptStore.config.appPrompts.compactMap(\.appBundleId)),
                            onSelect: { app in
                                selectedApp = app
                            },
                            onCancel: {
                                isAddingAppPrompt = false
                                resetNewAppFields()
                            }
                        )
                    }
                }
            }
        } label: {
            Label(lang.s("prompts.app_prompts"), systemImage: "app.badge.checkmark")
        }
    }

    // MARK: - Helpers

    private func addTerm() {
        promptStore.addGlossaryTerm(newTerm)
        newTerm = ""
    }

    private func resetNewAppFields() {
        selectedApp = nil
        newAppPromptTags = []
        newAppTagInput = ""
    }

    private func addNewAppTag() {
        let trimmed = newAppTagInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !newAppPromptTags.contains(trimmed) else { return }
        newAppPromptTags.append(trimmed)
        newAppTagInput = ""
    }
}

// MARK: - Glossary Tag

private struct GlossaryTag: View {
    let term: String
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(term)
                .font(.callout)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}

// MARK: - App Prompt Row

private struct AppPromptRow: View {
    @Binding var appPrompt: AppPrompt
    let onDelete: () -> Void

    @ObservedObject private var lang = LanguageManager.shared
    @State private var newTag = ""

    private var appIcon: NSImage? {
        guard let bundleId = appPrompt.appBundleId,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                if let icon = appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 28, height: 28)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(appPrompt.appName)
                        .font(.callout.weight(.medium))
                    if let bundleId = appPrompt.appBundleId {
                        Text(bundleId)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            // Prompt tags
            if !appPrompt.prompts.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(appPrompt.prompts, id: \.self) { tag in
                        PromptTag(tag: tag) {
                            appPrompt.prompts.removeAll { $0 == tag }
                        }
                    }
                }
            }

            // Add new tag
            HStack(spacing: 8) {
                TextField(lang.s("prompts.enter_prompt_tag"), text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .onSubmit { addTag() }

                Button(lang.s("prompts.add")) { addTag() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.background.secondary)
        )
    }

    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !appPrompt.prompts.contains(trimmed) else { return }
        appPrompt.prompts.append(trimmed)
        newTag = ""
    }
}

// MARK: - Prompt Tag

private struct PromptTag: View {
    let tag: String
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.caption)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - App Picker View

private struct AppPickerView: View {
    let existingBundleIds: Set<String>
    let onSelect: (InstalledApp) -> Void
    let onCancel: () -> Void

    @StateObject private var scanner = InstalledAppScanner()
    @ObservedObject private var lang = LanguageManager.shared
    @State private var searchText = ""

    private var filteredApps: [InstalledApp] {
        let available = scanner.apps.filter { !existingBundleIds.contains($0.bundleId) }
        if searchText.isEmpty { return available }
        let query = searchText.lowercased()
        return available.filter {
            $0.name.lowercased().contains(query) || $0.bundleId.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lang.s("prompts.select_app"))
                .font(.callout.weight(.medium))

            TextField(lang.s("prompts.search_app"), text: $searchText)
                .textFieldStyle(.roundedBorder)

            if scanner.isScanning {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(lang.s("prompts.scanning_apps"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredApps) { app in
                            AppPickerRow(app: app, onSelect: onSelect)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .padding(16)
        .frame(width: 500, height: 420)
        .onAppear {
            scanner.scan()
        }
    }
}

// MARK: - App Picker Row

private struct AppPickerRow: View {
    let app: InstalledApp
    let onSelect: (InstalledApp) -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            onSelect(app)
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(app.name)
                            .font(.callout)
                        if app.isRunning {
                            Circle()
                                .fill(.green)
                                .frame(width: 6, height: 6)
                        }
                    }
                    Text(app.bundleId)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.accentColor.opacity(0.08) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews)
        -> (positions: [CGPoint], sizes: [CGSize], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            sizes.append(size)
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return (positions, sizes, CGSize(width: maxX, height: y + rowHeight))
    }
}
