import Foundation
import Cocoa
import CoreGraphics

class HotkeyService {
    // MARK: - Event tap state
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var healthCheckTimer: Timer?
    private var eventTapDisableCount = 0

    // MARK: - NSEvent monitor state (fallback)
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var usingNSEventMonitor = false

    // MARK: - Fn key tracking
    private var isFnDown = false
    private var fnUsedAsModifier = false

    // MARK: - Custom hotkey tracking
    private var isCustomKeyDown = false
    private(set) var currentConfig: HotkeyConfig = .defaultFn

    // MARK: - Modifier-only hotkey tracking
    private var isModifierKeyDown = false
    private var modifierUsedAsCombo = false

    var onHotkeyDown: (() -> Void)?
    var onHotkeyUp: (() -> Void)?

    func start() {
        currentConfig = HotkeyConfig.load()
        NSLog("[HotkeyService] start() called, AXIsProcessTrusted=\(AXIsProcessTrusted()), config=\(currentConfig.displayString)")

        if tryStartEventTap() {
            startHealthCheck()
        } else {
            NSLog("[HotkeyService] CGEventTap creation failed, using NSEvent monitors")
            startNSEventMonitors()
        }
    }

    func stop() {
        stopEventTap()
        stopNSEventMonitors()
    }

    func updateHotkey(_ config: HotkeyConfig) {
        currentConfig = config
        config.save()
        isFnDown = false
        fnUsedAsModifier = false
        isCustomKeyDown = false
        isModifierKeyDown = false
        modifierUsedAsCombo = false
        NSLog("[HotkeyService] Hotkey updated to: \(config.displayString)")

        stop()
        if tryStartEventTap() {
            startHealthCheck()
        } else {
            startNSEventMonitors()
        }
    }

    // MARK: - CGEventTap

    private func tryStartEventTap() -> Bool {
        var eventMask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        if !currentConfig.isFnKey && !currentConfig.isModifierOnly {
            eventMask |= (1 << CGEventType.keyUp.rawValue)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: hotkeyEventCallback,
            userInfo: refcon
        ) else {
            NSLog("[HotkeyService] Failed to create session event tap")
            return false
        }

        NSLog("[HotkeyService] Session event tap created successfully")
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        let enabled = CGEvent.tapIsEnabled(tap: tap)
        NSLog("[HotkeyService] Session event tap enabled, isEnabled=\(enabled)")

        if !enabled {
            NSLog("[HotkeyService] Session event tap immediately disabled, falling back to NSEvent monitors")
            stopEventTap()
            startNSEventMonitors()
        }

        return enabled
    }

    private func stopEventTap() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        runLoopSource = nil
        eventTap = nil
    }

    private func startHealthCheck() {
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let tap = self.eventTap else { return }
            if !CGEvent.tapIsEnabled(tap: tap) {
                self.eventTapDisableCount += 1
                NSLog("[HotkeyService] Health check: tap disabled (count=\(self.eventTapDisableCount))")

                if self.eventTapDisableCount >= 3 {
                    NSLog("[HotkeyService] Tap repeatedly disabled, switching to NSEvent monitors")
                    self.stopEventTap()
                    self.startNSEventMonitors()
                } else {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            } else {
                self.eventTapDisableCount = 0
            }
        }
    }

    fileprivate func handleTapDisabled() {
        eventTapDisableCount += 1
        NSLog("[HotkeyService] Event tap DISABLED (count=\(eventTapDisableCount))")

        if eventTapDisableCount >= 3 {
            NSLog("[HotkeyService] Tap repeatedly disabled, switching to NSEvent monitors")
            DispatchQueue.main.async { [weak self] in
                self?.stopEventTap()
                self?.startNSEventMonitors()
            }
        } else if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    // MARK: - NSEvent Monitors (fallback)

    private func startNSEventMonitors() {
        guard !usingNSEventMonitor else { return }
        usingNSEventMonitor = true

        var eventTypes: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        if !currentConfig.isFnKey && !currentConfig.isModifierOnly {
            eventTypes.insert(.keyUp)
        }

        NSLog("[HotkeyService] Starting NSEvent monitors for \(eventTypes)")

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventTypes) { [weak self] event in
            self?.handleNSEvent(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: eventTypes) { [weak self] event in
            self?.handleNSEvent(event)
            return event
        }

        NSLog("[HotkeyService] NSEvent monitors started (global=\(globalMonitor != nil), local=\(localMonitor != nil))")
    }

    private func stopNSEventMonitors() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        usingNSEventMonitor = false
    }

    // MARK: - NSEvent Handling

    private func handleNSEvent(_ event: NSEvent) {
        if currentConfig.isFnKey {
            handleNSEventFn(event)
        } else if currentConfig.isModifierOnly {
            handleNSEventModifierOnly(event)
        } else {
            handleNSEventCustom(event)
        }
    }

    private func handleNSEventFn(_ event: NSEvent) {
        if event.type == .keyDown && isFnDown {
            fnUsedAsModifier = true
            return
        }

        guard event.type == .flagsChanged else { return }

        let fnPressed = event.modifierFlags.contains(.function)

        if fnPressed && !isFnDown {
            isFnDown = true
            fnUsedAsModifier = false
            onHotkeyDown?()
        } else if !fnPressed && isFnDown {
            isFnDown = false
            if !fnUsedAsModifier {
                onHotkeyUp?()
            }
            fnUsedAsModifier = false
        }
    }

    private func handleNSEventModifierOnly(_ event: NSEvent) {
        let config = currentConfig

        if event.type == .keyDown && isModifierKeyDown {
            modifierUsedAsCombo = true
            return
        }

        guard event.type == .flagsChanged else { return }

        let deviceMask = nxDeviceMaskForKeyCode(config.keyCode)
        let isTargetPressed = (event.modifierFlags.rawValue & deviceMask) != 0

        if isTargetPressed && !isModifierKeyDown && event.keyCode == config.keyCode {
            isModifierKeyDown = true
            modifierUsedAsCombo = false
            onHotkeyDown?()
        } else if !isTargetPressed && isModifierKeyDown {
            isModifierKeyDown = false
            if !modifierUsedAsCombo {
                onHotkeyUp?()
            }
            modifierUsedAsCombo = false
        }
    }

    private func handleNSEventCustom(_ event: NSEvent) {
        let config = currentConfig

        if event.type == .keyDown {
            guard !isCustomKeyDown, event.keyCode == config.keyCode else { return }

            // Check generic modifier types
            guard modifiersMatch(event.modifierFlags, expected: NSEvent.ModifierFlags(rawValue: UInt(config.modifierFlags))) else { return }

            // Check left/right distinction if device mask is configured
            if config.modifierDeviceMask != 0 {
                let eventRawFlags = event.modifierFlags.rawValue
                guard (eventRawFlags & config.modifierDeviceMask) == config.modifierDeviceMask else { return }
            }

            isCustomKeyDown = true
            onHotkeyDown?()

        } else if event.type == .keyUp {
            guard isCustomKeyDown, event.keyCode == config.keyCode else { return }

            isCustomKeyDown = false
            onHotkeyUp?()

        } else if event.type == .flagsChanged {
            if isCustomKeyDown && config.modifierFlags != 0 {
                if config.modifierDeviceMask != 0 {
                    let eventRawFlags = event.modifierFlags.rawValue
                    if (eventRawFlags & config.modifierDeviceMask) != config.modifierDeviceMask {
                        isCustomKeyDown = false
                        onHotkeyUp?()
                    }
                } else if !modifiersMatch(event.modifierFlags, expected: NSEvent.ModifierFlags(rawValue: UInt(config.modifierFlags))) {
                    isCustomKeyDown = false
                    onHotkeyUp?()
                }
            }
        }
    }

    // MARK: - CGEventTap Handling

    fileprivate func handleEvent(_ type: CGEventType, _ event: CGEvent) {
        if currentConfig.isFnKey {
            handleEventFn(type, event)
        } else if currentConfig.isModifierOnly {
            handleEventModifierOnly(type, event)
        } else {
            handleEventCustom(type, event)
        }
    }

    private func handleEventFn(_ type: CGEventType, _ event: CGEvent) {
        if type == .keyDown && isFnDown {
            fnUsedAsModifier = true
            return
        }

        guard type == .flagsChanged else { return }

        let fnPressed = event.flags.contains(.maskSecondaryFn)

        if fnPressed && !isFnDown {
            isFnDown = true
            fnUsedAsModifier = false
            onHotkeyDown?()
        } else if !fnPressed && isFnDown {
            isFnDown = false
            if !fnUsedAsModifier {
                onHotkeyUp?()
            }
            fnUsedAsModifier = false
        }
    }

    private func handleEventModifierOnly(_ type: CGEventType, _ event: CGEvent) {
        let config = currentConfig

        if type == .keyDown && isModifierKeyDown {
            modifierUsedAsCombo = true
            return
        }

        guard type == .flagsChanged else { return }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let deviceMask = nxDeviceMaskForKeyCode(config.keyCode)
        let isTargetPressed = (UInt(event.flags.rawValue) & deviceMask) != 0

        if isTargetPressed && !isModifierKeyDown && keyCode == config.keyCode {
            isModifierKeyDown = true
            modifierUsedAsCombo = false
            onHotkeyDown?()
        } else if !isTargetPressed && isModifierKeyDown {
            isModifierKeyDown = false
            if !modifierUsedAsCombo {
                onHotkeyUp?()
            }
            modifierUsedAsCombo = false
        }
    }

    private func handleEventCustom(_ type: CGEventType, _ event: CGEvent) {
        let config = currentConfig
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        if type == .keyDown {
            guard !isCustomKeyDown, keyCode == config.keyCode else { return }

            // Check generic modifier types first
            guard cgModifiersMatch(event.flags, expected: config.modifierFlags) else { return }

            // Check left/right distinction if device mask is configured
            if config.modifierDeviceMask != 0 {
                let eventRawFlags = UInt(event.flags.rawValue)
                guard (eventRawFlags & config.modifierDeviceMask) == config.modifierDeviceMask else { return }
            }

            isCustomKeyDown = true
            onHotkeyDown?()

        } else if type == .keyUp {
            guard isCustomKeyDown, keyCode == config.keyCode else { return }

            isCustomKeyDown = false
            onHotkeyUp?()

        } else if type == .flagsChanged {
            if isCustomKeyDown && config.modifierFlags != 0 {
                if config.modifierDeviceMask != 0 {
                    let eventRawFlags = UInt(event.flags.rawValue)
                    if (eventRawFlags & config.modifierDeviceMask) != config.modifierDeviceMask {
                        isCustomKeyDown = false
                        onHotkeyUp?()
                    }
                } else if !cgModifiersMatch(event.flags, expected: config.modifierFlags) {
                    isCustomKeyDown = false
                    onHotkeyUp?()
                }
            }
        }
    }

    // MARK: - Modifier Matching

    private func modifiersMatch(_ current: NSEvent.ModifierFlags, expected: NSEvent.ModifierFlags) -> Bool {
        let mask: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        return current.intersection(mask) == expected.intersection(mask)
    }

    private func cgModifiersMatch(_ current: CGEventFlags, expected: UInt) -> Bool {
        let relevantFlags: [(CGEventFlags, NSEvent.ModifierFlags)] = [
            (.maskCommand, .command),
            (.maskControl, .control),
            (.maskAlternate, .option),
            (.maskShift, .shift),
        ]
        let expectedFlags = NSEvent.ModifierFlags(rawValue: UInt(expected))
        for (cgFlag, nsFlag) in relevantFlags {
            let currentHas = current.contains(cgFlag)
            let expectedHas = expectedFlags.contains(nsFlag)
            if currentHas != expectedHas { return false }
        }
        return true
    }
}

// MARK: - C Callback

private func hotkeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let service = Unmanaged<HotkeyService>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        service.handleTapDisabled()
        return Unmanaged.passUnretained(event)
    }

    service.handleEvent(type, event)
    return Unmanaged.passUnretained(event)
}
