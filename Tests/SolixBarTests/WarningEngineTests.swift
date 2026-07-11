import Foundation
import Testing
@testable import SolixBarKit

@Suite("WarningEngine")
struct WarningEngineTests {
    private let base = Date(timeIntervalSince1970: 1_752_000_000)
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func snapshot(
        battery: Int? = nil,
        solar: Int? = nil,
        pv: [Int]? = nil,
        at date: Date
    ) -> SolixSnapshot {
        SolixSnapshot(siteName: "Test", batteryPercent: battery, solarWatts: solar, updatedAt: date, pvWatts: pv)
    }

    /// Spielt eine Serie (Minuten-Offset, Snapshot-Werte) durch und sammelt
    /// alle gefeuerten Ereignisse mit ihrem Offset ein.
    private func run(
        _ engine: inout WarningEngine,
        config: WarningEngine.Config,
        steps: [(minute: Int, battery: Int?, solar: Int?, pv: [Int]?)]
    ) -> [(minute: Int, event: WarningEngine.Event)] {
        var fired: [(Int, WarningEngine.Event)] = []
        for step in steps {
            let date = base.addingTimeInterval(Double(step.minute) * 60)
            let events = engine.evaluate(
                snapshot: snapshot(battery: step.battery, solar: step.solar, pv: step.pv, at: date),
                at: date,
                config: config,
                calendar: utc
            )
            fired.append(contentsOf: events.map { (step.minute, $0) })
        }
        return fired
    }

    @Test("battery warning fires once and re-arms with hysteresis")
    func batteryHysteresis() {
        var engine = WarningEngine()
        var config = WarningEngine.Config()
        config.batteryLowEnabled = true
        config.batteryLowThreshold = 20

        let fired = run(&engine, config: config, steps: [
            (0, 25, 300, nil),
            (5, 19, 300, nil),   // Durchgang nach unten -> feuert
            (10, 18, 300, nil),  // bleibt unten -> still
            (15, 23, 300, nil),  // über Schwelle, aber unter Schwelle+5 -> bleibt entschärft
            (20, 19, 300, nil),  // wieder unten -> still (nicht neu scharf)
            (25, 26, 300, nil),  // > Schwelle+5 -> neu scharf
            (30, 20, 300, nil)   // Durchgang -> feuert erneut
        ])
        #expect(fired.map(\.minute) == [5, 30])
        #expect(fired.first?.event == .batteryLow(percent: 19))
    }

    @Test("a night of zeros never fires the stall warning")
    func nightIsSilent() {
        var engine = WarningEngine()
        var config = WarningEngine.Config()
        config.pvStallEnabled = true

        let steps = (0..<48).map { (minute: $0 * 5, battery: Int?.none, solar: Int?(0), pv: [Int]?.none) }
        let fired = run(&engine, config: config, steps: steps)
        #expect(fired.isEmpty)
    }

    @Test("collapse after production fires once, recovery re-arms")
    func collapseFiresOnce() {
        var engine = WarningEngine()
        var config = WarningEngine.Config()
        config.pvStallEnabled = true
        config.pvStallMinutes = 15

        var steps: [(minute: Int, battery: Int?, solar: Int?, pv: [Int]?)] = []
        // Eine Stunde solide Erzeugung, dann Einbruch auf 0.
        for minute in stride(from: 0, through: 55, by: 5) { steps.append((minute, nil, 300, nil)) }
        for minute in stride(from: 60, through: 90, by: 5) { steps.append((minute, nil, 0, nil)) }
        // Erholung, dann zweiter Einbruch.
        for minute in stride(from: 95, through: 150, by: 5) { steps.append((minute, nil, 250, nil)) }
        for minute in stride(from: 155, through: 185, by: 5) { steps.append((minute, nil, 0, nil)) }

        let fired = run(&engine, config: config, steps: steps)
        #expect(fired.map(\.minute) == [75, 170])
        #expect(fired.allSatisfy { $0.event == .pvStalled })
    }

    @Test("stall detection is refresh-interval independent")
    func intervalIndependence() {
        for interval in [1, 5] {
            var engine = WarningEngine()
            var config = WarningEngine.Config()
            config.pvStallEnabled = true
            config.pvStallMinutes = 15

            var steps: [(minute: Int, battery: Int?, solar: Int?, pv: [Int]?)] = []
            for minute in stride(from: 0, through: 55, by: interval) { steps.append((minute, nil, 300, nil)) }
            for minute in stride(from: 60, through: 90, by: interval) { steps.append((minute, nil, 0, nil)) }
            let fired = run(&engine, config: config, steps: steps)
            #expect(fired.count == 1, "interval \(interval)")
            #expect(fired.first?.minute == 75, "interval \(interval)")
        }
    }

    @Test("daytime window fires at noon but not at night")
    func daytimeWindow() {
        var config = WarningEngine.Config()
        config.pvWindowEnabled = true
        config.pvWindowStartHour = 9
        config.pvWindowEndHour = 17
        config.pvStallMinutes = 15

        // base auf 12:00 UTC schieben: 1_752_000_000 = 2025-07-08 18:40 UTC.
        // Statt zu rechnen, bauen wir die Daten direkt über DateComponents.
        func date(hour: Int, minute: Int) -> Date {
            utc.date(from: DateComponents(year: 2026, month: 7, day: 11, hour: hour, minute: minute))!
        }

        var noonEngine = WarningEngine()
        var fired: [WarningEngine.Event] = []
        for offset in stride(from: 0, through: 30, by: 5) {
            let at = date(hour: 12, minute: offset)
            fired += noonEngine.evaluate(
                snapshot: snapshot(solar: 0, at: at), at: at, config: config, calendar: utc
            )
        }
        #expect(fired == [.pvStalled])

        var nightEngine = WarningEngine()
        var nightFired: [WarningEngine.Event] = []
        for offset in stride(from: 0, through: 30, by: 5) {
            let at = date(hour: 22, minute: offset)
            nightFired += nightEngine.evaluate(
                snapshot: snapshot(solar: 0, at: at), at: at, config: config, calendar: utc
            )
        }
        #expect(nightFired.isEmpty)
    }

    @Test("dead channel fires while siblings produce, both dark stays silent")
    func perChannel() {
        var config = WarningEngine.Config()
        config.perPVEnabled = true
        config.pvStallMinutes = 15

        var engine = WarningEngine()
        var steps: [(minute: Int, battery: Int?, solar: Int?, pv: [Int]?)] = []
        for minute in stride(from: 0, through: 30, by: 5) { steps.append((minute, nil, 250, [0, 250])) }
        let fired = run(&engine, config: config, steps: steps)
        #expect(fired.map(\.event) == [.pvChannelDead(index: 0)])
        #expect(fired.first?.minute == 15)

        var darkEngine = WarningEngine()
        var darkSteps: [(minute: Int, battery: Int?, solar: Int?, pv: [Int]?)] = []
        for minute in stride(from: 0, through: 30, by: 5) { darkSteps.append((minute, nil, 0, [0, 0])) }
        #expect(run(&darkEngine, config: config, steps: darkSteps).isEmpty)
    }

    @Test("per-channel dip fires from own history even when siblings are dark too")
    func perChannelDip() {
        var config = WarningEngine.Config()
        config.perPVDipEnabled = true
        config.pvStallMinutes = 15

        // Beide Eingänge erzeugen, dann brechen BEIDE ein (z. B. Kabeldefekt
        // am gemeinsamen Strang) — der Geschwister-Vergleich griffe hier nicht.
        var engine = WarningEngine()
        var steps: [(minute: Int, battery: Int?, solar: Int?, pv: [Int]?)] = []
        for minute in stride(from: 0, through: 30, by: 5) { steps.append((minute, nil, 500, [300, 200])) }
        for minute in stride(from: 35, through: 60, by: 5) { steps.append((minute, nil, 0, [0, 0])) }
        let fired = run(&engine, config: config, steps: steps)
        #expect(fired.map(\.event).contains(.pvChannelDead(index: 0)))
        #expect(fired.map(\.event).contains(.pvChannelDead(index: 1)))

        // Ohne die Dip-Option bleibt derselbe Verlauf still (Geschwister dunkel).
        var strictEngine = WarningEngine()
        var strictConfig = WarningEngine.Config()
        strictConfig.perPVEnabled = true
        strictConfig.pvStallMinutes = 15
        #expect(run(&strictEngine, config: strictConfig, steps: steps).isEmpty)

        // Nachts (nie erzeugt) bleibt auch die Dip-Option still.
        var nightEngine = WarningEngine()
        var nightSteps: [(minute: Int, battery: Int?, solar: Int?, pv: [Int]?)] = []
        for minute in stride(from: 0, through: 60, by: 5) { nightSteps.append((minute, nil, 0, [0, 0])) }
        #expect(run(&nightEngine, config: config, steps: nightSteps).isEmpty)
    }

    @Test("warning-test demo scenario drives all three warnings")
    func demoWarningsScenario() async throws {
        // Szenario-Start 6 reale Minuten in der Vergangenheit = Demo-Minute 60:
        // Endphase, kompletter Einbruch.
        let provider = DemoWarningsSolixDataProvider(start: Date().addingTimeInterval(-6 * 60))
        let late = try await provider.fetchSnapshot()
        #expect(late.batteryPercent == 16)
        #expect(late.pvWatts == [0, 0])
        #expect(late.solarWatts == 0)

        // Demo-Minute ~15: Akku niedrig, Eingang 2 tot, Eingang 1 erzeugt.
        let mid = try await DemoWarningsSolixDataProvider(start: Date().addingTimeInterval(-90)).fetchSnapshot()
        #expect(mid.batteryPercent == 16)
        #expect(mid.pvWatts == [385, 0])

        // Demo-Minute ~5: alles normal.
        let early = try await DemoWarningsSolixDataProvider(start: Date().addingTimeInterval(-30)).fetchSnapshot()
        #expect(early.batteryPercent == 42)
        #expect(early.pvWatts == [385, 235])
    }

    @Test("disabled warnings never fire")
    func disabledStaysSilent() {
        var engine = WarningEngine()
        let config = WarningEngine.Config() // alles aus
        let fired = run(&engine, config: config, steps: [
            (0, 25, 300, [300, 0]),
            (5, 10, 0, [0, 0]),
            (60, 10, 0, [0, 0])
        ])
        #expect(fired.isEmpty)
    }

    @Test("warning settings survive the snapshot/apply round-trip")
    @MainActor
    func settingsRoundTrip() {
        let settings = AppSettings.shared
        let original = settings.snapshot()
        defer { settings.apply(original) }

        var modified = original
        modified.warnPerPVDipEnabled = true
        modified.warnBatteryLowEnabled = true
        modified.warnBatteryLowThreshold = 33
        modified.warnPVStallEnabled = true
        modified.warnPVStallMinutes = 42
        modified.warnPVStallMinRecentWatts = 111
        modified.warnPVWindowEnabled = true
        modified.warnPVWindowStart = 8
        modified.warnPVWindowEnd = 18
        modified.warnPerPVEnabled = true
        settings.apply(modified)
        #expect(settings.snapshot() == modified)
        #expect(settings.warningConfig().batteryLowThreshold == 33)
        #expect(settings.warningConfig().pvWindowStartHour == 8)
    }
}
