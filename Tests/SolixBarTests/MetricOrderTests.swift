import Foundation
import Testing
@testable import SolixBarKit

@MainActor
@Suite("Metrik-Reihenfolge", .serialized)
struct MetricOrderTests {
    @Test("bar metric order survives storage and snapshot/apply")
    func orderSurvives() {
        let settings = AppSettings.shared
        let original = settings.snapshot()
        defer { settings.apply(original) }

        let custom: [BarMetric] = [.status, .grid, .battery]
        settings.barMetrics = custom
        #expect(settings.barMetrics == custom)

        var modified = settings.snapshot()
        modified.barMetrics = [.total, .solar]
        settings.apply(modified)
        #expect(settings.barMetrics == [.total, .solar])
    }

    @Test("empty stacked lists follow their single-line list")
    func stackedFollowChain() {
        let settings = AppSettings.shared
        let original = settings.snapshot()
        defer { settings.apply(original) }

        settings.barMetrics = [.solar, .battery]
        settings.stackedBarMetrics = []
        settings.detachedBarMetrics = [.grid, .home]
        settings.detachedStackedBarMetrics = []

        #expect(settings.effectiveStackedBarMetrics == [.solar, .battery])
        #expect(settings.effectiveDetachedStackedBarMetrics == [.grid, .home])

        settings.stackedBarMetrics = [.today, .total]
        #expect(settings.effectiveStackedBarMetrics == [.today, .total])
        // Einzeilige Liste bleibt unberührt.
        #expect(settings.barMetrics == [.solar, .battery])
    }

    @Test("stacked entries respect a custom order")
    func stackedEntriesOrder() {
        let formatter = MenuBarFormatter()
        let options = MenuBarDisplayOptions(
            metrics: [.grid, .battery, .solar],
            showLabels: true,
            showSymbols: false,
            showArrows: false,
            showColors: true
        )
        let entries = formatter.stackedEntries(for: .demo, options: options)
        #expect(entries.count == 3)
        // Reihenfolge der Einträge = Reihenfolge der Metrik-Liste
        // (erkennbar an den Symbolen: Netz, Akku, Solar).
        #expect(entries[0].symbolName == "powerplug.fill")
        #expect(entries[1].symbolName.hasPrefix("battery"))
        #expect(entries[2].symbolName == "sun.max.fill")
    }
}
