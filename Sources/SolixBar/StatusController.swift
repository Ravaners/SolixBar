import AppKit

@MainActor
final class StatusController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let settings = AppSettings.shared
    private let historyStore = SolixHistoryStore.shared
    private var timer: Timer?
    private var lastSnapshot: SolixSnapshot?
    private var lastSnapshotMode: DataSourceMode?
    private var lastError: String?
    private var settingsWindow: SettingsWindowController?
    private var largeGraphWindow: LargeGraphWindowController?
    private var desktopWidgetWindow: DesktopWidgetWindowController?
    private var detachedDashboardWindow: DetachedDashboardWindowController?
    private var detachedMenuBarWindow: DetachedMenuBarWindowController?
    private var isMenuBarDetached = false

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
        if isMenuBarDetached {
            setStatusAttributedTitle(detachedMenuBarStatusAttributedTitle())
        } else {
            setStatusTitle("SOLIX ...")
        }
        Task {
            do {
                let snapshot = try await provider().fetchSnapshot()
                lastSnapshot = snapshot
                lastSnapshotMode = settings.dataSourceMode
                lastError = nil
                historyStore.record(snapshot)
            } catch {
                lastSnapshot = nil
                lastSnapshotMode = nil
                lastError = error.localizedDescription
            }
            updateTitle()
            rebuildMenu()
            desktopWidgetWindow?.rebuild()
            detachedDashboardWindow?.rebuild()
            detachedMenuBarWindow?.rebuild()
            largeGraphWindow?.rebuild()
        }
    }

    private func updateTitle() {
        if isMenuBarDetached {
            setStatusAttributedTitle(detachedMenuBarStatusAttributedTitle())
            return
        }

        guard let snapshot = currentSnapshot() else {
            setStatusTitle(lastError == nil ? "SOLIX" : "SOLIX !")
            return
        }

        let battery = snapshot.batteryPercent.map { "\($0)%" } ?? "--%"
        if settings.showMenuBarMetricSymbols || settings.showEnergyFlowArrows || settings.barMetrics.contains(.flow) {
            setStatusAttributedTitle(barAttributedText(for: snapshot, scale: settings.menuBarScale))
        } else {
            let parts = settings.barMetrics.map { metric in
                barText(for: metric, snapshot: snapshot)
            }
            setStatusTitle(parts.isEmpty ? battery : parts.joined(separator: separator()))
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        if let snapshot = currentSnapshot() {
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
        menu.addItem(action("Menüleiste abdocken", #selector(openDetachedMenuBar), "menubar.rectangle"))
        menu.addItem(action("Dashboard abdocken", #selector(openDetachedDashboard), "macwindow.on.rectangle"))
        menu.addItem(action("Widget anzeigen", #selector(openDesktopWidget), "rectangle.inset.filled"))
        menu.addItem(action("Einstellungen ...", #selector(openSettings), "gearshape"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(versionItem())
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

    private func versionItem() -> NSMenuItem {
        let item = NSMenuItem(title: AppVersion.display, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Version")
        item.attributedTitle = NSAttributedString(
            string: AppVersion.display,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
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

    private func separator(scale: Double? = nil) -> String {
        (scale ?? settings.menuBarScale) < 0.95 ? " " : "  "
    }

    private func symbol(for metric: BarMetric, snapshot: SolixSnapshot) -> String {
        switch metric {
        case .battery:
            batterySymbol(snapshot.batteryPercent)
        case .batteryFlow:
            batteryFlowSymbol(snapshot.batteryWatts)
        case .flow:
            metric.symbolName
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
        case .flow:
            .systemGreen
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
        if watts > 0 { return .systemRed }
        if watts < 0 { return .systemGreen }
        return .systemGray
    }

    private var solarColor: NSColor {
        NSColor(calibratedRed: 0.93, green: 0.66, blue: 0.08, alpha: 1)
    }

    private func batteryFlowSymbol(_ watts: Int?) -> String {
        guard let watts else { return "bolt.fill" }
        return watts >= 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill"
    }

    private func batteryFlowColor(_ watts: Int?) -> NSColor {
        guard let watts else { return .systemGray }
        if watts > 0 { return .systemGreen }
        if watts < 0 { return .systemRed }
        return .systemGray
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
        case .flow:
            settings.showMetricLabels ? "\(metric.shortTitle)" : "Flow"
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

    private func barAttributedText(for snapshot: SolixSnapshot, scale: Double) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let metrics = settings.barMetrics.isEmpty ? [BarMetric.battery, .solar] : settings.barMetrics
        for (index, metric) in metrics.enumerated() {
            if index > 0 {
                result.append(textAttachment(separator(scale: scale), scale: scale))
            }
            if metric == .flow {
                appendFlowField(to: result, snapshot: snapshot, scale: scale)
                continue
            }
            if settings.showEnergyFlowArrows,
               let flow = energyFlowText(for: metric, snapshot: snapshot) {
                result.append(textAttachment(flow.text, color: flow.color, weight: .bold, scale: scale))
                result.append(textAttachment(" ", scale: scale))
            }
            if settings.showMenuBarMetricSymbols,
               let image = coloredSymbol(symbol(for: metric, snapshot: snapshot), color: color(for: metric, snapshot: snapshot), accessibilityDescription: metric.title) {
                result.append(imageAttachment(image, scale: scale))
                result.append(textAttachment(" ", scale: scale))
            }
            result.append(textAttachment(barText(for: metric, snapshot: snapshot), color: valueColor(for: metric, snapshot: snapshot), scale: scale))
        }
        return result
    }

    private func appendFlowField(to result: NSMutableAttributedString, snapshot: SolixSnapshot, scale: Double) {
        if settings.showMetricLabels {
            result.append(textAttachment("Flow ", color: .secondaryLabelColor, scale: scale))
        }

        guard settings.showEnergyFlowArrows else {
            result.append(textAttachment("aus", color: .secondaryLabelColor, scale: scale))
            return
        }

        let flows: [BarMetric] = [.solar, .batteryFlow, .grid]
        var didAppend = false
        for metric in flows {
            guard let flow = energyFlowText(for: metric, snapshot: snapshot) else {
                continue
            }
            if didAppend {
                result.append(textAttachment(" ", scale: scale))
            }
            result.append(textAttachment(flow.text, color: flow.color, weight: .bold, scale: scale))
            didAppend = true
        }

        if !didAppend {
            result.append(textAttachment("-", color: .secondaryLabelColor, scale: scale))
        }
    }

    private func energyFlowText(for metric: BarMetric, snapshot: SolixSnapshot) -> (text: String, color: NSColor)? {
        switch metric {
        case .solar:
            guard let watts = snapshot.solarWatts else { return nil }
            return watts > 0 ? ("⬇", highContrastGreen) : ("•", .systemGray)
        case .grid:
            guard let watts = snapshot.gridWatts else { return nil }
            if watts > 0 { return ("⬆", highContrastRed) }
            if watts < 0 { return ("⬇", highContrastGreen) }
            return ("•", .systemGray)
        case .batteryFlow:
            guard let watts = snapshot.batteryWatts else { return nil }
            if watts > 0 { return ("⬇", highContrastGreen) }
            if watts < 0 { return ("⬆", highContrastRed) }
            return ("•", .systemGray)
        default:
            return nil
        }
    }

    private func energyFlowArrow(for metric: BarMetric, snapshot: SolixSnapshot) -> (symbol: String, color: NSColor, description: String)? {
        switch metric {
        case .solar:
            guard let watts = snapshot.solarWatts else { return nil }
            return watts > 0
                ? ("arrow.down.circle.fill", productionColor(watts), "Solar erzeugt Energie")
                : ("minus.circle.fill", .systemGray, "Keine Solarleistung")
        case .grid:
            guard let watts = snapshot.gridWatts else { return nil }
            if watts > 0 {
                return ("arrow.up.circle.fill", consumptionColor(watts), "Strom wird aus dem Netz bezogen")
            }
            if watts < 0 {
                return ("arrow.down.circle.fill", storageColor(abs(watts)), "Strom wird ins Netz eingespeist")
            }
            return ("minus.circle.fill", .systemGray, "Kein Netzfluss")
        case .batteryFlow:
            guard let watts = snapshot.batteryWatts else { return nil }
            if watts > 0 {
                return ("arrow.down.circle.fill", storageColor(watts), "Akku wird geladen")
            }
            if watts < 0 {
                return ("arrow.up.circle.fill", consumptionColor(abs(watts)), "Akku gibt Strom ab")
            }
            return ("minus.circle.fill", .systemGray, "Kein Akku-Fluss")
        default:
            return nil
        }
    }

    private func imageAttachment(_ image: NSImage, scale: Double) -> NSAttributedString {
        let attachment = NSTextAttachment()
        let size = round(13 * scale)
        image.size = NSSize(width: size, height: size)
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: -2, width: size, height: size)
        return NSAttributedString(attachment: attachment)
    }

    private func textAttachment(_ string: String, color: NSColor = .labelColor, weight: NSFont.Weight = .medium, scale: Double) -> NSAttributedString {
        NSAttributedString(
            string: string,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(
                    ofSize: round((string.contains("⬇") || string.contains("⬆")) ? 15 * scale : 13 * scale),
                    weight: weight
                ),
                .foregroundColor: color
            ]
        )
    }

    private func valueColor(for metric: BarMetric, snapshot: SolixSnapshot) -> NSColor {
        switch metric {
        case .solar:
            return snapshot.solarWatts.map(productionColor) ?? .secondaryLabelColor
        case .home:
            return snapshot.homeWatts.map(consumptionColor) ?? .secondaryLabelColor
        case .grid:
            guard let watts = snapshot.gridWatts else { return .secondaryLabelColor }
            if watts > 0 { return consumptionColor(watts) }
            if watts < 0 { return storageColor(abs(watts)) }
            return .secondaryLabelColor
        case .batteryFlow:
            guard let watts = snapshot.batteryWatts else { return .secondaryLabelColor }
            if watts > 0 { return storageColor(watts) }
            if watts < 0 { return consumptionColor(abs(watts)) }
            return .secondaryLabelColor
        default:
            return .labelColor
        }
    }

    private func productionColor(_ watts: Int) -> NSColor {
        if watts <= 0 { return .secondaryLabelColor }
        if watts < 250 { return .systemYellow }
        return storageColor(watts)
    }

    private var highContrastGreen: NSColor {
        NSColor(calibratedRed: 0.00, green: 0.58, blue: 0.22, alpha: 1)
    }

    private var highContrastRed: NSColor {
        NSColor(calibratedRed: 0.88, green: 0.08, blue: 0.12, alpha: 1)
    }

    private func storageColor(_ watts: Int) -> NSColor {
        let fraction = min(1, max(0, Double(watts) / 2000.0))
        return interpolateColor(
            from: NSColor(calibratedRed: 0.95, green: 0.72, blue: 0.16, alpha: 1),
            to: NSColor(calibratedRed: 0.18, green: 0.76, blue: 0.36, alpha: 1),
            fraction: fraction
        )
    }

    private func consumptionColor(_ watts: Int) -> NSColor {
        let fraction = min(1, max(0, Double(watts) / 2000.0))
        return interpolateColor(
            from: NSColor(calibratedRed: 0.95, green: 0.72, blue: 0.16, alpha: 1),
            to: NSColor(calibratedRed: 0.94, green: 0.20, blue: 0.22, alpha: 1),
            fraction: fraction
        )
    }

    private func interpolateColor(from start: NSColor, to end: NSColor, fraction: Double) -> NSColor {
        guard let start = start.usingColorSpace(.deviceRGB),
              let end = end.usingColorSpace(.deviceRGB) else {
            return fraction > 0.5 ? end : start
        }
        let t = CGFloat(fraction)
        return NSColor(
            calibratedRed: start.redComponent + (end.redComponent - start.redComponent) * t,
            green: start.greenComponent + (end.greenComponent - start.greenComponent) * t,
            blue: start.blueComponent + (end.blueComponent - start.blueComponent) * t,
            alpha: 1
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
                snapshotProvider: { [weak self] in self?.currentSnapshot() },
                graphProvider: { [weak self] in self?.graphSamples() ?? [] }
            )
        }
        desktopWidgetWindow?.rebuild()
        desktopWidgetWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openDetachedDashboard() {
        if detachedDashboardWindow == nil {
            detachedDashboardWindow = DetachedDashboardWindowController(
                snapshotProvider: { [weak self] in self?.currentSnapshot() },
                graphProvider: { [weak self] in self?.graphSamples() ?? [] },
                onRangeChange: { [weak self] in
                    self?.desktopWidgetWindow?.rebuild()
                    self?.detachedDashboardWindow?.rebuild()
                    self?.largeGraphWindow?.rebuild()
                },
                onOpenLarge: { [weak self] in
                    self?.openLargeGraph()
                }
            )
        }
        detachedDashboardWindow?.showBelowMenuBar(anchor: statusButtonFrameOnScreen())
    }

    @objc private func openDetachedMenuBar() {
        if detachedMenuBarWindow == nil {
            detachedMenuBarWindow = DetachedMenuBarWindowController(
                attributedBarProvider: { [weak self] in
                    guard let self, let snapshot = self.currentSnapshot() else { return nil }
                    return self.barAttributedText(for: snapshot, scale: self.settings.detachedMenuBarScale)
                },
                onClose: { [weak self] in
                    self?.isMenuBarDetached = false
                    self?.detachedMenuBarWindow = nil
                    self?.updateTitle()
                }
            )
        }
        isMenuBarDetached = true
        updateTitle()
        detachedMenuBarWindow?.showBelowMenuBar(anchor: statusButtonFrameOnScreen())
    }

    private func detachedMenuBarStatusAttributedTitle() -> NSAttributedString {
        let isOnline: Bool
        if let snapshot = currentSnapshot() {
            isOnline = snapshot.status?.localizedCaseInsensitiveContains("offline") != true
        } else {
            isOnline = lastError == nil
        }

        let result = NSMutableAttributedString()
        result.append(NSAttributedString(
            string: "● ",
            attributes: [
                .font: NSFont.systemFont(ofSize: round(12 * settings.menuBarScale), weight: .bold),
                .foregroundColor: isOnline ? NSColor.systemGreen : NSColor.systemRed
            ]
        ))
        result.append(NSAttributedString(
            string: isOnline ? "Online" : "Offline",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: round(13 * settings.menuBarScale), weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
        ))
        return result
    }

    private func statusButtonFrameOnScreen() -> NSRect? {
        guard let button = item.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func applyCurrentSettings(refreshNow: Bool) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: settings.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        updateMenuBarIcon()
        clearStaleSnapshotIfNeeded()
        updateTitle()
        rebuildMenu()
        detachedMenuBarWindow?.rebuild()
        if refreshNow {
            refresh()
        }
    }

    private func currentSnapshot() -> SolixSnapshot? {
        guard lastSnapshotMode == settings.dataSourceMode else { return nil }
        return lastSnapshot
    }

    private func clearStaleSnapshotIfNeeded() {
        guard lastSnapshotMode == settings.dataSourceMode else {
            lastSnapshot = nil
            lastSnapshotMode = nil
            lastError = configurationMessage()
            return
        }

        if !isCurrentDataSourceConfigured {
            lastSnapshot = nil
            lastSnapshotMode = nil
            lastError = configurationMessage()
        }
    }

    private var isCurrentDataSourceConfigured: Bool {
        switch settings.dataSourceMode {
        case .demo:
            true
        case .command:
            !settings.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .url:
            !settings.urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func configurationMessage() -> String? {
        switch settings.dataSourceMode {
        case .demo:
            nil
        case .command:
            isCurrentDataSourceConfigured ? "Noch keine Daten vom JSON-Befehl geladen." : "Kein JSON-Befehl konfiguriert."
        case .url:
            isCurrentDataSourceConfigured ? "Noch keine Daten von der JSON-URL geladen." : "Keine JSON-URL konfiguriert."
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
