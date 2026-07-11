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
    private var detachedDashboardWindow: DetachedDashboardWindowController?
    private var detachedMenuBarWindow: DetachedMenuBarWindowController?
    private var isMenuBarDetached = false
    private var isTerminating = false
    private var isRefreshing = false
    private var displayLevel: MenuBarDisplayLevel = .full
    private var lastDisplaySignature = ""
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
        logMenuBarDiagnostics()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(systemAppearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
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
            return DemoSolixDataProvider()
        case .command:
            // Passwort kommt aus dem Schlüsselbund und wird nur als
            // Umgebungsvariable an den Befehl übergeben, nie auf Platte.
            var environment: [String: String] = [:]
            let stored = SolixEnvFile.read(from: SolixPaths.envFileURL)
            if let user = stored["ANKER_SOLIX_USER"],
               let password = KeychainStore.password(account: user),
               !password.isEmpty {
                environment["ANKER_SOLIX_PASSWORD"] = password
            }
            return CommandSolixDataProvider(command: settings.command, extraEnvironment: environment)
        case .url:
            return URLSolixDataProvider(urlString: settings.urlString)
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
                historyStore.record(
                    snapshot,
                    sourceKey: settings.dataSourceMode.rawValue,
                    refreshInterval: settings.refreshInterval
                )
                AppLogger.info("Refresh succeeded: battery=\(snapshot.batteryPercent.map(String.init) ?? "-")%, solar=\(snapshot.solarWatts.map(String.init) ?? "-")W, grid=\(snapshot.gridWatts.map(String.init) ?? "-")W.")
            } catch {
                // Letzten gültigen Snapshot behalten: ein transienter Fehler
                // soll die Anzeige nicht leeren, nur als veraltet markieren.
                lastError = error.localizedDescription
                AppLogger.error("Refresh failed (keeping last snapshot): \(Self.describeError(error))")
            }
            updateTitle()
            rebuildMenu()
            detachedDashboardWindow?.rebuild()
            detachedMenuBarWindow?.rebuild()
            largeGraphWindow?.rebuild()
        }
    }

    /// DecodingError & Co. mit vollem Kontext ins Log — die blosse
    /// localizedDescription ("Die Daten konnten nicht gelesen werden") ist
    /// für die Fehlersuche wertlos.
    private static func describeError(_ error: Error) -> String {
        if let decoding = error as? DecodingError {
            return "DecodingError: \(decoding)"
        }
        if let urlError = error as? URLError {
            return "URLError \(urlError.code.rawValue): \(urlError.localizedDescription)"
        }
        return error.localizedDescription
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

    private func stackedEntries(for snapshot: SolixSnapshot, options: MenuBarDisplayOptions) -> [StackedMenuBarRenderer.Entry] {
        visibleBarMetrics(for: snapshot, options: options)
            .filter { $0 != .flow && $0 != .status }
            .compactMap { metric -> StackedMenuBarRenderer.Entry? in
                guard let text = stackedText(for: metric, snapshot: snapshot) else { return nil }
                return StackedMenuBarRenderer.Entry(
                    symbolName: symbol(for: metric, snapshot: snapshot),
                    text: text,
                    role: roleTag(for: metric, snapshot: snapshot)
                )
            }
    }

    /// Kompaktwert für die zweizeilige Anzeige: nur Zahl + Einheit, die
    /// Metrik-Identität trägt das Glyph.
    private func stackedText(for metric: BarMetric, snapshot: SolixSnapshot) -> String? {
        switch metric {
        case .battery:
            return snapshot.batteryPercent.map { "\($0)%" } ?? "--%"
        case .solar:
            return snapshot.solarWatts.map { "\($0)W" } ?? "--W"
        case .home:
            return snapshot.homeWatts.map { "\($0)W" } ?? "--W"
        case .grid:
            return snapshot.gridWatts.map { "\($0)W" } ?? "--W"
        case .batteryFlow:
            return snapshot.batteryWatts.map { "\($0 > 0 ? "+" : "")\($0)W" } ?? "--W"
        case .today:
            return snapshot.todayKWh.map { String(format: "%.1fk", $0) }
        case .total:
            return snapshot.totalKWh.map { String(format: "%.0fk", $0) }
        case .flow, .status:
            return nil
        }
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

        applyTitle(for: snapshot, level: displayLevel)
        enforceNotchFit(with: snapshot)
    }

    private var settingsDisplayOptions: MenuBarDisplayOptions {
        MenuBarDisplayOptions(
            metrics: settings.barMetrics,
            showLabels: settings.showMetricLabels,
            showSymbols: settings.showMenuBarMetricSymbols,
            showArrows: settings.showEnergyFlowArrows
        )
    }

    private var detachedDisplayOptions: MenuBarDisplayOptions {
        MenuBarDisplayOptions(
            metrics: settings.detachedBarMetrics,
            showLabels: settings.detachedShowLabels,
            showSymbols: settings.detachedShowSymbols,
            showArrows: settings.detachedShowArrows
        )
    }

    private func applyTitle(for snapshot: SolixSnapshot, level: MenuBarDisplayLevel) {
        let options = settingsDisplayOptions.applying(level)

        if settings.menuBarStacked {
            let entries = stackedEntries(for: snapshot, options: options)
            if entries.count >= 2,
               let image = StackedMenuBarRenderer.image(
                   entries: entries,
                   scale: settings.menuBarScale,
                   showWarning: lastError != nil
               ) {
                item.button?.image = image
                item.button?.imagePosition = .imageOnly
                item.button?.attributedTitle = NSAttributedString()
                return
            }
        }
        // Normale einzeilige Darstellung: Icon-Zustand wiederherstellen,
        // falls zuvor das gestapelte Bild aktiv war.
        updateMenuBarIcon()
        let warn = lastError == nil ? "" : " ⚠"

        if options.metrics.isEmpty {
            let battery = snapshot.batteryPercent.map { "\($0)%" } ?? "SOLIX"
            setStatusTitle(battery + warn)
            return
        }

        if options.showSymbols || options.showArrows || options.metrics.contains(.flow) {
            let text = NSMutableAttributedString(
                attributedString: barAttributedText(for: snapshot, scale: settings.menuBarScale, options: options)
            )
            if !warn.isEmpty {
                text.append(textAttachment(warn, color: Theme.color(.batteryMedium), scale: settings.menuBarScale))
            }
            setStatusAttributedTitle(text)
        } else {
            let battery = snapshot.batteryPercent.map { "\($0)%" } ?? "--%"
            let parts = visibleBarMetrics(for: snapshot, options: options).map { metric in
                barText(for: metric, snapshot: snapshot, options: options)
            }
            let title = (parts.isEmpty ? battery : parts.joined(separator: separator())) + warn
            setStatusTitle(title)
        }
    }

    /// Prüft nach dem Layout, ob das Item in die Notch-Zone ragt, und
    /// verdichtet die Anzeige stufenweise, bis es passt. macOS würde ein
    /// überlappendes Item sonst komplett ausblenden.
    private func enforceNotchFit(with snapshot: SolixSnapshot, attempt: Int = 0) {
        // Kurze Verzögerung: die Menüleiste positioniert das Item erst nach
        // dem Setzen des Titels neu; ein sofortiger Check sähe veraltete Frames.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            guard let self else { return }
            let screen = self.item.button?.window?.screen ?? NSScreen.main
            guard let notch = NotchGeometry.notchRect(on: screen) else { return }

            let frame = self.statusButtonFrameOnScreen()
            let isUsable = frame.map { $0.width > 1 && $0.minX > 1 } ?? false
            guard let frame, isUsable else {
                // Kein brauchbarer Frame: entweder ist das Layout noch nicht
                // fertig (kurz erneut versuchen) oder macOS hat das Item
                // bereits hinter der Notch versteckt — dann hilft nur
                // Verdichten, sonst bleibt die Anzeige dauerhaft unsichtbar.
                if attempt < 4 {
                    self.enforceNotchFit(with: snapshot, attempt: attempt + 1)
                } else if let next = self.displayLevel.next {
                    AppLogger.info("Status item frame unusable (likely hidden behind the notch): degrading to level \(next.rawValue).")
                    self.displayLevel = next
                    self.applyTitle(for: snapshot, level: next)
                    self.enforceNotchFit(with: snapshot)
                }
                return
            }

            guard NotchGeometry.overlaps(
                itemMinX: frame.minX,
                itemMaxX: frame.maxX,
                notchMinX: notch.minX,
                notchMaxX: notch.maxX
            ) else { return }
            guard let next = self.displayLevel.next else { return }
            AppLogger.info(
                "Menu bar item overlaps notch (item \(Int(frame.minX))-\(Int(frame.maxX)), notch \(Int(notch.minX))-\(Int(notch.maxX))): degrading to level \(next.rawValue)."
            )
            self.displayLevel = next
            self.applyTitle(for: snapshot, level: next)
            self.enforceNotchFit(with: snapshot)
        }
    }

    private func logMenuBarDiagnostics() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, let frame = self.statusButtonFrameOnScreen() else { return }
            if let notch = NotchGeometry.notchRect(on: self.item.button?.window?.screen) {
                AppLogger.info(
                    "Menu bar item at x=\(Int(frame.minX))-\(Int(frame.maxX)) (width \(Int(frame.width))), notch zone \(Int(notch.minX))-\(Int(notch.maxX))."
                )
            } else {
                AppLogger.info("Menu bar item at x=\(Int(frame.minX))-\(Int(frame.maxX)) (width \(Int(frame.width))), no notch.")
            }
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
        // Demo-Modus: immer eine synthetische Kurve über die volle gewählte
        // Spanne — der Verlauf enthält sonst nur die seit Erstnutzung
        // aufgezeichneten Minuten und lange Zeiträume blieben leer.
        if settings.dataSourceMode == .demo {
            return demoGraphSamples(duration: settings.historyDuration)
        }
        return historyStore.samples(
            duration: settings.historyDuration,
            sourceKey: settings.dataSourceMode.rawValue
        )
    }

    private func demoGraphSamples(duration: TimeInterval) -> [SolixHistorySample] {
        let now = Date()
        let days = max(1.0, duration / 86_400)
        let count = min(240, max(48, Int(days * 24)))
        return (0..<count).map { index in
            let progress = Double(index) / Double(count - 1)
            // Tageszyklen: Sonne folgt dem Tagesrhythmus über die ganze Spanne.
            let dayPhase = (progress * days).truncatingRemainder(dividingBy: 1)
            let sunlight = max(0, sin(dayPhase * .pi))
            let seasonal = 0.75 + 0.25 * sin(progress * .pi * 2)
            let wave = sin(progress * .pi * 2.4)
            return SolixHistorySample(
                date: now.addingTimeInterval(-duration * (1 - progress)),
                batteryPercent: min(100, max(15, 58 + Int(progress * 22) + Int(wave * 12))),
                solarWatts: Int(720 * sunlight * seasonal),
                gridWatts: Int(max(0, 220 - (720 * sunlight * seasonal * 0.45)))
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
        return configured.tinted(color)
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

    /// Template-Glyph statt herunterskaliertem App-Icon: Das 1,5-MB-PNG war bei
    /// 18 px nur noch ein Farbfleck, wurde bei jedem Menu-Rebuild neu von Platte
    /// geladen und verstiess als Vollfarbbild an der HIG für Statusitems.
    private func menuBarIcon() -> NSImage? {
        guard let image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "SOLIX") else {
            return nil
        }
        let configuration = NSImage.SymbolConfiguration(
            pointSize: round(13 * settings.menuBarScale),
            weight: .semibold
        )
        let configured = image.withSymbolConfiguration(configuration) ?? image
        configured.isTemplate = true
        return configured
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
        Theme.color(roleTag(for: metric, snapshot: snapshot))
    }

    private func roleTag(for metric: BarMetric, snapshot: SolixSnapshot) -> ColorRole {
        switch metric {
        case .battery:
            Theme.battery(percent: snapshot.batteryPercent)
        case .solar:
            .solar
        case .home:
            .load
        case .grid:
            Theme.grid(watts: snapshot.gridWatts)
        case .batteryFlow:
            Theme.batteryFlow(watts: snapshot.batteryWatts)
        case .flow:
            .batteryCharging
        case .today:
            .yieldToday
        case .total:
            .yieldTotal
        case .status:
            .status
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

    private func formatFlowWatts(_ value: Int?, options: MenuBarDisplayOptions) -> String? {
        guard let value else { return nil }
        return options.showArrows ? "\(abs(value)) W" : formatSignedWatts(value)
    }

    private func barText(for metric: BarMetric, snapshot: SolixSnapshot, options: MenuBarDisplayOptions) -> String {
        switch metric {
        case .battery:
            formatBarMetric(metric, value: snapshot.batteryPercent.map { "\($0)%" } ?? "--%", options: options)
        case .solar:
            formatBarMetric(metric, value: snapshot.solarWatts.map { "\($0)W" } ?? "--W", options: options)
        case .home:
            formatBarMetric(metric, value: snapshot.homeWatts.map { "\($0)W" } ?? "--W", options: options)
        case .grid:
            formatBarMetric(metric, value: formatFlowWatts(snapshot.gridWatts, options: options) ?? "--W", options: options)
        case .batteryFlow:
            formatBarMetric(metric, value: formatFlowWatts(snapshot.batteryWatts, options: options) ?? "--W", options: options)
        case .flow:
            options.showLabels ? "\(metricShortTitle(metric))" : "Flow"
        case .today:
            formatBarMetric(metric, value: snapshot.todayKWh.map { String(format: "%.2fkWh", $0) } ?? "--kWh", options: options)
        case .total:
            formatBarMetric(metric, value: snapshot.totalKWh.map { String(format: "%.1fkWh", $0) } ?? "--kWh", options: options)
        case .status:
            formatBarMetric(metric, value: snapshot.status ?? "-", options: options)
        }
    }

    private func formatBarMetric(_ metric: BarMetric, value: String, options: MenuBarDisplayOptions) -> String {
        options.showLabels ? "\(metricShortTitle(metric)) \(value)" : value
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

    private func barAttributedText(for snapshot: SolixSnapshot, scale: Double, options: MenuBarDisplayOptions) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let metrics = visibleBarMetrics(for: snapshot, options: options)
        for (index, metric) in metrics.enumerated() {
            let role = roleTag(for: metric, snapshot: snapshot)
            if index > 0 {
                result.append(textAttachment(separator(scale: scale), scale: scale))
            }
            if metric == .flow {
                appendFlowField(to: result, snapshot: snapshot, scale: scale, options: options)
                continue
            }
            if options.showArrows,
               let flow = energyFlowText(for: metric, snapshot: snapshot) {
                result.append(textAttachment(flow.text, color: Theme.color(flow.role), weight: .bold, scale: scale, role: flow.role))
                result.append(textAttachment(" ", scale: scale))
            }
            if options.showSymbols,
                let image = coloredSymbol(
                    symbol(for: metric, snapshot: snapshot),
                    color: (metric == .battery || options.showArrows)
                        ? color(for: metric, snapshot: snapshot)
                        : .labelColor,
                    accessibilityDescription: metricTitle(metric)
                ) {
                result.append(imageAttachment(image, scale: scale, role: role))
                result.append(textAttachment(" ", scale: scale))
            }
            result.append(textAttachment(
                barText(for: metric, snapshot: snapshot, options: options),
                color: valueColor(for: metric, snapshot: snapshot, options: options),
                scale: scale,
                role: role
            ))
        }
        return result
    }

    private func visibleBarMetrics(for snapshot: SolixSnapshot, options: MenuBarDisplayOptions) -> [BarMetric] {
        let metrics = options.metrics.isEmpty ? [BarMetric.battery, .solar, .grid] : options.metrics
        return metrics.filter { metric in
            metric != .total || snapshot.totalKWh != nil
        }
    }

    private func appendFlowField(to result: NSMutableAttributedString, snapshot: SolixSnapshot, scale: Double, options: MenuBarDisplayOptions) {
        if options.showLabels {
            result.append(textAttachment("\(metricShortTitle(.flow)) ", color: .secondaryLabelColor, scale: scale))
        }

        guard options.showArrows else {
            result.append(textAttachment(LocalizedText.text("aus", "off"), color: .secondaryLabelColor, scale: scale))
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
            result.append(textAttachment(flow.text, color: Theme.color(flow.role), weight: .bold, scale: scale, role: flow.role))
            didAppend = true
        }

        if !didAppend {
            result.append(textAttachment("-", color: .secondaryLabelColor, scale: scale))
        }
    }

    private func energyFlowText(for metric: BarMetric, snapshot: SolixSnapshot) -> (text: String, role: ColorRole)? {
        switch metric {
        case .solar:
            guard let watts = snapshot.solarWatts else { return nil }
            return watts > 0
                ? (LocalizedText.text("↓ Erzeugt", "↓ Producing"), .solar)
                : ("•", .neutral)
        case .grid:
            guard let watts = snapshot.gridWatts else { return nil }
            if watts > 0 {
                return (LocalizedText.text("← Bezug", "← Import"), .gridImport)
            }
            if watts < 0 {
                return (LocalizedText.text("→ Einspeisen", "→ Export"), .gridExport)
            }
            return ("•", .neutral)
        case .batteryFlow:
            guard let watts = snapshot.batteryWatts else { return nil }
            if watts > 0 {
                return (LocalizedText.text("↓ Laden", "↓ Charging"), .batteryCharging)
            }
            if watts < 0 {
                return (LocalizedText.text("↑ Entladen", "↑ Discharging"), .batteryDischarging)
            }
            return ("•", .neutral)
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

    private func imageAttachment(_ image: NSImage, scale: Double, role: ColorRole? = nil) -> NSAttributedString {
        let attachment = NSTextAttachment()
        let height = round(13 * scale)
        // Seitenverhältnis erhalten: breite Symbole (Batterie) nicht ins
        // Quadrat stauchen.
        let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
        let width = round(height * aspect)
        image.size = NSSize(width: width, height: height)
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: -2, width: width, height: height)
        let result = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
        if let role {
            result.addAttribute(.solixRole, value: role.rawValue, range: NSRange(location: 0, length: result.length))
        }
        return result
    }

    private func textAttachment(_ string: String, color: NSColor = .labelColor, weight: NSFont.Weight = .medium, scale: Double, role: ColorRole? = nil) -> NSAttributedString {
        // Einheitliche Schriftgröße für alle Läufe — die frühere 13,5-pt-
        // Sonderbehandlung der Pfeiltexte erzeugte sichtbar gemischte Größen.
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: round(13 * scale), weight: weight),
            .foregroundColor: color,
            .shadow: menuBarTextShadow
        ]
        if let role {
            attributes[.solixRole] = role.rawValue
        }
        return NSAttributedString(string: string, attributes: attributes)
    }

    private func valueColor(for metric: BarMetric, snapshot: SolixSnapshot, options: MenuBarDisplayOptions) -> NSColor {
        if metric == .battery {
            return snapshot.batteryPercent.map(batteryColor) ?? .secondaryLabelColor
        }
        guard options.showArrows else { return .labelColor }
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

    private var solarFlowColor: NSColor { Theme.color(.solar) }
    private var homeConsumptionColor: NSColor { Theme.color(.load) }
    private var batteryChargingColor: NSColor { Theme.color(.batteryCharging) }
    private var batteryDischargingColor: NSColor { Theme.color(.batteryDischarging) }
    private var gridImportColor: NSColor { Theme.color(.gridImport) }
    private var gridExportColor: NSColor { Theme.color(.gridExport) }
    private var refreshColor: NSColor { Theme.color(.refresh) }
    private var batteryLowColor: NSColor { Theme.color(.batteryLow) }
    private var batteryMediumColor: NSColor { Theme.color(.batteryMedium) }
    private var batteryHighColor: NSColor { Theme.color(.batteryHigh) }

    private var menuBarTextShadow: NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(name: nil) { appearance in
            Theme.usesDarkBackground(appearance)
                ? NSColor.black.withAlphaComponent(0.85)
                : NSColor.white.withAlphaComponent(0.90)
        }
        shadow.shadowBlurRadius = 1.5
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        return shadow
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

    /// Systemweiter Hell/Dunkel-Wechsel: Menü-Dashboard und Fenster neu
    /// aufbauen, damit keine Ansicht mit alten Farben hängen bleibt.
    @objc private func systemAppearanceChanged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            AppLogger.info("System appearance changed: rebuilding views.")
            self.updateTitle()
            self.rebuildMenu()
            self.detachedDashboardWindow?.rebuild()
            self.detachedMenuBarWindow?.rebuild()
            self.largeGraphWindow?.rebuild()
        }
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
                    return self.barAttributedText(
                        for: snapshot,
                        scale: self.settings.detachedMenuBarScale,
                        options: self.detachedDisplayOptions
                    )
                },
                stackedImageProvider: { [weak self] in
                    guard let self, self.settings.detachedBarStacked,
                          let snapshot = self.currentSnapshot() else { return nil }
                    let entries = self.stackedEntries(for: snapshot, options: self.detachedDisplayOptions)
                    guard entries.count >= 2 else { return nil }
                    return StackedMenuBarRenderer.image(
                        entries: entries,
                        scale: self.settings.detachedMenuBarScale * 1.3,
                        showWarning: self.lastError != nil,
                        brightPalette: true,
                        height: round(30 * self.settings.detachedMenuBarScale)
                    )
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
        // Verdichtungsstufe nur zurücksetzen, wenn sich anzeige-relevante
        // Optionen geändert haben. Sonst blendet z. B. das Umschalten von
        // "Leiste fixieren" das Item kurz in voller Breite ein, macOS
        // versteckt es hinter der Notch, und die Anzeige verschwindet.
        let signature = [
            settings.barMetrics.map(\.rawValue).joined(separator: ","),
            String(settings.showMetricLabels),
            String(settings.showMenuBarMetricSymbols),
            String(settings.showEnergyFlowArrows),
            String(settings.showMenuBarIcon),
            String(settings.menuBarStacked),
            String(settings.menuBarScale)
        ].joined(separator: "|")
        if signature != lastDisplaySignature {
            lastDisplaySignature = signature
            displayLevel = .full
        }
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
