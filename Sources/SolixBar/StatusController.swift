import AppKit

private func menuBarUsesDarkBackground(_ appearance: NSAppearance) -> Bool {
    var label: NSColor?
    appearance.performAsCurrentDrawingAppearance {
        label = NSColor.labelColor.usingColorSpace(.deviceRGB)
    }
    if let label {
        let luminance = 0.2126 * label.redComponent
            + 0.7152 * label.greenComponent
            + 0.0722 * label.blueComponent
        return luminance > 0.55
    }

    let match = appearance.bestMatch(from: [.vibrantDark, .darkAqua, .vibrantLight, .aqua])
    return match == .vibrantDark || match == .darkAqua
}

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
    private var detachedDashboardWindow: DetachedDashboardWindowController?
    private var detachedMenuBarWindow: DetachedMenuBarWindowController?
    private var isMenuBarDetached = false
    private var isTerminating = false
    private var isRefreshing = false
    private var refreshAnimationTimer: Timer?
    private var refreshAnimationFrame = 0
    private let refreshFrames = ["↻", "↺"]

    func start() {
        settings.migrateMenuBarGridMetricIfNeeded()
        applyAppearance()
        updateMenuBarIcon()
        setStatusTitle("SOLIX")
        rebuildMenu()
        refresh()
        if settings.isDetachedMenuBarActive {
            AppLogger.info("Restoring detached slim bar from previous session.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.openDetachedMenuBar()
            }
        }
        scheduleRefreshTimer()
    }

    func prepareForTermination() {
        isTerminating = true
        settings.isDetachedMenuBarActive = isMenuBarDetached
        AppLogger.info("Persisted detached slim bar state: \(isMenuBarDetached ? "active" : "inactive").")
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
        guard !isRefreshing else {
            AppLogger.info("Refresh skipped because a previous refresh is still running.")
            return
        }
        isRefreshing = true
        startRefreshAnimation()
        AppLogger.info("Refreshing data source: \(settings.dataSourceMode.rawValue).")
        updateTitle()
        Task {
            defer {
                isRefreshing = false
                stopRefreshAnimation()
            }
            do {
                var snapshot = try await provider().fetchSnapshot()
                snapshot.updatedAt = Date()
                snapshot.totalKWh = historyStore.cumulativeSolarKWh(
                    recording: snapshot,
                    sourceKey: settings.dataSourceMode.rawValue
                )
                lastSnapshot = snapshot
                lastSnapshotMode = settings.dataSourceMode
                lastError = nil
                historyStore.record(snapshot)
                AppLogger.info("Refresh succeeded: battery=\(snapshot.batteryPercent.map(String.init) ?? "-")%, solar=\(snapshot.solarWatts.map(String.init) ?? "-")W, grid=\(snapshot.gridWatts.map(String.init) ?? "-")W.")
            } catch {
                lastSnapshot = nil
                lastSnapshotMode = nil
                lastError = error.localizedDescription
                AppLogger.error("Refresh failed: \(error.localizedDescription)")
            }
            updateTitle()
            rebuildMenu()
            detachedDashboardWindow?.rebuild()
            detachedMenuBarWindow?.rebuild()
            largeGraphWindow?.rebuild()
        }
    }

    private func startRefreshAnimation() {
        refreshAnimationFrame = 0
        refreshAnimationTimer?.invalidate()
        let timer = Timer(timeInterval: 0.16, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refreshAnimationFrame = (self.refreshAnimationFrame + 1) % self.refreshFrames.count
                self.updateTitle()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshAnimationTimer = timer
    }

    private func stopRefreshAnimation() {
        refreshAnimationTimer?.invalidate()
        refreshAnimationTimer = nil
        refreshAnimationFrame = 0
        updateTitle()
    }

    private func scheduleRefreshTimer() {
        timer?.invalidate()
        let interval = max(60, settings.refreshInterval)
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        newTimer.tolerance = min(5, interval * 0.1)
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
        AppLogger.info("Refresh timer scheduled every \(Int(interval)) seconds in common run loop modes.")
    }

    private func updateTitle() {
        if isRefreshing {
            setStatusAttributedTitle(refreshStatusAttributedTitle(scale: settings.menuBarScale))
            return
        }

        if isMenuBarDetached {
            setStatusAttributedTitle(detachedMenuBarStatusAttributedTitle())
            return
        }

        guard let snapshot = currentSnapshot() else {
            let title = lastError == nil ? "SOLIX" : "SOLIX !"
            setStatusTitle(title)
            return
        }

        let battery = snapshot.batteryPercent.map { "\($0)%" } ?? "--%"
        if settings.showMenuBarMetricSymbols || settings.showEnergyFlowArrows || settings.barMetrics.contains(.flow) {
            setStatusAttributedTitle(barAttributedText(for: snapshot, scale: settings.menuBarScale))
        } else {
            let parts = visibleBarMetrics(for: snapshot).map { metric in
                barText(for: metric, snapshot: snapshot)
            }
            let title = parts.isEmpty ? battery : parts.joined(separator: separator())
            setStatusTitle(title)
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        if let snapshot = currentSnapshot() {
            menu.addItem(dashboardItem(snapshot))
        } else {
            menu.addItem(header("Anker SOLIX"))
            menu.addItem(value(LocalizedText.text("Status", "Status"), lastError ?? LocalizedText.text("Warte auf Daten ...", "Waiting for data ..."), symbol: "hourglass", color: .systemGray))
        }

        if let lastError {
            menu.addItem(NSMenuItem.separator())
            menu.addItem(value(LocalizedText.text("Fehler", "Error"), lastError, symbol: "exclamationmark.triangle.fill", color: .systemRed))
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(action(LocalizedText.text("Aktualisieren", "Refresh"), #selector(refreshMenuAction), "arrow.clockwise"))
        menu.addItem(action(
            isMenuBarDetached
                ? LocalizedText.text("Menüleiste andocken", "Dock menu bar")
                : LocalizedText.text("Menüleiste abdocken", "Detach menu bar"),
            #selector(toggleDetachedMenuBar),
            "menubar.rectangle"
        ))
        menu.addItem(action(LocalizedText.text("Dashboard abdocken", "Detach dashboard"), #selector(openDetachedDashboard), "macwindow.on.rectangle"))
        menu.addItem(action(LocalizedText.text("Einstellungen ...", "Settings ..."), #selector(openSettings), "gearshape"))
        menu.addItem(action(LocalizedText.text("Logdatei anzeigen", "Show log file"), #selector(showLogFile), "doc.text.magnifyingglass"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(versionItem())
        menu.addItem(action(LocalizedText.text("Beenden", "Quit"), #selector(quit), "power"))
        item.menu = menu
    }

    private func dashboardItem(_ snapshot: SolixSnapshot) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = SolixMenuDashboardView(
            snapshot: snapshot,
            graphProvider: { [weak self] in self?.graphSamples() ?? [] },
            onRangeChange: { [weak self] in
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
        value(label ?? metricTitle(metric), text, symbol: symbol(for: metric, snapshot: snapshot), color: color(for: metric, snapshot: snapshot))
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
        guard shouldShowMenuBarIcon else {
            item.button?.image = nil
            item.button?.imagePosition = .noImage
            return
        }

        item.button?.image = menuBarIcon()
        item.button?.imagePosition = .imageLeading
    }

    private var shouldShowMenuBarIcon: Bool {
        settings.showMenuBarIcon || isMenuBarDetached
    }

    private func menuBarIcon() -> NSImage? {
        let appIcon = Bundle.main.url(forResource: "SolixBar", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }

        guard let image = appIcon ?? coloredSymbol("bolt.fill", color: .systemYellow, accessibilityDescription: "SOLIX") else {
            return nil
        }

        let size = round(18 * settings.menuBarScale)
        return roundedIconImage(image, size: size)
    }

    private func setStatusTitle(_ title: String) {
        let prefix = shouldShowMenuBarIcon ? " " : ""
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
        if shouldShowMenuBarIcon {
            title.append(NSAttributedString(string: " "))
        }
        title.append(value)
        item.button?.attributedTitle = title
    }

    private func refreshIndicator() -> String {
        refreshFrames[refreshAnimationFrame % refreshFrames.count]
    }

    private func refreshIndicatorAttributedText(scale: Double) -> NSAttributedString {
        NSAttributedString(
            string: refreshIndicator(),
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: round(14 * scale), weight: .bold),
                .foregroundColor: refreshColor,
                .shadow: menuBarTextShadow
            ]
        )
    }

    private func refreshStatusAttributedTitle(scale: Double) -> NSAttributedString {
        NSAttributedString(
            string: "\(refreshIndicator()) \(LocalizedText.text("Aktualisiert ...", "Refreshing ..."))",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: round(13 * scale), weight: .bold),
                .foregroundColor: refreshColor,
                .shadow: menuBarTextShadow
            ]
        )
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
            homeConsumptionColor
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
        if percent <= 20 { return batteryLowColor }
        if percent <= 60 { return batteryMediumColor }
        return batteryHighColor
    }

    private func gridColor(_ watts: Int?) -> NSColor {
        guard let watts else { return .systemGray }
        if watts > 0 { return gridImportColor }
        if watts < 0 { return gridExportColor }
        return .systemGray
    }

    private var solarColor: NSColor {
        solarFlowColor
    }

    private func batteryFlowSymbol(_ watts: Int?) -> String {
        guard let watts else { return "bolt.fill" }
        return watts >= 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill"
    }

    private func batteryFlowColor(_ watts: Int?) -> NSColor {
        guard let watts else { return .systemGray }
        if watts > 0 { return batteryChargingColor }
        if watts < 0 { return batteryDischargingColor }
        return .systemGray
    }

    private func formatSignedWatts(_ value: Int?) -> String? {
        guard let value else { return nil }
        return value > 0 ? "+\(value) W" : "\(value) W"
    }

    private func formatFlowWatts(_ value: Int?) -> String? {
        guard let value else { return nil }
        return settings.showEnergyFlowArrows ? "\(abs(value)) W" : formatSignedWatts(value)
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
            formatBarMetric(metric, value: formatFlowWatts(snapshot.gridWatts) ?? "--W")
        case .batteryFlow:
            formatBarMetric(metric, value: formatFlowWatts(snapshot.batteryWatts) ?? "--W")
        case .flow:
            settings.showMetricLabels ? "\(metricShortTitle(metric))" : "Flow"
        case .today:
            formatBarMetric(metric, value: snapshot.todayKWh.map { String(format: "%.2fkWh", $0) } ?? "--kWh")
        case .total:
            formatBarMetric(metric, value: snapshot.totalKWh.map { String(format: "%.1fkWh", $0) } ?? "--kWh")
        case .status:
            formatBarMetric(metric, value: snapshot.status ?? "-")
        }
    }

    private func formatBarMetric(_ metric: BarMetric, value: String) -> String {
        settings.showMetricLabels ? "\(metricShortTitle(metric)) \(value)" : value
    }

    private func metricTitle(_ metric: BarMetric) -> String {
        guard settings.appLanguage == .english else { return metric.title }
        switch metric {
        case .battery:
            return "Battery"
        case .solar:
            return "PV"
        case .home:
            return "Home Load"
        case .grid:
            return "Grid Import"
        case .batteryFlow:
            return "Battery Flow"
        case .flow:
            return "Energy Flow"
        case .today:
            return "Today's Yield"
        case .total:
            return "Total Yield"
        case .status:
            return "Status"
        }
    }

    private func metricShortTitle(_ metric: BarMetric) -> String {
        guard settings.appLanguage == .english else { return metric.shortTitle }
        switch metric {
        case .battery:
            return "Batt"
        case .solar:
            return "PV"
        case .home:
            return "Load"
        case .grid:
            return "Grid"
        case .batteryFlow:
            return "Flow"
        case .flow:
            return "Flow"
        case .today:
            return "Yield"
        case .total:
            return "Total"
        case .status:
            return "Status"
        }
    }

    private func barAttributedText(for snapshot: SolixSnapshot, scale: Double) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let metrics = visibleBarMetrics(for: snapshot)
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
                let image = coloredSymbol(
                    symbol(for: metric, snapshot: snapshot),
                    color: (metric == .battery || settings.showEnergyFlowArrows)
                        ? color(for: metric, snapshot: snapshot)
                        : .labelColor,
                    accessibilityDescription: metricTitle(metric)
                ) {
                result.append(imageAttachment(image, scale: scale))
                result.append(textAttachment(" ", scale: scale))
            }
            result.append(textAttachment(barText(for: metric, snapshot: snapshot), color: valueColor(for: metric, snapshot: snapshot), scale: scale))
        }
        return result
    }

    private func visibleBarMetrics(for snapshot: SolixSnapshot) -> [BarMetric] {
        let metrics = settings.barMetrics.isEmpty ? [BarMetric.battery, .solar, .grid] : settings.barMetrics
        return metrics.filter { metric in
            metric != .total || snapshot.totalKWh != nil
        }
    }

    private func appendFlowField(to result: NSMutableAttributedString, snapshot: SolixSnapshot, scale: Double) {
        if settings.showMetricLabels {
            result.append(textAttachment("\(metricShortTitle(.flow)) ", color: .secondaryLabelColor, scale: scale))
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
            return watts > 0
                ? (LocalizedText.text("↓ Erzeugt", "↓ Producing"), solarFlowColor)
                : ("•", .systemGray)
        case .grid:
            guard let watts = snapshot.gridWatts else { return nil }
            if watts > 0 {
                return (LocalizedText.text("← Bezug", "← Import"), gridImportColor)
            }
            if watts < 0 {
                return (LocalizedText.text("→ Einspeisen", "→ Export"), gridExportColor)
            }
            return ("•", .systemGray)
        case .batteryFlow:
            guard let watts = snapshot.batteryWatts else { return nil }
            if watts > 0 {
                return (LocalizedText.text("↓ Laden", "↓ Charging"), batteryChargingColor)
            }
            if watts < 0 {
                return (LocalizedText.text("↑ Entladen", "↑ Discharging"), batteryDischargingColor)
            }
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
                    ofSize: round((string.contains("↓") || string.contains("↑") || string.contains("←") || string.contains("→")) ? 13.5 * scale : 13 * scale),
                    weight: weight
                ),
                .foregroundColor: color,
                .shadow: menuBarTextShadow
            ]
        )
    }

    private func valueColor(for metric: BarMetric, snapshot: SolixSnapshot) -> NSColor {
        if metric == .battery {
            return snapshot.batteryPercent.map(batteryColor) ?? .secondaryLabelColor
        }
        guard settings.showEnergyFlowArrows else { return .labelColor }
        switch metric {
        case .solar:
            return snapshot.solarWatts == nil ? .secondaryLabelColor : solarFlowColor
        case .home:
            return snapshot.homeWatts == nil ? .secondaryLabelColor : homeConsumptionColor
        case .grid:
            guard let watts = snapshot.gridWatts else { return .secondaryLabelColor }
            if watts > 0 { return gridImportColor }
            if watts < 0 { return gridExportColor }
            return .secondaryLabelColor
        case .batteryFlow:
            guard let watts = snapshot.batteryWatts else { return .secondaryLabelColor }
            if watts > 0 { return batteryChargingColor }
            if watts < 0 { return batteryDischargingColor }
            return .secondaryLabelColor
        default:
            return .labelColor
        }
    }

    private func productionColor(_ watts: Int) -> NSColor {
        if watts <= 0 { return .secondaryLabelColor }
        return readableSolarColor(watts)
    }

    private func readableSolarColor(_ watts: Int) -> NSColor {
        let fraction = min(1, max(0, Double(watts) / 2000.0))
        return interpolateColor(
            from: NSColor(calibratedRed: 0.82, green: 0.45, blue: 0.00, alpha: 1),
            to: NSColor(calibratedRed: 0.00, green: 0.54, blue: 0.25, alpha: 1),
            fraction: fraction
        )
    }

    private var solarFlowColor: NSColor {
        adaptiveFlowColor(
            light: (0.48, 0.22, 0.00),
            dark: (1.00, 0.82, 0.30)
        )
    }

    private var homeConsumptionColor: NSColor {
        adaptiveFlowColor(
            light: (0.00, 0.20, 0.80),
            dark: (0.40, 0.88, 1.00)
        )
    }

    private var batteryChargingColor: NSColor {
        adaptiveFlowColor(
            light: (0.00, 0.36, 0.12),
            dark: (0.42, 1.00, 0.58)
        )
    }

    private var batteryDischargingColor: NSColor {
        adaptiveFlowColor(
            light: (0.55, 0.12, 0.00),
            dark: (1.00, 0.55, 0.32)
        )
    }

    private var gridImportColor: NSColor {
        adaptiveFlowColor(
            light: (0.00, 0.20, 0.80),
            dark: (0.40, 0.88, 1.00)
        )
    }

    private var gridExportColor: NSColor {
        adaptiveFlowColor(
            light: (0.34, 0.10, 0.58),
            dark: (0.82, 0.65, 1.00)
        )
    }

    private var refreshColor: NSColor {
        adaptiveFlowColor(
            light: (0.00, 0.20, 0.80),
            dark: (0.40, 0.88, 1.00)
        )
    }

    private var batteryLowColor: NSColor {
        adaptiveFlowColor(
            light: (0.69, 0.00, 0.13),
            dark: (1.00, 0.42, 0.46)
        )
    }

    private var batteryMediumColor: NSColor {
        adaptiveFlowColor(
            light: (0.54, 0.35, 0.00),
            dark: (1.00, 0.85, 0.30)
        )
    }

    private var batteryHighColor: NSColor {
        adaptiveFlowColor(
            light: (0.00, 0.36, 0.12),
            dark: (0.42, 1.00, 0.58)
        )
    }

    private var menuBarTextShadow: NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(name: nil) { appearance in
            menuBarUsesDarkBackground(appearance)
                ? NSColor.black.withAlphaComponent(0.85)
                : NSColor.white.withAlphaComponent(0.90)
        }
        shadow.shadowBlurRadius = 1.5
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        return shadow
    }

    private func adaptiveFlowColor(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> NSColor {
        NSColor(name: nil) { appearance in
            let components = menuBarUsesDarkBackground(appearance) ? dark : light
            return NSColor(
                calibratedRed: components.0,
                green: components.1,
                blue: components.2,
                alpha: 1
            )
        }
    }

    private func storageColor(_ watts: Int) -> NSColor {
        let fraction = min(1, max(0, Double(watts) / 2000.0))
        return interpolateColor(
            from: NSColor(calibratedRed: 1.00, green: 0.65, blue: 0.03, alpha: 1),
            to: NSColor(calibratedRed: 0.00, green: 0.68, blue: 0.32, alpha: 1),
            fraction: fraction
        )
    }

    private func consumptionColor(_ watts: Int) -> NSColor {
        let fraction = min(1, max(0, Double(watts) / 2000.0))
        return interpolateColor(
            from: NSColor(calibratedRed: 1.00, green: 0.65, blue: 0.03, alpha: 1),
            to: NSColor(calibratedRed: 0.92, green: 0.08, blue: 0.12, alpha: 1),
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
        AppLogger.info("Manual refresh requested from menu.")
        refresh()
    }

    @objc private func toggleDetachedMenuBar() {
        AppLogger.info(isMenuBarDetached ? "Dock slim menu bar requested." : "Detach slim menu bar requested.")
        if isMenuBarDetached {
            dockDetachedMenuBar()
        } else {
            openDetachedMenuBar()
        }
    }

    @objc private func openSettings() {
        AppLogger.info("Settings window requested.")
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(
                onPreview: { [weak self] in
                    AppLogger.info("Settings preview applied.")
                    self?.applyCurrentSettings(refreshNow: false)
                },
                onSave: { [weak self] in
                    AppLogger.info("Settings saved.")
                    self?.applyCurrentSettings(refreshNow: true)
                },
                onReset: { [weak self] in
                    AppLogger.info("Settings reset or cancelled.")
                    self?.applyCurrentSettings(refreshNow: true)
                }
            )
        }
        settingsWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openLargeGraph() {
        AppLogger.info("Large graph window requested.")
        if largeGraphWindow == nil {
            largeGraphWindow = LargeGraphWindowController(graphProvider: { [weak self] in self?.graphSamples() ?? [] })
        }
        largeGraphWindow?.rebuild()
        largeGraphWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openDetachedDashboard() {
        AppLogger.info("Detached dashboard requested.")
        if detachedDashboardWindow == nil {
            detachedDashboardWindow = DetachedDashboardWindowController(
                snapshotProvider: { [weak self] in self?.currentSnapshot() },
                graphProvider: { [weak self] in self?.graphSamples() ?? [] },
                onRangeChange: { [weak self] in
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
                    if self?.isTerminating != true {
                        self?.settings.isDetachedMenuBarActive = false
                        AppLogger.info("Detached slim bar closed by user.")
                    }
                    self?.detachedMenuBarWindow = nil
                    self?.updateMenuBarIcon()
                    self?.updateTitle()
                    self?.rebuildMenu()
                }
            )
        }
        isMenuBarDetached = true
        settings.isDetachedMenuBarActive = true
        AppLogger.info("Detached slim bar opened.")
        updateMenuBarIcon()
        updateTitle()
        rebuildMenu()
        detachedMenuBarWindow?.showBelowMenuBar(anchor: statusButtonFrameOnScreen())
    }

    private func dockDetachedMenuBar() {
        if let detachedMenuBarWindow {
            detachedMenuBarWindow.closeFromOwner()
            return
        }
        isMenuBarDetached = false
        settings.isDetachedMenuBarActive = false
        updateMenuBarIcon()
        updateTitle()
        rebuildMenu()
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
            string: isRefreshing ? "\(refreshIndicator()) " : "● ",
            attributes: [
                .font: NSFont.systemFont(ofSize: round(12 * settings.menuBarScale), weight: .bold),
                .foregroundColor: isRefreshing ? refreshColor : (isOnline ? NSColor.systemGreen : NSColor.systemRed),
                .shadow: menuBarTextShadow
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
        scheduleRefreshTimer()
        applyAppearance()
        updateMenuBarIcon()
        clearStaleSnapshotIfNeeded()
        updateTitle()
        rebuildMenu()
        detachedMenuBarWindow?.rebuild()
        if refreshNow {
            refresh()
        }
    }

    private func applyAppearance() {
        switch settings.appearanceMode {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
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

    @objc private func showLogFile() {
        AppLogger.info("Log file requested from menu.")
        NSWorkspace.shared.activateFileViewerSelecting([AppLogger.logURL])
    }
}
