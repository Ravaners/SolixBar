import Foundation
import Testing
@testable import SolixBarKit

@MainActor
@Suite("SolixHistoryStore")
struct HistoryStoreTests {
    private func makeStore() -> (SolixHistoryStore, UserDefaults) {
        let suite = "solixbar-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (SolixHistoryStore(defaults: defaults), defaults)
    }

    private func snapshot(solar: Int?, at date: Date, totalKWh: Double? = nil) -> SolixSnapshot {
        SolixSnapshot(siteName: "Test", solarWatts: solar, totalKWh: totalKWh, updatedAt: date)
    }

    @Test("accumulates trapezoid energy between samples")
    func accumulatesEnergy() {
        let (store, _) = makeStore()
        let start = Date()
        _ = store.cumulativeSolarKWh(recording: snapshot(solar: 1000, at: start), sourceKey: "demo")
        let total = store.cumulativeSolarKWh(
            recording: snapshot(solar: 1000, at: start.addingTimeInterval(15 * 60)),
            sourceKey: "demo"
        )
        // 1000 W constant over 15 minutes = 0.25 kWh
        #expect(abs(total - 0.25) < 0.001)
    }

    @Test("ignores gaps longer than 30 minutes")
    func ignoresLongGaps() {
        let (store, _) = makeStore()
        let start = Date()
        _ = store.cumulativeSolarKWh(recording: snapshot(solar: 1000, at: start), sourceKey: "demo")
        let total = store.cumulativeSolarKWh(
            recording: snapshot(solar: 1000, at: start.addingTimeInterval(2 * 3600)),
            sourceKey: "demo"
        )
        #expect(total == 0)
    }

    @Test("provider total overrides smaller accumulated value")
    func providerTotalWins() {
        let (store, _) = makeStore()
        let total = store.cumulativeSolarKWh(
            recording: snapshot(solar: 0, at: Date(), totalKWh: 427.8),
            sourceKey: "url"
        )
        #expect(total == 427.8)
    }

    @Test("accumulators are separated per source")
    func accumulatorsPerSource() {
        let (store, _) = makeStore()
        _ = store.cumulativeSolarKWh(
            recording: snapshot(solar: 0, at: Date(), totalKWh: 100),
            sourceKey: "demo"
        )
        let urlTotal = store.cumulativeSolarKWh(
            recording: snapshot(solar: 0, at: Date()),
            sourceKey: "url"
        )
        #expect(urlTotal == 0)
    }

    @Test("record and samples roundtrip with duration filter")
    func recordRoundtrip() {
        let (store, _) = makeStore()
        let now = Date()
        store.record(snapshot(solar: 500, at: now.addingTimeInterval(-7200)))
        store.record(snapshot(solar: 600, at: now.addingTimeInterval(-60)))
        let recent = store.samples(duration: 3600)
        #expect(recent.count == 1)
        #expect(recent.first?.solarWatts == 600)
    }
}
