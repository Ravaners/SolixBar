import Foundation

enum AppVersion {
    static var short: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
    }

    static var display: String {
        "Version \(short) (\(build))"
    }
}
