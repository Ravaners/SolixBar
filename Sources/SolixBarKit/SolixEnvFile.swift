import Foundation

/// Pfade der App für lokale Daten und den SOLIX-Hilfsbefehl.
/// Ersetzt die früher hartkodierten Pfade ins Home des Originalautors.
enum SolixPaths {
    static var appSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("SolixBar", isDirectory: true)
    }

    static var envFileURL: URL {
        appSupportDirectory.appendingPathComponent("solixbar.env")
    }

    static var historyFileURL: URL {
        appSupportDirectory.appendingPathComponent("history.json")
    }

    /// Findet das SOLIX-Hilfsscript: bevorzugt im App-Bundle, sonst im
    /// Arbeitsverzeichnis (Entwicklung mit `swift run`).
    static func helperScriptURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "run_solix_snapshot", withExtension: "sh") {
            return bundled
        }
        let dev = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts/run_solix_snapshot.sh")
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }

    /// Vollständiger Befehl für den Modus "Lokaler JSON-Befehl": Script mit
    /// explizitem Verweis auf die Env-Datei in Application Support.
    static func helperCommand() -> String? {
        guard let script = helperScriptURL() else { return nil }
        return "SOLIXBAR_ENV_FILE=\(SolixEnvFile.shellQuoted(envFileURL.path)) \(SolixEnvFile.shellQuoted(script.path))"
    }
}

/// Lesen/Schreiben der lokalen Env-Datei (Key=Value, shell-quotiert).
/// Wird mit 0600 geschrieben, da sie Zugangsdaten enthalten kann.
enum SolixEnvFile {
    static func read(from url: URL) -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<equals])
            let value = String(line[line.index(after: equals)...])
            values[key] = unquote(value)
        }
        return values
    }

    /// Schreibt Zeilen in stabiler Reihenfolge und setzt die Rechte auf 0600.
    static func write(_ values: [(key: String, value: String)], to url: URL) throws {
        let text = values.map { "\($0.key)=\(shellQuoted($0.value))" }.joined(separator: "\n") + "\n"
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    static func unquote(_ value: String) -> String {
        var value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
            value.removeFirst()
            value.removeLast()
            return value.replacingOccurrences(of: "'\\''", with: "'")
        }
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value.removeFirst()
            value.removeLast()
        }
        return value
    }
}
