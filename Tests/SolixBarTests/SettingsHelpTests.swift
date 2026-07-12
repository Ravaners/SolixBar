import AppKit
import Testing
@testable import SolixBarKit

@MainActor
@Suite("Einstellungs-Hilfe")
struct SettingsHelpTests {
    @Test("Bekannte Kurztexte liefern ausführliche Hilfe (DE und EN)")
    func knownKeysHaveExtendedHelp() {
        let shortTexts = [
            "Legt fest, woher SolixBar die Werte lädt.",
            "E-Mail-Adresse deines Anker/SOLIX-Kontos.",
            "Passwort deines Anker/SOLIX-Kontos. Wird sicher im macOS-Schlüsselbund gespeichert und nie hochgeladen.",
            "Land deines Anker-Kontos, normalerweise DE.",
            "Zeit zwischen zwei Aktualisierungen in Sekunden.",
            "Warnschwelle in Prozent (5–95).",
            "Warning threshold in percent (5–95).",
            "Startet SolixBar automatisch nach dem Anmelden.",
            "Passt die Größe der Menüleistenanzeige an.",
            "Window start (hour, 0–23)."
        ]
        for short in shortTexts {
            let extended = SettingsHelp.extended(for: short)
            #expect(extended != nil, "Kein ausführlicher Hilfetext für: \(short)")
            // Ausführlich heisst: deutlich mehr Erklärung als der Kurztext.
            #expect((extended ?? "").count > short.count, "Hilfetext nicht länger als Kurztext: \(short)")
        }
    }

    @Test("Unbekannter Text fällt auf nil zurück")
    func unknownKeyReturnsNil() {
        #expect(SettingsHelp.extended(for: "gibt es nicht") == nil)
    }

    @Test("Popover-Inhalt hat echte Grösse und wächst mit dem Text")
    func popoverContentHasRealSize() {
        let short = SettingsWindowController.helpPopoverContent(for: "Kurzer Text.")
        #expect(short.size.width > 100)
        #expect(short.size.height > 20)
        #expect(short.view.frame.size == short.size)
        #expect(!short.view.subviews.isEmpty)

        let long = SettingsWindowController.helpPopoverContent(
            for: String(repeating: "Ein deutlich längerer Hilfetext über mehrere Zeilen. ", count: 10)
        )
        #expect(long.size.height > short.size.height * 3)
    }
}
