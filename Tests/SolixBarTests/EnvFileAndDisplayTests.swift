import AppKit
import Testing
@testable import SolixBarKit

@Suite("SolixEnvFile")
struct EnvFileTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("solixbar-env-\(UUID().uuidString)")
            .appendingPathComponent("solixbar.env")
    }

    @Test("roundtrips values incl. quotes, spaces, and umlauts")
    func roundtrip() throws {
        let url = tempURL()
        let values: [(key: String, value: String)] = [
            ("ANKER_SOLIX_USER", "mail@example.com"),
            ("ANKER_SOLIX_PASSWORD", "pa'ss wörd\"!"),
            ("ANKER_SOLIX_COUNTRY", "DE")
        ]
        try SolixEnvFile.write(values, to: url)
        let read = SolixEnvFile.read(from: url)
        #expect(read["ANKER_SOLIX_USER"] == "mail@example.com")
        #expect(read["ANKER_SOLIX_PASSWORD"] == "pa'ss wörd\"!")
        #expect(read["ANKER_SOLIX_COUNTRY"] == "DE")
    }

    @Test("written file is only readable by the owner (0600)")
    func permissions() throws {
        let url = tempURL()
        try SolixEnvFile.write([("A", "b")], to: url)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = (attrs[.posixPermissions] as? NSNumber)?.uint16Value
        #expect(permissions == 0o600)
    }

    @Test("helper command references app-support env file, never a foreign home")
    @MainActor
    func helperCommand() throws {
        // Dev-Fallback sucht das Script relativ zum Arbeitsverzeichnis —
        // fürs Testen deterministisch auf die Paketwurzel setzen.
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let previous = FileManager.default.currentDirectoryPath
        FileManager.default.changeCurrentDirectoryPath(packageRoot.path)
        defer { FileManager.default.changeCurrentDirectoryPath(previous) }
        let command = try #require(SolixPaths.helperCommand())
        #expect(command.contains("Application Support/SolixBar/solixbar.env"))
        #expect(!command.contains("/Users/holger"))
        #expect(command.hasSuffix("run_solix_snapshot.sh'"))
    }
}

@Suite("MenuBarDisplay")
struct MenuBarDisplayTests {
    private let base = MenuBarDisplayOptions(
        metrics: [.battery, .solar, .grid],
        showLabels: true,
        showSymbols: true,
        showArrows: true
    )

    @Test("levels strip options progressively")
    func degradation() {
        #expect(base.applying(.full).showLabels)
        #expect(!base.applying(.noLabels).showLabels)
        #expect(base.applying(.noLabels).showSymbols)
        let values = base.applying(.valuesOnly)
        #expect(!values.showLabels && !values.showSymbols && !values.showArrows)
        #expect(base.applying(.compact).metrics == [.battery, .solar])
        #expect(base.applying(.minimal).metrics.isEmpty)
    }

    @Test("notch overlap predicate")
    func overlap() {
        // Item 739..1202, Notch 771..956 (der reale Fall auf dem 16" MBP)
        #expect(NotchGeometry.overlaps(itemMinX: 739, itemMaxX: 1202, notchMinX: 771, notchMaxX: 956))
        // Rechts der Notch: kein Overlap
        #expect(!NotchGeometry.overlaps(itemMinX: 1037, itemMaxX: 1202, notchMinX: 771, notchMaxX: 956))
        // Links der Notch endend: kein Overlap
        #expect(!NotchGeometry.overlaps(itemMinX: 600, itemMaxX: 771, notchMinX: 771, notchMaxX: 956))
    }
}
