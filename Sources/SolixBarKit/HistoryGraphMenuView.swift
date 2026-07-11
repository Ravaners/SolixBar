import AppKit

/// Verlaufs-Sektion im Dashboard: gemeinsame Chip-Kopfzeile
/// (GraphControlHeader) über dem Graphen.
@MainActor
final class HistoryGraphMenuView: NSView {
    private let settings = AppSettings.shared
    private let graphProvider: () -> [SolixHistorySample]
    private let onRangeChange: () -> Void
    private let onOpenLarge: () -> Void
    private let graphContainer = NSView()
    private var header: GraphControlHeader?

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
        let header = GraphControlHeader(onChange: { [weak self] in
            self?.reload()
            self?.onRangeChange()
        })
        self.header = header

        for view in [header, graphContainer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),

            graphContainer.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 14),
            graphContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            graphContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            graphContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            // Ohne explizite Höhe kollabiert der Container (der Graph hat keine
            // intrinsische Größe).
            graphContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 190)
        ])
    }

    /// Umrechnung Tage <-> Anzeigeeinheit des eigenen Zeitraums
    /// (Speicherformat bleibt Tage). Auch von den Einstellungen genutzt.
    static func customValue(days: Double, unit: String) -> Int {
        switch unit {
        case "hours": max(1, Int((days * 24).rounded()))
        case "weeks": max(1, Int((days / 7).rounded()))
        case "months": max(1, Int((days / 30).rounded()))
        default: max(1, Int(days.rounded()))
        }
    }

    static func days(fromValue value: Int, unit: String) -> Double {
        switch unit {
        case "hours": max(1.0 / 24, Double(value) / 24)
        case "weeks": Double(value) * 7
        case "months": Double(value) * 30
        default: Double(value)
        }
    }

    private func reload() {
        header?.reload()
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
