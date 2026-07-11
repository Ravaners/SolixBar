import AppKit

/// Borderless Button mit symmetrischem Innenabstand — Leerzeichen-Padding
/// zentriert nicht (Trailing-Spaces werden beim Rendern verschluckt).
@MainActor
final class ChipButton: NSButton {
    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 20
        size.height = 22
        return size
    }
}

/// Gemeinsame Kopfzeile aller Verlaufs-Ansichten: Titel, Zeitraum-Chips und
/// Legend-Chips — Dashboard-Dropdown, abgedocktes Dashboard und großes
/// Verlaufsfenster nutzen exakt dieselben Bedienelemente.
@MainActor
final class GraphControlHeader: NSView {
    private let settings = AppSettings.shared
    private let onChange: () -> Void
    private var rangeChips: [HistoryRange: NSButton] = [:]
    private var legendChips: [GraphMetric: NSButton] = [:]

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
        buildView()
        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildView() {
        let title = NSTextField(labelWithString: LocalizedText.text("Verlauf", "History"))
        title.font = .boldSystemFont(ofSize: 13)
        title.textColor = .labelColor

        let rangeRow = NSStackView()
        rangeRow.orientation = .horizontal
        rangeRow.spacing = 4
        for range in HistoryRange.allCases {
            let chip = makeChip(action: #selector(changeRange(_:)))
            chip.tag = HistoryRange.allCases.firstIndex(of: range) ?? 0
            chip.toolTip = range == .custom
                ? LocalizedText.text(
                    "Eigener Zeitraum — Dauer in den Einstellungen (App) festlegen.",
                    "Custom range — set the duration in Settings (App)."
                )
                : LocalizedText.text("Zeitraum: \(range.title)", "Range: \(range.title)")
            rangeChips[range] = chip
            rangeRow.addArrangedSubview(chip)
        }

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

        for view in [title, rangeRow, legendRow] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor),
            title.centerYAnchor.constraint(equalTo: rangeRow.centerYAnchor),

            rangeRow.topAnchor.constraint(equalTo: topAnchor),
            rangeRow.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 14),
            rangeRow.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            legendRow.topAnchor.constraint(equalTo: rangeRow.bottomAnchor, constant: 8),
            legendRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            legendRow.bottomAnchor.constraint(equalTo: bottomAnchor)
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

    func reload() {
        for range in HistoryRange.allCases {
            guard let chip = rangeChips[range] else { continue }
            styleRangeChip(chip, title: range.shortTitle, selected: settings.historyRange == range)
        }
        let selectedMetrics = Set(settings.graphMetrics)
        for metric in GraphMetric.allCases {
            guard let chip = legendChips[metric] else { continue }
            styleLegendChip(chip, metric: metric, active: selectedMetrics.contains(metric))
        }
    }

    @objc private func changeRange(_ sender: NSButton) {
        settings.historyRange = HistoryRange.allCases[safe: sender.tag] ?? .day
        AppLogger.info("Graph range changed to \(settings.historyRange.rawValue).")
        reload()
        onChange()
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
        AppLogger.info("Graph metrics changed to \(settings.graphMetrics.map(\.rawValue).joined(separator: ","))")
        reload()
        onChange()
    }
}
