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
    private let solixTodayBaseField = NSTextField()
    private let solixTotalBaseField = NSTextField()
    private let commandRow = NSStackView()
    private let urlRow = NSStackView()
    private let solixTitle = NSTextField(labelWithString: "SOLIX Login")
    private let solixHint = NSTextField(wrappingLabelWithString: "Nur fuer den vorbereiteten SOLIX-Befehl. Mail und Passwort werden lokal gespeichert.")
    private let solixEmailRow = NSStackView()
    private let solixPasswordRow = NSStackView()
    private let solixCountryRow = NSStackView()
    private let solixTodayBaseRow = NSStackView()
    private let solixTotalBaseRow = NSStackView()
    private let autostartButton = NSButton(checkboxWithTitle: "Beim Login automatisch starten", target: nil, action: nil)
    private let autostartStatus = NSTextField(labelWithString: "")
    private let showIconButton = NSButton(checkboxWithTitle: "App-Symbol in der Menüleiste anzeigen", target: nil, action: nil)
    private let showLabelsButton = NSButton(checkboxWithTitle: "Werte mit Bezeichnung anzeigen", target: nil, action: nil)
    private let showMetricSymbolsButton = NSButton(checkboxWithTitle: "Symbole vor den Werten anzeigen", target: nil, action: nil)
    private let showEnergyFlowArrowsButton = NSButton(checkboxWithTitle: "Farbige Pfeile beim Energiefluss anzeigen", target: nil, action: nil)
    private let lockDetachedMenuBarButton = NSButton(checkboxWithTitle: "Abgedockte Leiste fixieren", target: nil, action: nil)
    private let scaleSlider = NSSlider(value: 1.0, minValue: 0.75, maxValue: 1.6, target: nil, action: nil)
    private let scaleValue = NSTextField(labelWithString: "100 %")
    private let detachedScaleSlider = NSSlider(value: 1.0, minValue: 0.75, maxValue: 1.9, target: nil, action: nil)
    private let detachedScaleValue = NSTextField(labelWithString: "100 %")
    private let appearancePopup = NSPopUpButton()
    private let languagePopup = NSPopUpButton()
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
        window.title = LocalizedText.text("SOLIX Bar Einstellungen", "SOLIX Bar Settings")
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
        appearancePopup.addItems(withTitles: ["Automatisch", "Hell", "Dunkel"])
        languagePopup.addItems(withTitles: ["Deutsch", "English"])
        applyLocalizedControlTitles()
        modePopup.toolTip = "Legt fest, woher SolixBar die Werte lädt."
        appearancePopup.toolTip = "Waehlt helle Darstellung, dunkle Darstellung oder automatisch passend zum macOS-System."
        languagePopup.toolTip = "Waehlt die Sprache fuer sichtbare App-Texte."
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
        solixTodayBaseField.placeholderString = "z.B. 7.2"
        solixTodayBaseField.toolTip = "Optionaler Korrekturwert fuer den heutigen Ertrag in kWh, falls Anker heute 0 kWh meldet. SolixBar zaehlt ab diesem Wert weiter."
        solixTotalBaseField.placeholderString = "z.B. 427.8"
        solixTotalBaseField.toolTip = LocalizedText.text(
            "Optionaler Startwert fuer den Gesamtertrag. Ohne API-Gesamtwert kumuliert SolixBar alle fortlaufenden Solarmessungen lokal.",
            "Optional starting value for total yield. Without an API total, SolixBar locally accumulates all continuous solar measurements."
        )

        for textField in [commandField, urlField, intervalField, solixEmailField, solixPasswordField, solixCountryField, solixTodayBaseField, solixTotalBaseField] {
            textField.delegate = self
        }

        for control in [modePopup, appearancePopup, languagePopup, showIconButton, showLabelsButton, showMetricSymbolsButton, showEnergyFlowArrowsButton, lockDetachedMenuBarButton, scaleSlider, detachedScaleSlider] {
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
        showEnergyFlowArrowsButton.toolTip = "Schaltet kontrastreiche Flussfarben, Richtungspfeile und Begriffe wie Laden, Entladen, Bezug und Einspeisen gemeinsam ein oder aus."
        lockDetachedMenuBarButton.toolTip = "Fixiert die abgedockte Leiste, damit sie nicht versehentlich verschoben wird."
        scaleSlider.toolTip = "Vergrößert oder verkleinert Text und Symbole in der Menüleiste."
        scaleValue.toolTip = "Aktuell eingestellte Größe der Menüleistenanzeige."
        detachedScaleSlider.toolTip = "Vergrößert oder verkleinert nur die abgedockte Menüleistenanzeige."
        detachedScaleValue.toolTip = "Aktuell eingestellte Größe der abgedockten Leiste."

        let title = NSTextField(labelWithString: "SOLIX Bar \(AppVersion.short)")
        title.font = .boldSystemFont(ofSize: 20)

        let tabs = NSTabView()
        tabs.tabViewType = .topTabsBezelBorder
        tabs.addTabViewItem(tab(title: LocalizedText.text("Menüleiste", "Menu Bar"), view: menuBarPane()))
        tabs.addTabViewItem(tab(title: LocalizedText.text("Datenquelle", "Data Source"), view: dataSourcePane()))
        tabs.addTabViewItem(tab(title: LocalizedText.text("App", "App"), view: appPane()))
        tabs.addTabViewItem(tab(title: LocalizedText.text("Start", "Startup"), view: startupPane()))

        let cancel = NSButton(title: LocalizedText.text("Abbrechen", "Cancel"), target: self, action: #selector(cancelSettings))
        cancel.bezelStyle = .rounded
        cancel.toolTip = "Verwirft die Vorschau und stellt die alten Einstellungen wieder her."

        let save = NSButton(title: LocalizedText.text("Speichern", "Save"), target: self, action: #selector(saveSettings))
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

    private func applyLocalizedControlTitles() {
        showIconButton.title = LocalizedText.text("App-Symbol in der Menüleiste anzeigen", "Show app icon in the menu bar")
        showLabelsButton.title = LocalizedText.text("Werte mit Bezeichnung anzeigen", "Show labels next to values")
        showMetricSymbolsButton.title = LocalizedText.text("Symbole vor den Werten anzeigen", "Show symbols before values")
        showEnergyFlowArrowsButton.title = LocalizedText.text("Farben und Flussrichtung anzeigen", "Show colors and flow direction")
        lockDetachedMenuBarButton.title = LocalizedText.text("Abgedockte Leiste fixieren", "Lock detached slim bar")
        autostartButton.title = LocalizedText.text("Beim Login automatisch starten", "Start automatically at login")
    }

    private func menuBarPane() -> NSView {
        let container = NSView()
        let metricTitle = sectionTitle(LocalizedText.text("Angezeigte Werte", "Visible Values"))
        let metricGrid = buildMetricGrid()
        let displayTitle = sectionTitle(LocalizedText.text("Darstellung", "Display"))
        let showIconRow = settingRow(showIconButton, help: showIconButton.toolTip ?? "")
        let showLabelsRow = settingRow(showLabelsButton, help: showLabelsButton.toolTip ?? "")
        let showMetricSymbolsRow = settingRow(showMetricSymbolsButton, help: showMetricSymbolsButton.toolTip ?? "")
        let showEnergyFlowArrowsRow = settingRow(showEnergyFlowArrowsButton, help: showEnergyFlowArrowsButton.toolTip ?? "")
        let lockDetachedMenuBarRow = settingRow(lockDetachedMenuBarButton, help: lockDetachedMenuBarButton.toolTip ?? "")
        let scaleRow = NSStackView(views: [label(LocalizedText.text("Skalierung", "Scale")), scaleSlider, scaleValue, helpButton(labelTooltip("Skalierung"))])
        scaleRow.orientation = .horizontal
        scaleRow.spacing = 12
        scaleRow.alignment = .centerY
        scaleValue.alignment = .right
        scaleValue.widthAnchor.constraint(equalToConstant: 56).isActive = true
        let detachedScaleRow = NSStackView(views: [label(LocalizedText.text("Abgedockt", "Detached")), detachedScaleSlider, detachedScaleValue, helpButton(labelTooltip("Abgedockt"))])
        detachedScaleRow.orientation = .horizontal
        detachedScaleRow.spacing = 12
        detachedScaleRow.alignment = .centerY
        detachedScaleValue.alignment = .right
        detachedScaleValue.widthAnchor.constraint(equalToConstant: 56).isActive = true

        for view in [metricTitle, metricGrid, displayTitle, showIconRow, showLabelsRow, showMetricSymbolsRow, showEnergyFlowArrowsRow, lockDetachedMenuBarRow, scaleRow, detachedScaleRow] {
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

            showIconRow.topAnchor.constraint(equalTo: displayTitle.bottomAnchor, constant: 10),
            showIconRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            showLabelsRow.topAnchor.constraint(equalTo: showIconRow.bottomAnchor, constant: 8),
            showLabelsRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            showMetricSymbolsRow.topAnchor.constraint(equalTo: showLabelsRow.bottomAnchor, constant: 8),
            showMetricSymbolsRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            showEnergyFlowArrowsRow.topAnchor.constraint(equalTo: showMetricSymbolsRow.bottomAnchor, constant: 8),
            showEnergyFlowArrowsRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            lockDetachedMenuBarRow.topAnchor.constraint(equalTo: showEnergyFlowArrowsRow.bottomAnchor, constant: 8),
            lockDetachedMenuBarRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            scaleRow.topAnchor.constraint(equalTo: lockDetachedMenuBarRow.bottomAnchor, constant: 16),
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
        let title = sectionTitle(LocalizedText.text("Datenquelle", "Data Source"))
        let hint = NSTextField(wrappingLabelWithString: "Die gewählte Datenquelle muss ein JSON-Objekt mit Feldern wie batteryPercent, solarWatts, homeWatts und updatedAt liefern. Mindestintervall: 60 Sekunden.")
        hint.textColor = .secondaryLabelColor

        let rows = NSStackView()
        rows.orientation = .vertical
        rows.spacing = 12

        solixTitle.font = .boldSystemFont(ofSize: 13)
        solixHint.textColor = .secondaryLabelColor

        rows.addArrangedSubview(formRow(labelText: LocalizedText.text("Modus", "Mode"), control: modePopup))
        rows.addArrangedSubview(solixTitle)
        configure(row: solixEmailRow, labelText: LocalizedText.text("Mail", "Email"), control: solixEmailField)
        configure(row: solixPasswordRow, labelText: LocalizedText.text("Passwort", "Password"), control: solixPasswordField)
        configure(row: solixCountryRow, labelText: LocalizedText.text("Land", "Country"), control: solixCountryField)
        configure(row: solixTodayBaseRow, labelText: LocalizedText.text("Ertrag heute", "Yield today"), control: solixTodayBaseField)
        configure(row: solixTotalBaseRow, labelText: LocalizedText.text("Gesamtertrag", "Total yield"), control: solixTotalBaseField)
        rows.addArrangedSubview(solixEmailRow)
        rows.addArrangedSubview(solixPasswordRow)
        rows.addArrangedSubview(solixCountryRow)
        rows.addArrangedSubview(solixTodayBaseRow)
        rows.addArrangedSubview(solixTotalBaseRow)
        rows.addArrangedSubview(solixHint)
        configure(row: commandRow, labelText: LocalizedText.text("Befehl", "Command"), control: commandField)
        configure(row: urlRow, labelText: "URL", control: urlField)
        rows.addArrangedSubview(commandRow)
        rows.addArrangedSubview(urlRow)
        rows.addArrangedSubview(formRow(labelText: LocalizedText.text("Intervall", "Interval"), control: intervalField))

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

    private func appPane() -> NSView {
        let container = NSView()
        let title = sectionTitle(LocalizedText.text("App-Darstellung", "App Appearance"))
        let appearanceRow = formRow(labelText: LocalizedText.text("Design", "Theme"), control: appearancePopup)
        let languageRow = formRow(labelText: LocalizedText.text("Sprache", "Language"), control: languagePopup)
        let hint = NSTextField(wrappingLabelWithString: LocalizedText.text(
            "Aenderungen wirken sofort als Vorschau. Erst Speichern macht sie dauerhaft.",
            "Changes apply immediately as a preview. Press Save to keep them."
        ))
        hint.textColor = .secondaryLabelColor

        for view in [title, appearanceRow, languageRow, hint] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 22),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            appearanceRow.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            appearanceRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            languageRow.topAnchor.constraint(equalTo: appearanceRow.bottomAnchor, constant: 12),
            languageRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            hint.topAnchor.constraint(equalTo: languageRow.bottomAnchor, constant: 18),
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
        row.addArrangedSubview(helpButton(control.toolTip ?? labelTooltip(labelText)))

        NSLayoutConstraint.activate([
            rowLabel.widthAnchor.constraint(equalToConstant: 88),
            control.widthAnchor.constraint(equalToConstant: 420)
        ])
    }

    private func startupPane() -> NSView {
        let container = NSView()
        let title = sectionTitle(LocalizedText.text("Startverhalten", "Startup"))

        let autostartRow = settingRow(autostartButton, help: autostartButton.toolTip ?? "")

        for view in [title, autostartRow, autostartStatus] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 22),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            autostartRow.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            autostartRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            autostartRow.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),

            autostartStatus.topAnchor.constraint(equalTo: autostartRow.bottomAnchor, constant: 8),
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
                let button = NSButton(checkboxWithTitle: localizedMetricTitle(metric), target: self, action: #selector(applyPreview))
                button.toolTip = metricTooltip(metric)
                metricButtons[metric] = button
                return settingRow(button, help: metricTooltip(metric))
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

    private func settingRow(_ control: NSView, help: String) -> NSStackView {
        let row = NSStackView(views: [control, helpButton(help)])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        return row
    }

    private func helpButton(_ tooltip: String) -> NSButton {
        let button = NSButton(title: "?", target: nil, action: nil)
        button.isBordered = false
        button.font = .systemFont(ofSize: 12, weight: .bold)
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = tooltip
        button.setButtonType(.momentaryChange)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 22).isActive = true
        button.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return button
    }

    private func metricTooltip(_ metric: BarMetric) -> String {
        if settings.appLanguage == .english {
            switch metric {
            case .battery:
                return "Shows the current battery level in percent in the menu bar."
            case .solar:
                return "Shows the current solar output in watts in the menu bar."
            case .home:
                return "Shows the current real home load in watts in the menu bar."
            case .grid:
                return "Shows current grid import or export in watts."
            case .batteryFlow:
                return "Shows whether the battery is charging or discharging."
            case .flow:
                return "Shows the energy-flow field in the menu bar. Arrows appear when the arrow option is enabled."
            case .today:
                return "Shows today's solar yield in kWh."
            case .total:
                return "Shows the total measured solar yield in kWh."
            case .status:
                return "Shows the current data-source status."
            }
        }
        switch metric {
        case .battery:
            return "Zeigt den aktuellen Akkustand in Prozent in der Menüleiste."
        case .solar:
            return "Zeigt die aktuelle Solarleistung in Watt in der Menüleiste."
        case .home:
            return "Zeigt die aktuelle echte Hauslast in Watt in der Menüleiste."
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

    private func localizedMetricTitle(_ metric: BarMetric) -> String {
        guard settings.appLanguage == .english else { return metric.title }
        switch metric {
        case .battery:
            return "Battery"
        case .solar:
            return "PV"
        case .home:
            return "Home"
        case .grid:
            return "Grid Import"
        case .batteryFlow:
            return "Battery Flow"
        case .flow:
            return "Energy Flow"
        case .today:
            return "Today's Yield"
        case .total:
            return "Total Yield"
        case .status:
            return "Status"
        }
    }

    private func labelTooltip(_ text: String) -> String {
        switch text {
        case "Skalierung", "Scale":
            return "Passt die Größe der Menüleistenanzeige an."
        case "Abgedockt", "Detached":
            return "Passt nur die Größe der abgedockten Menüleistenleiste an."
        case "Modus", "Mode":
            return "Wählt Demo, lokalen JSON-Befehl oder JSON-URL."
        case "Mail", "Email":
            return "E-Mail-Adresse deines Anker/SOLIX-Kontos."
        case "Passwort", "Password":
            return "Passwort deines Anker/SOLIX-Kontos."
        case "Land", "Country":
            return "Land des Anker-Kontos, meistens DE."
        case "Ertrag heute", "Yield today":
            return "Korrigiert den heutigen Ertrag in kWh, wenn Anker fuer heute 0 kWh liefert."
        case "Gesamtertrag", "Total yield":
            return LocalizedText.text(
                "Setzt optional den Gesamtertrag aus der Anker-App als Startwert. Ohne API-Gesamtwert zaehlt SolixBar alle fortlaufenden Messungen zusammen.",
                "Optionally sets the Anker app total as a starting value. Without an API total, SolixBar adds up all continuous measurements."
            )
        case "Befehl", "Command":
            return "Der lokale Befehl muss ein JSON-Objekt ausgeben."
        case "URL":
            return "Die Adresse muss ein JSON-Objekt liefern."
        case "Intervall", "Interval":
            return "Legt fest, wie oft neue Daten geholt werden."
        case "Design", "Theme":
            return "Waehlt Hell, Dunkel oder Automatisch passend zum System."
        case "Sprache", "Language":
            return "Waehlt Deutsch oder Englisch fuer sichtbare App-Texte."
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
        switch settings.appearanceMode {
        case .system:
            appearancePopup.selectItem(at: 0)
        case .light:
            appearancePopup.selectItem(at: 1)
        case .dark:
            appearancePopup.selectItem(at: 2)
        }
        languagePopup.selectItem(at: settings.appLanguage == .english ? 1 : 0)
        commandField.stringValue = settings.command
        urlField.stringValue = settings.urlString
        intervalField.stringValue = String(Int(settings.refreshInterval))
        loadSolixCredentials()
        showIconButton.state = settings.showMenuBarIcon ? .on : .off
        showLabelsButton.state = settings.showMetricLabels ? .on : .off
        showMetricSymbolsButton.state = settings.showMenuBarMetricSymbols ? .on : .off
        showEnergyFlowArrowsButton.state = settings.showEnergyFlowArrows ? .on : .off
        lockDetachedMenuBarButton.state = settings.lockDetachedMenuBar ? .on : .off
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
        switch appearancePopup.indexOfSelectedItem {
        case 1:
            settings.appearanceMode = .light
        case 2:
            settings.appearanceMode = .dark
        default:
            settings.appearanceMode = .system
        }
        settings.appLanguage = languagePopup.indexOfSelectedItem == 1 ? .english : .german
        settings.command = commandField.stringValue
        settings.urlString = urlField.stringValue
        settings.refreshInterval = TimeInterval(max(60, intervalField.integerValue))
        settings.barMetrics = BarMetric.allCases.filter { metricButtons[$0]?.state == .on }
        settings.showMenuBarIcon = showIconButton.state == .on
        settings.showMetricLabels = showLabelsButton.state == .on
        settings.showMenuBarMetricSymbols = showMetricSymbolsButton.state == .on
        settings.showEnergyFlowArrows = showEnergyFlowArrowsButton.state == .on
        settings.lockDetachedMenuBar = lockDetachedMenuBarButton.state == .on
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
        solixTodayBaseRow.isHidden = hidden
        solixTotalBaseRow.isHidden = hidden
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
        SolixPaths.helperCommand() ?? ""
    }

    private func loadSolixCredentials() {
        let values = SolixEnvFile.read(from: SolixPaths.envFileURL)
        let email = values["ANKER_SOLIX_USER"] ?? ""
        solixEmailField.stringValue = email
        // Passwort bevorzugt aus dem Schluesselbund; Env-Eintrag ist Altbestand.
        if !email.isEmpty, let stored = KeychainStore.password(account: email) {
            solixPasswordField.stringValue = stored
        } else {
            solixPasswordField.stringValue = values["ANKER_SOLIX_PASSWORD"] ?? ""
        }
        solixCountryField.stringValue = values["ANKER_SOLIX_COUNTRY"] ?? "DE"
        solixTodayBaseField.stringValue = values["SOLIXBAR_TODAY_KWH_BASE"] ?? ""
        solixTotalBaseField.stringValue = values["SOLIXBAR_TOTAL_KWH_BASE"] ?? ""
    }

    private func saveSolixCredentialsIfNeeded() {
        guard shouldUseSolixHelper else { return }
        let email = solixEmailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = solixPasswordField.stringValue
        let country = solixCountryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "DE"
            : solixCountryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let todayBase = solixTodayBaseField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let totalBase = solixTotalBaseField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        // Passwort in den Schluesselbund; die Env-Datei enthaelt keine Secrets.
        var values: [(key: String, value: String)] = [
            ("ANKER_SOLIX_USER", email),
            ("ANKER_SOLIX_COUNTRY", country)
        ]
        if !todayBase.isEmpty {
            values.append(("SOLIXBAR_TODAY_KWH_BASE", todayBase.replacingOccurrences(of: ",", with: ".")))
            values.append(("SOLIXBAR_TODAY_KWH_DATE", Self.todayKey()))
        }
        if !totalBase.isEmpty {
            values.append(("SOLIXBAR_TOTAL_KWH_BASE", totalBase.replacingOccurrences(of: ",", with: ".")))
        }

        do {
            if !email.isEmpty, !password.isEmpty {
                try KeychainStore.setPassword(password, account: email)
            }
            try SolixEnvFile.write(values, to: SolixPaths.envFileURL)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
