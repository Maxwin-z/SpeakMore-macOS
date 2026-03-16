import AppKit
import Foundation

struct InstalledApp: Identifiable, Hashable {
    let id: String  // bundleIdentifier
    let name: String
    let bundleId: String
    let url: URL
    var isRunning: Bool

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleId)
    }

    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool {
        lhs.bundleId == rhs.bundleId
    }
}

@MainActor
final class InstalledAppScanner: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var isScanning = false

    func scan() {
        guard !isScanning else { return }
        isScanning = true

        Task.detached {
            let results = Self.scanApplications()
            await MainActor.run {
                self.apps = results
                self.isScanning = false
            }
        }
    }

    nonisolated private static func scanApplications() -> [InstalledApp] {
        let runningBundleIds = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )

        var seen = Set<String>()
        var results: [InstalledApp] = []

        let searchPaths = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications",
        ]

        let fm = FileManager.default
        for dir in searchPaths {
            guard let contents = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in contents where item.hasSuffix(".app") {
                let fullPath = (dir as NSString).appendingPathComponent(item)
                let url = URL(fileURLWithPath: fullPath)
                guard let bundle = Bundle(url: url),
                      let bundleId = bundle.bundleIdentifier else { continue }

                guard !seen.contains(bundleId) else { continue }
                seen.insert(bundleId)

                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent

                results.append(InstalledApp(
                    id: bundleId, name: name, bundleId: bundleId,
                    url: url, isRunning: runningBundleIds.contains(bundleId)
                ))
            }
        }

        // Running apps first, then alphabetical within each group
        return results.sorted {
            if $0.isRunning != $1.isRunning { return $0.isRunning }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
