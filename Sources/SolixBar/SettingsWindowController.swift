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
    private let solixEmailField = NSTextField()
    private let solixPasswordField = NSSecureTextField()
    private let solixCountryField = NSTextField()
    private let commandRow = NSStackView()
    private let urlRow = NSStackView()
    private let solixTitle = NSTextField(labelWithString: "SOLIX Login")
    private let solixHint = NSTextField(wrappingLabelWithString: "Nur fuer den vorbereiteten SOLIX-Befehl. Mail und Passwort werden lokal gespeichert.")
    private let solixEmailRow = NSStackView()
    private let solixPasswordRow = NSStackView()
    private let solixCountryRow = NSStackView()
    private let autostartButton = NSButton(checkboxWithTitle: "Beim Login automatisch starten", target: nil, action: nil)
    private let autostartStatus = NSTextField(labelWithString: "")
    private let showIconButton = NSButton(checkboxWithTitle: "App-Symbol in der Menüleiste anzeigen", target: nil, action: nil)
    private let showLabelsButton = NSButton(checkboxWithTitle: "Werte mit Bezeichnung anzeigen", target: nil, action: nil)
    private let showMetricSymbolsButton = NSButton(checkboxWithTitle: "Symbole vor den Werten anzeigen", target: nil, action: nil)
    private let showEnergyFlowArrowsButton = NSButton(checkboxWithTitle: "Farbige Pfeile beim Energiefluss anzeigen", target: nil, action: nil)
    private let scaleSlider = NSSlider(value: 1.0, minValue: 0.75, maxValue: 1.6, target: nil, action: nil)
    private let scaleValue = NSTextField(labelWithString: "100 %")
    private let detachedScaleSlider = NSSlider(value: 1.0, minValue: 0.75, maxValue: 1.9, target: nil, action: nil)
    private let detachedScaleValue = NSTextField(labelWithString: "100 %")
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
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 660),
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
        commandField.placeholderString = solixHelperCommand
        commandField.toolTip = "Führt einen lokalen Befehl aus und liest dessen JSON-Ausgabe."
        urlField.placeholderString = "http://127.0.0.1:8787/solix.json"
        urlField.toolTip = "Lädt die Werte von einer JSON-Adresse."
        intervalField.placeholderString = "300"
        intervalField.toolTip = "Zeit zwischen zwei Aktualisierungen in Sekunden."
        solixEmailField.placeholderString = "mail@example.com"
        solixEmailField.toolTip = "E-Mail-Adresse deines Anker/SOLIX-Kontos."
        solixPasswordField.placeholderString = "Passwort"
        solixPasswordField.toolTip = "Passwort deines Anker/SOLIX-Kontos. Wird lokal in work/solixbar.env gespeichert und nicht hochgeladen."
        solixCountryField.placeholderString = "DE"
        solixCountryField.toolTip = "Land deines Anker-Kontos, normalerweise DE."

        for textField in [commandField, urlField, intervalField, solixEmailField, solixPasswordField, solixCountryField] {
            textField.delegate = self
        }

        for control in [modePopup, showIconButton, showLabelsButton, showMetricSymbolsButton, showEnergyFlowArrowsButton, scaleSlider, detachedScaleSlider] {
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
        showEnergyFlowArrowsButton.toolTip = "Schaltet die farbigen Richtungspfeile für das Energiefluss-Feld und einzelne Energie-Werte ein oder aus."
        scaleSlider.toolTip = "Vergrößert oder verkleinert Text und Symbole in der Menüleiste."
        scaleValue.toolTip = "Aktuell eingestellte Größe der Menüleistenanzeige."
        detachedScaleSlider.toolTip = "Vergrößert oder verkleinert nur die abgedockte Menüleistenanzeige."
        detachedScaleValue.toolTip = "Aktuell eingestellte Größe der abgedockten Leiste."

        let title = NSTextField(labelWithString: "SOLIX Bar \(AppVersion.short)")
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
        let detachedScaleRow = NSStackView(views: [label("Abgedockt"), detachedScaleSlider, detachedScaleValue])
        detachedScaleRow.orientation = .horizontal
        detachedScaleRow.spacing = 12
        detachedScaleValue.alignment = .right
        detachedScaleValue.widthAnchor.constraint(equalToConstant: 56).isActive = true

        for view in [metricTitle, metricGrid, displayTitle, showIconButton, showLabelsButton, showMetricSymbolsButton, showEnergyFlowArrowsButton, scaleRow, detachedScaleRow] {
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

            showEnergyFlowArrowsButton.topAnchor.constraint(equalTo: showMetricSymbolsButton.bottomAnchor, constant: 8),
            showEnergyFlowArrowsButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            scaleRow.topAnchor.constraint(equalTo: showEnergyFlowArrowsButton.bottomAnchor, constant: 16),
            scaleRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            scaleRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),

            detachedScaleRow.topAnchor.constraint(equalTo: scaleRow.bottomAnchor, constant: 10),
            detachedScaleRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            detachedScaleRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24)
        ])

        return container
    }

    private func dataSourcePane() -> NSView {
        let container = NSView()
        let title = sectionTitle("Datenquelle")
        let hint = NSTextField(wrappingLabelWithString: "Die gewählte Datenquelle muss ein JSON-Objekt mit Feldern wie batteryPercent, solarWatts, homeWatts und updatedAt liefern. Mindestintervall: 60 Sekunden.")
        hint.textColor = .secondaryLabelColor

        let rows = NSStackView()
        rows.orientation = .vertical
        rows.spacing = 12

        solixTitle.font = .boldSystemFont(ofSize: 13)
        solixHint.textColor = .secondaryLabelColor

        rows.addArrangedSubview(formRow(labelText: "Modus", control: modePopup))
        rows.addArrangedSubview(solixTitle)
        configure(row: solixEmailRow, labelText: "Mail", control: solixEmailField)
        configure(row: solixPasswordRow, labelText: "Passwort", control: solixPasswordField)
        configure(row: solixCountryRow, labelText: "Land", control: solixCountryField)
        rows.addArrangedSubview(solixEmailRow)
        rows.addArrangedSubview(solixPasswordRow)
        rows.addArrangedSubview(solixCountryRow)
        rows.addArrangedSubview(solixHint)
        configure(row: commandRow, labelText: "Befehl", control: commandField)
        configure(row: urlRow, labelText: "URL", control: urlField)
        rows.addArrangedSubview(commandRow)
        rows.addArrangedSubview(urlRow)
        rows.addArrangedSubview(formRow(labelText: "Intervall", control: intervalField))

        for view in [title, rows, hint] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 22),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            rows.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            rows.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            rows.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),

            hint.topAnchor.constraint(equalTo: rows.bottomAnchor, constant: 18),
            hint.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            hint.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24)
        ])

        return container
    }

    private func formRow(labelText: String, control: NSView) -> NSStackView {
        let row = NSStackView()
        configure(row: row, labelText: labelText, control: control)
        return row
    }

    private func configure(row: NSStackView, labelText: String, control: NSView) {
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY

        let rowLabel = label(labelText)
        rowLabel.alignment = .right
        rowLabel.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(rowLabel)
        row.addArrangedSubview(control)

        NSLayoutConstraint.activate([
            rowLabel.widthAnchor.constraint(equalToConstant: 88),
            control.widthAnchor.constraint(equalToConstant: 450)
        ])
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
            [BarMetric.grid, .batteryFlow, .flow],
            [BarMetric.today, .total, .status]
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
        case .flow:
            return "Zeigt das Energiefluss-Feld in der Menüleiste. Die Pfeile erscheinen, wenn die Pfeil-Option aktiviert ist."
        case .today:
            return "Zeigt den heutigen Solarertrag in kWh."
        case .total:
            return "Zeigt den gesamten bisher gemessenen Solarertrag in kWh."
        case .status:
            return "Zeigt den aktuellen Status der Datenquelle."
        }
    }

    private func labelTooltip(_ text: String) -> String {
        switch text {
        case "Skalierung":
            return "Passt die Größe der Menüleistenanzeige an."
        case "Abgedockt":
            return "Passt nur die Größe der abgedockten Menüleistenleiste an."
        case "Modus":
            return "Wählt Demo, lokalen JSON-Befehl oder JSON-URL."
        case "Mail":
            return "E-Mail-Adresse deines Anker/SOLIX-Kontos."
        case "Passwort":
            return "Passwort deines Anker/SOLIX-Kontos."
        case "Land":
            return "Land des Anker-Kontos, meistens DE."
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
        loadSolixCredentials()
        showIconButton.state = settings.showMenuBarIcon ? .on : .off
        showLabelsButton.state = settings.showMetricLabels ? .on : .off
        showMetricSymbolsButton.state = settings.showMenuBarMetricSymbols ? .on : .off
        showEnergyFlowArrowsButton.state = settings.showEnergyFlowArrows ? .on : .off
        scaleSlider.doubleValue = settings.menuBarScale
        scaleValue.stringValue = "\(Int(round(scaleSlider.doubleValue * 100))) %"
        detachedScaleSlider.doubleValue = settings.detachedMenuBarScale
        detachedScaleValue.stringValue = "\(Int(round(detachedScaleSlider.doubleValue * 100))) %"

        let selected = Set(settings.barMetrics)
        for metric in BarMetric.allCases {
            metricButtons[metric]?.state = selected.contains(metric) ? .on : .off
        }
        refreshAutostartState()
        updateDataSourceFieldVisibility()
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
        settings.showEnergyFlowArrows = showEnergyFlowArrowsButton.state == .on
        settings.menuBarScale = scaleSlider.doubleValue
        settings.detachedMenuBarScale = detachedScaleSlider.doubleValue
        if settings.dataSourceMode == .command && shouldUseSolixHelper {
            settings.dataSourceMode = .command
            settings.command = solixHelperCommand
            commandField.stringValue = solixHelperCommand
            modePopup.selectItem(at: 1)
        }
        updateDataSourceFieldVisibility()
    }

    private func updateDataSourceFieldVisibility() {
        switch modePopup.indexOfSelectedItem {
        case 1:
            commandRow.isHidden = false
            urlRow.isHidden = true
            setSolixRowsHidden(false)
        case 2:
            commandRow.isHidden = true
            urlRow.isHidden = false
            setSolixRowsHidden(true)
        default:
            commandRow.isHidden = true
            urlRow.isHidden = true
            setSolixRowsHidden(true)
        }
    }

    private func setSolixRowsHidden(_ hidden: Bool) {
        solixTitle.isHidden = hidden
        solixHint.isHidden = hidden
        solixEmailRow.isHidden = hidden
        solixPasswordRow.isHidden = hidden
        solixCountryRow.isHidden = hidden
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
        detachedScaleValue.stringValue = "\(Int(round(detachedScaleSlider.doubleValue * 100))) %"
        applyControlsToSettings()
        onPreview()
    }

    @objc private func cancelSettings() {
        window?.close()
    }

    @objc private func saveSettings() {
        isSaving = true
        applyControlsToSettings()
        if settings.dataSourceMode == .command {
            saveSolixCredentialsIfNeeded()
            if shouldUseSolixHelper {
                settings.command = solixHelperCommand
                commandField.stringValue = solixHelperCommand
            }
        }
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

    private var shouldUseSolixHelper: Bool {
        !solixEmailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !solixPasswordField.stringValue.isEmpty
            || !solixCountryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var solixHelperCommand: String {
        "/Users/holger/Documents/Codex/2026-07-06/bi/scripts/run_solix_snapshot.sh"
    }

    private var solixEnvURL: URL {
        URL(fileURLWithPath: "/Users/holger/Documents/Codex/2026-07-06/bi/work/solixbar.env")
    }

    private func loadSolixCredentials() {
        let values = readSolixEnv()
        solixEmailField.stringValue = values["ANKER_SOLIX_USER"] ?? ""
        solixPasswordField.stringValue = values["ANKER_SOLIX_PASSWORD"] ?? ""
        solixCountryField.stringValue = values["ANKER_SOLIX_COUNTRY"] ?? "DE"
    }

    private func saveSolixCredentialsIfNeeded() {
        guard shouldUseSolixHelper else { return }
        let email = solixEmailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = solixPasswordField.stringValue
        let country = solixCountryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "DE"
            : solixCountryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        let text = [
            "ANKER_SOLIX_USER=\(shellQuoted(email))",
            "ANKER_SOLIX_PASSWORD=\(shellQuoted(password))",
            "ANKER_SOLIX_COUNTRY=\(shellQuoted(country))"
        ].joined(separator: "\n") + "\n"

        do {
            try FileManager.default.createDirectory(at: solixEnvURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: solixEnvURL, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func readSolixEnv() -> [String: String] {
        guard let text = try? String(contentsOf: solixEnvURL, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<equals])
            let value = String(line[line.index(after: equals)...])
            values[key] = unquoteShellValue(value)
        }
        return values
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func unquoteShellValue(_ value: String) -> String {
        var value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
            value.removeFirst()
            value.removeLast()
            return value.replacingOccurrences(of: "'\\''", with: "'")
        }
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value.removeFirst()
            value.removeLast()
        }
        return value
    }
}
