import SwiftUI

struct PromptsScreen: View {
    @EnvironmentObject var promptStore: PromptStore
    @StateObject private var contextService = ContextProfileService.shared
    @ObservedObject private var lang = LanguageManager.shared
    @State private var newTerm = ""
    @State private var isAddingAppPrompt = false
    @State private var newAppName = ""
    @State private var newAppBundleId = ""
    @State private var newAppPrompt = ""
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
                    ForEach(promptStore.config.appPrompts) { appPrompt in
                        AppPromptRow(appPrompt: appPrompt) {
                            if let idx = promptStore.config.appPrompts.firstIndex(where: { $0.id == appPrompt.id }) {
                                promptStore.config.appPrompts.remove(at: idx)
                            }
                        }
                    }
                }

                Divider()

                // Add new app prompt
                if isAddingAppPrompt {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(lang.s("prompts.app_name"), text: $newAppName)
                            .textFieldStyle(.roundedBorder)
                        TextField(lang.s("prompts.bundle_id"), text: $newAppBundleId)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        TextField(lang.s("prompts.prompt_content"), text: $newAppPrompt)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            Button(lang.s("prompts.cancel")) {
                                isAddingAppPrompt = false
                                resetNewAppFields()
                            }
                            .buttonStyle(.bordered)

                            Button(lang.s("prompts.add")) {
                                let prompt = AppPrompt(
                                    appName: newAppName,
                                    appBundleId: newAppBundleId.isEmpty ? nil : newAppBundleId,
                                    prompt: newAppPrompt
                                )
                                promptStore.addAppPrompt(prompt)
                                isAddingAppPrompt = false
                                resetNewAppFields()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newAppName.isEmpty || newAppPrompt.isEmpty)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.background.secondary)
                    )
                } else {
                    Button {
                        isAddingAppPrompt = true
                    } label: {
                        Label(lang.s("prompts.add_app_prompt"), systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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
        newAppName = ""
        newAppBundleId = ""
        newAppPrompt = ""
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
    let appPrompt: AppPrompt
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(appPrompt.appName)
                    .font(.callout.weight(.medium))
                if let bundleId = appPrompt.appBundleId {
                    Text(bundleId)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text(appPrompt.prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.background.secondary)
        )
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
