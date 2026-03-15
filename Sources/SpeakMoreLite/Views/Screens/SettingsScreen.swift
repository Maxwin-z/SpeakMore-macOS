import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var multimodalStore: MultimodalConfigStore
    @ObservedObject private var lang = LanguageManager.shared
    @State private var currentHotkeyDisplay = "FN"
    @State private var isRecordingHotkey = false
    @State private var apiKeyVisible = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(lang.s("settings.title"))
                    .font(.largeTitle.bold())
                    .padding(.bottom, 4)

                // MARK: - Language
                languageSection

                // MARK: - Permissions
                permissionsSection

                // MARK: - Hotkey
                hotkeySection

                // MARK: - Multimodal API
                multimodalSection
            }
            .padding(24)
        }
        .onAppear {
            appViewModel.checkPermissions()
            currentHotkeyDisplay = appViewModel.currentHotkeyConfig.displayString
        }
    }

    // MARK: - Language Section

    private var languageSection: some View {
        GroupBox {
            Picker(lang.s("settings.interface_language"), selection: $lang.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.menu)
        } label: {
            Label(lang.s("settings.language"), systemImage: "globe")
        }
    }

    // MARK: - Permissions Section

    private var permissionsSection: some View {
        GroupBox {
            VStack(spacing: 10) {
                PermissionRow(
                    icon: "hand.raised.fill",
                    title: lang.s("settings.accessibility_permission"),
                    description: lang.s("settings.accessibility_desc"),
                    isGranted: appViewModel.isAccessibilityGranted,
                    actionTitle: lang.s("settings.authorize")
                ) {
                    appViewModel.requestAccessibilityPermission()
                }

                if currentHotkeyDisplay == "FN" {
                    Divider()

                    PermissionRow(
                        icon: "keyboard",
                        title: lang.s("settings.fn_key_setup"),
                        description: lang.s("settings.fn_key_desc"),
                        isGranted: appViewModel.isFnKeyConfigured,
                        actionTitle: lang.s("settings.open_keyboard_settings")
                    ) {
                        appViewModel.openKeyboardSettings()
                    }
                }
            }
        } label: {
            Label(lang.s("settings.permission_status"), systemImage: "shield.checkered")
        }
    }

    // MARK: - Hotkey Section

    private var hotkeySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HotkeyRecorderView(
                    currentDisplay: $currentHotkeyDisplay,
                    isRecording: $isRecordingHotkey,
                    onHotkeyRecorded: { config in
                        appViewModel.updateHotkey(config)
                    },
                    onResetToDefault: {
                        appViewModel.updateHotkey(.defaultFn)
                    }
                )

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(lang.s("settings.hotkey_hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label(lang.s("settings.hotkey"), systemImage: "command.square")
        }
    }

    // MARK: - Multimodal API Section

    private var multimodalSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                // Provider selection
                Picker(lang.s("settings.provider"), selection: $multimodalStore.config.provider) {
                    ForEach(MultimodalProvider.allCases) { provider in
                        Label(provider.displayName, systemImage: provider.icon)
                            .tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: multimodalStore.config.provider) {
                    let newProvider = multimodalStore.config.provider
                    multimodalStore.config.endpoint = newProvider.defaultEndpoint
                    if let first = newProvider.defaultModels.first {
                        multimodalStore.config.selectedModelId = first.id
                    }
                    multimodalStore.config.customModelId = ""
                    apiKeyVisible = false
                }

                Divider()

                // API Key
                VStack(alignment: .leading, spacing: 6) {
                    Text("API Key")
                        .font(.subheadline.weight(.medium))

                    HStack(spacing: 8) {
                        Group {
                            if apiKeyVisible {
                                TextField(lang.s("settings.api_key_placeholder"), text: $multimodalStore.config.apiKey)
                                    .textFieldStyle(.roundedBorder)
                            } else if multimodalStore.config.apiKey.isEmpty {
                                TextField(lang.s("settings.api_key_placeholder"), text: $multimodalStore.config.apiKey)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                Text(maskedApiKey(multimodalStore.config.apiKey))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                                    )
                            }
                        }
                        .font(.system(.body, design: .monospaced))

                        Button {
                            apiKeyVisible.toggle()
                        } label: {
                            Image(systemName: apiKeyVisible ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                // API Endpoint
                VStack(alignment: .leading, spacing: 6) {
                    Text(lang.s("settings.api_endpoint"))
                        .font(.subheadline.weight(.medium))

                    TextField("https://…", text: $multimodalStore.config.endpoint)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                // Model selection
                modelSelectionSection

                // Custom model ID
                VStack(alignment: .leading, spacing: 6) {
                    Text(lang.s("settings.custom_model_id"))
                        .font(.subheadline.weight(.medium))
                    Text(lang.s("settings.custom_model_hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField(lang.s("settings.custom_model_placeholder"), text: $multimodalStore.config.customModelId)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                Divider()

                // Status
                HStack(spacing: 6) {
                    Image(systemName: multimodalStore.isConfigured ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(multimodalStore.isConfigured ? .green : .orange)
                    Text(multimodalStore.isConfigured
                         ? String(format: lang.s("settings.configured_fmt"), multimodalStore.config.provider.displayName)
                         : lang.s("settings.enter_api_key"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label(lang.s("settings.multimodal_api"), systemImage: "waveform.badge.magnifyingglass")
        }
    }

    // MARK: - Helpers

    private func maskedApiKey(_ key: String) -> String {
        if key.count <= 6 { return key }
        return String(key.prefix(6)) + String(repeating: "•", count: min(key.count - 6, 20))
    }

    // MARK: - Model Selection

    @ViewBuilder
    private var modelSelectionSection: some View {
        let models = multimodalStore.config.provider.defaultModels
        if !models.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(lang.s("settings.model"))
                    .font(.subheadline.weight(.medium))

                ForEach(models) { model in
                    ModelSelectionRow(
                        model: model,
                        isSelected: multimodalStore.config.selectedModelId == model.id
                            && multimodalStore.config.customModelId.trimmingCharacters(in: .whitespaces).isEmpty
                    ) {
                        multimodalStore.config.selectedModelId = model.id
                        multimodalStore.config.customModelId = ""
                    }
                }
            }
        }
    }
}

// MARK: - Permission Row

private struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : icon)
                .font(.title3)
                .foregroundStyle(isGranted ? .green : .orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if !isGranted {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}

// MARK: - Model Selection Row

private struct ModelSelectionRow: View {
    let model: MultimodalModel
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(model.displayName)
                        .font(.callout.weight(.medium))
                    Text(model.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Hotkey Recorder

struct HotkeyRecorderView: View {
    @Binding var currentDisplay: String
    @Binding var isRecording: Bool
    var onHotkeyRecorded: (HotkeyConfig) -> Void
    var onResetToDefault: () -> Void
    @ObservedObject private var lang = LanguageManager.shared

    @State private var pulseOpacity: Double = 1.0
    @State private var pendingModifiers: String = ""
    @State private var localMonitor: Any?
    @State private var flagsMonitor: Any?
    @State private var pendingModifierKeyCode: UInt16? = nil
    @State private var activeModifierKeyCodes: Set<UInt16> = []

    var body: some View {
        HStack(spacing: 12) {
            // Hotkey display
            HStack(spacing: 6) {
                if isRecording {
                    if pendingModifiers.isEmpty {
                        Text(lang.s("settings.press_hotkey"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.blue)
                            .opacity(pulseOpacity)
                            .onAppear {
                                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                                    pulseOpacity = 0.4
                                }
                            }
                            .onDisappear {
                                pulseOpacity = 1.0
                            }
                    } else {
                        Text(pendingModifiers + " ...")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.blue)
                    }
                } else {
                    ForEach(currentDisplay.split(separator: " ").map(String.init), id: \.self) { part in
                        Text(part)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.primary.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                            )
                    }
                }
            }
            .frame(minWidth: 120, minHeight: 28)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isRecording ? Color.blue.opacity(0.06) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isRecording ? Color.blue.opacity(0.3) : Color.primary.opacity(0.1), lineWidth: isRecording ? 1.5 : 0.5)
            )

            // Record button
            Button(isRecording ? lang.s("settings.cancel") : lang.s("settings.record_hotkey")) {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }
            .controlSize(.small)
            .buttonStyle(.bordered)

            // Reset button
            if currentDisplay != "FN" && !isRecording {
                Button(lang.s("settings.reset_default")) {
                    currentDisplay = "FN"
                    onResetToDefault()
                }
                .controlSize(.small)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Recording Logic

    private func startRecording() {
        isRecording = true
        pendingModifiers = ""
        pendingModifierKeyCode = nil
        activeModifierKeyCodes = []
        installMonitors()
    }

    private func stopRecording() {
        removeMonitors()
        pendingModifiers = ""
        pendingModifierKeyCode = nil
        activeModifierKeyCodes = []
        isRecording = false
    }

    private func installMonitors() {
        // Monitor keyDown to capture the main key (non-modifier keys)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Escape cancels recording
            if event.keyCode == 53 { // kVK_Escape
                stopRecording()
                return nil
            }

            // A non-modifier key was pressed — this is a regular hotkey (possibly with modifiers)
            pendingModifierKeyCode = nil

            let keyCode = event.keyCode
            let relevantModifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])

            // Build device mask from tracked modifier keyCodes for left/right distinction
            var deviceMask: UInt = 0
            for kc in activeModifierKeyCodes {
                deviceMask |= nxDeviceMaskForKeyCode(kc)
            }

            let displayString: String
            if deviceMask != 0 {
                displayString = buildHotkeyDisplayStringWithDeviceMask(keyCode: keyCode, deviceMask: deviceMask)
            } else {
                displayString = buildHotkeyDisplayString(keyCode: keyCode, modifiers: relevantModifiers)
            }

            let config = HotkeyConfig(
                keyCode: keyCode,
                modifierFlags: UInt(relevantModifiers.rawValue),
                modifierDeviceMask: deviceMask,
                isFnKey: false,
                displayString: displayString
            )

            currentDisplay = displayString
            onHotkeyRecorded(config)
            stopRecording()
            return nil
        }

        // Monitor flagsChanged for:
        // 1. Real-time modifier preview when building a combo (with left/right distinction)
        // 2. Single modifier key recording (press then release = confirm)
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            guard isRecording else { return event }

            let keyCode = event.keyCode

            // Detect Fn key
            let relevantModifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            let fnPressed = event.modifierFlags.contains(.function)

            if fnPressed && relevantModifiers.isEmpty && keyCode == 0x3F {
                currentDisplay = "FN"
                onHotkeyRecorded(.defaultFn)
                stopRecording()
                return nil
            }

            // Is this a modifier key?
            if modifierKeyCodes.contains(keyCode) {
                let deviceMask = nxDeviceMaskForKeyCode(keyCode)
                let isPressed = (event.modifierFlags.rawValue & deviceMask) != 0

                if isPressed {
                    // If another modifier is already held, this is a multi-modifier combo
                    if activeModifierKeyCodes.isEmpty {
                        pendingModifierKeyCode = keyCode
                    } else {
                        // Multiple modifiers pressed — not a solo modifier tap
                        pendingModifierKeyCode = nil
                    }
                    activeModifierKeyCodes.insert(keyCode)

                    // Show all active modifiers with left/right distinction
                    let parts = sortedModifierKeyCodes(activeModifierKeyCodes).map { modifierKeyCodeToString($0) }
                    pendingModifiers = parts.joined(separator: " ")
                } else {
                    // Modifier released
                    if pendingModifierKeyCode == keyCode && activeModifierKeyCodes.count == 1 {
                        // The only modifier was pressed and released with no other key → solo modifier tap
                        let displayStr = modifierKeyCodeToString(keyCode)

                        let config = HotkeyConfig(
                            keyCode: keyCode,
                            modifierFlags: 0,
                            isFnKey: false,
                            isModifierOnly: true,
                            displayString: displayStr
                        )

                        currentDisplay = displayStr
                        onHotkeyRecorded(config)
                        stopRecording()
                        return nil
                    }

                    activeModifierKeyCodes.remove(keyCode)

                    // Update preview with remaining modifiers (left/right aware)
                    if activeModifierKeyCodes.isEmpty {
                        pendingModifiers = ""
                    } else {
                        let parts = sortedModifierKeyCodes(activeModifierKeyCodes).map { modifierKeyCodeToString($0) }
                        pendingModifiers = parts.joined(separator: " ")
                    }
                }
            }

            return event
        }
    }

    private func removeMonitors() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
    }
}
