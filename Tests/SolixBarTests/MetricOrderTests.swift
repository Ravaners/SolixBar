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

    @Test("PV display modes: total, per input, and both")
    func pvDisplayModes() {
        let formatter = MenuBarFormatter()
        var options = MenuBarDisplayOptions(
            metrics: [.solar],
            showLabels: false,
            showSymbols: false,
            showArrows: false,
            showColors: false
        )
        var snapshot = SolixSnapshot.demo
        snapshot.solarWatts = 642
        snapshot.pvWatts = [438, 204]

        options.pvDisplay = .perInput
        #expect(formatter.plainTitle(for: snapshot, options: options) == "438·204W")
        // Kompaktansicht nutzt dieselben Einzelwerte, mit Pfeil wenn aktiv.
        options.showArrows = true
        let stacked = formatter.stackedEntries(for: snapshot, options: options)
        #expect(stacked.first?.text == "↓438·204W")
        options.showArrows = false

        options.pvDisplay = .both
        #expect(formatter.plainTitle(for: snapshot, options: options) == "642W (438·204)")

        // Ohne Kanalwerte (Solarbank 1) fällt jede Einstellung auf die Summe zurück.
        snapshot.pvWatts = nil
        #expect(formatter.plainTitle(for: snapshot, options: options) == "642W")

        options.pvDisplay = .total
        snapshot.pvWatts = [438, 204]
        #expect(formatter.plainTitle(for: snapshot, options: options) == "642W")
    }

    @Test("PV display settings survive the snapshot/apply round-trip")
    func pvDisplaySettingsRoundTrip() {
        let settings = AppSettings.shared
        let original = settings.snapshot()
        defer { settings.apply(original) }

        var modified = original
        modified.dashboardPVDisplay = .both
        modified.detachedDashboardPVDisplay = .perInput
        modified.menuBarPVDisplay = .perInput
        modified.detachedPVDisplay = .total
        settings.apply(modified)
        #expect(settings.snapshot() == modified)
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
