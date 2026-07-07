import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private let settings = AppSettings.shared
    private let onPreview: () -> Void
    private let onSave: () -> Void
    private let onReset: () -> Void

    private let modePopup = NSPopUpButton()
    private let commandField = NSTextField()
    private let urlField = NSTextField()
    private let intervalField = NSTextField()
    private let autostartButton = NSButton(checkboxWithTitle: "Beim Login automatisch starten", target: nil, action: nil)
    private let autostartStatus = NSTextField(labelWithString: "")
    private let showIconButton = NSButton(checkboxWithTitle: "App-Symbol in der Menüleiste anzeigen", target: nil, action: nil)
    private let showLabelsButton = NSButton(checkboxWithTitle: "Werte mit Bezeichnung anzeigen", target: nil, action: nil)
    private let showMetricSymbolsButton = NSButton(checkboxWithTitle: "Symbole vor den Werten anzeigen", target: nil, action: nil)
    private let scaleSlider = NSSlider(value: 1.0, minValue: 0.75, maxValue: 1.6, target: nil, action: nil)
    private let scaleValue = NSTextField(labelWithString: "100 %")
    private var metricButtons: [BarMetric: NSButton] = [:]
    private var originalSettings: AppSettingsSnapshot?
    private var originalAutostart = false
    private var isSaving = false
    private var isLoading = false

    init(onPreview: @escaping () -> Void, onSave: @escaping () -> Void, onReset: @escaping () -> Void) {
        self.onPreview = onPreview
        self.onSave = onSave
        self.onReset = onReset
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SOLIX Bar Einstellungen"
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = buildView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        originalSettings = settings.snapshot()
        originalAutostart = AutostartManager.isEnabled
        isSaving = false
        loadSettings()
        super.showWindow(sender)
    }

    private func buildView() -> NSView {
        let container = NSView()

        modePopup.addItems(withTitles: ["Demo", "Lokaler JSON-Befehl", "JSON-URL"])
        modePopup.toolTip = "Legt fest, woher SolixBar die Werte lädt."
        commandField.placeholderString = "/usr/bin/env python3 scripts/solix_snapshot.py"
        commandField.toolTip = "Führt einen lokalen Befehl aus und liest dessen JSON-Ausgabe."
        urlField.placeholderString = "http://127.0.0.1:8787/solix.json"
        urlField.toolTip = "Lädt die Werte von einer JSON-Adresse."
        intervalField.placeholderString = "300"
        intervalField.toolTip = "Zeit zwischen zwei Aktualisierungen in Sekunden."

        for textField in [commandField, urlField, intervalField] {
            textField.delegate = self
        }

        for control in [modePopup, showIconButton, showLabelsButton, showMetricSymbolsButton, scaleSlider] {
            control.target = self
            control.action = #selector(applyPreview)
        }
        autostartButton.target = self
        autostartButton.action = #selector(toggleAutostart)
        autostartButton.toolTip = "Startet SolixBar automatisch nach dem Anmelden."
        autostartStatus.textColor = .secondaryLabelColor
        autostartStatus.lineBreakMode = .byTruncatingMiddle
        showIconButton.toolTip = "Zeigt oder versteckt das SolixBar-Symbol in der Menüleiste."
        showLabelsButton.toolTip = "Zeigt kurze Namen wie Akku oder Solar vor den Zahlen."
        showMetricSymbolsButton.toolTip = "Zeigt farbige Symbole direkt vor den Menüleistenwerten."
        scaleSlider.toolTip = "Vergrößert oder verkleinert Text und Symbole in der Menüleiste."
        scaleValue.toolTip = "Aktuell eingestellte Größe der Menüleistenanzeige."

        let title = NSTextField(labelWithString: "SOLIX Bar")
        title.font = .boldSystemFont(ofSize: 20)

        let tabs = NSTabView()
        tabs.tabViewType = .topTabsBezelBorder
        tabs.addTabViewItem(tab(title: "Menüleiste", view: menuBarPane()))
        tabs.addTabViewItem(tab(title: "Datenquelle", view: dataSourcePane()))
        tabs.addTabViewItem(tab(title: "Start", view: startupPane()))

        let cancel = NSButton(title: "Abbrechen", target: self, action: #selector(cancelSettings))
        cancel.bezelStyle = .rounded
        cancel.toolTip = "Verwirft die Vorschau und stellt die alten Einstellungen wieder her."

        let save = NSButton(title: "Speichern", target: self, action: #selector(saveSettings))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        save.toolTip = "Speichert die aktuellen Einstellungen dauerhaft."

        for view in [title, tabs, cancel, save] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            tabs.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            tabs.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            tabs.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            tabs.bottomAnchor.constraint(equalTo: save.topAnchor, constant: -18),

            cancel.trailingAnchor.constraint(equalTo: save.leadingAnchor, constant: -10),
            cancel.centerYAnchor.constraint(equalTo: save.centerYAnchor),

            save.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            save.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24)
        ])

        return container
    }

    private func tab(title: String, view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        item.view = view
        return item
    }

    private func menuBarPane() -> NSView {
        let container = NSView()
        let metricTitle = sectionTitle("Angezeigte Werte")
        let metricGrid = buildMetricGrid()
        let displayTitle = sectionTitle("Darstellung")
        let scaleRow = NSStackView(views: [label("Skalierung"), scaleSlider, scaleValue])
        scaleRow.orientation = .horizontal
        scaleRow.spacing = 12
        scaleValue.alignment = .right
        scaleValue.widthAnchor.constraint(equalToConstant: 56).isActive = true

        for view in [metricTitle, metricGrid, displayTitle, showIconButton, showLabelsButton, showMetricSymbolsButton, scaleRow] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }

        NSLayoutConstraint.activate([
            metricTitle.topAnchor.constraint(equalTo: container.topAnchor, constant: 22),
            metricTitle.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            metricGrid.topAnchor.constraint(equalTo: metricTitle.bottomAnchor, constant: 10),
            metricGrid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            metricGrid.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),

            displayTitle.topAnchor.constraint(equalTo: metricGrid.bottomAnchor, constant: 24),
            displayTitle.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            showIconButton.topAnchor.constraint(equalTo: displayTitle.bottomAnchor, constant: 10),
            showIconButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            showLabelsButton.topAnchor.constraint(equalTo: showIconButton.bottomAnchor, constant: 8),
            showLabelsButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            showMetricSymbolsButton.topAnchor.constraint(equalTo: showLabelsButton.bottomAnchor, constant: 8),
            showMetricSymbolsButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            scaleRow.topAnchor.constraint(equalTo: showMetricSymbolsButton.bottomAnchor, constant: 16),
            scaleRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            scaleRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24)
        ])

        return container
    }

    private func dataSourcePane() -> NSView {
        let container = NSView()
        let title = sectionTitle("Datenquelle")
        let hint = NSTextField(wrappingLabelWithString: "Der Befehl oder die URL muss ein JSON-Objekt mit Feldern wie batteryPercent, solarWatts, homeWatts und updatedAt liefern. Mindestintervall: 60 Sekunden.")
        hint.textColor = .secondaryLabelColor

        let grid = NSGridView(views: [
            [label("Modus"), modePopup],
            [label("Befehl"), commandField],
            [label("URL"), urlField],
            [label("Intervall"), intervalField]
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 450
        grid.rowSpacing = 12
        grid.columnSpacing = 12

        for view in [title, grid, hint] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 22),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            grid.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),

            hint.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 18),
            hint.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            hint.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24)
        ])

        return container
    }

    private func startupPane() -> NSView {
        let container = NSView()
        let title = sectionTitle("Startverhalten")

        for view in [title, autostartButton, autostartStatus] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 22),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            autostartButton.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            autostartButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            autostartButton.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),

            autostartStatus.topAnchor.constraint(equalTo: autostartButton.bottomAnchor, constant: 8),
            autostartStatus.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            autostartStatus.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24)
        ])

        return container
    }

    private func buildMetricGrid() -> NSGridView {
        let rows = [
            [BarMetric.battery, .solar, .home],
            [BarMetric.grid, .batteryFlow, .today],
            [BarMetric.status]
        ].map { metrics in
            metrics.map { metric in
                let button = NSButton(checkboxWithTitle: metric.title, target: self, action: #selector(applyPreview))
                button.toolTip = metricTooltip(metric)
                metricButtons[metric] = button
                return button
            }
        }

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 6
        grid.columnSpacing = 16
        return grid
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 13)
        return label
    }

    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = .secondaryLabelColor
        label.toolTip = labelTooltip(text)
        return label
    }

    private func metricTooltip(_ metric: BarMetric) -> String {
        switch metric {
        case .battery:
            return "Zeigt den aktuellen Akkustand in Prozent in der Menüleiste."
        case .solar:
            return "Zeigt die aktuelle Solarleistung in Watt in der Menüleiste."
        case .home:
            return "Zeigt den aktuellen Hausverbrauch in Watt in der Menüleiste."
        case .grid:
            return "Zeigt den aktuellen Netzbezug oder die Einspeisung in Watt."
        case .batteryFlow:
            return "Zeigt, ob der Akku gerade lädt oder entlädt."
        case .today:
            return "Zeigt den heutigen Solarertrag in kWh."
        case .status:
            return "Zeigt den aktuellen Status der Datenquelle."
        }
    }

    private func labelTooltip(_ text: String) -> String {
        switch text {
        case "Skalierung":
            return "Passt die Größe der Menüleistenanzeige an."
        case "Modus":
            return "Wählt Demo, lokalen JSON-Befehl oder JSON-URL."
        case "Befehl":
            return "Der lokale Befehl muss ein JSON-Objekt ausgeben."
        case "URL":
            return "Die Adresse muss ein JSON-Objekt liefern."
        case "Intervall":
            return "Legt fest, wie oft neue Daten geholt werden."
        default:
            return text
        }
    }

    private func loadSettings() {
        isLoading = true
        switch settings.dataSourceMode {
        case .demo:
            modePopup.selectItem(at: 0)
        case .command:
            modePopup.selectItem(at: 1)
        case .url:
            modePopup.selectItem(at: 2)
        }
        commandField.stringValue = settings.command
        urlField.stringValue = settings.urlString
        intervalField.stringValue = String(Int(settings.refreshInterval))
        showIconButton.state = settings.showMenuBarIcon ? .on : .off
        showLabelsButton.state = settings.showMetricLabels ? .on : .off
        showMetricSymbolsButton.state = settings.showMenuBarMetricSymbols ? .on : .off
        scaleSlider.doubleValue = settings.menuBarScale
        scaleValue.stringValue = "\(Int(round(scaleSlider.doubleValue * 100))) %"

        let selected = Set(settings.barMetrics)
        for metric in BarMetric.allCases {
            metricButtons[metric]?.state = selected.contains(metric) ? .on : .off
        }
        refreshAutostartState()
        isLoading = false
    }

    private func refreshAutostartState(message: String? = nil) {
        autostartButton.state = AutostartManager.isEnabled ? .on : .off
        if let message {
            autostartStatus.stringValue = message
        } else {
            autostartStatus.stringValue = AutostartManager.isEnabled
                ? "Autostart ist aktiv."
                : "Autostart ist deaktiviert."
        }
    }

    private func applyControlsToSettings() {
        switch modePopup.indexOfSelectedItem {
        case 1:
            settings.dataSourceMode = .command
        case 2:
            settings.dataSourceMode = .url
        default:
            settings.dataSourceMode = .demo
        }
        settings.command = commandField.stringValue
        settings.urlString = urlField.stringValue
        settings.refreshInterval = TimeInterval(max(60, intervalField.integerValue))
        settings.barMetrics = BarMetric.allCases.filter { metricButtons[$0]?.state == .on }
        settings.showMenuBarIcon = showIconButton.state == .on
        settings.showMetricLabels = showLabelsButton.state == .on
        settings.showMenuBarMetricSymbols = showMetricSymbolsButton.state == .on
        settings.menuBarScale = scaleSlider.doubleValue
    }

    private func restoreOriginalSettings() {
        if let originalSettings {
            settings.apply(originalSettings)
        }
        if AutostartManager.isEnabled != originalAutostart {
            try? AutostartManager.setEnabled(originalAutostart)
        }
        refreshAutostartState()
        onReset()
    }

    @objc private func toggleAutostart() {
        do {
            try AutostartManager.setEnabled(autostartButton.state == .on)
            refreshAutostartState()
        } catch {
            refreshAutostartState(message: "Autostart konnte nicht geändert werden: \(error.localizedDescription)")
        }
    }

    @objc private func applyPreview() {
        guard !isLoading else { return }
        scaleValue.stringValue = "\(Int(round(scaleSlider.doubleValue * 100))) %"
        applyControlsToSettings()
        onPreview()
    }

    @objc private func cancelSettings() {
        window?.close()
    }

    @objc private func saveSettings() {
        isSaving = true
        applyControlsToSettings()
        onSave()
        window?.close()
    }

    func controlTextDidChange(_ obj: Notification) {
        applyPreview()
    }

    func windowWillClose(_ notification: Notification) {
        guard !isSaving else { return }
        restoreOriginalSettings()
    }
}
