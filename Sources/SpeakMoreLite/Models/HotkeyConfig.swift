import Foundation
import AppKit
import Carbon.HIToolbox

// MARK: - Hotkey Configuration

struct HotkeyConfig: Codable, Equatable {
    let keyCode: UInt16
    let modifierFlags: UInt
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

    init(keyCode: UInt16, modifierFlags: UInt, isFnKey: Bool, isModifierOnly: Bool = false, displayString: String) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.isFnKey = isFnKey
        self.isModifierOnly = isModifierOnly
        self.displayString = displayString
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
    case kVK_Command:       return "左⌘"
    case kVK_RightCommand:  return "右⌘"
    case kVK_Shift:         return "左⇧"
    case kVK_RightShift:    return "右⇧"
    case kVK_Option:        return "左⌥"
    case kVK_RightOption:   return "右⌥"
    case kVK_Control:       return "左⌃"
    case kVK_RightControl:  return "右⌃"
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
    case kVK_Command:       return "左⌘"
    case kVK_RightCommand:  return "右⌘"
    case kVK_Shift:         return "左⇧"
    case kVK_RightShift:    return "右⇧"
    case kVK_Option:        return "左⌥"
    case kVK_RightOption:   return "右⌥"
    case kVK_Control:       return "左⌃"
    case kVK_RightControl:  return "右⌃"
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
