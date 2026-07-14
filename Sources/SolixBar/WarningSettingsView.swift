import AppKit

@MainActor
final class WarningSettingsView: NSView, NSTextFieldDelegate {
    private let onChange: ([WarningKind: WarningRule]) -> Void
    private var enableButtons: [WarningKind: NSButton] = [:]
    private var thresholdFields: [WarningKind: NSTextField] = [:]
    private var durationFields: [WarningKind: NSTextField] = [:]
    private var isLoading = false

    init(onChange: @escaping ([WarningKind: WarningRule]) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
        buildView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var rules: [WarningKind: WarningRule] {
        Dictionary(uniqueKeysWithValues: WarningKind.allCases.map { kind in
            let threshold = parsed(thresholdFields[kind]?.stringValue, fallback: kind.defaultThreshold)
            let duration = parsed(durationFields[kind]?.stringValue, fallback: kind.defaultDurationMinutes)
            return (kind, WarningRule(
                isEnabled: enableButtons[kind]?.state == .on,
                threshold: max(0, threshold),
                durationMinutes: max(0, duration)
            ))
        })
    }

    func load(_ rules: [WarningKind: WarningRule]) {
        isLoading = true
        for kind in WarningKind.allCases {
            let rule = rules[kind] ?? .defaultRule(for: kind)
            enableButtons[kind]?.state = rule.isEnabled ? .on : .off
            thresholdFields[kind]?.stringValue = formatted(rule.threshold)
            durationFields[kind]?.stringValue = formatted(rule.durationMinutes)
            updateEnabledState(for: kind)
        }
        isLoading = false
    }

    private func buildView() {
        let heading = NSStackView(views: [
            header(LocalizedText.text("Aktiv", "On"), width: 58),
            header(LocalizedText.text("Warnung", "Warning"), width: 205),
            header(LocalizedText.text("Schwelle", "Threshold"), width: 120),
            header(LocalizedText.text("Dauer", "Duration"), width: 150),
            header(LocalizedText.text("Info", "Info"), width: 30)
        ])
        heading.orientation = .horizontal
        heading.spacing = 8

        let rows = NSStackView()
        rows.orientation = .vertical
        rows.spacing = 9
        for kind in WarningKind.allCases {
            rows.addArrangedSubview(makeRow(for: kind))
        }

        let solarHint = NSTextField(wrappingLabelWithString: LocalizedText.text(
            "Solar-Einbruch vergleicht die aktuelle Leistung mit dem höchsten Wert der letzten 30 Minuten. Unter 100 W Ausgangsleistung wird kein Einbruch ausgelöst, damit nachts keine Warnung erscheint.",
            "Solar drop compares current output with the highest value from the last 30 minutes. No drop is triggered below a 100 W baseline, avoiding alerts at night."
        ))
        solarHint.textColor = .secondaryLabelColor
        solarHint.font = .systemFont(ofSize: 11)

        let notificationHint = NSTextField(wrappingLabelWithString: LocalizedText.text(
            "Beim Aktivieren fragt macOS einmal nach der Erlaubnis für Mitteilungen. Jede Warnung wird nur einmal gesendet und erst nach Normalisierung erneut aktiviert.",
            "When enabled, macOS asks once for notification permission. Each warning is sent once and is armed again only after the value returns to normal."
        ))
        notificationHint.textColor = .secondaryLabelColor

        for view in [heading, rows, solarHint, notificationHint] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: topAnchor),
            heading.leadingAnchor.constraint(equalTo: leadingAnchor),
            rows.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 8),
            rows.leadingAnchor.constraint(equalTo: leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor),
            solarHint.topAnchor.constraint(equalTo: rows.bottomAnchor, constant: 14),
            solarHint.leadingAnchor.constraint(equalTo: leadingAnchor),
            solarHint.trailingAnchor.constraint(equalTo: trailingAnchor),
            notificationHint.topAnchor.constraint(equalTo: solarHint.bottomAnchor, constant: 10),
            notificationHint.leadingAnchor.constraint(equalTo: leadingAnchor),
            notificationHint.trailingAnchor.constraint(equalTo: trailingAnchor),
            notificationHint.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }

    private func makeRow(for kind: WarningKind) -> NSView {
        let enabled = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleRule(_:)))
        enabled.tag = WarningKind.allCases.firstIndex(of: kind) ?? 0
        enabled.widthAnchor.constraint(equalToConstant: 58).isActive = true
        enableButtons[kind] = enabled

        let title = NSTextField(labelWithString: kind.title)
        title.widthAnchor.constraint(equalToConstant: 205).isActive = true

        let threshold = NSTextField()
        threshold.alignment = .right
        threshold.placeholderString = formatted(kind.defaultThreshold)
        threshold.delegate = self
        threshold.widthAnchor.constraint(equalToConstant: 76).isActive = true
        thresholdFields[kind] = threshold
        let unit = NSTextField(labelWithString: kind.unit)
        unit.widthAnchor.constraint(equalToConstant: 36).isActive = true
        let thresholdStack = NSStackView(views: [threshold, unit])
        thresholdStack.orientation = .horizontal
        thresholdStack.spacing = 5
        thresholdStack.widthAnchor.constraint(equalToConstant: 120).isActive = true

        let duration = NSTextField()
        duration.alignment = .right
        duration.placeholderString = formatted(kind.defaultDurationMinutes)
        duration.delegate = self
        duration.widthAnchor.constraint(equalToConstant: 62).isActive = true
        durationFields[kind] = duration
        let minutes = NSTextField(labelWithString: LocalizedText.text("Minuten", "minutes"))
        let durationStack = NSStackView(views: [duration, minutes])
        durationStack.orientation = .horizontal
        durationStack.spacing = 5
        durationStack.widthAnchor.constraint(equalToConstant: 150).isActive = true

        let help = helpButton(for: kind)
        let row = NSStackView(views: [enabled, title, thresholdStack, durationStack, help])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func helpButton(for kind: WarningKind) -> NSButton {
        let button = NSButton(title: "?", target: nil, action: nil)
        button.isBordered = false
        button.font = .systemFont(ofSize: 12, weight: .bold)
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = warningTooltip(for: kind)
        button.setButtonType(.momentaryChange)
        button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        button.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return button
    }

    private func warningTooltip(for kind: WarningKind) -> String {
        switch kind {
        case .batteryLow:
            LocalizedText.text("Warnt, wenn der Akkustand mindestens für die eingestellte Dauer unter der Schwelle liegt.", "Warns when the battery level stays below the threshold for at least the configured duration.")
        case .solarDrop:
            LocalizedText.text("Warnt, wenn die Solarleistung gegenüber dem 30-Minuten-Höchstwert um mindestens diesen Prozentsatz einbricht und der Einbruch so lange anhält.", "Warns when solar output drops by at least this percentage from the 30-minute peak and remains low for the configured duration.")
        case .homeHigh:
            LocalizedText.text("Warnt, wenn die Hauslast mindestens für die eingestellte Dauer über der Watt-Schwelle liegt.", "Warns when home load stays above the watt threshold for the configured duration.")
        case .gridImportHigh:
            LocalizedText.text("Warnt bei anhaltend hohem Strombezug aus dem Netz.", "Warns when grid import remains above the configured threshold.")
        case .gridExportHigh:
            LocalizedText.text("Warnt bei anhaltend hoher Einspeisung in das Netz.", "Warns when grid export remains above the configured threshold.")
        case .batteryChargeHigh:
            LocalizedText.text("Warnt bei anhaltend hoher Ladeleistung des Akkus.", "Warns when battery charging power remains above the configured threshold.")
        case .batteryDischargeHigh:
            LocalizedText.text("Warnt bei anhaltend hoher Entladeleistung des Akkus.", "Warns when battery discharging power remains above the configured threshold.")
        }
    }

    private func header(_ text: String, width: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
        return label
    }

    @objc private func toggleRule(_ sender: NSButton) {
        let kind = WarningKind.allCases[sender.tag]
        updateEnabledState(for: kind)
        changed()
    }

    func controlTextDidChange(_ obj: Notification) {
        changed()
    }

    private func updateEnabledState(for kind: WarningKind) {
        let enabled = enableButtons[kind]?.state == .on
        thresholdFields[kind]?.isEnabled = enabled
        durationFields[kind]?.isEnabled = enabled
    }

    private func changed() {
        guard !isLoading else { return }
        onChange(rules)
    }

    private func parsed(_ value: String?, fallback: Double) -> Double {
        guard let value else { return fallback }
        return Double(value.replacingOccurrences(of: ",", with: ".")) ?? fallback
    }

    private func formatted(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}
