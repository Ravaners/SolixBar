import Foundation

enum AutostartManager {
    private static let label = "local.codex.SolixBar"

    static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try install()
        } else {
            try remove()
        }
    }

    private static func install() throws {
        let executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let appURL = appBundleURL(from: executableURL)
        let launchPath = appURL?.path ?? executableURL.path
        let programArguments = appURL == nil ? [launchPath] : ["/usr/bin/open", "-a", launchPath]

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": programArguments,
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
