import Foundation
import AppKit
import Carbon.HIToolbox

// MARK: - Hotkey Configuration

struct HotkeyConfig: Codable, Equatable {
    let keyCode: UInt16
    let modifierFlags: UInt
    /// NX device masks for left/right modifier distinction in combo hotkeys.
    /// 0 means no left/right distinction (backward compatible).
    let modifierDeviceMask: UInt
    let isFnKey: Bool
    let isModifierOnly: Bool
    let displayString: String

    static let defaultFn = HotkeyConfig(
        keyCode: .max,
        modifierFlags: 0,
        isFnKey: true,
        isModifierOnly: false,
        displayString: "FN"
    )

    init(keyCode: UInt16, modifierFlags: UInt, modifierDeviceMask: UInt = 0, isFnKey: Bool, isModifierOnly: Bool = false, displayString: String) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.modifierDeviceMask = modifierDeviceMask
        self.isFnKey = isFnKey
        self.isModifierOnly = isModifierOnly
        self.displayString = displayString
    }

    // MARK: - Custom Codable (backward compatible)

    enum CodingKeys: String, CodingKey {
        case keyCode, modifierFlags, modifierDeviceMask, isFnKey, isModifierOnly, displayString
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        modifierFlags = try container.decode(UInt.self, forKey: .modifierFlags)
        modifierDeviceMask = try container.decodeIfPresent(UInt.self, forKey: .modifierDeviceMask) ?? 0
        isFnKey = try container.decode(Bool.self, forKey: .isFnKey)
        isModifierOnly = try container.decodeIfPresent(Bool.self, forKey: .isModifierOnly) ?? false
        displayString = try container.decode(String.self, forKey: .displayString)
    }

    // MARK: - Persistence

    private static let userDefaultsKey = "customHotkey"

    static func load() -> HotkeyConfig {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) else {
            return .defaultFn
        }
        return config
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: HotkeyConfig.userDefaultsKey)
        }
    }
}

// MARK: - NX Device-dependent modifier masks (for left/right distinction)

enum NXDeviceMask {
    static let leftControl:  UInt = 0x00000001
    static let leftShift:    UInt = 0x00000002
    static let rightShift:   UInt = 0x00000004
    static let leftCommand:  UInt = 0x00000008
    static let rightCommand: UInt = 0x00000010
    static let leftOption:   UInt = 0x00000020
    static let rightOption:  UInt = 0x00000040
    static let rightControl: UInt = 0x00002000
}

// MARK: - Modifier Key keyCodes

let modifierKeyCodes: Set<UInt16> = [
    UInt16(kVK_Command),
    UInt16(kVK_RightCommand),
    UInt16(kVK_Shift),
    UInt16(kVK_RightShift),
    UInt16(kVK_Option),
    UInt16(kVK_RightOption),
    UInt16(kVK_Control),
    UInt16(kVK_RightControl),
]

func nxDeviceMaskForKeyCode(_ keyCode: UInt16) -> UInt {
    switch Int(keyCode) {
    case kVK_Command:       return NXDeviceMask.leftCommand
    case kVK_RightCommand:  return NXDeviceMask.rightCommand
    case kVK_Shift:         return NXDeviceMask.leftShift
    case kVK_RightShift:    return NXDeviceMask.rightShift
    case kVK_Option:        return NXDeviceMask.leftOption
    case kVK_RightOption:   return NXDeviceMask.rightOption
    case kVK_Control:       return NXDeviceMask.leftControl
    case kVK_RightControl:  return NXDeviceMask.rightControl
    default: return 0
    }
}

func modifierKeyCodeToString(_ keyCode: UInt16) -> String {
    switch Int(keyCode) {
    case kVK_Command:       return L("hotkey.left_cmd")
    case kVK_RightCommand:  return L("hotkey.right_cmd")
    case kVK_Shift:         return L("hotkey.left_shift")
    case kVK_RightShift:    return L("hotkey.right_shift")
    case kVK_Option:        return L("hotkey.left_opt")
    case kVK_RightOption:   return L("hotkey.right_opt")
    case kVK_Control:       return L("hotkey.left_ctrl")
    case kVK_RightControl:  return L("hotkey.right_ctrl")
    default: return "Mod\(keyCode)"
    }
}

// MARK: - Key Display Mapping

func modifierFlagsToSymbols(_ flags: NSEvent.ModifierFlags) -> String {
    var parts: [String] = []
    if flags.contains(.control) { parts.append("⌃") }
    if flags.contains(.option)  { parts.append("⌥") }
    if flags.contains(.shift)   { parts.append("⇧") }
    if flags.contains(.command) { parts.append("⌘") }
    return parts.joined(separator: " ")
}

func keyCodeToString(_ keyCode: UInt16) -> String {
    switch Int(keyCode) {
    case kVK_F1:  return "F1"
    case kVK_F2:  return "F2"
    case kVK_F3:  return "F3"
    case kVK_F4:  return "F4"
    case kVK_F5:  return "F5"
    case kVK_F6:  return "F6"
    case kVK_F7:  return "F7"
    case kVK_F8:  return "F8"
    case kVK_F9:  return "F9"
    case kVK_F10: return "F10"
    case kVK_F11: return "F11"
    case kVK_F12: return "F12"
    case kVK_Return:        return "⏎"
    case kVK_Tab:           return "⇥"
    case kVK_Space:         return "Space"
    case kVK_Delete:        return "⌫"
    case kVK_Escape:        return "⎋"
    case kVK_UpArrow:    return "↑"
    case kVK_DownArrow:  return "↓"
    case kVK_LeftArrow:  return "←"
    case kVK_RightArrow: return "→"
    case kVK_Command:       return L("hotkey.left_cmd")
    case kVK_RightCommand:  return L("hotkey.right_cmd")
    case kVK_Shift:         return L("hotkey.left_shift")
    case kVK_RightShift:    return L("hotkey.right_shift")
    case kVK_Option:        return L("hotkey.left_opt")
    case kVK_RightOption:   return L("hotkey.right_opt")
    case kVK_Control:       return L("hotkey.left_ctrl")
    case kVK_RightControl:  return L("hotkey.right_ctrl")
    default:
        return characterForKeyCode(keyCode)
    }
}

private func characterForKeyCode(_ keyCode: UInt16) -> String {
    let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
    guard let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
        return "Key\(keyCode)"
    }
    let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self) as Data
    return layoutData.withUnsafeBytes { rawBuffer -> String in
        guard let ptr = rawBuffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
            return "Key\(keyCode)"
        }
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length: Int = 0
        let result = UCKeyTranslate(
            ptr,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            UInt32(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            chars.count,
            &length,
            &chars
        )
        if result == noErr, length > 0 {
            return String(utf16CodeUnits: chars, count: length).uppercased()
        }
        return "Key\(keyCode)"
    }
}

func buildHotkeyDisplayString(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
    let modStr = modifierFlagsToSymbols(modifiers)
    let keyStr = keyCodeToString(keyCode)
    if modStr.isEmpty {
        return keyStr
    }
    return "\(modStr) \(keyStr)"
}

/// Converts NX device mask to display symbols with left/right distinction.
/// Order follows macOS convention: ⌃ ⌥ ⇧ ⌘
func deviceMaskToSymbols(_ mask: UInt) -> String {
    var parts: [String] = []
    if mask & NXDeviceMask.leftControl  != 0 { parts.append(L("hotkey.left_ctrl")) }
    if mask & NXDeviceMask.rightControl != 0 { parts.append(L("hotkey.right_ctrl")) }
    if mask & NXDeviceMask.leftOption   != 0 { parts.append(L("hotkey.left_opt")) }
    if mask & NXDeviceMask.rightOption  != 0 { parts.append(L("hotkey.right_opt")) }
    if mask & NXDeviceMask.leftShift    != 0 { parts.append(L("hotkey.left_shift")) }
    if mask & NXDeviceMask.rightShift   != 0 { parts.append(L("hotkey.right_shift")) }
    if mask & NXDeviceMask.leftCommand  != 0 { parts.append(L("hotkey.left_cmd")) }
    if mask & NXDeviceMask.rightCommand != 0 { parts.append(L("hotkey.right_cmd")) }
    return parts.joined(separator: " ")
}

/// Builds hotkey display string with left/right modifier distinction.
func buildHotkeyDisplayStringWithDeviceMask(keyCode: UInt16, deviceMask: UInt) -> String {
    let modStr = deviceMaskToSymbols(deviceMask)
    let keyStr = keyCodeToString(keyCode)
    if modStr.isEmpty {
        return keyStr
    }
    return "\(modStr) \(keyStr)"
}

/// Returns modifier keyCodes sorted in macOS display order: ⌃ ⌥ ⇧ ⌘
func sortedModifierKeyCodes(_ keyCodes: Set<UInt16>) -> [UInt16] {
    let order: [UInt16] = [
        UInt16(kVK_Control), UInt16(kVK_RightControl),
        UInt16(kVK_Option), UInt16(kVK_RightOption),
        UInt16(kVK_Shift), UInt16(kVK_RightShift),
        UInt16(kVK_Command), UInt16(kVK_RightCommand),
    ]
    return order.filter { keyCodes.contains($0) }
}
