import Foundation

enum AppLogger {
    private static let lock = NSLock()
    private static let maxLogSize = 512 * 1024
    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static var logURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("SolixBar", isDirectory: true).appendingPathComponent("SolixBar.log")
    }

    static func info(_ message: String) {
        write("INFO", message)
    }

    static func error(_ message: String) {
        write("ERROR", message)
    }

    private static func write(_ level: String, _ message: String) {
        lock.lock()
        defer { lock.unlock() }

        do {
            let directory = logURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            rotateIfNeeded()

            let line = "\(timestamp()) [\(level)] \(message)\n"
            let data = Data(line.utf8)
            if FileManager.default.fileExists(atPath: logURL.path) {
                let handle = try FileHandle(forWritingTo: logURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: logURL, options: .atomic)
            }
        } catch {
            NSLog("SolixBar logging failed: \(error.localizedDescription)")
        }
    }

    private static func rotateIfNeeded() {
        guard let size = try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? NSNumber,
              size.intValue > maxLogSize else {
            return
        }

        let oldURL = logURL.deletingLastPathComponent().appendingPathComponent("SolixBar.old.log")
        try? FileManager.default.removeItem(at: oldURL)
        try? FileManager.default.moveItem(at: logURL, to: oldURL)
    }

    private static func timestamp() -> String {
        return formatter.string(from: Date())
    }
}
