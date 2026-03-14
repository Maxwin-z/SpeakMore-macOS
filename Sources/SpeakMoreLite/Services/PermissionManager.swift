import Foundation
import ApplicationServices
import AppKit

@MainActor
class PermissionManager: ObservableObject {
    @Published var isAccessibilityGranted = false
    @Published var isFnKeyConfiguredCorrectly = false

    private var pollingTimer: Timer?

    func checkAllPermissions() {
        checkAccessibilityPermission()
        checkFnKeyConfiguration()
    }

    func checkAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        NSLog("[PermissionManager] AXIsProcessTrusted() = \(trusted)")
        isAccessibilityGranted = trusted
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        startAccessibilityPolling()
    }

    func checkFnKeyConfiguration() {
        let defaults = UserDefaults(suiteName: "com.apple.HIToolbox")
        let fnUsageType = defaults?.integer(forKey: "AppleFnUsageType") ?? -1
        isFnKeyConfiguredCorrectly = (fnUsageType == 0)
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startAccessibilityPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else {
                    timer.invalidate()
                    return
                }
                if AXIsProcessTrusted() {
                    self.isAccessibilityGranted = true
                    timer.invalidate()
                    self.pollingTimer = nil
                }
            }
        }
    }

    deinit {
        pollingTimer?.invalidate()
    }
}
