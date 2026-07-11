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
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("solixbar-history-\(UUID().uuidString).json")
        return (SolixHistoryStore(defaults: defaults, fileURL: fileURL), defaults)
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

    @Test("samples are separated per data source")
    func samplesPerSource() {
        let (store, _) = makeStore()
        let now = Date()
        store.record(snapshot(solar: 500, at: now), sourceKey: "demo", refreshInterval: 300)
        store.record(snapshot(solar: 999, at: now), sourceKey: "url", refreshInterval: 300)
        let demo = store.samples(duration: 3600, sourceKey: "demo")
        let url = store.samples(duration: 3600, sourceKey: "url")
        #expect(demo.count == 1 && demo.first?.solarWatts == 500)
        #expect(url.count == 1 && url.first?.solarWatts == 999)
    }

    @Test("cap covers the 30 day view at the configured interval")
    func capMath() {
        // 300 s Intervall: 30 Tage = 8640 Samples -> Cap muss darüber liegen
        #expect(SolixHistoryStore.maxSamples(refreshInterval: 300) >= 8640)
        // 60 s Intervall: 43200 Samples
        #expect(SolixHistoryStore.maxSamples(refreshInterval: 60) >= 43200)
        // nie unter dem alten Limit
        #expect(SolixHistoryStore.maxSamples(refreshInterval: 100_000) >= 2000)
    }

    @Test("migrates legacy UserDefaults blob to the demo source")
    func legacyMigration() throws {
        let suite = "solixbar-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let legacy = [SolixHistorySample(date: Date(), batteryPercent: 50, solarWatts: 123, gridWatts: 0)]
        defaults.set(try JSONEncoder().encode(legacy), forKey: "solixHistorySamples")
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("solixbar-history-\(UUID().uuidString).json")
        let store = SolixHistoryStore(defaults: defaults, fileURL: fileURL)
        let migrated = store.samples(duration: 3600, sourceKey: "demo")
        #expect(migrated.count == 1)
        #expect(migrated.first?.solarWatts == 123)
        #expect(defaults.data(forKey: "solixHistorySamples") == nil)
    }

    @Test("keeps year-old data hourly-thinned, recent data at full resolution")
    func twoTierRetention() {
        let (store, _) = makeStore()
        let now = Date()
        // 40 Tage alt, auf eine volle Stunde gepinnt: 12 Samples in EINEM
        // Stunden-Bucket -> genau eines (das letzte) bleibt.
        let hourBase = Date(
            timeIntervalSince1970: floor((now.timeIntervalSince1970 - 40 * 86_400) / 3600) * 3600
        )
        for minute in 0..<12 {
            store.record(
                snapshot(solar: 100 + minute, at: hourBase.addingTimeInterval(Double(minute) * 300)),
                sourceKey: "url",
                refreshInterval: 300
            )
        }
        // 400 Tage alt: faellt ganz raus
        store.record(snapshot(solar: 1, at: now.addingTimeInterval(-400 * 86_400)), sourceKey: "url", refreshInterval: 300)
        // frisch: bleibt voll aufgeloest
        store.record(snapshot(solar: 555, at: now.addingTimeInterval(-60)), sourceKey: "url", refreshInterval: 300)
        store.record(snapshot(solar: 556, at: now.addingTimeInterval(-30)), sourceKey: "url", refreshInterval: 300)

        let year = store.samples(duration: 366 * 86_400, sourceKey: "url")
        let old = year.filter { $0.date < now.addingTimeInterval(-31 * 86_400) }
        #expect(old.count == 1)
        #expect(old.first?.solarWatts == 111)
        let fresh = year.filter { $0.date >= now.addingTimeInterval(-3600) }
        #expect(fresh.count == 2)
    }

    @Test("persists across store instances")
    func persistence() {
        let suite = "solixbar-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("solixbar-history-\(UUID().uuidString).json")
        let store = SolixHistoryStore(defaults: defaults, fileURL: fileURL)
        store.record(snapshot(solar: 321, at: Date()), sourceKey: "url", refreshInterval: 300)
        let second = SolixHistoryStore(defaults: defaults, fileURL: fileURL)
        #expect(second.samples(duration: 3600, sourceKey: "url").first?.solarWatts == 321)
    }
}
