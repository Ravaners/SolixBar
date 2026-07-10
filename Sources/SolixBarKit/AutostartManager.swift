import Foundation
import ServiceManagement

/// Autostart ueber die moderne SMAppService-API. Ein frueher installiertes
/// LaunchAgent-Plist wird beim Umschalten entfernt (Migration).
enum AutostartManager {
    private static let label = "local.codex.SolixBar"

    static var legacyLaunchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
            || FileManager.default.fileExists(atPath: legacyLaunchAgentURL.path)
    }

    static func setEnabled(_ enabled: Bool) throws {
        // Altes LaunchAgent-Plist immer aufraeumen, sonst startet die App doppelt.
        if FileManager.default.fileExists(atPath: legacyLaunchAgentURL.path) {
            try? FileManager.default.removeItem(at: legacyLaunchAgentURL)
        }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
