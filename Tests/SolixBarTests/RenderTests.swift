import AppKit
import Testing
@testable import SolixBarKit

/// Rendert die zentralen Views offscreen als PNG — visuelle Verifikation ohne
/// Screen-Recording-Berechtigung. Ausgabeort: $SOLIXBAR_RENDER_DIR oder .build/renders.
@MainActor
@Suite("Offscreen renders", .serialized)
struct RenderTests {
    static let outputDir: URL = {
        let base = ProcessInfo.processInfo.environment["SOLIXBAR_RENDER_DIR"]
            ?? FileManager.default.currentDirectoryPath + "/.build/renders"
        let url = URL(fileURLWithPath: base)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private func render(_ view: NSView, appearance: NSAppearance.Name, name: String, settle: TimeInterval = 1.2) throws {
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.contentView = view
        RunLoop.main.run(until: Date().addingTimeInterval(settle))
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        let url = Self.outputDir.appendingPathComponent(name + ".png")
        try png.write(to: url)
        #expect(rep.pixelsWide > 0)
    }

    private func demoSamples() -> [SolixHistorySample] {
        let now = Date()
        let duration: TimeInterval = 24 * 60 * 60
        return (0..<48).map { index in
            let progress = Double(index) / 47.0
            let sunlight = max(0, sin(progress * .pi))
            return SolixHistorySample(
                date: now.addingTimeInterval(-duration * (1 - progress)),
                batteryPercent: 55 + Int(progress * 30) + Int(sin(progress * .pi * 2.4) * 6),
                solarWatts: Int(760 * sunlight),
                gridWatts: Int(max(0, 240 - 760 * sunlight * 0.45))
            )
        }
    }

    @Test("dashboard renders in light and dark")
    func dashboard() throws {
        var snapshot = SolixSnapshot.demo
        snapshot.updatedAt = Date().addingTimeInterval(-23)
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let view = SolixMenuDashboardView(
                snapshot: snapshot,
                graphProvider: { self.demoSamples() },
                onRangeChange: {},
                onOpenLarge: {}
            )
            try render(view, appearance: appearance, name: "dashboard-\(suffix)")
        }
    }

    @Test("large graph renders in light and dark")
    func largeGraph() throws {
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let view = HistoryGraphView(
                samples: demoSamples(),
                rangeTitle: "24 Stunden",
                range: .day,
                rangeDuration: 24 * 60 * 60,
                visibleMetrics: GraphMetric.allCases,
                size: NSSize(width: 680, height: 360)
            )
            try render(view, appearance: appearance, name: "graph-large-\(suffix)")
        }
    }

    @Test("detached slim bar renders")
    func detachedBar() throws {
        let text = NSMutableAttributedString(
            string: "Akku 82%  PV 642W  Netz -86W",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]
        )
        let controller = DetachedMenuBarWindowController(
            attributedBarProvider: { text },
            onClose: {}
        )
        let view = try #require(controller.window?.contentView)
        try render(view, appearance: .darkAqua, name: "detached-bar", settle: 0.6)
    }

    @Test("settings tabs render in light and dark")
    func settingsTabs() throws {
        let controller = SettingsWindowController(onPreview: {}, onSave: {}, onReset: {})
        let window = try #require(controller.window)
        let content = try #require(window.contentView)
        window.alphaValue = 0
        controller.showWindow(nil)
        window.setContentSize(NSSize(width: 720, height: 660))
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let tabs = try #require(findTabView(content))
        let names = ["menubar", "datasource", "app", "startup"]
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            for (index, name) in names.enumerated() where index < tabs.numberOfTabViewItems {
                tabs.selectTabViewItem(at: index)
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                let rep = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
                content.cacheDisplay(in: content.bounds, to: rep)
                let png = try #require(rep.representation(using: .png, properties: [:]))
                try png.write(to: Self.outputDir.appendingPathComponent("settings-\(name)-\(suffix).png"))
            }
        }
        window.close()
    }

    private func findTabView(_ view: NSView) -> NSTabView? {
        if let tab = view as? NSTabView { return tab }
        for sub in view.subviews {
            if let found = findTabView(sub) { return found }
        }
        return nil
    }
}
