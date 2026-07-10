import Foundation
import os

/// Loggt doppelt: ins Unified Logging (Console.app, Filterung per Subsystem)
/// und in eine Datei fuer Support-Faelle. DEBUG-Zeilen erscheinen nur, wenn
/// `defaults write local.codex.SolixBar verboseLogging -bool true` gesetzt ist.
enum AppLogger {
    private static let subsystem = "local.codex.SolixBar"
    private static let osLogger = Logger(subsystem: subsystem, category: "app")
    private static let lock = NSLock()
    private static let maxLogSize = 512 * 1024
    nonisolated(unsafe) private static var handle: FileHandle?
    nonisolated(unsafe) private static var cachedFormatter: ISO8601DateFormatter?

    static let isVerbose = UserDefaults.standard.bool(forKey: "verboseLogging")

    static var logURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("SolixBar", isDirectory: true).appendingPathComponent("SolixBar.log")
    }

    static func debug(_ message: String, function: String = #function) {
        guard isVerbose else { return }
        osLogger.debug("\(function, privacy: .public): \(message, privacy: .public)")
        write("DEBUG", "\(function): \(message)")
    }

    static func info(_ message: String, function: String = #function) {
        osLogger.info("\(message, privacy: .public)")
        write("INFO", isVerbose ? "\(function): \(message)" : message)
    }

    static func error(_ message: String, function: String = #function) {
        osLogger.error("\(function, privacy: .public): \(message, privacy: .public)")
        write("ERROR", "\(function): \(message)")
    }

    private static func write(_ level: String, _ message: String) {
        lock.lock()
        defer { lock.unlock() }

        do {
            let line = "\(timestamp()) [\(level)] \(message)\n"
            let data = Data(line.utf8)
            try ensureHandle()
            try handle?.write(contentsOf: data)
        } catch {
            NSLog("SolixBar logging failed: \(error.localizedDescription)")
        }
    }

    /// Haelt die Datei offen statt sie pro Zeile neu zu oeffnen; rotiert bei 512 KB.
    private static func ensureHandle() throws {
        if let size = try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? NSNumber,
           size.intValue > maxLogSize {
            try? handle?.close()
            handle = nil
            let oldURL = logURL.deletingLastPathComponent().appendingPathComponent("SolixBar.old.log")
            try? FileManager.default.removeItem(at: oldURL)
            try? FileManager.default.moveItem(at: logURL, to: oldURL)
        }
        if handle == nil {
            let directory = logURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            let newHandle = try FileHandle(forWritingTo: logURL)
            try newHandle.seekToEnd()
            handle = newHandle
        }
    }

    private static func timestamp() -> String {
        if let cachedFormatter {
            return cachedFormatter.string(from: Date())
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        cachedFormatter = formatter
        return formatter.string(from: Date())
    }
}
