import AppKit

@MainActor
final class SolixMenuDashboardView: NSView {
    private let snapshot: SolixSnapshot
    private let graphProvider: () -> [SolixHistorySample]
    private let onRangeChange: () -> Void
    private let onOpenLarge: () -> Void
    private var updatedLabel: NSTextField?
    private var updatedTimer: Timer?

    init(
        snapshot: SolixSnapshot,
        graphProvider: @escaping () -> [SolixHistorySample],
        onRangeChange: @escaping () -> Void,
        onOpenLarge: @escaping () -> Void
    ) {
        self.snapshot = snapshot
        self.graphProvider = graphProvider
        self.onRangeChange = onRangeChange
        self.onOpenLarge = onOpenLarge
        super.init(frame: NSRect(x: 0, y: 0, width: 430, height: 622))
        wantsLayer = true
        layer?.backgroundColor = backgroundColor.cgColor
        layer?.cornerRadius = 16
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.65).cgColor
        buildView()
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

        let status = badge(snapshot.status ?? "Online", color: statusColor)

        let battery = primaryMetricPanel(LocalizedText.text("Akku", "Battery"), snapshot.batteryPercent.map { "\($0) %" }, "battery.100percent", batteryColor)
        let solar = primaryMetricPanel("Solar", snapshot.solarWatts.map { "\($0) W" }, "sun.max.fill", solarColor)

        let primaryRow = NSStackView(views: [battery, solar])
        primaryRow.orientation = .horizontal
        primaryRow.spacing = 12
        primaryRow.distribution = .fillEqually

        var detailRows = [
            compactMetricRow(LocalizedText.text("Hauslast", "Home Load"), snapshot.homeWatts.map { "\($0) W" }, "house.fill", .systemBlue),
            compactMetricRow(LocalizedText.text("Netzbezug", "Grid Import"), signedWatts(snapshot.gridWatts), "powerplug.fill", gridColor),
            compactMetricRow(LocalizedText.text("Akku-Fluss", "Battery Flow"), signedWatts(snapshot.batteryWatts), "bolt.fill", batteryFlowColor),
            compactMetricRow(LocalizedText.text("Heutiger Ertrag", "Today's Yield"), snapshot.todayKWh.map { String(format: "%.2f kWh", $0) }, "chart.bar.fill", .systemPurple)
        ]
        if let totalKWh = snapshot.totalKWh {
            detailRows.append(compactMetricRow(LocalizedText.text("Gesamtertrag", "Total Yield"), String(format: "%.1f kWh", totalKWh), "sum", .systemIndigo))
        }
        let details = NSStackView(views: detailRows)
        details.orientation = .vertical
        details.spacing = 8
        details.wantsLayer = true
        details.layer?.cornerRadius = 13
        details.layer?.backgroundColor = panelColor.cgColor
        details.layer?.borderWidth = 1
        details.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor

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
            title.topAnchor.constraint(equalTo: topAnchor, constant: 18),
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
                self?.updatedLabel?.stringValue = self?.updatedText() ?? ""
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

    private func primaryMetricPanel(_ title: String, _ value: String?, _ symbol: String, _ color: NSColor) -> NSView {
        let panel = AnimatedPanelView()
        panel.toolTip = tooltip(for: title, value: value)
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 14
        panel.baseColor = panelBackground(for: color, strength: 0.18)
        panel.highlightColor = panelBackground(for: color, strength: 0.28)
        panel.layer?.borderWidth = 1
        panel.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor

        let iconPlate = iconPlate(symbol: symbol, color: color, size: 36, pointSize: 21)
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .labelColor

        let valueLabel = NSTextField(labelWithString: value ?? "-")
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 23, weight: .bold)
        valueLabel.textColor = color
        valueLabel.lineBreakMode = .byTruncatingTail

        for view in [iconPlate, titleLabel, valueLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            panel.addSubview(view)
        }

        NSLayoutConstraint.activate([
            iconPlate.topAnchor.constraint(equalTo: panel.topAnchor, constant: 12),
            iconPlate.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
            iconPlate.widthAnchor.constraint(equalToConstant: 36),
            iconPlate.heightAnchor.constraint(equalToConstant: 36),

            titleLabel.topAnchor.constraint(equalTo: panel.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: iconPlate.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12),

            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
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
        row.layer?.cornerRadius = 10
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
        view.layer?.cornerRadius = 12
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
        let copy = configured.copy() as? NSImage ?? configured
        copy.isTemplate = false
        copy.lockFocus()
        color.set()
        NSRect(origin: .zero, size: copy.size).fill(using: .sourceAtop)
        copy.unlockFocus()
        return copy
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
        let copy = configured.copy() as? NSImage ?? configured
        copy.isTemplate = false
        copy.lockFocus()
        color.set()
        NSRect(origin: .zero, size: copy.size).fill(using: .sourceAtop)
        copy.unlockFocus()
        return copy
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
        guard let percent = snapshot.batteryPercent else { return .systemGray }
        if percent <= 20 {
            return isDarkMode
                ? NSColor(calibratedRed: 1.00, green: 0.42, blue: 0.46, alpha: 1)
                : NSColor(calibratedRed: 0.69, green: 0.00, blue: 0.13, alpha: 1)
        }
        if percent <= 60 {
            return isDarkMode
                ? NSColor(calibratedRed: 1.00, green: 0.85, blue: 0.30, alpha: 1)
                : NSColor(calibratedRed: 0.54, green: 0.35, blue: 0.00, alpha: 1)
        }
        return isDarkMode
            ? NSColor(calibratedRed: 0.42, green: 1.00, blue: 0.58, alpha: 1)
            : NSColor(calibratedRed: 0.00, green: 0.36, blue: 0.12, alpha: 1)
    }

    private var solarColor: NSColor {
        NSColor(calibratedRed: 0.93, green: 0.66, blue: 0.08, alpha: 1)
    }

    private var gridColor: NSColor {
        guard let watts = snapshot.gridWatts else { return .systemGray }
        return watts > 0 ? .systemBlue : .systemTeal
    }

    private var batteryFlowColor: NSColor {
        guard let watts = snapshot.batteryWatts else { return .systemGray }
        return watts >= 0 ? .systemGreen : .systemOrange
    }

    private func panelBackground(for color: NSColor, strength: CGFloat) -> NSColor {
        let adjustedStrength = isDarkMode ? strength * 0.8 : strength
        return color.withAlphaComponent(adjustedStrength)
            .blended(withFraction: isDarkMode ? 0.72 : 0.80, of: panelColor) ?? panelColor
    }
}
