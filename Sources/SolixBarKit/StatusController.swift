import AppKit
import UniformTypeIdentifiers

@MainActor
final class StatusController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let settings = AppSettings.shared
    private let historyStore = SolixHistoryStore.shared
    private var timer: Timer?
    private var lastSnapshot: SolixSnapshot?
    private var previousSnapshot: SolixSnapshot?
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
    private let formatter = MenuBarFormatter()
    private var refreshAnimationTimer: Timer?
    private var refreshAnimationFrame = 0
    private let refreshFrames = ["↻", "↺"]
    private var updateCheckTimer: Timer?
    private var availableUpdate: ReleaseInfo?
    private var warningEngine = WarningEngine()

    func start() {
        settings.migrateMenuBarGridMetricIfNeeded()
        settings.migrateFlowMetricIfNeeded()
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
        if settings.isLargeGraphActive {
            AppLogger.info("Restoring detached graph window from previous session.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.openLargeGraph()
            }
        }
        scheduleRefreshTimer()
        scheduleUpdateChecks()
    }

    /// Update-Check: einmal kurz nach dem Start, danach täglich. Fehler sind
    /// still (offline/Rate-Limit) — es gibt schlicht keinen Hinweis.
    private func scheduleUpdateChecks() {
        updateCheckTimer?.invalidate()
        updateCheckTimer = nil
        guard settings.updateCheckEnabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.checkForUpdates()
        }
        let timer = Timer(timeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForUpdates()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        updateCheckTimer = timer
    }

    private func checkForUpdates() {
        guard settings.updateCheckEnabled else { return }
        Task { [weak self] in
            guard let release = try? await UpdateChecker.fetchLatestRelease() else { return }
            guard let self else { return }
            guard UpdateChecker.isNewer(release.version, than: AppVersion.short) else { return }
            AppLogger.info("Update available: \(release.version) (running \(AppVersion.short)).")
            self.availableUpdate = release
            self.rebuildMenu()
            if self.settings.lastNotifiedUpdateVersion != release.version {
                self.settings.lastNotifiedUpdateVersion = release.version
                NotificationManager.shared.post(
                    id: "solixbar.update.\(release.version)",
                    title: LocalizedText.text("SolixBar-Update verfügbar", "SolixBar update available"),
                    body: LocalizedText.text(
                        "Version \(release.version) steht auf GitHub bereit.",
                        "Version \(release.version) is available on GitHub."
                    ),
                    url: release.url
                )
            }
        }
    }

    @objc private func openUpdatePage() {
        NSWorkspace.shared.open(availableUpdate?.url ?? UpdateChecker.releasesPageURL)
    }

    /// Exportiert die History der aktuellen Datenquelle als CSV oder JSON.
    /// Formatwahl direkt im Speichern-Dialog (Popup unten im Panel).
    @objc private func exportData() {
        let panel = NSSavePanel()
        panel.title = LocalizedText.text("Daten exportieren", "Export data")
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = HistoryExporter.defaultFilename(ext: "csv")

        let formatLabel = NSTextField(labelWithString: LocalizedText.text("Format:", "Format:"))
        let formatPopup = NSPopUpButton()
        formatPopup.addItems(withTitles: ["CSV", "JSON"])
        let accessory = NSStackView(views: [formatLabel, formatPopup])
        accessory.orientation = .horizontal
        accessory.spacing = 8
        accessory.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        accessory.translatesAutoresizingMaskIntoConstraints = false
        let accessoryContainer = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 36))
        accessoryContainer.addSubview(accessory)
        NSLayoutConstraint.activate([
            accessory.centerXAnchor.constraint(equalTo: accessoryContainer.centerXAnchor),
            accessory.centerYAnchor.constraint(equalTo: accessoryContainer.centerYAnchor)
        ])
        panel.accessoryView = accessoryContainer

        @MainActor
        final class FormatSwitcher: NSObject {
            let panel: NSSavePanel
            init(panel: NSSavePanel) { self.panel = panel }
            @objc func formatChanged(_ sender: NSPopUpButton) {
                let isJSON = sender.indexOfSelectedItem == 1
                panel.allowedContentTypes = [isJSON ? .json : .commaSeparatedText]
                panel.nameFieldStringValue = HistoryExporter.defaultFilename(ext: isJSON ? "json" : "csv")
            }
        }
        let switcher = FormatSwitcher(panel: panel)
        formatPopup.target = switcher
        formatPopup.action = #selector(FormatSwitcher.formatChanged(_:))

        NSApp.activate(ignoringOtherApps: true)
        let response = panel.runModal()
        withExtendedLifetime(switcher) {}
        guard response == .OK, let url = panel.url else { return }

        let sourceKey = settings.dataSourceMode.rawValue
        let samples = historyStore.samples(duration: 366 * 24 * 60 * 60, sourceKey: sourceKey)
        let current = currentSnapshot()
        do {
            if formatPopup.indexOfSelectedItem == 1 {
                let data = try HistoryExporter.json(samples: samples, current: current, sourceKey: sourceKey)
                try data.write(to: url, options: .atomic)
            } else {
                let csv = HistoryExporter.csv(samples: samples, current: current)
                try Data(csv.utf8).write(to: url, options: .atomic)
            }
            AppLogger.info("Exported \(samples.count) samples to \(url.lastPathComponent).")
        } catch {
            AppLogger.error("Export failed: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = LocalizedText.text("Export fehlgeschlagen", "Export failed")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func evaluateWarnings(for snapshot: SolixSnapshot) {
        let events = warningEngine.evaluate(
            snapshot: snapshot,
            at: snapshot.updatedAt,
            config: settings.warningConfig()
        )
        for event in events {
            let (id, title, body) = warningText(for: event)
            AppLogger.info("Warning fired: \(id)")
            NotificationManager.shared.post(id: id, title: title, body: body)
        }
        // Aktive Warnungen erscheinen zusätzlich oben im Menü — der immer
        // funktionierende Weg, falls Mitteilungen nicht erlaubt wurden.
        if !events.isEmpty {
            rebuildMenu()
        }
    }

    private func warningText(for event: WarningEngine.Event) -> (id: String, title: String, body: String) {
        switch event {
        case .batteryLow(let percent):
            return (
                "solixbar.warning.battery-low",
                LocalizedText.text("Akku niedrig", "Battery low"),
                LocalizedText.text(
                    "Der Akku ist auf \(percent) % gefallen.",
                    "The battery has dropped to \(percent)%."
                )
            )
        case .pvStalled:
            return (
                "solixbar.warning.pv-stalled",
                LocalizedText.text("PV liefert nichts", "PV not generating"),
                LocalizedText.text(
                    "Die Solarmodule liefern seit längerem keine Leistung.",
                    "The solar panels have not produced any power for a while."
                )
            )
        case .pvChannelDead(let index):
            return (
                "solixbar.warning.pv-channel-\(index)",
                LocalizedText.text("PV-Eingang \(index + 1) liefert nichts", "PV input \(index + 1) not generating"),
                LocalizedText.text(
                    "Eingang \(index + 1) liefert 0 W, während die anderen Eingänge erzeugen.",
                    "Input \(index + 1) is at 0 W while the other inputs are producing."
                )
            )
        }
    }

    func prepareForTermination() {
        isTerminating = true
        settings.isDetachedMenuBarActive = isMenuBarDetached
        settings.isLargeGraphActive = largeGraphWindow != nil
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
                // Vorwert für Trend-Pfeile im Dashboard (nur bei gleicher Quelle).
                previousSnapshot = (lastSnapshotMode == settings.dataSourceMode) ? lastSnapshot : nil
                lastSnapshot = snapshot
                lastSnapshotMode = settings.dataSourceMode
                lastError = nil
                historyStore.record(
                    snapshot,
                    sourceKey: settings.dataSourceMode.rawValue,
                    refreshInterval: settings.refreshInterval
                )
                AppLogger.info("Refresh succeeded: battery=\(snapshot.batteryPercent.map(String.init) ?? "-")%, solar=\(snapshot.solarWatts.map(String.init) ?? "-")W, grid=\(snapshot.gridWatts.map(String.init) ?? "-")W.")
                evaluateWarnings(for: snapshot)
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
        // Animation nur beim Erststart ohne Werte — danach bleibt die
        // Anzeige während des Refreshs unangetastet.
        guard currentSnapshot() == nil else { return }
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
            // Laufende Anzeige nicht verdrängen (kein Breiten-Zucken alle
            // 5 Minuten); Lade-Feedback nur, solange noch keine Werte da sind.
            if currentSnapshot() == nil {
                setStatusAttributedTitle(refreshStatusAttributedTitle(scale: settings.menuBarScale))
            }
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
            showArrows: settings.showEnergyFlowArrows,
            showColors: settings.showFlowColors
        )
    }

    private var detachedDisplayOptions: MenuBarDisplayOptions {
        MenuBarDisplayOptions(
            metrics: settings.detachedBarMetrics,
            showLabels: settings.detachedShowLabels,
            showSymbols: settings.detachedShowSymbols,
            showArrows: settings.detachedShowArrows,
            showColors: settings.detachedShowFlowColors
        )
    }

    private func applyTitle(for snapshot: SolixSnapshot, level: MenuBarDisplayLevel) {
        let options = settingsDisplayOptions.applying(level)

        if settings.menuBarStacked {
            let entries = formatter.stackedEntries(for: snapshot, options: options)
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

        if options.showSymbols || options.showArrows || options.showColors {
            setStatusAttributedTitle(formatter.attributedTitle(
                for: snapshot,
                scale: settings.menuBarScale,
                options: options,
                showWarning: lastError != nil
            ))
        } else {
            let battery = snapshot.batteryPercent.map { "\($0)%" } ?? "--%"
            let title = (formatter.plainTitle(for: snapshot, options: options) ?? battery) + warn
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

        if !warningEngine.activeEvents.isEmpty {
            menu.addItem(NSMenuItem.separator())
            for event in warningEngine.activeEvents {
                let text = warningText(for: event)
                menu.addItem(value(
                    LocalizedText.text("Warnung", "Warning"),
                    text.title,
                    symbol: "exclamationmark.triangle.fill",
                    color: .systemOrange
                ))
            }
        }

        if let update = availableUpdate {
            menu.addItem(NSMenuItem.separator())
            menu.addItem(action(
                LocalizedText.text("Update verfügbar (\(update.version))", "Update available (\(update.version))"),
                #selector(openUpdatePage),
                "arrow.down.circle.fill"
            ))
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(action(LocalizedText.text("Aktualisieren", "Refresh"), #selector(refreshMenuAction), "arrow.clockwise"))
        menu.addItem(action(
            isMenuBarDetached
                ? LocalizedText.text("Abgedockte Leiste ausblenden", "Hide detached bar")
                : LocalizedText.text("Abgedockte Leiste anzeigen", "Show detached bar"),
            #selector(toggleDetachedMenuBar),
            "menubar.rectangle"
        ))
        menu.addItem(action(LocalizedText.text("Dashboard abdocken", "Detach dashboard"), #selector(openDetachedDashboard), "macwindow.on.rectangle"))
        menu.addItem(action(
            largeGraphWindow == nil
                ? LocalizedText.text("Verlauf abdocken", "Detach history graph")
                : LocalizedText.text("Verlaufsfenster schließen", "Close history window"),
            #selector(toggleLargeGraph),
            "chart.xyaxis.line"
        ))
        menu.addItem(action(LocalizedText.text("Daten exportieren ...", "Export data ..."), #selector(exportData), "square.and.arrow.up"))
        menu.addItem(action(LocalizedText.text("Einstellungen ...", "Settings ..."), #selector(openSettings), "gearshape"))
        menu.addItem(action(LocalizedText.text("Logdatei anzeigen", "Show log file"), #selector(showLogFile), "doc.text.magnifyingglass"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(versionItem())
        menu.addItem(action(LocalizedText.text("Beenden", "Quit"), #selector(quit), "power"))
        // NSMenus folgen NSApp.appearance nicht automatisch: Bei erzwungenem
        // Hell/Dunkel muss das Menü die Appearance explizit erben, sonst
        // bleibt das Dropdown im Systemlook.
        menu.appearance = settings.appearanceMode == .system ? nil : NSApp.appearance
        item.menu = menu
    }

    private func dashboardItem(_ snapshot: SolixSnapshot) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = SolixMenuDashboardView(
            snapshot: snapshot,
            previous: previousSnapshot,
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
        item.image = formatter.coloredSymbol(symbol, color: color, accessibilityDescription: label)
        return item
    }

    private func metricValue(_ metric: BarMetric, _ text: String?, snapshot: SolixSnapshot, label: String? = nil) -> NSMenuItem {
        value(label ?? metric.localizedTitle, text, symbol: formatter.symbol(for: metric, snapshot: snapshot), color: formatter.color(for: metric, snapshot: snapshot))
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
        settings.showMenuBarIcon
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
                .foregroundColor: Theme.color(.refresh),
                .shadow: formatter.textShadow
            ]
        )
    }

    private func refreshStatusAttributedTitle(scale: Double) -> NSAttributedString {
        NSAttributedString(
            string: "\(refreshIndicator()) \(LocalizedText.text("Aktualisiert ...", "Refreshing ..."))",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: round(13 * scale), weight: .bold),
                .foregroundColor: Theme.color(.refresh),
                .shadow: formatter.textShadow
            ]
        )
    }

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
            largeGraphWindow = LargeGraphWindowController(
                graphProvider: { [weak self] in self?.graphSamples() ?? [] },
                onClose: { [weak self] in
                    guard let self, !self.isTerminating, self.largeGraphWindow != nil else { return }
                    self.largeGraphWindow = nil
                    self.settings.isLargeGraphActive = false
                    self.rebuildMenu()
                }
            )
        }
        settings.isLargeGraphActive = true
        largeGraphWindow?.rebuild()
        largeGraphWindow?.showWindow(nil)
        rebuildMenu()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleLargeGraph() {
        if let open = largeGraphWindow {
            open.close()
        } else {
            openLargeGraph()
        }
    }

    @objc private func openDetachedDashboard() {
        AppLogger.info("Detached dashboard requested.")
        if detachedDashboardWindow == nil {
            detachedDashboardWindow = DetachedDashboardWindowController(
                snapshotProvider: { [weak self] in self?.currentSnapshot() },
                previousProvider: { [weak self] in self?.previousSnapshot },
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
                    return self.formatter.attributedTitle(
                        for: snapshot,
                        scale: self.settings.detachedMenuBarScale,
                        options: self.detachedDisplayOptions
                    )
                },
                stackedImageProvider: { [weak self] in
                    guard let self, self.settings.detachedBarStacked,
                          let snapshot = self.currentSnapshot() else { return nil }
                    let entries = self.formatter.stackedEntries(for: snapshot, options: self.detachedDisplayOptions)
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
            String(settings.showFlowColors),
            String(settings.showMenuBarIcon),
            String(settings.menuBarStacked),
            String(settings.menuBarScale)
        ].joined(separator: "|")
        if signature != lastDisplaySignature {
            lastDisplaySignature = signature
            displayLevel = .full
        }
        scheduleRefreshTimer()
        scheduleUpdateChecks()
        applyAppearance()
        updateMenuBarIcon()
        clearStaleSnapshotIfNeeded()
        updateTitle()
        rebuildMenu()
        detachedMenuBarWindow?.rebuild()
        detachedDashboardWindow?.rebuild()
        largeGraphWindow?.applyWindowLevel()
        largeGraphWindow?.rebuild()
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
