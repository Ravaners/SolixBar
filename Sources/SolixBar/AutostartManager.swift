import Foundation

@MainActor
enum AutostartManager {
    private static let label = "local.codex.SolixBar"

    static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    static func repairIfNeeded() {
        guard isEnabled, !isConfiguredForCurrentApp else { return }
        do {
            try install()
            AppLogger.info("Repaired the enabled autostart entry for the currently running app.")
        } catch {
            AppLogger.error("Could not repair the autostart entry: \(error.localizedDescription)")
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try install()
        } else {
            try remove()
        }
    }

    private static func install() throws {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": currentProgramArguments,
            "RunAtLoad": true,
            "KeepAlive": false
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let directory = launchAgentURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: launchAgentURL, options: .atomic)
    }

    private static func remove() throws {
        guard isEnabled else { return }
        try FileManager.default.removeItem(at: launchAgentURL)
    }

    private static var isConfiguredForCurrentApp: Bool {
        guard let data = try? Data(contentsOf: launchAgentURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = plist as? [String: Any],
              let arguments = dictionary["ProgramArguments"] as? [String] else {
            return false
        }
        return arguments == currentProgramArguments
    }

    private static var currentProgramArguments: [String] {
        let executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        guard let appURL = appBundleURL(from: executableURL) else {
            return [executableURL.standardizedFileURL.path]
        }
        return ["/usr/bin/open", "-a", appURL.standardizedFileURL.path]
    }

    private static func appBundleURL(from executableURL: URL) -> URL? {
        var url = executableURL
        while url.path != "/" {
            if url.pathExtension == "app" {
                return url
            }
            url.deleteLastPathComponent()
        }
        return nil
    }
}
