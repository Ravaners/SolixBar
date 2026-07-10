import AppKit

@MainActor
final class HistoryGraphMenuView: NSView {
    private let settings = AppSettings.shared
    private let graphProvider: () -> [SolixHistorySample]
    private let onRangeChange: () -> Void
    private let onOpenLarge: () -> Void
    private let segmented = NSSegmentedControl(labels: HistoryRange.allCases.map(\.shortTitle), trackingMode: .selectOne, target: nil, action: nil)
    private let customDaysField = NSTextField()
    private let graphContainer = NSView()
    private var graphMetricButtons: [GraphMetric: NSButton] = [:]

    init(graphProvider: @escaping () -> [SolixHistorySample], onRangeChange: @escaping () -> Void, onOpenLarge: @escaping () -> Void) {
        self.graphProvider = graphProvider
        self.onRangeChange = onRangeChange
        self.onOpenLarge = onOpenLarge
        super.init(frame: NSRect(x: 0, y: 0, width: 396, height: 282))
        wantsLayer = true
        layer?.cornerRadius = Theme.radiusCard
        layer?.backgroundColor = menuBackground.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
        buildView()
        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildView() {
        let title = NSTextField(labelWithString: "Verlauf")
        title.font = .boldSystemFont(ofSize: 13)
        title.textColor = .labelColor
        title.toolTip = "Zeigt den zeitlichen Verlauf von Akku, Solar und Netzbezug."

        segmented.target = self
        segmented.action = #selector(changeRange)
        segmented.segmentStyle = .rounded
        segmented.controlSize = .small
        segmented.font = .systemFont(ofSize: 11, weight: .semibold)
        segmented.toolTip = "Wählt den Zeitraum für den Graphen."

        customDaysField.placeholderString = "Tage"
        customDaysField.target = self
        customDaysField.action = #selector(changeCustomDays)
        customDaysField.cell = CenteredTextFieldCell(textCell: "")
        customDaysField.alignment = .center
        customDaysField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        customDaysField.backgroundColor = fieldBackground
        customDaysField.textColor = .labelColor
        customDaysField.toolTip = "Anzahl der Tage für den individuellen Zeitraum."

        let metricControls = graphMetricControls()

        for view in [title, segmented, customDaysField, metricControls, graphContainer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),

            segmented.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            segmented.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 12),
            segmented.widthAnchor.constraint(equalToConstant: 220),
            segmented.heightAnchor.constraint(equalToConstant: 25),

            customDaysField.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            customDaysField.leadingAnchor.constraint(equalTo: segmented.trailingAnchor, constant: 8),
            customDaysField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
            customDaysField.widthAnchor.constraint(equalToConstant: 54),
            customDaysField.heightAnchor.constraint(equalToConstant: 25),

            metricControls.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            metricControls.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            metricControls.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -13),
            metricControls.heightAnchor.constraint(equalToConstant: 24),

            graphContainer.topAnchor.constraint(equalTo: metricControls.bottomAnchor, constant: 8),
            graphContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            graphContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
            graphContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            // Ohne explizite Höhe kollabiert der Container (der Graph hat keine
            // intrinsische Größe) und der Plot quetscht seinen eigenen Header.
            graphContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 190)
        ])
    }

    private func graphMetricControls() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8

        for metric in GraphMetric.allCases {
            let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(changeGraphMetrics))
            button.attributedTitle = Self.legendTitle(for: metric, fontSize: 11)
            button.controlSize = .small
            button.toolTip = LocalizedText.text(
                "Blendet \(metric.title) im Graphen ein oder aus.",
                "Shows or hides \(metric.title) in the graph."
            )
            graphMetricButtons[metric] = button
            stack.addArrangedSubview(button)
        }
        return stack
    }

    /// Checkbox-Titel mit Farbpunkt in der Linienfarbe — die Checkboxen sind
    /// zugleich die Legende des kompakten Graphen.
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

    private func reload() {
        segmented.selectedSegment = HistoryRange.allCases.firstIndex(of: settings.historyRange) ?? 0
        customDaysField.stringValue = String(Int(settings.customHistoryDays))
        customDaysField.isEnabled = settings.historyRange == .custom
        // Nur zeigen, wenn "Eig." aktiv ist — sonst ist das Feld Rauschen.
        customDaysField.isHidden = settings.historyRange != .custom
        let selectedMetrics = Set(settings.graphMetrics)
        for metric in GraphMetric.allCases {
            graphMetricButtons[metric]?.state = selectedMetrics.contains(metric) ? .on : .off
        }

        graphContainer.subviews.forEach { $0.removeFromSuperview() }
        let graph = HistoryGraphView(
            samples: graphProvider(),
            rangeTitle: settings.historyRange.title,
            range: settings.historyRange,
            rangeDuration: settings.historyDuration,
            visibleMetrics: settings.graphMetrics,
            size: NSSize(width: 370, height: 191)
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

    @objc private func changeRange() {
        settings.historyRange = HistoryRange.allCases[safe: segmented.selectedSegment] ?? .day
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

    @objc private func changeGraphMetrics() {
        let selected = GraphMetric.allCases.filter { graphMetricButtons[$0]?.state == .on }
        settings.graphMetrics = selected.isEmpty ? GraphMetric.allCases : selected
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
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
        }
        needsDisplay = true
    }

    private var menuBackground: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.105, green: 0.115, blue: 0.125, alpha: 1)
                : NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 1)
        }
    }

    private var fieldBackground: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.18, alpha: 1)
                : NSColor.white
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
