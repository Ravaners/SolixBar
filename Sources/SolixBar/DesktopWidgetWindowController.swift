import AppKit

@MainActor
final class DesktopWidgetWindowController: NSWindowController {
    private let snapshotProvider: () -> SolixSnapshot?
    private let graphProvider: () -> [SolixHistorySample]

    init(snapshotProvider: @escaping () -> SolixSnapshot?, graphProvider: @escaping () -> [SolixHistorySample]) {
        self.snapshotProvider = snapshotProvider
        self.graphProvider = graphProvider
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 520),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "SOLIX Widget"
        window.minSize = NSSize(width: 360, height: 460)
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.center()
        super.init(window: window)
        rebuild()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func rebuild() {
        window?.contentView = DesktopWidgetView(snapshot: snapshotProvider(), samples: graphProvider())
    }
}

final class DesktopWidgetView: NSView {
    private let snapshot: SolixSnapshot?
    private let samples: [SolixHistorySample]

    init(snapshot: SolixSnapshot?, samples: [SolixHistorySample]) {
        self.snapshot = snapshot
        self.samples = samples
        super.init(frame: NSRect(x: 0, y: 0, width: 390, height: 520))
        wantsLayer = true
        layer?.cornerRadius = 20
        layer?.backgroundColor = widgetBackground.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.7).cgColor
        buildView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildView() {
        let title = NSTextField(labelWithString: snapshot?.siteName ?? "Anker SOLIX")
        title.font = .boldSystemFont(ofSize: 23)
        title.textColor = .labelColor
        title.toolTip = "Name deiner SOLIX-Anlage."

        let subtitle = NSTextField(labelWithString: snapshot.map { "Aktualisiert \(RelativeDateTimeFormatter().localizedString(for: $0.updatedAt, relativeTo: Date()))" } ?? "Warte auf Daten")
        subtitle.textColor = .secondaryLabelColor
        subtitle.font = .systemFont(ofSize: 12, weight: .medium)
        subtitle.toolTip = "Wann die Werte zuletzt aktualisiert wurden."

        let statusPill = statusBadge()

        let battery = bigMetric(
            title: "Akku",
            value: snapshot?.batteryPercent.map { "\($0) %" } ?? "-",
            symbol: "battery.100percent",
            color: .systemGreen
        )
        let solar = bigMetric(
            title: "Solar",
            value: snapshot?.solarWatts.map { "\($0) W" } ?? "-",
            symbol: "sun.max.fill",
            color: solarColor
        )

        let grid = NSGridView(views: [
            [smallMetric("Haus", snapshot?.homeWatts.map { "\($0) W" }, "house.fill", .systemBlue),
             smallMetric("Netzbezug", signedWatts(snapshot?.gridWatts), "powerplug.fill", gridColor())],
            [smallMetric("Batteriefluss", signedWatts(snapshot?.batteryWatts), "bolt.fill", batteryFlowColor()),
             smallMetric("Heutiger Ertrag", snapshot?.todayKWh.map { String(format: "%.2f kWh", $0) }, "chart.bar.fill", .systemPurple)],
            [smallMetric("Gesamtertrag", snapshot?.totalKWh.map { String(format: "%.1f kWh", $0) }, "sum", .systemIndigo),
             smallMetric("Status", snapshot?.status, "checkmark.circle.fill", statusColor)]
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.column(at: 0).width = 160
        grid.column(at: 1).width = 160

        let graph = HistoryGraphView(
            samples: samples,
            rangeTitle: AppSettings.shared.historyRange.title,
            visibleMetrics: AppSettings.shared.graphMetrics,
            size: NSSize(width: 342, height: 150)
        )

        for view in [title, subtitle, statusPill, battery, solar, grid, graph] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: 28),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            title.trailingAnchor.constraint(lessThanOrEqualTo: statusPill.leadingAnchor, constant: -12),

            statusPill.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            statusPill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            statusPill.heightAnchor.constraint(equalToConstant: 26),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),

            battery.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 18),
            battery.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            battery.trailingAnchor.constraint(equalTo: centerXAnchor, constant: -6),
            battery.heightAnchor.constraint(equalToConstant: 92),

            solar.topAnchor.constraint(equalTo: battery.topAnchor),
            solar.leadingAnchor.constraint(equalTo: centerXAnchor, constant: 6),
            solar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            solar.heightAnchor.constraint(equalToConstant: 92),

            grid.topAnchor.constraint(equalTo: battery.bottomAnchor, constant: 12),
            grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            graph.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 16),
            graph.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            graph.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            graph.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24)
        ])
    }

    private func bigMetric(title: String, value: String, symbol: String, color: NSColor) -> NSView {
        metricPanel(title: title, value: value, symbol: symbol, color: color, valueSize: 26)
    }

    private func smallMetric(_ title: String, _ value: String?, _ symbol: String, _ color: NSColor) -> NSView {
        metricPanel(title: title, value: value ?? "-", symbol: symbol, color: color, valueSize: 16)
    }

    private func metricPanel(title: String, value: String, symbol: String, color: NSColor, valueSize: CGFloat) -> NSView {
        let panel = AnimatedPanelView()
        panel.toolTip = tooltip(for: title, value: value)
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 12
        panel.baseColor = metricBackground(for: color, strength: 0.16)
        panel.highlightColor = metricBackground(for: color, strength: 0.25)
        panel.layer?.borderWidth = 1
        panel.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor

        let imageView = NSImageView(image: coloredSymbol(symbol, color: color) ?? NSImage())
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.textColor = .labelColor
        titleLabel.font = .systemFont(ofSize: valueSize > 20 ? 15 : 13, weight: .bold)
        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: valueSize, weight: .semibold)
        valueLabel.textColor = .labelColor
        valueLabel.lineBreakMode = .byTruncatingTail

        for view in [imageView, titleLabel, valueLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            panel.addSubview(view)
        }

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: panel.topAnchor, constant: 12),
            imageView.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
            imageView.widthAnchor.constraint(equalToConstant: 20),
            imageView.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -10),

            valueLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 8),
            valueLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12),
            valueLabel.bottomAnchor.constraint(lessThanOrEqualTo: panel.bottomAnchor, constant: -10)
        ])
        return panel
    }

    private func coloredSymbol(_ symbol: String, color: NSColor) -> NSImage? {
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else { return nil }
        let configured = image.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)) ?? image
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

    private func statusBadge() -> NSView {
        let badge = AnimatedPanelView()
        badge.toolTip = "Zeigt, ob die Datenquelle online ist."
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 13
        badge.baseColor = statusColor.withAlphaComponent(0.18)
        badge.highlightColor = statusColor.withAlphaComponent(0.28)
        badge.layer?.borderWidth = 1
        badge.layer?.borderColor = statusColor.withAlphaComponent(0.45).cgColor

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = statusColor.cgColor

        let label = NSTextField(labelWithString: snapshot?.status ?? "Bereit")
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .labelColor

        for view in [dot, label] {
            view.translatesAutoresizingMaskIntoConstraints = false
            badge.addSubview(view)
        }

        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 10),
            dot.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),

            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: badge.centerYAnchor)
        ])
        return badge
    }

    private var widgetBackground: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.10, alpha: 0.98)
                : NSColor(calibratedRed: 0.97, green: 0.98, blue: 0.98, alpha: 0.98)
        }
    }

    private var panelBackground: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.24, green: 0.25, blue: 0.26, alpha: 1)
                : NSColor(calibratedRed: 0.995, green: 0.998, blue: 1, alpha: 1)
        }
    }

    private var isDarkMode: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func tooltip(for title: String, value: String) -> String {
        switch title {
        case "Akku":
            return "Hier wird angezeigt, wie voll der Speicher aktuell geladen ist: \(value)."
        case "Solar":
            return "Hier wird angezeigt, wie viel Leistung die Solarmodule gerade erzeugen: \(value)."
        case "Haus":
            return "Hier wird angezeigt, wie viel Leistung dein Haus gerade verbraucht: \(value)."
        case "Netzbezug":
            return "Hier wird angezeigt, wie viel Leistung aus dem Netz bezogen wird. Negative Werte bedeuten Einspeisung: \(value)."
        case "Batteriefluss":
            return "Hier wird angezeigt, ob und mit welcher Leistung der Akku lädt oder entlädt: \(value)."
        case "Heutiger Ertrag":
            return "Hier wird angezeigt, wie viel Solarenergie heute bereits erzeugt wurde: \(value)."
        case "Gesamtertrag":
            return "Hier wird angezeigt, wie viel Solarenergie insgesamt bisher erfasst wurde: \(value)."
        case "Status":
            return "Hier wird angezeigt, ob die Datenquelle aktuell erreichbar ist: \(value)."
        default:
            return "\(title): \(value)."
        }
    }

    private var statusColor: NSColor {
        snapshot?.status?.localizedCaseInsensitiveContains("offline") == true ? .systemRed : .systemGreen
    }

    private var solarColor: NSColor {
        NSColor(calibratedRed: 0.93, green: 0.66, blue: 0.08, alpha: 1)
    }

    private func gridColor() -> NSColor {
        guard let watts = snapshot?.gridWatts else { return .systemGray }
        return watts > 0 ? .systemBlue : .systemTeal
    }

    private func batteryFlowColor() -> NSColor {
        guard let watts = snapshot?.batteryWatts else { return .systemGray }
        return watts >= 0 ? .systemGreen : .systemOrange
    }

    private func metricBackground(for color: NSColor, strength: CGFloat) -> NSColor {
        let adjustedStrength = isDarkMode ? strength * 0.8 : strength
        return color.withAlphaComponent(adjustedStrength)
            .blended(withFraction: isDarkMode ? 0.72 : 0.80, of: panelBackground) ?? panelBackground
    }
}
