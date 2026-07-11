import AppKit

/// Großes Verlaufsfenster: nutzt dieselbe Chip-Kopfzeile wie das Dashboard.
@MainActor
final class LargeGraphWindowController: NSWindowController {
    private let settings = AppSettings.shared
    private let graphProvider: () -> [SolixHistorySample]
    private let graphContainer = NSView()
    private var header: GraphControlHeader?

    init(graphProvider: @escaping () -> [SolixHistorySample]) {
        self.graphProvider = graphProvider
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = LocalizedText.text("SOLIX Verlauf", "SOLIX History")
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
        header?.reload()
        graphContainer.subviews.forEach { $0.removeFromSuperview() }
        let graph = HistoryGraphView(
            samples: graphProvider(),
            rangeTitle: settings.historyRange.title,
            range: settings.historyRange,
            rangeDuration: settings.historyDuration,
            visibleMetrics: settings.graphMetrics,
            showsHeader: false,
            size: NSSize(width: 680, height: 360)
        )
        graph.isInteractive = true
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
        let header = GraphControlHeader(onChange: { [weak self] in
            self?.rebuild()
        })
        self.header = header

        for view in [header, graphContainer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20),

            graphContainer.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            graphContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            graphContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            graphContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20)
        ])

        return container
    }
}
