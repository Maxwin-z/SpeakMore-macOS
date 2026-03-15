import SwiftUI

struct PromptsScreen: View {
    @EnvironmentObject var promptStore: PromptStore
    @StateObject private var contextService = ContextProfileService.shared
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
                    Text("AI增强")
                        .font(.largeTitle.bold())
                    Text("自定义转写指令与术语表，提升识别准确性。术语表具有最高优先级。")
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
                Text("添加品牌名、技术术语等，确保转写时使用指定写法。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Input
                HStack(spacing: 8) {
                    TextField("输入术语…", text: $newTerm)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addTerm() }

                    Button("添加") { addTerm() }
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
                    Text("暂无术语")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            }
        } label: {
            Label("术语表", systemImage: "text.book.closed")
        }
    }

    // MARK: - Base Instruction Section

    private var baseInstructionHasChanges: Bool {
        editingBaseInstruction != promptStore.config.baseInstruction
    }

    private var baseInstructionSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("作为转写的基础指令发送给大模型，对所有应用生效。选择预设模板或自定义编辑。")
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
                    .onChange(of: editingBaseInstruction) { newValue in
                        // If user edits text to no longer match any template, clear selection
                        if let current = selectedTemplate, newValue != current.prompt {
                            selectedTemplate = nil
                        }
                        // If user edits text to match a template, select it
                        if selectedTemplate == nil {
                            for t in BaseInstructionTemplate.allCases where newValue == t.prompt {
                                selectedTemplate = t
                                break
                            }
                        }
                    }

                HStack(spacing: 8) {
                    if selectedTemplate == nil {
                        Text("自定义")
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

                    Button("还原") {
                        editingBaseInstruction = promptStore.config.baseInstruction
                        selectedTemplate = promptStore.config.baseInstructionTemplate
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!baseInstructionHasChanges)

                    Button("保存") {
                        promptStore.config.baseInstruction = editingBaseInstruction
                        promptStore.config.baseInstructionTemplate = selectedTemplate
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!baseInstructionHasChanges)
                }
            }
        } label: {
            Label("基础指令", systemImage: "text.alignleft")
        }
    }

    // MARK: - App-specific Prompts Section

    private var appPromptsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("为特定应用设置专属的转写指令，作为基础指令的补充。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if promptStore.config.appPrompts.isEmpty {
                    Text("暂无应用专属提示词")
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
                        TextField("应用名称", text: $newAppName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Bundle ID（可选）", text: $newAppBundleId)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                        TextField("提示词内容", text: $newAppPrompt)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            Button("取消") {
                                isAddingAppPrompt = false
                                resetNewAppFields()
                            }
                            .buttonStyle(.bordered)

                            Button("添加") {
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
                        Label("添加应用提示词", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        } label: {
            Label("应用专属提示词", systemImage: "app.badge.checkmark")
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
