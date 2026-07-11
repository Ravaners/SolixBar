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

    /// Leicht abweichender Vorgänger-Snapshot, damit die Trend-Pfeile der
    /// Dashboard-Karten im Render sichtbar sind (wie in der echten App ab
    /// dem zweiten Refresh).
    private func previousDemoSnapshot(of snapshot: SolixSnapshot) -> SolixSnapshot {
        var previous = snapshot
        previous.batteryPercent = snapshot.batteryPercent.map { $0 - 3 }
        previous.solarWatts = snapshot.solarWatts.map { $0 - 60 }
        previous.gridWatts = snapshot.gridWatts.map { $0 + 40 }
        previous.batteryWatts = snapshot.batteryWatts.map { $0 + 25 }
        return previous
    }

    @Test("dashboard renders in light and dark")
    func dashboard() throws {
        var snapshot = SolixSnapshot.demo
        snapshot.updatedAt = Date().addingTimeInterval(-23)
        let previous = previousDemoSnapshot(of: snapshot)
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let view = SolixMenuDashboardView(
                snapshot: snapshot,
                previous: previous,
                graphProvider: { self.demoSamples() },
                onRangeChange: {},
                onOpenLarge: {}
            )
            try render(view, appearance: appearance, name: "dashboard-\(suffix)")

            let windowStyle = SolixMenuDashboardView(
                snapshot: snapshot,
                previous: previous,
                style: .window,
                graphProvider: { self.demoSamples() },
                onRangeChange: {},
                onOpenLarge: {}
            )
            try render(windowStyle, appearance: appearance, name: "dashboard-window-\(suffix)")
        }
    }

    /// Rendert das echte Verlaufsfenster (inkl. Chip-Kopfzeile) statt nur
    /// der nackten Graph-View — sonst zeigen die Bilder eine Kopfzeile,
    /// die es im Fenster gar nicht gibt.
    @Test("large graph window renders in light and dark")
    func largeGraph() throws {
        let savedAppearance = NSApp.appearance
        defer { NSApp.appearance = savedAppearance }
        for (suffix, name) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let appearance = try #require(NSAppearance(named: name))
            NSApp.appearance = appearance
            let controller = LargeGraphWindowController(graphProvider: { self.demoSamples() })
            let window = try #require(controller.window)
            window.appearance = appearance
            window.alphaValue = 0
            controller.showWindow(nil)
            let content = try #require(window.contentView)
            content.wantsLayer = true
            appearance.performAsCurrentDrawingAppearance {
                content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.8))
            let rep = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
            content.cacheDisplay(in: content.bounds, to: rep)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: Self.outputDir.appendingPathComponent("graph-large-\(suffix).png"))
            window.close()
        }
    }

    /// Baut die Leiste pro Appearance neu auf (cgColor-Auflösung!) und legt
    /// sie über einen Schreibtisch-artigen Verlauf: Offscreen rendert die
    /// Vibrancy nichts — ohne Hintergrund sah "dunkel" hell aus.
    @Test("detached slim bar renders")
    func detachedBar() throws {
        let formatter = MenuBarFormatter()
        var snapshot = SolixSnapshot.demo
        snapshot.updatedAt = Date()
        let options = MenuBarDisplayOptions(
            metrics: [.battery, .solar, .grid],
            showLabels: true,
            showSymbols: true,
            showArrows: false
        )
        let savedAppearance = NSApp.appearance
        defer { NSApp.appearance = savedAppearance }

        for (suffix, name) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            let appearance = try #require(NSAppearance(named: name))
            NSApp.appearance = appearance
            let controller = DetachedMenuBarWindowController(
                attributedBarProvider: { formatter.attributedTitle(for: snapshot, scale: 1.0, options: options) },
                onClose: {}
            )
            let bar = try #require(controller.window?.contentView)
            bar.autoresizingMask = []

            let canvas = NSView(frame: NSRect(x: 0, y: 0, width: bar.frame.width + 48, height: bar.frame.height + 48))
            canvas.wantsLayer = true
            let gradient = CAGradientLayer()
            gradient.frame = canvas.bounds
            gradient.startPoint = CGPoint(x: 0, y: 0)
            gradient.endPoint = CGPoint(x: 1, y: 1)
            gradient.colors = suffix == "dark"
                ? [NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.18, alpha: 1).cgColor,
                   NSColor(calibratedRed: 0.17, green: 0.13, blue: 0.24, alpha: 1).cgColor]
                : [NSColor(calibratedRed: 0.80, green: 0.86, blue: 0.93, alpha: 1).cgColor,
                   NSColor(calibratedRed: 0.94, green: 0.90, blue: 0.83, alpha: 1).cgColor]
            canvas.layer?.addSublayer(gradient)
            bar.setFrameOrigin(NSPoint(x: 24, y: 24))
            canvas.addSubview(bar)

            try render(canvas, appearance: name, name: "detached-bar-\(suffix)", settle: 0.6)
        }
    }

    @Test("settings tabs render in light and dark")
    func settingsTabs() throws {
        let controller = SettingsWindowController(onPreview: {}, onSave: {}, onReset: {})
        let window = try #require(controller.window)
        let content = try #require(window.contentView)
        // Nicht per alphaValue verstecken: dann lässt AppKit die Textzeichnung
        // beim cacheDisplay weg (leere Panes) — stattdessen aus dem sichtbaren
        // Bereich schieben.
        window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
        controller.showWindow(nil)
        window.setContentSize(NSSize(width: 720, height: 660))
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let tabs = try #require(findTabView(content))
        let names = ["menubar", "detachedbar", "datasource", "warnings", "app"]
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            for (index, name) in names.enumerated() where index < tabs.numberOfTabViewItems {
                tabs.selectTabViewItem(at: index)
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                // cacheDisplay lässt bei Fenster-Inhalten Text/Hintergrund weg;
                // der PDF-Pfad geht durch draw(_:) und erfasst alles.
                let pdfData = content.dataWithPDF(inside: content.bounds)
                let pdfImage = try #require(NSImage(data: pdfData))
                let scale: CGFloat = 2
                let size = content.bounds.size
                let rep = try #require(NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: Int(size.width * scale),
                    pixelsHigh: Int(size.height * scale),
                    bitsPerSample: 8,
                    samplesPerPixel: 4,
                    hasAlpha: true,
                    isPlanar: false,
                    colorSpaceName: .deviceRGB,
                    bytesPerRow: 0,
                    bitsPerPixel: 0
                ))
                rep.size = size
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                (NSAppearance(named: appearance) ?? NSAppearance.currentDrawing()).performAsCurrentDrawingAppearance {
                    NSColor.windowBackgroundColor.setFill()
                    NSRect(origin: .zero, size: size).fill()
                    pdfImage.draw(in: NSRect(origin: .zero, size: size))
                }
                NSGraphicsContext.restoreGraphicsState()
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

@MainActor
@Suite("Stacked menu bar renders")
struct StackedRenderTests {
    @Test("two-line compact image renders in light and dark")
    func stackedImage() throws {
        let entries: [StackedMenuBarRenderer.Entry] = [
            .init(symbolName: "battery.75percent", text: "82%", role: .batteryHigh),
            .init(symbolName: "sun.max.fill", text: "642W", role: .solar),
            .init(symbolName: "house.fill", text: "318W", role: .load),
            .init(symbolName: "powerplug.fill", text: "-86W", role: .gridExport)
        ]
        let image = try #require(StackedMenuBarRenderer.image(entries: entries, scale: 1.0, showWarning: false))
        #expect(image.size.width > 40 && image.size.width < 260)

        for (suffix, name) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let appearance = try #require(NSAppearance(named: name))
            let canvas = NSImage(size: NSSize(width: image.size.width + 12, height: 28))
            canvas.lockFocus()
            appearance.performAsCurrentDrawingAppearance {
                (suffix == "dark"
                    ? NSColor(calibratedWhite: 0.12, alpha: 1)
                    : NSColor(calibratedWhite: 0.94, alpha: 1)).setFill()
                NSRect(origin: .zero, size: canvas.size).fill()
                image.draw(
                    in: NSRect(x: 6, y: 3, width: image.size.width, height: 22),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
            }
            canvas.unlockFocus()
            let tiff = try #require(canvas.tiffRepresentation)
            let rep = try #require(NSBitmapImageRep(data: tiff))
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: RenderTests.outputDir.appendingPathComponent("menubar-stacked-\(suffix).png"))
        }
    }
}
