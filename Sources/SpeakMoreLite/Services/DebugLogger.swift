import Foundation

@MainActor
final class DebugLogger: ObservableObject {
    static let shared = DebugLogger()

    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
    }

    @Published private(set) var entries: [Entry] = []

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private init() {}

    func log(_ message: String) {
        let entry = Entry(timestamp: Date(), message: message)
        entries.append(entry)
        if entries.count > 500 {
            entries.removeFirst(entries.count - 500)
        }
        NSLog("[Debug] %@", message)
    }

    func clear() {
        entries.removeAll()
    }

    func formattedText() -> String {
        entries.map { "[\(dateFormatter.string(from: $0.timestamp))] \($0.message)" }
            .joined(separator: "\n")
    }
}
