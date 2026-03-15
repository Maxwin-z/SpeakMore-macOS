import AppKit
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {

    static var debugLogPath: String = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("SpeakMoreLite_debug.log").path
    }()

    static func fileLog(_ msg: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(msg)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: debugLogPath) {
                if let handle = FileHandle(forWritingAtPath: debugLogPath) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: debugLogPath, contents: data)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.fileLog("applicationDidFinishLaunching, AXIsProcessTrusted=\(AXIsProcessTrusted()), CGPreflightListenEventAccess=\(CGPreflightListenEventAccess())")

        let dominated = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        if dominated.count > 1 {
            NSLog("[AppDelegate] Another instance is already running, terminating.")
            NSApp.terminate(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in NSApp.windows {
                if window.identifier?.rawValue == "main-window" ||
                   window.title == "SpeakMore Lite" {
                    window.makeKeyAndOrderFront(nil)
                    return false
                }
            }
        }
        return true
    }
}
