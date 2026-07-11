import AppKit

/// Verlaufs-Sektion im Dashboard: Zeitraum und Legende als kompakte klickbare
/// Chips in einer Karte (statt Segmented Control + System-Checkboxen in drei
/// gestapelten Ebenen), darunter der Graph mit Luft dazwischen.
/// Borderless Button mit symmetrischem Innenabstand — der frühere
/// Leerzeichen-Trick zentrierte den Text nicht (Trailing-Spaces werden beim
/// Rendern verschluckt).
@MainActor
private final class ChipButton: NSButton {
    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 20
        size.height = 22
        return size
    }
}

@MainActor
final class HistoryGraphMenuView: NSView {
    private let settings = AppSettings.shared
    private let graphProvider: () -> [SolixHistorySample]
    private let onRangeChange: () -> Void
    private let onOpenLarge: () -> Void
    private let customDaysField = NSTextField()
    private let graphContainer = NSView()
    private var rangeChips: [HistoryRange: NSButton] = [:]
    private var legendChips: [GraphMetric: NSButton] = [:]

    init(graphProvider: @escaping () -> [SolixHistorySample], onRangeChange: @escaping () -> Void, onOpenLarge: @escaping () -> Void) {
        self.graphProvider = graphProvider
        self.onRangeChange = onRangeChange
        self.onOpenLarge = onOpenLarge
        super.init(frame: NSRect(x: 0, y: 0, width: 396, height: 300))
        wantsLayer = true
        layer?.cornerRadius = Theme.radiusCard
        layer?.masksToBounds = true
        layer?.backgroundColor = menuBackground.cgColor
        buildView()
        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildView() {
        let rangeRow = NSStackView()
        rangeRow.orientation = .horizontal
        rangeRow.spacing = 4
        for range in HistoryRange.allCases {
            let chip = makeChip(action: #selector(changeRange(_:)))
            chip.tag = HistoryRange.allCases.firstIndex(of: range) ?? 0
            chip.toolTip = LocalizedText.text(
                "Zeitraum: \(range.title)",
                "Range: \(range.title)"
            )
            rangeChips[range] = chip
            rangeRow.addArrangedSubview(chip)
        }

        customDaysField.placeholderString = LocalizedText.text("Tage", "days")
        customDaysField.target = self
        customDaysField.action = #selector(changeCustomDays)
        customDaysField.cell = CenteredTextFieldCell(textCell: "")
        customDaysField.alignment = .center
        customDaysField.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        customDaysField.textColor = .labelColor
        customDaysField.toolTip = LocalizedText.text(
            "Anzahl der Tage für den individuellen Zeitraum.",
            "Number of days for the custom range."
        )

        let legendRow = NSStackView()
        legendRow.orientation = .horizontal
        legendRow.spacing = 6
        for metric in GraphMetric.allCases {
            let chip = makeChip(action: #selector(toggleMetric(_:)))
            chip.tag = GraphMetric.allCases.firstIndex(of: metric) ?? 0
            chip.toolTip = LocalizedText.text(
                "Blendet \(metric.title) im Graphen ein oder aus.",
                "Shows or hides \(metric.title) in the graph."
            )
            legendChips[metric] = chip
            legendRow.addArrangedSubview(chip)
        }

        for view in [rangeRow, legendRow, customDaysField, graphContainer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            // Zeitraum-Chips linksbündig oben, Legende direkt darunter —
            // beide Steuerzeilen teilen sich eine linke Kante.
            rangeRow.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            rangeRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            rangeRow.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),

            legendRow.topAnchor.constraint(equalTo: rangeRow.bottomAnchor, constant: 8),
            legendRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),

            customDaysField.centerYAnchor.constraint(equalTo: rangeRow.centerYAnchor),
            customDaysField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            customDaysField.leadingAnchor.constraint(greaterThanOrEqualTo: rangeRow.trailingAnchor, constant: 10),
            customDaysField.widthAnchor.constraint(equalToConstant: 72),
            customDaysField.heightAnchor.constraint(equalToConstant: 22),

            graphContainer.topAnchor.constraint(equalTo: legendRow.bottomAnchor, constant: 14),
            graphContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            graphContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            graphContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            // Ohne explizite Höhe kollabiert der Container (der Graph hat keine
            // intrinsische Größe).
            graphContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 190)
        ])
    }

    private func makeChip(action: Selector) -> NSButton {
        let chip = ChipButton(title: "", target: self, action: action)
        chip.isBordered = false
        chip.wantsLayer = true
        chip.layer?.cornerRadius = 11
        chip.layer?.masksToBounds = true
        chip.heightAnchor.constraint(equalToConstant: 22).isActive = true
        chip.setContentHuggingPriority(.required, for: .horizontal)
        return chip
    }

    private func styleRangeChip(_ chip: NSButton, title: String, selected: Bool) {
        chip.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: selected ? .bold : .medium),
                .foregroundColor: selected ? NSColor.labelColor : NSColor.secondaryLabelColor
            ]
        )
        chip.layer?.backgroundColor = selected
            ? NSColor.labelColor.withAlphaComponent(0.12).cgColor
            : NSColor.clear.cgColor
    }

    private func styleLegendChip(_ chip: NSButton, metric: GraphMetric, active: Bool) {
        let accent: NSColor = switch metric {
        case .battery: Theme.accent(.batteryHigh)
        case .solar: Theme.accent(.solar)
        case .grid: Theme.accent(.gridImport)
        }
        let name = switch metric {
        case .battery: LocalizedText.text("Akku", "Battery")
        case .solar: "Solar"
        case .grid: LocalizedText.text("Netz", "Grid")
        }
        // Punkt kleiner und minimal angehoben, damit er die Zeile nicht
        // anhebt und optisch auf der Textmitte sitzt.
        let text = NSMutableAttributedString(
            string: "● ",
            attributes: [
                .font: NSFont.systemFont(ofSize: 9, weight: .bold),
                .baselineOffset: 0.5,
                .foregroundColor: active ? accent : NSColor.tertiaryLabelColor
            ]
        )
        text.append(NSAttributedString(
            string: name,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: active ? NSColor.labelColor : NSColor.tertiaryLabelColor
            ]
        ))
        chip.attributedTitle = text
        chip.layer?.backgroundColor = active
            ? accent.withAlphaComponent(0.14).cgColor
            : NSColor.labelColor.withAlphaComponent(0.05).cgColor
    }

    private func reload() {
        for range in HistoryRange.allCases {
            guard let chip = rangeChips[range] else { continue }
            styleRangeChip(chip, title: range.shortTitle, selected: settings.historyRange == range)
        }
        let selectedMetrics = Set(settings.graphMetrics)
        for metric in GraphMetric.allCases {
            guard let chip = legendChips[metric] else { continue }
            styleLegendChip(chip, metric: metric, active: selectedMetrics.contains(metric))
        }
        customDaysField.stringValue = LocalizedText.text(
            "\(Int(settings.customHistoryDays)) Tage",
            "\(Int(settings.customHistoryDays)) days"
        )
        customDaysField.isEnabled = settings.historyRange == .custom
        customDaysField.isHidden = settings.historyRange != .custom

        graphContainer.subviews.forEach { $0.removeFromSuperview() }
        let graph = HistoryGraphView(
            samples: graphProvider(),
            rangeTitle: settings.historyRange.title,
            range: settings.historyRange,
            rangeDuration: settings.historyDuration,
            visibleMetrics: settings.graphMetrics,
            showsHeader: false,
            size: NSSize(width: 368, height: 191)
        )
        graph.onClick = onOpenLarge
        graph.translatesAutoresizingMaskIntoConstraints = false
        graphContainer.addSubview(graph)

        NSLayoutConstraint.activate([
            graph.topAnchor.constraint(equalTo: graphContainer.topAnchor),
            graph.leadingAnchor.constraint(equalTo: graphContainer.leadingAnchor),
            graph.trailingAnchor.constraint(equalTo: graphContainer.trailingAnchor),
            graph.bottomAnchor.constraint(equalTo: graphContainer.bottomAnchor)
        ])
    }

    /// Chip-Titel mit Farbpunkt — auch vom großen Verlaufsfenster genutzt.
    static func legendTitle(for metric: GraphMetric, fontSize: CGFloat) -> NSAttributedString {
        let color: NSColor = switch metric {
        case .battery: Theme.accent(.batteryHigh)
        case .solar: Theme.accent(.solar)
        case .grid: Theme.accent(.gridImport)
        }
        let name = switch metric {
        case .battery: LocalizedText.text("Akku", "Battery")
        case .solar: "Solar"
        case .grid: LocalizedText.text("Netzbezug", "Grid import")
        }
        let title = NSMutableAttributedString(
            string: "● ",
            attributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: color
            ]
        )
        title.append(NSAttributedString(
            string: name,
            attributes: [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
        ))
        return title
    }

    @objc private func changeRange(_ sender: NSButton) {
        settings.historyRange = HistoryRange.allCases[safe: sender.tag] ?? .day
        AppLogger.info("Dashboard graph range changed to \(settings.historyRange.rawValue).")
        reload()
        onRangeChange()
    }

    @objc private func changeCustomDays() {
        settings.customHistoryDays = Double(max(1, customDaysField.integerValue))
        AppLogger.info("Dashboard graph custom days changed to \(Int(settings.customHistoryDays)).")
        reload()
        onRangeChange()
    }

    @objc private func toggleMetric(_ sender: NSButton) {
        guard let metric = GraphMetric.allCases[safe: sender.tag] else { return }
        var selected = Set(settings.graphMetrics)
        if selected.contains(metric) {
            selected.remove(metric)
        } else {
            selected.insert(metric)
        }
        let ordered = GraphMetric.allCases.filter { selected.contains($0) }
        settings.graphMetrics = ordered.isEmpty ? GraphMetric.allCases : ordered
        let metricNames = settings.graphMetrics.map(\.rawValue).joined(separator: ",")
        AppLogger.info("Dashboard graph metrics changed to \(metricNames).")
        reload()
        onRangeChange()
    }

    override func draw(_ dirtyRect: NSRect) {
        menuBackground.setFill()
        bounds.fill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance { [self] in
            layer?.backgroundColor = menuBackground.cgColor
        }
        reload()
        needsDisplay = true
    }

    private var menuBackground: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.105, green: 0.115, blue: 0.125, alpha: 1)
                : NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 1)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
