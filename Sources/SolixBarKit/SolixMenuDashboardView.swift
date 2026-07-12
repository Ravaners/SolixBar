import AppKit

@MainActor
final class SolixMenuDashboardView: NSView {
    /// Wo das Panel lebt: im Dropdown-Menü (eigener Rahmen) oder als Inhalt
    /// des abgedockten Fensters (Panel IST der Fensterrahmen; oben Platz für
    /// die Ampel-Buttons).
    enum Style {
        case menu
        case window
    }

    private let snapshot: SolixSnapshot
    private let previous: SolixSnapshot?
    private let style: Style
    private let graphProvider: () -> [SolixHistorySample]
    private let onRangeChange: () -> Void
    private let onOpenLarge: () -> Void
    private var updatedLabel: NSTextField?
    private var updatedTimer: Timer?
    private var isRebuildingForAppearance = false
    private weak var detailsContainer: NSStackView?

    init(
        snapshot: SolixSnapshot,
        previous: SolixSnapshot? = nil,
        style: Style = .menu,
        graphProvider: @escaping () -> [SolixHistorySample],
        onRangeChange: @escaping () -> Void,
        onOpenLarge: @escaping () -> Void
    ) {
        self.snapshot = snapshot
        self.previous = previous
        self.style = style
        self.graphProvider = graphProvider
        self.onRangeChange = onRangeChange
        self.onOpenLarge = onOpenLarge
        super.init(frame: NSRect(x: 0, y: 0, width: 430, height: style == .window ? 672 : 646))
        wantsLayer = true
        layer?.backgroundColor = backgroundColor.cgColor
        layer?.cornerRadius = Theme.radiusPanel
        layer?.masksToBounds = true
        // Im eigenen Fensterrahmen wirkt eine Konturlinie wie ein dunkler
        // Rand — dort traegt der Fensterschatten die Abgrenzung.
        if style == .menu {
            layer?.borderWidth = 1
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.65).cgColor
        }
        // cgColor-Auflösung dynamischer Farben folgt sonst der Prozess-
        // Default-Appearance (hell), nicht der App/Fenster-Appearance —
        // Ursache der weißen Streifen im Dark Mode.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            buildView()
        }
        // Hoehe aus den Constraints ableiten: eine geratene Festhoehe brach
        // das Layout im Menue-Kontext, sobald der Platzbedarf sich aenderte
        // (das abgedockte Fenster hatte Luft, das Dropdown nicht).
        layoutSubtreeIfNeeded()
        let fitted = fittingSize.height
        if fitted > 200 {
            setFrameSize(NSSize(width: frame.width, height: fitted))
        }
        startUpdatedTimer()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        bounds.fill()
    }

    private func buildView() {
        let title = NSTextField(labelWithString: snapshot.siteName)
        title.font = .boldSystemFont(ofSize: 18)
        title.textColor = .labelColor
        title.toolTip = LocalizedText.text("Name deiner SOLIX-Anlage.", "Name of your SOLIX system.")

        let updated = NSTextField(labelWithString: updatedText())
        updated.font = .systemFont(ofSize: 12, weight: .medium)
        updated.textColor = .secondaryLabelColor
        updated.toolTip = LocalizedText.text("Wann die Werte zuletzt aktualisiert wurden.", "When the values were last updated.")
        updatedLabel = updated

        // Demo-Modus deutlich kennzeichnen, damit niemand Beispieldaten für
        // echte Anlagenwerte hält.
        let isDemo = AppSettings.shared.dataSourceMode == .demo
            || AppSettings.shared.dataSourceMode == .demoWarnings
        let status = badge(
            isDemo ? "Demo" : (snapshot.status ?? LocalizedText.text("Unbekannt", "Unknown")),
            color: isDemo ? .systemBlue : statusColor
        )

        let batteryValue = withTrend(
            snapshot.batteryPercent.map { "\($0) %" },
            arrow: trendArrow(current: snapshot.batteryPercent, previous: previous?.batteryPercent, threshold: 1)
        ) ?? "-"
        let battery = primaryMetricPanel(
            LocalizedText.text("Akku", "Battery"),
            [batteryValue],
            "battery.100percent",
            batteryColor,
            plateColor: Theme.vivid(Theme.battery(percent: snapshot.batteryPercent))
        )
        // PV-Kachel je nach Modus: Summe, Einzelwerte ("438 · 204 W") oder
        // Summe in der Kachel plus Einzelwerte-Zeile in den Details.
        // Angedocktes Menü-Dashboard und abgedocktes Fenster haben getrennte
        // Einstellungen; der Trend-Pfeil bezieht sich immer auf die Summe.
        let pvMode = style == .window
            ? AppSettings.shared.detachedDashboardPVDisplay
            : AppSettings.shared.dashboardPVDisplay
        let pvChannels = (snapshot.pvWatts?.count ?? 0) > 1 ? snapshot.pvWatts : nil
        let solarArrow = trendArrow(current: snapshot.solarWatts, previous: previous?.solarWatts, threshold: 5)
        let solarLines = Self.solarValueLines(
            pvMode: pvMode, channels: pvChannels, totalWatts: snapshot.solarWatts, arrow: solarArrow
        )
        let solar = primaryMetricPanel(
            "Solar",
            solarLines,
            "sun.max.fill",
            solarColor,
            plateColor: Theme.vivid(.solar)
        )

        let primaryRow = NSStackView(views: [battery, solar])
        primaryRow.orientation = .horizontal
        primaryRow.spacing = 12
        primaryRow.distribution = .fillEqually

        var detailRows: [NSView] = []
        // Modus "Gesamt + Einzelwerte": Summe bleibt in der Kachel, die
        // Eingänge bekommen eine eigene Detail-Zeile.
        if pvMode == .both, let pvChannels {
            detailRows.append(compactMetricRow(
                LocalizedText.text("PV-Eingänge", "PV Inputs"),
                pvChannels.map { "\($0) W" }.joined(separator: " · "),
                "sun.max",
                Theme.vivid(.solar)
            ))
        }
        detailRows += [
            compactMetricRow(
                LocalizedText.text("Hauslast", "Home Load"),
                withTrend(snapshot.homeWatts.map { "\($0) W" }, arrow: trendArrow(current: snapshot.homeWatts, previous: previous?.homeWatts, threshold: 5)),
                "house.fill",
                Theme.vivid(.load)
            ),
            compactMetricRow(
                LocalizedText.text("Netzbezug", "Grid Import"),
                withTrend(signedWatts(snapshot.gridWatts), arrow: trendArrow(current: snapshot.gridWatts, previous: previous?.gridWatts, threshold: 5)),
                "powerplug.fill",
                gridColor
            ),
            compactMetricRow(
                LocalizedText.text("Akku-Fluss", "Battery Flow"),
                withTrend(signedWatts(snapshot.batteryWatts), arrow: trendArrow(current: snapshot.batteryWatts, previous: previous?.batteryWatts, threshold: 5)),
                "bolt.fill",
                batteryFlowColor
            ),
            compactMetricRow(LocalizedText.text("Heutiger Ertrag", "Today's Yield"), snapshot.todayKWh.map { String(format: "%.2f kWh", $0) }, "chart.bar.fill", Theme.vivid(.yieldToday))
        ]
        if let totalKWh = snapshot.totalKWh {
            detailRows.append(compactMetricRow(LocalizedText.text("Gesamtertrag", "Total Yield"), String(format: "%.1f kWh", totalKWh), "sum", Theme.vivid(.yieldTotal)))
        }
        let details = NSStackView(views: detailRows)
        details.orientation = .vertical
        details.spacing = 8
        // Kein eigener Container-Hintergrund: die Lücken zwischen den Reihen
        // zeigen den App-Hintergrund statt eines helleren Zwischentons.
        detailsContainer = details

        let graph = HistoryGraphMenuView(
            graphProvider: graphProvider,
            onRangeChange: onRangeChange,
            onOpenLarge: onOpenLarge
        )

        for view in [title, updated, status, primaryRow, details, graph] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: style == .window ? 44 : 18),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            title.trailingAnchor.constraint(lessThanOrEqualTo: status.leadingAnchor, constant: -10),

            status.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            status.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            status.heightAnchor.constraint(equalToConstant: 26),

            updated.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            updated.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            updated.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),

            primaryRow.topAnchor.constraint(equalTo: updated.bottomAnchor, constant: 16),
            primaryRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            primaryRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            primaryRow.heightAnchor.constraint(equalToConstant: 96),

            details.topAnchor.constraint(equalTo: primaryRow.bottomAnchor, constant: 12),
            details.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            details.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),

            graph.topAnchor.constraint(equalTo: details.bottomAnchor, constant: 14),
            graph.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 17),
            graph.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -17),
            graph.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
    }

    /// Kompletter Neuaufbau bei Appearance-Wechsel: einzelne Layer-Refreshes
    /// haben immer wieder eingefrorene cgColor-Reste übersehen (weiße Streifen
    /// zwischen den Reihen im Dark Mode) — neu bauen erschlägt die ganze
    /// Fehlerklasse.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        guard !isRebuildingForAppearance else { return }
        isRebuildingForAppearance = true
        defer { isRebuildingForAppearance = false }
        effectiveAppearance.performAsCurrentDrawingAppearance { [self] in
            layer?.backgroundColor = backgroundColor.cgColor
            if style == .menu {
                layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.65).cgColor
            }
            subviews.forEach { $0.removeFromSuperview() }
            buildView()
        }
        // Der Appearance-Neuaufbau passiert typischerweise beim ERSTEN
        // Einblenden im Menüfenster. Ohne erzwungenen Layout-Pass und
        // Höhen-Abgleich blieb der frisch gebaute Inhalt gelegentlich
        // kollabiert (unterster Abschnitt — der Graph — unsichtbar), bis das
        // Menü ein zweites Mal geöffnet wurde.
        layoutSubtreeIfNeeded()
        let fitted = fittingSize.height
        if fitted > 200, abs(fitted - frame.height) > 1 {
            setFrameSize(NSSize(width: frame.width, height: fitted))
        }
        needsDisplay = true
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        super.viewWillMove(toSuperview: newSuperview)
        if newSuperview == nil {
            updatedTimer?.invalidate()
            updatedTimer = nil
        }
    }

    private func startUpdatedTimer() {
        updatedTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.updatedLabel?.stringValue = self.updatedText()
                // Überfällige Daten sichtbar machen: orange ab dem doppelten
                // Aktualisierungsintervall.
                let age = Date().timeIntervalSince(self.snapshot.updatedAt)
                let staleAfter = max(120, AppSettings.shared.refreshInterval * 2)
                self.updatedLabel?.textColor = age > staleAfter ? .systemOrange : .secondaryLabelColor
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        updatedTimer = timer
    }

    private func updatedText() -> String {
        "\(LocalizedText.text("Aktualisiert", "Updated")) \(relativeUpdatedText())"
    }

    private func relativeUpdatedText() -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(snapshot.updatedAt)))
        if seconds < 60 {
            return LocalizedText.text("vor \(seconds) Sekunden", "\(seconds) seconds ago")
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return LocalizedText.text("vor \(minutes) Minuten", "\(minutes) minutes ago")
        }
        let hours = minutes / 60
        if hours < 24 {
            return LocalizedText.text("vor \(hours) Stunden", "\(hours) hours ago")
        }
        let days = hours / 24
        return LocalizedText.text("vor \(days) Tagen", "\(days) days ago")
    }

    private func primaryMetricPanel(_ title: String, _ valueLines: [String], _ symbol: String, _ color: NSColor, plateColor: NSColor) -> NSView {
        let panel = AnimatedPanelView()
        panel.toolTip = tooltip(for: title, value: valueLines.joined(separator: "  "))
        panel.wantsLayer = true
        panel.layer?.cornerRadius = Theme.radiusCard
        panel.baseColor = panelBackground(for: color, strength: 0.22)
        panel.highlightColor = panelBackground(for: color, strength: 0.30)

        // Plate mit Leuchtfarbe (vivid): die Textfarbe allein ergab im Dark
        // Mode einen kontrastarmen Kreis hinter dem Symbol.
        let iconPlate = iconPlate(symbol: symbol, color: plateColor, size: 36, pointSize: 21)
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .labelColor

        let valueLabel = FittingValueLabel()
        valueLabel.textColor = color
        valueLabel.setLines(valueLines)

        for view in [iconPlate, titleLabel, valueLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            panel.addSubview(view)
        }

        // Titel oben, Wert direkt darunter (kompaktes Stat-Tile). Ein
        // zweizeiliger PV-Wert wächst nach unten; ein einzeiliger Akku-Wert
        // steht dann auf Höhe der ersten PV-Zeile — die Titel bleiben auf
        // gleicher Höhe.
        NSLayoutConstraint.activate([
            iconPlate.centerYAnchor.constraint(equalTo: panel.centerYAnchor),
            iconPlate.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            iconPlate.widthAnchor.constraint(equalToConstant: 36),
            iconPlate.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.topAnchor.constraint(equalTo: panel.topAnchor, constant: 17),
            titleLabel.leadingAnchor.constraint(equalTo: iconPlate.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12),

            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            valueLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12)
        ])

        return panel
    }

    private func compactMetricRow(_ title: String, _ value: String?, _ symbol: String, _ color: NSColor) -> NSView {
        let row = AnimatedPanelView()
        row.toolTip = tooltip(for: title, value: value)
        row.baseColor = panelBackground(for: color, strength: 0.14)
        row.highlightColor = panelBackground(for: color, strength: 0.22)
        row.layer?.cornerRadius = Theme.radiusChip
        let icon = iconPlate(symbol: symbol, color: color, size: 30, pointSize: 17)
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        let valueLabel = NSTextField(labelWithString: value ?? "-")
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .bold)
        valueLabel.textColor = .labelColor
        valueLabel.alignment = .right

        for view in [icon, titleLabel, valueLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(view)
        }

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 38),

            icon.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalToConstant: 30),

            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 10),
            valueLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -12),
            valueLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])

        return row
    }

    private func badge(_ text: String, color: NSColor) -> NSView {
        let view = AnimatedPanelView()
        view.toolTip = LocalizedText.text("Zeigt, ob die Datenquelle online ist.", "Shows whether the data source is online.")
        view.wantsLayer = true
        view.layer?.cornerRadius = Theme.radiusChip
        view.baseColor = color.withAlphaComponent(0.18)
        view.highlightColor = color.withAlphaComponent(0.28)
        view.layer?.borderWidth = 1
        view.layer?.borderColor = color.withAlphaComponent(0.5).cgColor

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        return view
    }

    private func coloredSymbol(_ symbol: String, color: NSColor) -> NSImage? {
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else { return nil }
        let configured = image.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)) ?? image
        return configured.tinted(color)
    }

    private func iconPlate(symbol: String, color: NSColor, size: CGFloat, pointSize: CGFloat) -> NSView {
        let plate = NSView()
        plate.wantsLayer = true
        plate.layer?.cornerRadius = size / 2
        plate.layer?.backgroundColor = color.withAlphaComponent(0.18).cgColor
        plate.layer?.borderWidth = 1
        plate.layer?.borderColor = color.withAlphaComponent(0.45).cgColor

        let image = NSImageView(image: coloredSymbol(symbol, color: color, pointSize: pointSize) ?? NSImage())
        image.translatesAutoresizingMaskIntoConstraints = false
        plate.addSubview(image)

        NSLayoutConstraint.activate([
            image.centerXAnchor.constraint(equalTo: plate.centerXAnchor),
            image.centerYAnchor.constraint(equalTo: plate.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: pointSize + 3),
            image.heightAnchor.constraint(equalToConstant: pointSize + 3)
        ])
        return plate
    }

    private func coloredSymbol(_ symbol: String, color: NSColor, pointSize: CGFloat) -> NSImage? {
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else { return nil }
        let configured = image.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)) ?? image
        return configured.tinted(color)
    }

    /// Trend gegenüber dem vorherigen Messwert: ▲/▼ ab kleiner Schwelle,
    /// sonst nil (kein Rauschen anzeigen).
    private func trendArrow(current: Int?, previous: Int?, threshold: Int) -> String? {
        guard let current, let previous else { return nil }
        if current - previous >= threshold { return "▲" }
        if previous - current >= threshold { return "▼" }
        return nil
    }

    private func withTrend(_ value: String?, arrow: String?) -> String? {
        guard let value else { return nil }
        guard let arrow else { return value }
        return "\(value) \(arrow)"
    }

    /// Wertezeilen für die Solar-Kachel. Bei bis zu zwei PV-Eingängen (oder
    /// Summenanzeige) eine Zeile; ab drei Eingängen ein 2×2-Raster auf zwei
    /// Zeilen, damit die Werte nicht in einer überlangen Zeile abgeschnitten
    /// werden. Der Trend-Pfeil (bezieht sich auf die Summe) sitzt am Ende der
    /// letzten Zeile — konsistent mit den übrigen Feldern.
    nonisolated static func solarValueLines(pvMode: PVDisplayMode, channels: [Int]?, totalWatts: Int?, arrow: String?) -> [String] {
        func withArrow(_ text: String) -> String {
            guard let arrow else { return text }
            return "\(text) \(arrow)"
        }

        guard pvMode == .perInput, let channels, channels.count > 1 else {
            guard let totalWatts else { return ["-"] }
            return [withArrow("\(totalWatts) W")]
        }

        if channels.count <= 2 {
            return [withArrow(channels.map(String.init).joined(separator: " · ") + " W")]
        }

        // Drei bis vier Eingänge: obere Hälfte, untere Hälfte (Einheit + Pfeil
        // an die zweite Zeile).
        let half = (channels.count + 1) / 2
        let topLine = channels[..<half].map(String.init).joined(separator: " · ")
        let bottomLine = channels[half...].map(String.init).joined(separator: " · ")
        return [topLine, withArrow(bottomLine + " W")]
    }

    private func signedWatts(_ value: Int?) -> String? {
        guard let value else { return nil }
        return value > 0 ? "+\(value) W" : "\(value) W"
    }

    private func tooltip(for title: String, value: String?) -> String {
        let current = value ?? "-"
        if AppSettings.shared.appLanguage == .english {
            switch title {
            case "Battery":
                return "Shows the current battery charge level: \(current)."
            case "Solar":
                return "Shows how much power the solar panels are producing right now: \(current)."
            case "Home Load":
                return "Shows how much power your home is currently using: \(current)."
            case "Grid Import":
                return "Shows how much power is imported from the grid. Negative values mean export: \(current)."
            case "Battery Flow":
                return "Shows whether and how strongly the battery is charging or discharging: \(current)."
            case "Today's Yield":
                return "Shows how much solar energy was generated today: \(current)."
            case "Total Yield":
                return "Shows the total solar energy recorded so far: \(current)."
            default:
                return "\(title): \(current)."
            }
        }
        switch title {
        case "Akku":
            return "Hier wird angezeigt, wie voll der Speicher aktuell geladen ist: \(current)."
        case "Solar":
            return "Hier wird angezeigt, wie viel Leistung die Solarmodule gerade erzeugen: \(current)."
        case "Hauslast":
            return "Hier wird angezeigt, welche Leistung dein Haus gerade wirklich nutzt: \(current)."
        case "Netzbezug":
            return "Hier wird angezeigt, wie viel Leistung aus dem Netz bezogen wird. Negative Werte bedeuten Einspeisung: \(current)."
        case "Akku-Fluss":
            return "Hier wird angezeigt, ob und mit welcher Leistung der Akku lädt oder entlädt: \(current)."
        case "Heutiger Ertrag":
            return "Hier wird angezeigt, wie viel Solarenergie heute bereits erzeugt wurde: \(current)."
        case "Gesamtertrag":
            return "Hier wird angezeigt, wie viel Solarenergie insgesamt bisher erfasst wurde: \(current)."
        default:
            return "\(title): \(current)."
        }
    }

    private var backgroundColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.09, alpha: 1)
                : NSColor(calibratedRed: 0.96, green: 0.975, blue: 0.98, alpha: 1)
        }
    }

    private var panelColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.24, green: 0.25, blue: 0.26, alpha: 1)
                : NSColor(calibratedRed: 0.995, green: 0.998, blue: 1, alpha: 1)
        }
    }

    private var isDarkMode: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private var statusColor: NSColor {
        snapshot.status?.localizedCaseInsensitiveContains("offline") == true ? .systemRed : .systemGreen
    }

    private var batteryColor: NSColor {
        guard snapshot.batteryPercent != nil else { return .systemGray }
        return Theme.color(Theme.battery(percent: snapshot.batteryPercent))
    }

    private var solarColor: NSColor {
        Theme.vivid(.solar)
    }

    private var gridColor: NSColor {
        guard snapshot.gridWatts != nil else { return .systemGray }
        return Theme.vivid(Theme.grid(watts: snapshot.gridWatts))
    }

    private var batteryFlowColor: NSColor {
        guard snapshot.batteryWatts != nil else { return .systemGray }
        return Theme.vivid(Theme.batteryFlow(watts: snapshot.batteryWatts))
    }

    /// Dynamische Panel-Farbe: löst sich pro Appearance auf, statt den
    /// Build-Zeit-Zustand einzufrieren (sonst helle Pastellreihen im Dark Mode,
    /// wenn die View vor dem Einhängen ins dunkle Fenster gebaut wird).
    private func panelBackground(for color: NSColor, strength: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            var resolvedTint = color
            appearance.performAsCurrentDrawingAppearance {
                resolvedTint = color.usingColorSpace(.deviceRGB) ?? color
            }
            let base = dark
                ? NSColor(calibratedRed: 0.24, green: 0.25, blue: 0.26, alpha: 1)
                : NSColor(calibratedRed: 0.995, green: 0.998, blue: 1, alpha: 1)
            let adjusted = dark ? strength * 0.8 : strength
            return resolvedTint.withAlphaComponent(adjusted)
                .blended(withFraction: dark ? 0.72 : 0.80, of: base) ?? base
        }
    }
}
