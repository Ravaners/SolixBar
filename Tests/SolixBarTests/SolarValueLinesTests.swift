import Testing
@testable import SolixBarKit

@Suite("Solar-Wertezeilen")
struct SolarValueLinesTests {
    typealias V = SolixMenuDashboardView

    @Test("Summenmodus: eine Zeile mit Pfeil")
    func totalMode() {
        #expect(V.solarValueLines(pvMode: .total, channels: [438, 204], totalWatts: 659, arrow: "▲")
            == ["659 W ▲"])
    }

    @Test("Ohne Pfeil kein angehängtes Zeichen")
    func noArrow() {
        #expect(V.solarValueLines(pvMode: .total, channels: nil, totalWatts: 659, arrow: nil)
            == ["659 W"])
    }

    @Test("Fehlende Summe ergibt Platzhalter")
    func missingTotal() {
        #expect(V.solarValueLines(pvMode: .total, channels: nil, totalWatts: nil, arrow: nil)
            == ["-"])
    }

    @Test("Zwei Eingänge bleiben einzeilig")
    func twoChannels() {
        #expect(V.solarValueLines(pvMode: .perInput, channels: [438, 204], totalWatts: 642, arrow: "▲")
            == ["438 · 204 W ▲"])
    }

    @Test("Vier Eingänge: 2×2 auf zwei Zeilen, Pfeil unten")
    func fourChannels() {
        #expect(V.solarValueLines(pvMode: .perInput, channels: [438, 204, 210, 190], totalWatts: 1042, arrow: "▲")
            == ["438 · 204", "210 · 190 W ▲"])
    }

    @Test("Drei Eingänge: zwei oben, einer unten")
    func threeChannels() {
        #expect(V.solarValueLines(pvMode: .perInput, channels: [438, 204, 210], totalWatts: 852, arrow: nil)
            == ["438 · 204", "210 W"])
    }

    @Test("perInput ohne Kanäle fällt auf die Summe zurück")
    func perInputWithoutChannels() {
        #expect(V.solarValueLines(pvMode: .perInput, channels: nil, totalWatts: 659, arrow: "▼")
            == ["659 W ▼"])
    }
}
