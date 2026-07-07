import AppKit

@MainActor
final class LargeGraphWindowController: NSWindowController {
    private let settings = AppSettings.shared
    private let graphProvider: () -> [SolixHistorySample]
    private let segmented = NSSegmentedControl(labels: HistoryRange.allCases.map(\.shortTitle), trackingMode: .selectOne, target: nil, action: nil)
    private let customDaysField = NSTextField()
    private let graphContainer = NSView()
    private var graphMetricButtons: [GraphMetric: NSButton] = [:]

    init(graphProvider: @escaping () -> [SolixHistorySample]) {
        self.graphProvider = graphProvider
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SOLIX Verlauf"
        window.minSize = NSSize(width: 620, height: 400)
        window.center()
        super.init(window: window)
        window.contentView = buildView()
        rebuild()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func rebuild() {
        segmented.selectedSegment = HistoryRange.allCases.firstIndex(of: settings.historyRange) ?? 0
        customDaysField.stringValue = String(Int(settings.customHistoryDays))
        customDaysField.isEnabled = settings.historyRange == .custom

        let selectedMetrics = Set(settings.graphMetrics)
        for metric in GraphMetric.allCases {
            graphMetricButtons[metric]?.state = selectedMetrics.contains(metric) ? .on : .off
        }

        graphContainer.subviews.forEach { $0.removeFromSuperview() }
        let graph = HistoryGraphView(
            samples: graphProvider(),
            rangeTitle: settings.historyRange.title,
            visibleMetrics: settings.graphMetrics,
            size: NSSize(width: 680, height: 360)
        )
        graph.translatesAutoresizingMaskIntoConstraints = false
        graphContainer.addSubview(graph)

        NSLayoutConstraint.activate([
            graph.topAnchor.constraint(equalTo: graphContainer.topAnchor),
            graph.leadingAnchor.constraint(equalTo: graphContainer.leadingAnchor),
            graph.trailingAnchor.constraint(equalTo: graphContainer.trailingAnchor),
            graph.bottomAnchor.constraint(equalTo: graphContainer.bottomAnchor)
        ])
    }

    private func buildView() -> NSView {
        let container = NSView()

        let title = NSTextField(labelWithString: "Verlauf")
        title.font = .boldSystemFont(ofSize: 16)
        title.textColor = .labelColor

        segmented.target = self
        segmented.action = #selector(changeRange)
        segmented.segmentStyle = .rounded
        segmented.controlSize = .regular
        segmented.toolTip = "Wählt den Zeitraum für den Graphen."

        customDaysField.placeholderString = "Tage"
        customDaysField.target = self
        customDaysField.action = #selector(changeCustomDays)
        customDaysField.alignment = .right
        customDaysField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        customDaysField.toolTip = "Anzahl der Tage für den individuellen Zeitraum."

        let metricControls = graphMetricControls()

        for view in [title, segmented, customDaysField, metricControls, graphContainer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),

            segmented.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            segmented.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 18),
            segmented.widthAnchor.constraint(equalToConstant: 250),
            segmented.heightAnchor.constraint(equalToConstant: 28),

            customDaysField.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            customDaysField.leadingAnchor.constraint(equalTo: segmented.trailingAnchor, constant: 10),
            customDaysField.widthAnchor.constraint(equalToConstant: 64),
            customDaysField.heightAnchor.constraint(equalToConstant: 28),

            metricControls.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),
            metricControls.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            metricControls.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20),
            metricControls.heightAnchor.constraint(equalToConstant: 28),

            graphContainer.topAnchor.constraint(equalTo: metricControls.bottomAnchor, constant: 12),
            graphContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            graphContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            graphContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20)
        ])

        return container
    }

    private func graphMetricControls() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 12

        for metric in GraphMetric.allCases {
            let button = NSButton(checkboxWithTitle: metric.title, target: self, action: #selector(changeGraphMetrics))
            button.font = .systemFont(ofSize: 12, weight: .semibold)
            button.toolTip = "Blendet \(metric.title) im Graphen ein oder aus."
            graphMetricButtons[metric] = button
            stack.addArrangedSubview(button)
        }
        return stack
    }

    @objc private func changeRange() {
        settings.historyRange = historyRange(at: segmented.selectedSegment) ?? .day
        rebuild()
    }

    @objc private func changeCustomDays() {
        settings.customHistoryDays = Double(max(1, customDaysField.integerValue))
        rebuild()
    }

    @objc private func changeGraphMetrics() {
        let selected = GraphMetric.allCases.filter { graphMetricButtons[$0]?.state == .on }
        settings.graphMetrics = selected.isEmpty ? GraphMetric.allCases : selected
        rebuild()
    }

    private func historyRange(at index: Int) -> HistoryRange? {
        HistoryRange.allCases.indices.contains(index) ? HistoryRange.allCases[index] : nil
    }
}
