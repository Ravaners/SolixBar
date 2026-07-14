import AppKit

@MainActor
final class MetricOrderEditorView: NSView {
    private let rows = NSStackView()
    private let previewLabel = NSTextField(labelWithString: "")
    private let onChange: ([BarMetric]) -> Void
    private var orderedMetrics = BarMetric.allCases
    private var selected = Set(BarMetric.allCases)

    init(onChange: @escaping ([BarMetric]) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
        buildView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 620, height: 354)
    }

    var selectedMetrics: [BarMetric] {
        orderedMetrics.filter(selected.contains)
    }

    func load(_ metrics: [BarMetric]) {
        let values = metrics.isEmpty ? [BarMetric.battery, .solar, .grid] : metrics
        selected = Set(values)
        orderedMetrics = values + BarMetric.allCases.filter { !selected.contains($0) }
        rebuildRows()
        refreshPreview()
    }

    func refreshPreview() {
        let result = NSMutableAttributedString()
        for (index, metric) in selectedMetrics.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "   ", attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
            }
            result.append(NSAttributedString(
                string: sampleText(for: metric),
                attributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
                    .foregroundColor: sampleColor(for: metric)
                ]
            ))
        }
        previewLabel.attributedStringValue = result
    }

    private func buildView() {
        wantsLayer = true
        rows.orientation = .vertical
        rows.spacing = 2
        rows.alignment = .leading

        let previewTitle = NSTextField(labelWithString: LocalizedText.text("Live-Vorschau", "Live Preview"))
        previewTitle.font = .boldSystemFont(ofSize: 12)
        previewLabel.wantsLayer = true
        previewLabel.layer?.cornerRadius = 8
        previewLabel.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.85).cgColor
        previewLabel.drawsBackground = false
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.maximumNumberOfLines = 1

        for view in [rows, previewTitle, previewLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: topAnchor),
            rows.leadingAnchor.constraint(equalTo: leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor),

            previewTitle.topAnchor.constraint(equalTo: rows.bottomAnchor, constant: 10),
            previewTitle.leadingAnchor.constraint(equalTo: leadingAnchor),

            previewLabel.topAnchor.constraint(equalTo: previewTitle.bottomAnchor, constant: 5),
            previewLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            previewLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            previewLabel.heightAnchor.constraint(equalToConstant: 36),
            previewLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        rebuildRows()
        refreshPreview()
    }

    private func rebuildRows() {
        for view in rows.arrangedSubviews {
            rows.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for (index, metric) in orderedMetrics.enumerated() {
            let checkbox = NSButton(
                checkboxWithTitle: localizedTitle(metric),
                target: self,
                action: #selector(toggleMetric(_:))
            )
            checkbox.tag = index
            checkbox.state = selected.contains(metric) ? .on : .off
            checkbox.widthAnchor.constraint(equalToConstant: 420).isActive = true

            let up = moveButton(symbol: "chevron.up", tooltip: LocalizedText.text("Nach oben verschieben", "Move up"), index: index, action: #selector(moveMetricUp(_:)))
            let down = moveButton(symbol: "chevron.down", tooltip: LocalizedText.text("Nach unten verschieben", "Move down"), index: index, action: #selector(moveMetricDown(_:)))
            up.isEnabled = index > 0
            down.isEnabled = index < orderedMetrics.count - 1

            let row = NSStackView(views: [checkbox, up, down])
            row.orientation = .horizontal
            row.spacing = 8
            row.alignment = .centerY
            rows.addArrangedSubview(row)
        }
    }

    private func moveButton(symbol: String, tooltip: String, index: Int, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        let button = NSButton(image: image ?? NSImage(), target: self, action: action)
        button.tag = index
        button.toolTip = tooltip
        button.bezelStyle = .rounded
        button.widthAnchor.constraint(equalToConstant: 34).isActive = true
        return button
    }

    @objc private func toggleMetric(_ sender: NSButton) {
        let metric = orderedMetrics[sender.tag]
        if sender.state == .on {
            selected.insert(metric)
        } else if selected.count > 1 {
            selected.remove(metric)
        } else {
            sender.state = .on
            NSSound.beep()
            return
        }
        changed()
    }

    @objc private func moveMetricUp(_ sender: NSButton) {
        guard sender.tag > 0 else { return }
        orderedMetrics.swapAt(sender.tag, sender.tag - 1)
        changed(rebuild: true)
    }

    @objc private func moveMetricDown(_ sender: NSButton) {
        guard sender.tag < orderedMetrics.count - 1 else { return }
        orderedMetrics.swapAt(sender.tag, sender.tag + 1)
        changed(rebuild: true)
    }

    private func changed(rebuild: Bool = false) {
        if rebuild { rebuildRows() }
        refreshPreview()
        onChange(selectedMetrics)
    }

    private func localizedTitle(_ metric: BarMetric) -> String {
        guard AppSettings.shared.appLanguage == .english else { return metric.title }
        return switch metric {
        case .battery: "Battery"
        case .solar: "PV"
        case .home: "Home Load"
        case .grid: "Grid"
        case .batteryFlow: "Battery Flow"
        case .flow: "Energy Flow"
        case .today: "Today's Yield"
        case .total: "Total Yield"
        case .status: "Status"
        }
    }

    private func sampleText(for metric: BarMetric) -> String {
        switch metric {
        case .battery: LocalizedText.text("Akku 78%", "Batt 78%")
        case .solar: "PV 640W"
        case .home: LocalizedText.text("Last 420W", "Load 420W")
        case .grid: LocalizedText.text("Netz 80W", "Grid 80W")
        case .batteryFlow: LocalizedText.text("Laden 220W", "Charging 220W")
        case .flow: LocalizedText.text("↓ Erzeugt  ↑ Laden", "↓ Producing  ↑ Charging")
        case .today: LocalizedText.text("Ertrag 4.28kWh", "Yield 4.28kWh")
        case .total: LocalizedText.text("Gesamt 438.6kWh", "Total 438.6kWh")
        case .status: "Online"
        }
    }

    private func sampleColor(for metric: BarMetric) -> NSColor {
        switch metric {
        case .battery, .status: .systemGreen
        case .solar, .today: .systemYellow
        case .home, .grid: .systemBlue
        case .batteryFlow, .flow: .systemOrange
        case .total: .systemPurple
        }
    }
}
