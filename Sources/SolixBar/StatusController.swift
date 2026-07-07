import AppKit

@MainActor
final class StatusController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let settings = AppSettings.shared
    private let historyStore = SolixHistoryStore.shared
    private var timer: Timer?
    private var lastSnapshot: SolixSnapshot?
    private var lastError: String?
    private var settingsWindow: SettingsWindowController?
    private var largeGraphWindow: LargeGraphWindowController?
    private var desktopWidgetWindow: DesktopWidgetWindowController?

    func start() {
        updateMenuBarIcon()
        setStatusTitle("SOLIX")
        rebuildMenu()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: settings.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func provider() -> SolixDataProvider {
        switch settings.dataSourceMode {
        case .demo:
            DemoSolixDataProvider()
        case .command:
            CommandSolixDataProvider(command: settings.command)
        case .url:
            URLSolixDataProvider(urlString: settings.urlString)
        }
    }

    private func refresh() {
        setStatusTitle("SOLIX ...")
        Task {
            do {
                let snapshot = try await provider().fetchSnapshot()
                lastSnapshot = snapshot
                lastError = nil
                historyStore.record(snapshot)
            } catch {
                lastError = error.localizedDescription
            }
            updateTitle()
            rebuildMenu()
            desktopWidgetWindow?.rebuild()
            largeGraphWindow?.rebuild()
        }
    }

    private func updateTitle() {
        guard let snapshot = lastSnapshot else {
            setStatusTitle(lastError == nil ? "SOLIX" : "SOLIX !")
            return
        }

        let battery = snapshot.batteryPercent.map { "\($0)%" } ?? "--%"
        if settings.showMenuBarMetricSymbols || settings.showEnergyFlowArrows {
            setStatusAttributedTitle(barAttributedText(for: snapshot))
        } else {
            let parts = settings.barMetrics.map { metric in
                barText(for: metric, snapshot: snapshot)
            }
            setStatusTitle(parts.isEmpty ? battery : parts.joined(separator: separator()))
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        if let snapshot = lastSnapshot {
            menu.addItem(dashboardItem(snapshot))
        } else {
            menu.addItem(header("Anker SOLIX"))
            menu.addItem(value("Status", lastError ?? "Warte auf Daten ...", symbol: "hourglass", color: .systemGray))
        }

        if let lastError {
            menu.addItem(NSMenuItem.separator())
            menu.addItem(value("Fehler", lastError, symbol: "exclamationmark.triangle.fill", color: .systemRed))
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(action("Aktualisieren", #selector(refreshMenuAction), "arrow.clockwise"))
        menu.addItem(action("Widget anzeigen", #selector(openDesktopWidget), "rectangle.inset.filled"))
        menu.addItem(action("Einstellungen ...", #selector(openSettings), "gearshape"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(action("Beenden", #selector(quit), "power"))
        item.menu = menu
    }

    private func dashboardItem(_ snapshot: SolixSnapshot) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = SolixMenuDashboardView(
            snapshot: snapshot,
            graphProvider: { [weak self] in self?.graphSamples() ?? [] },
            onRangeChange: { [weak self] in
                self?.desktopWidgetWindow?.rebuild()
                self?.largeGraphWindow?.rebuild()
            },
            onOpenLarge: { [weak self] in
                self?.openLargeGraph()
            }
        )
        return item
    }

    private func historyGraphItem() -> NSMenuItem {
        let item = NSMenuItem()
        item.view = HistoryGraphMenuView(
            graphProvider: { [weak self] in self?.graphSamples() ?? [] },
            onRangeChange: { [weak self] in
                self?.desktopWidgetWindow?.rebuild()
                self?.largeGraphWindow?.rebuild()
            },
            onOpenLarge: { [weak self] in
                self?.openLargeGraph()
            }
        )
        return item
    }

    private func graphSamples() -> [SolixHistorySample] {
        let samples = historyStore.samples(duration: settings.historyDuration)
        guard samples.count < 3, settings.dataSourceMode == .demo else { return samples }
        return demoGraphSamples(duration: settings.historyDuration)
    }

    private func demoGraphSamples(duration: TimeInterval) -> [SolixHistorySample] {
        let now = Date()
        let count = 32
        return (0..<count).map { index in
            let progress = Double(index) / Double(count - 1)
            let wave = sin(progress * .pi * 2.4)
            let sunlight = max(0, sin(progress * .pi))
            return SolixHistorySample(
                date: now.addingTimeInterval(-duration * (1 - progress)),
                batteryPercent: 58 + Int(progress * 22) + Int(wave * 6),
                solarWatts: Int(720 * sunlight),
                gridWatts: Int(max(0, 220 - (720 * sunlight * 0.45)))
            )
        }
    }

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor
            ]
        )
        return item
    }

    private func value(_ label: String, _ text: String?, symbol: String, color: NSColor) -> NSMenuItem {
        let title = "\(label): \(text ?? "-")"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]
        )
        item.image = coloredSymbol(symbol, color: color, accessibilityDescription: label)
        return item
    }

    private func metricValue(_ metric: BarMetric, _ text: String?, snapshot: SolixSnapshot, label: String? = nil) -> NSMenuItem {
        value(label ?? metric.title, text, symbol: symbol(for: metric, snapshot: snapshot), color: color(for: metric, snapshot: snapshot))
    }

    private func action(_ title: String, _ selector: Selector, _ symbol: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }

    private func coloredSymbol(_ symbol: String, color: NSColor, accessibilityDescription: String) -> NSImage? {
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibilityDescription) else {
            return nil
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let configured = image.withSymbolConfiguration(configuration) ?? image
        let copy = configured.copy() as? NSImage ?? configured
        copy.isTemplate = false
        copy.lockFocus()
        color.set()
        NSRect(origin: .zero, size: copy.size).fill(using: .sourceAtop)
        copy.unlockFocus()
        return copy
    }

    private func updateMenuBarIcon() {
        guard settings.showMenuBarIcon else {
            item.button?.image = nil
            item.button?.imagePosition = .noImage
            return
        }

        item.button?.image = menuBarIcon()
        item.button?.imagePosition = .imageLeading
    }

    private func menuBarIcon() -> NSImage? {
        let appIcon = Bundle.main.url(forResource: "SolixBar", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }

        guard let image = appIcon ?? coloredSymbol("bolt.fill", color: .systemYellow, accessibilityDescription: "SOLIX") else {
            return nil
        }

        let copy = image.copy() as? NSImage ?? image
        let size = round(18 * settings.menuBarScale)
        copy.size = NSSize(width: size, height: size)
        copy.isTemplate = false
        return copy
    }

    private func setStatusTitle(_ title: String) {
        let prefix = settings.showMenuBarIcon ? " " : ""
        let fontSize = round(13 * settings.menuBarScale)
        item.button?.attributedTitle = NSAttributedString(
            string: prefix + title,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]
        )
    }

    private func setStatusAttributedTitle(_ value: NSAttributedString) {
        let title = NSMutableAttributedString()
        if settings.showMenuBarIcon {
            title.append(NSAttributedString(string: " "))
        }
        title.append(value)
        item.button?.attributedTitle = title
    }

    private func separator() -> String {
        settings.menuBarScale < 0.95 ? " " : "  "
    }

    private func symbol(for metric: BarMetric, snapshot: SolixSnapshot) -> String {
        switch metric {
        case .battery:
            batterySymbol(snapshot.batteryPercent)
        case .batteryFlow:
            batteryFlowSymbol(snapshot.batteryWatts)
        default:
            metric.symbolName
        }
    }

    private func color(for metric: BarMetric, snapshot: SolixSnapshot) -> NSColor {
        switch metric {
        case .battery:
            batteryColor(snapshot.batteryPercent)
        case .solar:
            solarColor
        case .home:
            .systemBlue
        case .grid:
            gridColor(snapshot.gridWatts)
        case .batteryFlow:
            batteryFlowColor(snapshot.batteryWatts)
        case .today:
            .systemGreen
        case .total:
            .systemPurple
        case .status:
            .systemGreen
        }
    }

    private func batterySymbol(_ percent: Int?) -> String {
        guard let percent else { return "battery.75percent" }
        if percent <= 20 { return "battery.25percent" }
        if percent <= 60 { return "battery.50percent" }
        return "battery.100percent"
    }

    private func batteryColor(_ percent: Int?) -> NSColor {
        guard let percent else { return .systemGray }
        if percent <= 20 { return .systemRed }
        if percent <= 45 { return .systemOrange }
        return .systemGreen
    }

    private func gridColor(_ watts: Int?) -> NSColor {
        guard let watts else { return .systemGray }
        return watts > 0 ? .systemBlue : .systemTeal
    }

    private var solarColor: NSColor {
        NSColor(calibratedRed: 0.93, green: 0.66, blue: 0.08, alpha: 1)
    }

    private func batteryFlowSymbol(_ watts: Int?) -> String {
        guard let watts else { return "bolt.fill" }
        return watts >= 0 ? "bolt.fill" : "arrow.down.circle.fill"
    }

    private func batteryFlowColor(_ watts: Int?) -> NSColor {
        guard let watts else { return .systemGray }
        return watts >= 0 ? .systemGreen : .systemOrange
    }

    private func formatSignedWatts(_ value: Int?) -> String? {
        guard let value else { return nil }
        return value > 0 ? "+\(value) W" : "\(value) W"
    }

    private func barText(for metric: BarMetric, snapshot: SolixSnapshot) -> String {
        switch metric {
        case .battery:
            formatBarMetric(metric, value: snapshot.batteryPercent.map { "\($0)%" } ?? "--%")
        case .solar:
            formatBarMetric(metric, value: snapshot.solarWatts.map { "\($0)W" } ?? "--W")
        case .home:
            formatBarMetric(metric, value: snapshot.homeWatts.map { "\($0)W" } ?? "--W")
        case .grid:
            formatBarMetric(metric, value: formatSignedWatts(snapshot.gridWatts) ?? "--W")
        case .batteryFlow:
            formatBarMetric(metric, value: formatSignedWatts(snapshot.batteryWatts) ?? "--W")
        case .today:
            formatBarMetric(metric, value: snapshot.todayKWh.map { String(format: "%.2fkWh", $0) } ?? "--kWh")
        case .total:
            formatBarMetric(metric, value: snapshot.totalKWh.map { String(format: "%.1fkWh", $0) } ?? "--kWh")
        case .status:
            formatBarMetric(metric, value: snapshot.status ?? "-")
        }
    }

    private func formatBarMetric(_ metric: BarMetric, value: String) -> String {
        settings.showMetricLabels ? "\(metric.shortTitle) \(value)" : value
    }

    private func barAttributedText(for snapshot: SolixSnapshot) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let metrics = settings.barMetrics.isEmpty ? [BarMetric.battery, .solar] : settings.barMetrics
        for (index, metric) in metrics.enumerated() {
            if index > 0 {
                result.append(textAttachment(separator()))
            }
            if settings.showEnergyFlowArrows,
               let flow = energyFlowArrow(for: metric, snapshot: snapshot),
               let image = coloredSymbol(flow.symbol, color: flow.color, accessibilityDescription: flow.description) {
                result.append(imageAttachment(image))
                result.append(textAttachment(" "))
            }
            if settings.showMenuBarMetricSymbols,
               let image = coloredSymbol(symbol(for: metric, snapshot: snapshot), color: color(for: metric, snapshot: snapshot), accessibilityDescription: metric.title) {
                result.append(imageAttachment(image))
                result.append(textAttachment(" "))
            }
            result.append(textAttachment(barText(for: metric, snapshot: snapshot)))
        }
        return result
    }

    private func energyFlowArrow(for metric: BarMetric, snapshot: SolixSnapshot) -> (symbol: String, color: NSColor, description: String)? {
        switch metric {
        case .solar:
            guard let watts = snapshot.solarWatts else { return nil }
            return watts > 0
                ? ("arrow.down.circle.fill", solarColor, "Solar erzeugt Energie")
                : ("minus.circle.fill", .systemGray, "Keine Solarleistung")
        case .grid:
            guard let watts = snapshot.gridWatts else { return nil }
            if watts > 0 {
                return ("arrow.up.circle.fill", .systemRed, "Strom wird aus dem Netz bezogen")
            }
            if watts < 0 {
                return ("arrow.down.circle.fill", .systemGreen, "Strom wird ins Netz eingespeist")
            }
            return ("minus.circle.fill", .systemGray, "Kein Netzfluss")
        case .batteryFlow:
            guard let watts = snapshot.batteryWatts else { return nil }
            if watts > 0 {
                return ("arrow.down.circle.fill", .systemGreen, "Akku gibt Strom ab")
            }
            if watts < 0 {
                return ("arrow.up.circle.fill", .systemOrange, "Akku wird geladen")
            }
            return ("minus.circle.fill", .systemGray, "Kein Akku-Fluss")
        default:
            return nil
        }
    }

    private func imageAttachment(_ image: NSImage) -> NSAttributedString {
        let attachment = NSTextAttachment()
        let size = round(13 * settings.menuBarScale)
        image.size = NSSize(width: size, height: size)
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: -2, width: size, height: size)
        return NSAttributedString(attachment: attachment)
    }

    private func textAttachment(_ string: String) -> NSAttributedString {
        NSAttributedString(
            string: string,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: round(13 * settings.menuBarScale), weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]
        )
    }

    @objc private func refreshMenuAction() {
        refresh()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(
                onPreview: { [weak self] in
                    self?.applyCurrentSettings(refreshNow: false)
                },
                onSave: { [weak self] in
                    self?.applyCurrentSettings(refreshNow: true)
                },
                onReset: { [weak self] in
                    self?.applyCurrentSettings(refreshNow: true)
                }
            )
        }
        settingsWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openLargeGraph() {
        if largeGraphWindow == nil {
            largeGraphWindow = LargeGraphWindowController(graphProvider: { [weak self] in self?.graphSamples() ?? [] })
        }
        largeGraphWindow?.rebuild()
        largeGraphWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openDesktopWidget() {
        if desktopWidgetWindow == nil {
            desktopWidgetWindow = DesktopWidgetWindowController(
                snapshotProvider: { [weak self] in self?.lastSnapshot },
                graphProvider: { [weak self] in self?.graphSamples() ?? [] }
            )
        }
        desktopWidgetWindow?.rebuild()
        desktopWidgetWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyCurrentSettings(refreshNow: Bool) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: settings.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        updateMenuBarIcon()
        updateTitle()
        rebuildMenu()
        if refreshNow {
            refresh()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
