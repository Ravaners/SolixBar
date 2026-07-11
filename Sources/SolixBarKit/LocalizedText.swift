import Foundation

@MainActor
enum LocalizedText {
    static func text(_ german: String, _ english: String) -> String {
        AppSettings.shared.appLanguage == .english ? english : german
    }
}
