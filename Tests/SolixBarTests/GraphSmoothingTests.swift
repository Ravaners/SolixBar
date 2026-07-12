import AppKit
import Testing
@testable import SolixBarKit

@MainActor
@Suite("Graph-Glättung und Demo-Akku")
struct GraphSmoothingTests {
    @Test("Geklemmte Glättung bleibt in der Plotfläche")
    func smoothClampStaysInBounds() {
        // Sägezahn mit harten Sprüngen — klassischer Überschwing-Kandidat.
        let points = [
            NSPoint(x: 0, y: 10), NSPoint(x: 10, y: 90), NSPoint(x: 20, y: 12),
            NSPoint(x: 30, y: 88), NSPoint(x: 40, y: 15), NSPoint(x: 50, y: 15)
        ]
        // Auf den echten Wertebereich [10, 90] geklemmt (z. B. Nulllinie unten).
        let path = HistoryGraphView.smoothPath(through: points, clampingY: 10...90)
        let box = path.bounds
        #expect(box.minY >= 10 - 0.001, "Kurve unterschreitet die Nulllinie: \(box.minY)")
        #expect(box.maxY <= 90 + 0.001, "Kurve verlässt die Plotfläche oben: \(box.maxY)")
        #expect(abs(box.minX - 0) < 0.001)
        #expect(abs(box.maxX - 50) < 0.001)
    }

    @Test("Ohne Klemmung schwingt Catmull-Rom sichtbar über die Punkte")
    func smoothOvershootsWithoutClamp() {
        // Genau der Effekt, den die Klemmung bändigt: nach einem steilen
        // Abfall auf 0 und anschliessendem Flachlauf zieht der Catmull-Rom-
        // Bogen unter die Nulllinie (scheinbar negative Watt).
        let points = [
            NSPoint(x: 0, y: 50), NSPoint(x: 10, y: 50), NSPoint(x: 20, y: 0),
            NSPoint(x: 30, y: 0), NSPoint(x: 40, y: 0)
        ]
        let unclamped = HistoryGraphView.smoothPath(through: points, clampingY: nil)
        #expect(unclamped.bounds.minY < -0.5, "Erwartetes Überschwingen unter 0 blieb aus")
    }

    @Test("Kurve beginnt und endet exakt auf den Messpunkten")
    func smoothEndpoints() {
        let points = [NSPoint(x: 0, y: 5), NSPoint(x: 20, y: 40), NSPoint(x: 40, y: 22)]
        let path = HistoryGraphView.smoothPath(through: points, clampingY: 0...100)
        #expect(path.currentPoint == points.last)
    }

    @Test("Wenige Punkte (≤2) bleiben ein gerader Zug")
    func smoothFewPoints() {
        let two = [NSPoint(x: 0, y: 5), NSPoint(x: 10, y: 20)]
        let path = HistoryGraphView.smoothPath(through: two, clampingY: 0...100)
        #expect(path.currentPoint == two.last)
        #expect(!path.isEmpty)
    }

    @Test("Gerader Pfad verbindet alle Punkte")
    func straightPath() {
        let points = [NSPoint(x: 0, y: 0), NSPoint(x: 5, y: 10), NSPoint(x: 10, y: 3)]
        let path = HistoryGraphView.straightPath(through: points)
        #expect(path.currentPoint == points.last)
        #expect(abs(path.bounds.maxY - 10) < 0.001)
    }

    @Test("Demo-Akku driftet langsam statt zu springen")
    func demoBatteryDriftsSlowly() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var maxStep = 0
        var values: Set<Int> = []
        // Ein kompletter 3-h-Zyklus in 5-Minuten-Schritten (Demo-Abruftakt).
        for step in 0...36 {
            let date = start.addingTimeInterval(Double(step) * 300)
            let value = DemoSolixDataProvider.demoBatteryPercent(at: date)
            #expect((40...84).contains(value), "Akkuwert ausserhalb des Demo-Bereichs: \(value)")
            if step > 0 {
                let previous = DemoSolixDataProvider.demoBatteryPercent(at: date.addingTimeInterval(-300))
                maxStep = max(maxStep, abs(value - previous))
            }
            values.insert(value)
        }
        // Kein Sägezahn-Cliff mehr: früher sprang der Demo-Akku alle 25 min
        // um 24 Punkte, jetzt driftet er (wenige Punkte je 5-min-Abruf).
        #expect(maxStep <= 5, "Sprung von \(maxStep) Punkten zwischen zwei Demo-Abrufen")
        // Und es bewegt sich wirklich etwas (kein konstanter Wert).
        #expect(values.count > 10)
    }

    @Test("Glättung und Füllungen überleben den Snapshot/Apply-Rundlauf")
    func settingsRoundTrip() {
        let settings = AppSettings.shared
        let original = settings.snapshot()
        defer { settings.apply(original) }

        settings.graphSmoothing = true
        settings.graphFilledMetrics = [.battery, .grid]
        let snapshot = settings.snapshot()
        #expect(snapshot.graphSmoothing)
        #expect(snapshot.graphFilledMetrics == [.battery, .grid])

        settings.graphSmoothing = false
        settings.graphFilledMetrics = []
        settings.apply(snapshot)
        #expect(settings.graphSmoothing)
        #expect(settings.graphFilledMetrics == [.battery, .grid])
    }
}
