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
    private let solixTitle = NSTextField(labelWithString: LocalizedText.text("SOLIX Login", "SOLIX Login"))
    private let solixHint = NSTextField(wrappingLabelWithString: LocalizedText.text(
        "Direkter SOLIX-Zugriff. Das Passwort wird verschlüsselt lokal gespeichert.",
        "Direct SOLIX access. The password is stored locally in encrypted form."
    ))
    private let solixEmailRow = NSStackView()
    private let solixPasswordRow = NSStackView()
    private let solixCountryRow = NSStackView()
    private let solixTodayBaseRow = NSStackView()
    private let solixTotalBaseRow = NSStackView()
    private let autostartButton = NSButton(checkboxWithTitle: LocalizedText.text("Beim Login automatisch starten", "Start automatically at login"), target: nil, action: nil)
    private let autostartStatus = NSTextField(labelWithString: "")
    private let showIconButton = NSButton(checkboxWithTitle: LocalizedText.text("App-Symbol in der Menüleiste anzeigen", "Show app icon in the menu bar"), target: nil, action: nil)
    private let showLabelsButton = NSButton(checkboxWithTitle: LocalizedText.text("Werte mit Bezeichnung anzeigen", "Show labels next to values"), target: nil, action: nil)
    private let showMetricSymbolsButton = NSButton(checkboxWithTitle: LocalizedText.text("Symbole vor den Werten anzeigen", "Show symbols before values"), target: nil, action: nil)
    private let showEnergyFlowArrowsButton = NSButton(checkboxWithTitle: LocalizedText.text("Farben und Flussrichtung anzeigen", "Show colors and flow direction"), target: nil, action: nil)
    private let showDetachedIconButton = NSButton(checkboxWithTitle: LocalizedText.text("App-Symbol anzeigen", "Show app icon"), target: nil, action: nil)
    private let showDetachedLabelsButton = NSButton(checkboxWithTitle: LocalizedText.text("Werte mit Bezeichnung anzeigen", "Show labels next to values"), target: nil, action: nil)
    private let showDetachedSymbolsButton = NSButton(checkboxWithTitle: LocalizedText.text("Symbole vor den Werten anzeigen", "Show symbols before values"), target: nil, action: nil)
    private let showDetachedFlowButton = NSButton(checkboxWithTitle: LocalizedText.text("Farben und Flussrichtung anzeigen", "Show colors and flow direction"), target: nil, action: nil)
    private let lockDetachedMenuBarButton = NSButton(checkboxWithTitle: LocalizedText.text("Abgedockte Leiste fixieren", "Lock detached slim bar"), target: nil, action: nil)
    private let scaleSlider = NSSlider(value: 1.0, minValue: 0.75, maxValue: 1.6, target: nil, action: nil)
    private let scaleValue = NSTextField(labelWithString: "100 %")
    private let detachedScaleSlider = NSSlider(value: 1.0, minValue: 0.75, maxValue: 1.9, target: nil, action: nil)
    private let detachedScaleValue = NSTextField(labelWithString: "100 %")
    private let appearancePopup = NSPopUpButton()
    private let languagePopup = NSPopUpButton()
    private lazy var menuMetricEditor = MetricOrderEditorView { [weak self] metrics in
        self?.metricEditorChanged(metrics, detached: false)
    }
    private lazy var detachedMetricEditor = MetricOrderEditorView { [weak self] metrics in
        self?.metricEditorChanged(metrics, detached: true)
    }
    private lazy var warningSettingsView = WarningSettingsView { [weak self] rules in
        self?.warningRulesChanged(rules)
    }
    private var originalSettings: AppSettingsSnapshot?
    private var originalAutostart = false
    private var isSaving = false
    private var isLoading = false

    init(onPreview: @escaping () -> Void, onSave: @escaping () -> Void, onReset: @escaping () -> Void) {
        self.onPreview = onPreview
        self.onSave = onSave
        self.onReset = onReset
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 760),
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

        modePopup.addItems(withTitles: [
            LocalizedText.text("SOLIX Login", "SOLIX Login"),
            "Demo",
            LocalizedText.text("Lokaler JSON-Befehl", "Local JSON Command"),
            "JSON-URL"
        ])
        appearancePopup.addItems(withTitles: [
            LocalizedText.text("Automatisch", "Automatic"),
            LocalizedText.text("Hell", "Light"),
            LocalizedText.text("Dunkel", "Dark")
        ])
        languagePopup.addItems(withTitles: AppLanguage.allCases.map(\.displayName))
        applyLocalizedControlTitles()
        modePopup.toolTip = LocalizedText.text("Legt fest, woher SolixBar die Werte lädt.", "Selects where SolixBar loads its values from.")
        appearancePopup.toolTip = LocalizedText.text("Wählt helle Darstellung, dunkle Darstellung oder automatisch passend zum macOS-System.", "Selects light, dark, or automatic appearance to match macOS.")
        languagePopup.toolTip = LocalizedText.text("Wählt die Sprache für alle sichtbaren App-Texte.", "Selects the language for all visible app text.")
        commandField.placeholderString = "/path/to/command-that-prints-json"
        commandField.toolTip = LocalizedText.text("Führt einen lokalen Befehl aus und liest dessen JSON-Ausgabe.", "Runs a local command and reads its JSON output.")
        urlField.placeholderString = "http://127.0.0.1:8787/solix.json"
        urlField.toolTip = LocalizedText.text("Lädt die Werte von einer JSON-Adresse.", "Loads values from a JSON address.")
        intervalField.placeholderString = "300"
        intervalField.toolTip = LocalizedText.text("Zeit zwischen zwei Aktualisierungen in Sekunden.", "Time between refreshes in seconds.")
        solixEmailField.placeholderString = "mail@example.com"
        solixEmailField.toolTip = LocalizedText.text("E-Mail-Adresse deines Anker/SOLIX-Kontos.", "Email address of your Anker/SOLIX account.")
        solixPasswordField.placeholderString = LocalizedText.text("Passwort", "Password")
        solixPasswordField.toolTip = LocalizedText.text(
            "Passwort deines Anker/SOLIX-Kontos. Es wird verschlüsselt lokal gespeichert.",
            "Your Anker/SOLIX password. It is stored locally in encrypted form."
        )
        solixCountryField.placeholderString = "DE"
        solixCountryField.toolTip = LocalizedText.text("Land deines Anker-Kontos, normalerweise DE.", "Country of your Anker account, usually DE.")
        solixTodayBaseField.placeholderString = LocalizedText.text("z. B. 7,2", "e.g. 7.2")
        solixTodayBaseField.toolTip = LocalizedText.text(
            "Optionaler Korrekturwert für den heutigen Ertrag in kWh, falls Anker heute 0 kWh meldet. SolixBar zählt ab diesem Wert weiter.",
            "Optional correction value for today's yield in kWh if Anker reports 0 kWh. SolixBar continues counting from this value."
        )
        solixTotalBaseField.placeholderString = LocalizedText.text("z. B. 427,8", "e.g. 427.8")
        solixTotalBaseField.toolTip = LocalizedText.text(
            "Optionaler Startwert fuer den Gesamtertrag. Ohne API-Gesamtwert kumuliert SolixBar alle fortlaufenden Solarmessungen lokal.",
            "Optional starting value for total yield. Without an API total, SolixBar locally accumulates all continuous solar measurements."
        )

        for textField in [commandField, urlField, intervalField, solixEmailField, solixPasswordField, solixCountryField, solixTodayBaseField, solixTotalBaseField] {
            textField.delegate = self
        }

        for control in [modePopup, appearancePopup, languagePopup, showIconButton, showLabelsButton, showMetricSymbolsButton, showEnergyFlowArrowsButton, showDetachedIconButton, showDetachedLabelsButton, showDetachedSymbolsButton, showDetachedFlowButton, lockDetachedMenuBarButton, scaleSlider, detachedScaleSlider] {
            control.target = self
            control.action = #selector(applyPreview)
        }
        autostartButton.target = self
        autostartButton.action = #selector(toggleAutostart)
        autostartButton.toolTip = LocalizedText.text("Startet SolixBar automatisch nach dem Anmelden.", "Starts SolixBar automatically after login.")
        autostartStatus.textColor = .secondaryLabelColor
        autostartStatus.lineBreakMode = .byTruncatingMiddle
        showIconButton.toolTip = LocalizedText.text("Zeigt oder versteckt das SolixBar-Symbol in der Menüleiste.", "Shows or hides the SolixBar icon in the menu bar.")
        showLabelsButton.toolTip = LocalizedText.text("Zeigt kurze Namen wie Akku oder Solar vor den Zahlen.", "Shows short labels such as Battery or Solar before the values.")
        showMetricSymbolsButton.toolTip = LocalizedText.text("Zeigt farbige Symbole direkt vor den Menüleistenwerten.", "Shows colored symbols directly before menu-bar values.")
        showEnergyFlowArrowsButton.toolTip = LocalizedText.text("Schaltet kontrastreiche Flussfarben, Richtungspfeile und Begriffe wie Laden, Entladen, Bezug und Einspeisen gemeinsam ein oder aus.", "Turns high-contrast flow colors, direction arrows, and labels such as Charging, Discharging, Import, and Export on or off together.")
        showDetachedIconButton.toolTip = LocalizedText.text("Zeigt oder versteckt das SolixBar-Symbol nur in der abgedockten Leiste.", "Shows or hides the SolixBar icon only in the detached bar.")
        showDetachedLabelsButton.toolTip = LocalizedText.text("Zeigt Bezeichnungen nur in der abgedockten Leiste.", "Shows labels only in the detached bar.")
        showDetachedSymbolsButton.toolTip = LocalizedText.text("Zeigt die bestehenden farbigen Symbole nur in der abgedockten Leiste.", "Shows the existing colored symbols only in the detached bar.")
        showDetachedFlowButton.toolTip = LocalizedText.text("Verwendet die bestehenden Flussfarben und Richtungspfeile in der abgedockten Leiste.", "Uses the existing flow colors and direction arrows in the detached bar.")
        lockDetachedMenuBarButton.toolTip = LocalizedText.text("Fixiert die abgedockte Leiste, damit sie nicht versehentlich verschoben wird.", "Locks the detached bar so it cannot be moved accidentally.")
        scaleSlider.toolTip = LocalizedText.text("Vergrößert oder verkleinert Text und Symbole in der Menüleiste.", "Enlarges or reduces text and symbols in the menu bar.")
        scaleValue.toolTip = LocalizedText.text("Aktuell eingestellte Größe der Menüleistenanzeige.", "Currently selected menu-bar display size.")
        detachedScaleSlider.toolTip = LocalizedText.text("Vergrößert oder verkleinert nur die abgedockte Menüleistenanzeige.", "Enlarges or reduces only the detached menu-bar display.")
        detachedScaleValue.toolTip = LocalizedText.text("Aktuell eingestellte Größe der abgedockten Leiste.", "Currently selected detached-bar size.")

        let title = NSTextField(labelWithString: "SOLIX Bar \(AppVersion.short)")
        title.font = .boldSystemFont(ofSize: 20)

        let tabs = NSTabView()
        tabs.tabViewType = .topTabsBezelBorder
        tabs.addTabViewItem(tab(title: LocalizedText.text("Menüleiste", "Menu Bar"), view: menuBarPane()))
        tabs.addTabViewItem(tab(title: LocalizedText.text("Abgedockt", "Detached"), view: detachedMenuBarPane()))
        tabs.addTabViewItem(tab(title: LocalizedText.text("Warnungen", "Warnings"), view: warningsPane()))
        tabs.addTabViewItem(tab(title: LocalizedText.text("Datenquelle", "Data Source"), view: dataSourcePane()))
        tabs.addTabViewItem(tab(title: LocalizedText.text("App", "App"), view: appPane()))
        tabs.addTabViewItem(tab(title: LocalizedText.text("Start", "Startup"), view: startupPane()))

        let cancel = NSButton(title: LocalizedText.text("Abbrechen", "Cancel"), target: self, action: #selector(cancelSettings))
        cancel.bezelStyle = .rounded
        cancel.toolTip = LocalizedText.text("Verwirft die Vorschau und stellt die alten Einstellungen wieder her.", "Discards the preview and restores the previous settings.")

        let save = NSButton(title: LocalizedText.text("Speichern", "Save"), target: self, action: #selector(saveSettings))
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        save.toolTip = LocalizedText.text("Speichert die aktuellen Einstellungen dauerhaft.", "Saves the current settings permanently.")

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
        showDetachedIconButton.title = LocalizedText.text("App-Symbol anzeigen", "Show app icon")
        showDetachedLabelsButton.title = LocalizedText.text("Werte mit Bezeichnung anzeigen", "Show labels next to values")
        showDetachedSymbolsButton.title = LocalizedText.text("Symbole vor den Werten anzeigen", "Show symbols before values")
        showDetachedFlowButton.title = LocalizedText.text("Farben und Flussrichtung anzeigen", "Show colors and flow direction")
        lockDetachedMenuBarButton.title = LocalizedText.text("Abgedockte Leiste fixieren", "Lock detached slim bar")
        autostartButton.title = LocalizedText.text("Beim Login automatisch starten", "Start automatically at login")
    }

    private func menuBarPane() -> NSView {
        let container = NSView()
        let metricTitle = sectionTitle(LocalizedText.text("Werte und Reihenfolge", "Values and Order"))
        let displayTitle = sectionTitle(LocalizedText.text("Darstellung", "Display"))
        let showIconRow = settingRow(showIconButton, help: showIconButton.toolTip ?? "")
        let showLabelsRow = settingRow(showLabelsButton, help: showLabelsButton.toolTip ?? "")
        let showMetricSymbolsRow = settingRow(showMetricSymbolsButton, help: showMetricSymbolsButton.toolTip ?? "")
        let showEnergyFlowArrowsRow = settingRow(showEnergyFlowArrowsButton, help: showEnergyFlowArrowsButton.toolTip ?? "")
        let scaleRow = NSStackView(views: [label(LocalizedText.text("Skalierung", "Scale")), scaleSlider, scaleValue, helpButton(labelTooltip("Skalierung"))])
        scaleRow.orientation = .horizontal
        scaleRow.spacing = 12
        scaleRow.alignment = .centerY
        scaleValue.alignment = .right
        scaleValue.widthAnchor.constraint(equalToConstant: 56).isActive = true
        for view in [metricTitle, menuMetricEditor, displayTitle, showIconRow, showLabelsRow, showMetricSymbolsRow, showEnergyFlowArrowsRow, scaleRow] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }

        NSLayoutConstraint.activate([
            metricTitle.topAnchor.constraint(equalTo: container.topAnchor, constant: 22),
            metricTitle.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            menuMetricEditor.topAnchor.constraint(equalTo: metricTitle.bottomAnchor, constant: 10),
            menuMetricEditor.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            menuMetricEditor.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),

            displayTitle.topAnchor.constraint(equalTo: menuMetricEditor.bottomAnchor, constant: 14),
            displayTitle.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            showIconRow.topAnchor.constraint(equalTo: displayTitle.bottomAnchor, constant: 10),
            showIconRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            showLabelsRow.topAnchor.constraint(equalTo: showIconRow.bottomAnchor, constant: 8),
            showLabelsRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            showMetricSymbolsRow.topAnchor.constraint(equalTo: showLabelsRow.bottomAnchor, constant: 8),
            showMetricSymbolsRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            showEnergyFlowArrowsRow.topAnchor.constraint(equalTo: showMetricSymbolsRow.bottomAnchor, constant: 8),
            showEnergyFlowArrowsRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            scaleRow.topAnchor.constraint(equalTo: showEnergyFlowArrowsRow.bottomAnchor, constant: 12),
            scaleRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            scaleRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24)
        ])

        return container
    }

    private func detachedMenuBarPane() -> NSView {
        let container = NSView()
        let metricTitle = sectionTitle(LocalizedText.text("Werte und Reihenfolge", "Values and Order"))
        let displayTitle = sectionTitle(LocalizedText.text("Darstellung der abgedockten Leiste", "Detached Bar Display"))
        let iconRow = settingRow(showDetachedIconButton, help: showDetachedIconButton.toolTip ?? "")
        let labelsRow = settingRow(showDetachedLabelsButton, help: showDetachedLabelsButton.toolTip ?? "")
        let symbolsRow = settingRow(showDetachedSymbolsButton, help: showDetachedSymbolsButton.toolTip ?? "")
        let flowRow = settingRow(showDetachedFlowButton, help: showDetachedFlowButton.toolTip ?? "")
        let lockRow = settingRow(lockDetachedMenuBarButton, help: lockDetachedMenuBarButton.toolTip ?? "")
        let scaleRow = NSStackView(views: [label(LocalizedText.text("Skalierung", "Scale")), detachedScaleSlider, detachedScaleValue, helpButton(labelTooltip("Abgedockt"))])
        scaleRow.orientation = .horizontal
        scaleRow.spacing = 12
        scaleRow.alignment = .centerY
        detachedScaleValue.alignment = .right
        detachedScaleValue.widthAnchor.constraint(equalToConstant: 56).isActive = true

        for view in [metricTitle, detachedMetricEditor, displayTitle, iconRow, labelsRow, symbolsRow, flowRow, lockRow, scaleRow] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            metricTitle.topAnchor.constraint(equalTo: container.topAnchor, constant: 22),
            metricTitle.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            detachedMetricEditor.topAnchor.constraint(equalTo: metricTitle.bottomAnchor, constant: 10),
            detachedMetricEditor.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            detachedMetricEditor.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            displayTitle.topAnchor.constraint(equalTo: detachedMetricEditor.bottomAnchor, constant: 14),
            displayTitle.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            iconRow.topAnchor.constraint(equalTo: displayTitle.bottomAnchor, constant: 8),
            iconRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            labelsRow.topAnchor.constraint(equalTo: iconRow.bottomAnchor, constant: 7),
            labelsRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            symbolsRow.topAnchor.constraint(equalTo: labelsRow.bottomAnchor, constant: 7),
            symbolsRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            flowRow.topAnchor.constraint(equalTo: symbolsRow.bottomAnchor, constant: 7),
            flowRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            lockRow.topAnchor.constraint(equalTo: flowRow.bottomAnchor, constant: 7),
            lockRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            scaleRow.topAnchor.constraint(equalTo: lockRow.bottomAnchor, constant: 10),
            scaleRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            scaleRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24)
        ])
        return container
    }

    private func warningsPane() -> NSView {
        let container = NSView()
        let title = sectionTitle(LocalizedText.text("Individuelle Warnungen", "Individual Warnings"))
        let hint = NSTextField(wrappingLabelWithString: LocalizedText.text(
            "Schwelle und Mindestdauer lassen sich für jeden Eingang getrennt festlegen.",
            "Threshold and minimum duration can be configured separately for every input."
        ))
        hint.textColor = .secondaryLabelColor
        for view in [title, hint, warningSettingsView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 22),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            hint.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            hint.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            hint.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            warningSettingsView.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 16),
            warningSettingsView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            warningSettingsView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            warningSettingsView.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -18)
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
        switch metric {
        case .battery:
            return LocalizedText.text("Zeigt den aktuellen Akkustand in Prozent in der Menüleiste.", "Shows the current battery level in percent in the menu bar.")
        case .solar:
            return LocalizedText.text("Zeigt die aktuelle Solarleistung in Watt in der Menüleiste.", "Shows the current solar output in watts in the menu bar.")
        case .home:
            return LocalizedText.text("Zeigt die aktuelle echte Hauslast in Watt in der Menüleiste.", "Shows the current real home load in watts in the menu bar.")
        case .grid:
            return LocalizedText.text("Zeigt den aktuellen Netzbezug oder die Einspeisung in Watt.", "Shows current grid import or export in watts.")
        case .batteryFlow:
            return LocalizedText.text("Zeigt, ob der Akku gerade lädt oder entlädt.", "Shows whether the battery is charging or discharging.")
        case .flow:
            return LocalizedText.text("Zeigt das Energiefluss-Feld in der Menüleiste. Die Pfeile erscheinen, wenn die Pfeil-Option aktiviert ist.", "Shows the energy-flow field in the menu bar. Arrows appear when the arrow option is enabled.")
        case .today:
            return LocalizedText.text("Zeigt den heutigen Solarertrag in kWh.", "Shows today's solar yield in kWh.")
        case .total:
            return LocalizedText.text("Zeigt den gesamten bisher gemessenen Solarertrag in kWh.", "Shows the total measured solar yield in kWh.")
        case .status:
            return LocalizedText.text("Zeigt den aktuellen Status der Datenquelle.", "Shows the current data-source status.")
        }
    }

    private func localizedMetricTitle(_ metric: BarMetric) -> String {
        LocalizedText.metricTitle(metric)
    }

    private func labelTooltip(_ text: String) -> String {
        if LocalizedText.matches(text, german: "Skalierung", english: "Scale") {
            return LocalizedText.text("Passt die Größe der Menüleistenanzeige an.", "Adjusts the size of the menu-bar display.")
        }
        if LocalizedText.matches(text, german: "Abgedockt", english: "Detached") {
            return LocalizedText.text("Passt nur die Größe der abgedockten Menüleistenleiste an.", "Adjusts only the size of the detached menu bar.")
        }
        if LocalizedText.matches(text, german: "Modus", english: "Mode") {
            return LocalizedText.text("Wählt Demo, lokalen JSON-Befehl oder JSON-URL.", "Selects Demo, Local JSON Command, or JSON URL.")
        }
        if LocalizedText.matches(text, german: "Mail", english: "Email") {
            return LocalizedText.text("E-Mail-Adresse deines Anker/SOLIX-Kontos.", "Email address of your Anker/SOLIX account.")
        }
        if LocalizedText.matches(text, german: "Passwort", english: "Password") {
            return LocalizedText.text("Passwort deines Anker/SOLIX-Kontos.", "Password of your Anker/SOLIX account.")
        }
        if LocalizedText.matches(text, german: "Land", english: "Country") {
            return LocalizedText.text("Land des Anker-Kontos, meistens DE.", "Country of the Anker account, usually DE.")
        }
        if LocalizedText.matches(text, german: "Ertrag heute", english: "Yield today") {
            return LocalizedText.text("Korrigiert den heutigen Ertrag in kWh, wenn Anker für heute 0 kWh liefert.", "Corrects today's yield in kWh when Anker reports 0 kWh for today.")
        }
        if LocalizedText.matches(text, german: "Gesamtertrag", english: "Total yield") {
            return LocalizedText.text(
                "Setzt optional den Gesamtertrag aus der Anker-App als Startwert. Ohne API-Gesamtwert zaehlt SolixBar alle fortlaufenden Messungen zusammen.",
                "Optionally sets the Anker app total as a starting value. Without an API total, SolixBar adds up all continuous measurements."
            )
        }
        if LocalizedText.matches(text, german: "Befehl", english: "Command") {
            return LocalizedText.text("Der lokale Befehl muss ein JSON-Objekt ausgeben.", "The local command must output a JSON object.")
        }
        if text == "URL" {
            return LocalizedText.text("Die Adresse muss ein JSON-Objekt liefern.", "The address must return a JSON object.")
        }
        if LocalizedText.matches(text, german: "Intervall", english: "Interval") {
            return LocalizedText.text("Legt fest, wie oft neue Daten geholt werden.", "Sets how often new data is fetched.")
        }
        if LocalizedText.matches(text, german: "Design", english: "Theme") {
            return LocalizedText.text("Wählt Hell, Dunkel oder Automatisch passend zum System.", "Selects Light, Dark, or Automatic to match the system.")
        }
        if LocalizedText.matches(text, german: "Sprache", english: "Language") {
            return LocalizedText.text("Wählt die Sprache für alle sichtbaren App-Texte.", "Selects the language for all visible app text.")
        }
        return text
    }

    private func loadSettings() {
        isLoading = true
        switch settings.dataSourceMode {
        case .solix:
            modePopup.selectItem(at: 0)
        case .demo:
            modePopup.selectItem(at: 1)
        case .command:
            modePopup.selectItem(at: 2)
        case .url:
            modePopup.selectItem(at: 3)
        }
        switch settings.appearanceMode {
        case .system:
            appearancePopup.selectItem(at: 0)
        case .light:
            appearancePopup.selectItem(at: 1)
        case .dark:
            appearancePopup.selectItem(at: 2)
        }
        languagePopup.selectItem(at: AppLanguage.allCases.firstIndex(of: settings.appLanguage) ?? 0)
        commandField.stringValue = settings.command
        urlField.stringValue = settings.urlString
        intervalField.stringValue = String(Int(settings.refreshInterval))
        loadSolixCredentials()
        showIconButton.state = settings.showMenuBarIcon ? .on : .off
        showLabelsButton.state = settings.showMetricLabels ? .on : .off
        showMetricSymbolsButton.state = settings.showMenuBarMetricSymbols ? .on : .off
        showEnergyFlowArrowsButton.state = settings.showEnergyFlowArrows ? .on : .off
        showDetachedIconButton.state = settings.showDetachedMenuBarIcon ? .on : .off
        showDetachedLabelsButton.state = settings.showDetachedMetricLabels ? .on : .off
        showDetachedSymbolsButton.state = settings.showDetachedMetricSymbols ? .on : .off
        showDetachedFlowButton.state = settings.showDetachedEnergyFlowArrows ? .on : .off
        lockDetachedMenuBarButton.state = settings.lockDetachedMenuBar ? .on : .off
        scaleSlider.doubleValue = settings.menuBarScale
        scaleValue.stringValue = "\(Int(round(scaleSlider.doubleValue * 100))) %"
        detachedScaleSlider.doubleValue = settings.detachedMenuBarScale
        detachedScaleValue.stringValue = "\(Int(round(detachedScaleSlider.doubleValue * 100))) %"

        menuMetricEditor.load(settings.barMetrics)
        detachedMetricEditor.load(settings.detachedBarMetrics)
        warningSettingsView.load(settings.warningRules)
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
                ? LocalizedText.text("Autostart ist aktiv.", "Automatic startup is enabled.")
                : LocalizedText.text("Autostart ist deaktiviert.", "Automatic startup is disabled.")
        }
    }

    private func applyControlsToSettings() {
        switch modePopup.indexOfSelectedItem {
        case 0:
            settings.dataSourceMode = .solix
        case 2:
            settings.dataSourceMode = .command
        case 3:
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
        settings.appLanguage = AppLanguage.allCases.indices.contains(languagePopup.indexOfSelectedItem)
            ? AppLanguage.allCases[languagePopup.indexOfSelectedItem]
            : .german
        settings.command = commandField.stringValue
        settings.urlString = urlField.stringValue
        settings.refreshInterval = TimeInterval(max(60, intervalField.integerValue))
        settings.barMetrics = menuMetricEditor.selectedMetrics
        settings.detachedBarMetrics = detachedMetricEditor.selectedMetrics
        settings.showMenuBarIcon = showIconButton.state == .on
        settings.showDetachedMenuBarIcon = showDetachedIconButton.state == .on
        settings.showMetricLabels = showLabelsButton.state == .on
        settings.showDetachedMetricLabels = showDetachedLabelsButton.state == .on
        settings.showMenuBarMetricSymbols = showMetricSymbolsButton.state == .on
        settings.showDetachedMetricSymbols = showDetachedSymbolsButton.state == .on
        settings.showEnergyFlowArrows = showEnergyFlowArrowsButton.state == .on
        settings.showDetachedEnergyFlowArrows = showDetachedFlowButton.state == .on
        settings.lockDetachedMenuBar = lockDetachedMenuBarButton.state == .on
        settings.menuBarScale = scaleSlider.doubleValue
        settings.detachedMenuBarScale = detachedScaleSlider.doubleValue
        settings.solixCountry = solixCountryField.stringValue
        settings.solixTodayBaseKWh = parsedOptionalDouble(solixTodayBaseField.stringValue)
        settings.solixTotalBaseKWh = parsedOptionalDouble(solixTotalBaseField.stringValue)
        settings.warningRules = warningSettingsView.rules
        updateDataSourceFieldVisibility()
    }

    private func updateDataSourceFieldVisibility() {
        switch modePopup.indexOfSelectedItem {
        case 0:
            commandRow.isHidden = true
            urlRow.isHidden = true
            setSolixRowsHidden(false)
        case 2:
            commandRow.isHidden = false
            urlRow.isHidden = true
            setSolixRowsHidden(true)
        case 3:
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
            refreshAutostartState(message: LocalizedText.format(
                "Autostart konnte nicht geändert werden: {error}",
                "Automatic startup could not be changed: {error}",
                replacements: ["error": error.localizedDescription]
            ))
        }
    }

    @objc private func applyPreview() {
        guard !isLoading else { return }
        scaleValue.stringValue = "\(Int(round(scaleSlider.doubleValue * 100))) %"
        detachedScaleValue.stringValue = "\(Int(round(detachedScaleSlider.doubleValue * 100))) %"
        applyControlsToSettings()
        menuMetricEditor.refreshPreview()
        detachedMetricEditor.refreshPreview()
        onPreview()
    }

    private func metricEditorChanged(_ metrics: [BarMetric], detached: Bool) {
        guard !isLoading else { return }
        if detached {
            settings.detachedBarMetrics = metrics
        } else {
            settings.barMetrics = metrics
        }
        onPreview()
    }

    private func warningRulesChanged(_ rules: [WarningKind: WarningRule]) {
        guard !isLoading else { return }
        settings.warningRules = rules
    }

    @objc private func cancelSettings() {
        window?.close()
    }

    @objc private func saveSettings() {
        isSaving = true
        applyControlsToSettings()
        if settings.dataSourceMode == .solix {
            do {
                try EncryptedCredentialStore.save(
                    SolixCredentials(
                        email: solixEmailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                        password: solixPasswordField.stringValue
                    )
                )
            } catch {
                isSaving = false
                NSAlert(error: error).runModal()
                return
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

    private func loadSolixCredentials() {
        let credentials = EncryptedCredentialStore.load()
        solixEmailField.stringValue = credentials.email
        solixPasswordField.stringValue = credentials.password
        solixCountryField.stringValue = settings.solixCountry
        solixTodayBaseField.stringValue = settings.solixTodayBaseKWh.map { String(format: "%.3f", $0) } ?? ""
        solixTotalBaseField.stringValue = settings.solixTotalBaseKWh.map { String(format: "%.3f", $0) } ?? ""
    }

    private func parsedOptionalDouble(_ text: String) -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        return value.isEmpty ? nil : Double(value)
    }
}
