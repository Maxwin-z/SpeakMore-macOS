import Foundation
import AppKit
import ApplicationServices

class TextInsertionService {

    private var savedElement: AXUIElement?
    private var savedAppName: String?
    private var savedAppBundleId: String?
    private var savedWindowTitle: String?
    private var savedDocumentPath: String?
    private var savedIsTextInput = false

    private var insertionStartOffset: Int?
    private var totalInsertedCharCount: Int = 0

    var capturedAppName: String? { savedAppName }
    var capturedAppBundleId: String? { savedAppBundleId }
    var capturedWindowTitle: String? { savedWindowTitle }
    var capturedDocumentPath: String? { savedDocumentPath }

    enum InsertionResult {
        case insertedViaAccessibility
        case insertedViaCGEvent
        case insertedViaClipboard
        case noTextFieldFocused
        case failed
    }

    private func debugLog(_ msg: String) {
        let message = "[TextInsertion] \(msg)"
        NSLog("%@", message)
        DispatchQueue.main.async { DebugLogger.shared.log(message) }
    }

    func captureFocusedElement() {
        savedElement = getFocusedElement()
        savedAppName = nil
        savedAppBundleId = nil
        savedWindowTitle = nil
        savedDocumentPath = nil
        savedIsTextInput = false

        if let element = savedElement {
            var role: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)

            // Get app info via NSWorkspace (reliable on macOS 26+)
            if let frontApp = NSWorkspace.shared.frontmostApplication {
                savedAppName = frontApp.localizedName ?? "unknown"
                savedAppBundleId = frontApp.bundleIdentifier

                let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
                var focusedWindow: AnyObject?
                if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow) == .success {
                    var winTitle: AnyObject?
                    AXUIElementCopyAttributeValue(focusedWindow as! AXUIElement, kAXTitleAttribute as CFString, &winTitle)
                    savedWindowTitle = winTitle as? String

                    var docPath: AnyObject?
                    AXUIElementCopyAttributeValue(focusedWindow as! AXUIElement, kAXDocumentAttribute as CFString, &docPath)
                    savedDocumentPath = docPath as? String
                }
            }

            savedIsTextInput = isTextInputElement(element)

            debugLog("Captured focus: app=\"\(savedAppName ?? "?")\", bundleId=\"\(savedAppBundleId ?? "?")\", window=\"\(savedWindowTitle ?? "?")\", isTextInput=\(savedIsTextInput)")
        } else {
            debugLog("captureFocusedElement: no focused element found")
        }
    }

    func hasCapturedTextInput() -> Bool {
        return savedElement != nil && savedIsTextInput
    }

    func clearCapturedElement() {
        savedElement = nil
        savedAppName = nil
        savedAppBundleId = nil
        savedWindowTitle = nil
        savedDocumentPath = nil
        savedIsTextInput = false
        insertionStartOffset = nil
        totalInsertedCharCount = 0
    }

    var hasInsertionTracking: Bool {
        return savedElement != nil && insertionStartOffset != nil && totalInsertedCharCount > 0
    }

    var insertedCharacterCount: Int {
        return totalInsertedCharCount
    }

    func captureInsertionStart() {
        insertionStartOffset = nil
        totalInsertedCharCount = 0

        guard let element = savedElement else { return }

        var rangeValue: AnyObject?
        let err = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue)
        guard err == .success, let range = rangeValue else { return }

        var cfRange = CFRange(location: 0, length: 0)
        guard AXValueGetValue(range as! AXValue, .cfRange, &cfRange) else { return }

        insertionStartOffset = cfRange.location
        debugLog("captureInsertionStart: cursor at offset \(cfRange.location)")
    }

    func selectInsertedText() -> Bool {
        guard let element = savedElement,
              let startOffset = insertionStartOffset,
              totalInsertedCharCount > 0 else { return false }

        var cfRange = CFRange(location: startOffset, length: totalInsertedCharCount)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else { return false }

        let selectResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        )
        guard selectResult == .success else { return false }

        var selectedText: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText)
        if let text = selectedText as? String, !text.isEmpty {
            debugLog("selectInsertedText: verified — selected \(text.count) chars")
            return true
        }

        return false
    }

    func insertText(_ text: String) async -> InsertionResult {
        debugLog("insertText called, text=\"\(text.prefix(80))\"")

        let focusedElement: AXUIElement
        if let saved = savedElement {
            focusedElement = saved
        } else {
            guard let live = getFocusedElement() else {
                return .noTextFieldFocused
            }
            focusedElement = live
        }

        var role: AnyObject?
        AXUIElementCopyAttributeValue(focusedElement, kAXRoleAttribute as CFString, &role)

        guard isTextInputElement(focusedElement) else {
            return .noTextFieldFocused
        }

        var axValueBefore: AnyObject?
        AXUIElementCopyAttributeValue(focusedElement, kAXValueAttribute as CFString, &axValueBefore)
        let canReadAXValue = (axValueBefore as? String) != nil
        let lengthBefore = (axValueBefore as? String)?.count ?? 0

        // Layer 1: Accessibility API
        let axResult = tryAccessibilityInsertion(text, element: focusedElement)
        switch axResult {
        case .inserted:
            totalInsertedCharCount += text.count
            return .insertedViaAccessibility
        case .fakeSuccess, .failed:
            break
        }

        // Layer 2: CGEvent keyboard simulation
        if tryCGEventInsertion(text) {
            if canReadAXValue {
                usleep(50_000)
                var axValueAfter: AnyObject?
                AXUIElementCopyAttributeValue(focusedElement, kAXValueAttribute as CFString, &axValueAfter)
                let lengthAfter = (axValueAfter as? String)?.count ?? 0
                if lengthAfter > lengthBefore {
                    totalInsertedCharCount += text.count
                    return .insertedViaCGEvent
                }
            } else {
                totalInsertedCharCount += text.count
                return .insertedViaCGEvent
            }
        }

        // Layer 3: Clipboard + Cmd+V
        let clipboardSuccess = await tryClipboardInsertion(text)
        if clipboardSuccess { totalInsertedCharCount += text.count }
        return clipboardSuccess ? .insertedViaClipboard : .failed
    }

    // MARK: - Accessibility API Insertion

    private enum AXInsertionResult {
        case inserted
        case fakeSuccess
        case failed
    }

    private func tryAccessibilityInsertion(_ text: String, element: AXUIElement) -> AXInsertionResult {
        var valueBefore: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueBefore)
        let lengthBefore = (valueBefore as? String)?.count ?? 0

        var settable: DarwinBoolean = false
        let checkResult = AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &settable
        )
        guard checkResult == .success, settable.boolValue else { return .failed }

        let setResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        guard setResult == .success else { return .failed }

        var valueAfter: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueAfter)
        let lengthAfter = (valueAfter as? String)?.count ?? 0

        if lengthAfter <= lengthBefore {
            return .fakeSuccess
        }

        return .inserted
    }

    // MARK: - CGEvent Unicode Insertion

    private func tryCGEventInsertion(_ text: String) -> Bool {
        let utf16 = Array(text.utf16)
        guard !utf16.isEmpty else { return false }

        let chunkSize = 20
        for startIndex in stride(from: 0, to: utf16.count, by: chunkSize) {
            let endIndex = min(startIndex + chunkSize, utf16.count)
            let chunk = Array(utf16[startIndex..<endIndex])

            guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else {
                return false
            }
            keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            keyDown.post(tap: .cgAnnotatedSessionEventTap)

            if let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                keyUp.post(tap: .cgAnnotatedSessionEventTap)
            }

            if endIndex < utf16.count {
                usleep(10_000)
            }
        }
        return true
    }

    // MARK: - Clipboard Fallback

    private func tryClipboardInsertion(_ text: String) async -> Bool {
        let pasteboard = NSPasteboard.general
        let savedChangeCount = pasteboard.changeCount

        let savedItems: [(NSPasteboard.PasteboardType, Data)] = pasteboard.pasteboardItems?.flatMap { item in
            item.types.compactMap { type in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            }
        } ?? []

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .hidSystemState)
        let vKeyCode: CGKeyCode = 0x09
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        try? await Task.sleep(nanoseconds: 500_000_000)

        if pasteboard.changeCount == savedChangeCount + 1, !savedItems.isEmpty {
            pasteboard.clearContents()
            let newItem = NSPasteboardItem()
            for (type, data) in savedItems {
                newItem.setData(data, forType: type)
            }
            pasteboard.writeObjects([newItem])
        }

        return true
    }

    // MARK: - Focus Detection

    private func getFocusedElement() -> AXUIElement? {
        // Try system-wide kAXFocusedApplicationAttribute first
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: AnyObject?
        let appResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )

        let appElement: AXUIElement
        if appResult == .success {
            appElement = focusedApp as! AXUIElement
        } else {
            // Fallback: use NSWorkspace to get frontmost app PID, then create AXUIElement
            debugLog("getFocusedElement: kAXFocusedApplicationAttribute failed (\(appResult.rawValue)), falling back to NSWorkspace")
            guard let frontApp = NSWorkspace.shared.frontmostApplication else {
                debugLog("getFocusedElement: NSWorkspace.frontmostApplication is nil")
                return nil
            }
            debugLog("getFocusedElement: frontmost app via NSWorkspace: \(frontApp.localizedName ?? "?") (pid=\(frontApp.processIdentifier))")
            appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        }

        let appTitle = axString(appElement, kAXTitleAttribute) ?? "unknown"
        debugLog("getFocusedElement: focused app=\"\(appTitle)\"")

        AXUIElementSetAttributeValue(
            appElement,
            "AXEnhancedUserInterface" as CFString,
            true as CFTypeRef
        )

        var focusedElement: AnyObject?
        let elemResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard elemResult == .success else {
            debugLog("getFocusedElement: kAXFocusedUIElementAttribute failed, error=\(elemResult.rawValue)")
            return nil
        }

        var element = focusedElement as! AXUIElement
        let role = axString(element, kAXRoleAttribute) ?? ""
        let subrole = axString(element, kAXSubroleAttribute) ?? ""
        debugLog("getFocusedElement: element role=\(role), subrole=\(subrole)")

        if role == "AXWebArea" {
            var webFocused: AnyObject?
            AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &webFocused)
            if let inner = webFocused as! AXUIElement? {
                let innerRole = axString(inner, kAXRoleAttribute) ?? ""
                if !innerRole.isEmpty && innerRole != "AXWebArea" {
                    debugLog("getFocusedElement: drilled into AXWebArea → role=\(innerRole)")
                    element = inner
                }
            }
        }

        return element
    }

    private func isTextInputElement(_ element: AXUIElement) -> Bool {
        let role = axString(element, kAXRoleAttribute) ?? "unknown"
        let subrole = axString(element, kAXSubroleAttribute)

        let (isInput, _) = classifyInputField(element, role: role, subrole: subrole)
        if isInput { return true }

        if let (_, parentElement) = walkParentsForInput(element) {
            savedElement = parentElement
            return true
        }

        return false
    }

    private func classifyInputField(_ element: AXUIElement, role: String, subrole: String?) -> (Bool, String) {
        let inputRoles: Set<String> = [
            "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField",
        ]
        if inputRoles.contains(role) {
            return (true, "role=\(role)")
        }

        let inputSubroles: Set<String> = ["AXSearchField", "AXSecureTextField"]
        if let sr = subrole, inputSubroles.contains(sr) {
            return (true, "subrole=\(sr)")
        }

        let containerRoles: Set<String> = [
            "AXWebArea", "AXScrollArea", "AXGroup", "AXList",
            "AXTable", "AXOutline", "AXStaticText", "AXImage",
            "AXButton", "AXLink", "AXHeading", "AXCell",
            "AXMenuButton", "AXMenu", "AXMenuItem",
        ]

        if !containerRoles.contains(role) {
            var attrNames: CFArray?
            AXUIElementCopyAttributeNames(element, &attrNames)
            let attrs = (attrNames as? [String]) ?? []

            if attrs.contains("AXSelectedTextRange") && attrs.contains("AXNumberOfCharacters") {
                return (true, "\(role) with text editing attrs")
            }
        }

        if role == "AXWebArea" {
            var settable: DarwinBoolean = false
            let err = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
            if err == .success && settable.boolValue {
                return (true, "editable AXWebArea")
            }
        }

        var domClassVal: AnyObject?
        AXUIElementCopyAttributeValue(element, "AXDOMClassList" as CFString, &domClassVal)
        if let classList = domClassVal as? [String] {
            let editorPatterns = ["monaco-editor", "codemirror", "ace_editor",
                                  "prosemirror", "ql-editor", "trix-editor",
                                  "cm-editor", "ce-editor"]
            for cls in classList {
                let lower = cls.lowercased()
                for pattern in editorPatterns {
                    if lower.contains(pattern) {
                        return (true, "DOM class=\(cls)")
                    }
                }
            }
        }

        let roleDesc = axString(element, kAXRoleDescriptionAttribute) ?? ""
        if roleDesc.lowercased().contains("editing") || roleDesc.lowercased().contains("text entry") {
            return (true, "roleDesc=\(roleDesc)")
        }

        var settable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable)
        if result == .success && settable.boolValue {
            return (true, "kAXSelectedTextAttribute settable")
        }

        return (false, "")
    }

    private func walkParentsForInput(_ element: AXUIElement) -> (reason: String, element: AXUIElement)? {
        var current = element
        for depth in 1...8 {
            var parentRef: AnyObject?
            AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentRef)
            guard let parent = parentRef as! AXUIElement? else { return nil }

            let role = axString(parent, kAXRoleAttribute) ?? ""
            let subrole = axString(parent, kAXSubroleAttribute)

            if role == "AXApplication" || role == "AXWindow" { return nil }

            if role == "AXWebArea" {
                let (isInput, reason) = classifyInputField(parent, role: role, subrole: subrole)
                if isInput { return ("\(reason) at depth \(depth)", parent) }
                return nil
            }

            let (isInput, reason) = classifyInputField(parent, role: role, subrole: subrole)
            if isInput { return ("\(reason) at depth \(depth)", parent) }

            current = parent
        }
        return nil
    }

    private func axString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }
}
