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

    init(graphProvider: @escaping () -> [SolixHistorySample], onRangeChange: @escaping () -> Void, onOpenLarge: @escaping () -> Void) {
        self.graphProvider = graphProvider
        self.onRangeChange = onRangeChange
        self.onOpenLarge = onOpenLarge
        super.init(frame: NSRect(x: 0, y: 0, width: 396, height: 250))
        wantsLayer = true
        layer?.cornerRadius = 14
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
        customDaysField.alignment = .right
        customDaysField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        customDaysField.backgroundColor = fieldBackground
        customDaysField.textColor = .labelColor
        customDaysField.toolTip = "Anzahl der Tage für den individuellen Zeitraum."

        for view in [title, segmented, customDaysField, graphContainer] {
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

            graphContainer.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),
            graphContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            graphContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
            graphContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
    }

    private func reload() {
        segmented.selectedSegment = HistoryRange.allCases.firstIndex(of: settings.historyRange) ?? 0
        customDaysField.stringValue = String(Int(settings.customHistoryDays))
        customDaysField.isEnabled = settings.historyRange == .custom

        graphContainer.subviews.forEach { $0.removeFromSuperview() }
        let graph = HistoryGraphView(
            samples: graphProvider(),
            rangeTitle: settings.historyRange.title,
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
        reload()
        onRangeChange()
    }

    @objc private func changeCustomDays() {
        settings.customHistoryDays = Double(max(1, customDaysField.integerValue))
        reload()
        onRangeChange()
    }

    override func draw(_ dirtyRect: NSRect) {
        menuBackground.setFill()
        bounds.fill()
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
