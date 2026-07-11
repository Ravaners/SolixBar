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
    private let solixHint = NSTextField(wrappingLabelWithString: "Nur für den vorbereiteten SOLIX-Befehl. Das Passwort liegt im macOS-Schlüsselbund, Mail und Land in einer lokalen Datei.")
    private let solixEmailRow = NSStackView()
    private let solixPasswordRow = NSStackView()
    private let solixCountryRow = NSStackView()
    private let solixTodayBaseRow = NSStackView()
    private let solixTotalBaseRow = NSStackView()
    private let graphFitButton = NSButton(checkboxWithTitle: "Graph an vorhandene Daten anpassen", target: nil, action: nil)
    private let customRangeField = NSTextField()
    private let customRangeUnitPopup = NSPopUpButton()
    private let autostartButton = NSButton(checkboxWithTitle: "Beim Login automatisch starten", target: nil, action: nil)
    private let autostartStatus = NSTextField(labelWithString: "")
    private let showIconButton = NSButton(checkboxWithTitle: "App-Symbol in der Menüleiste anzeigen", target: nil, action: nil)
    private let stackedButton = NSButton(checkboxWithTitle: "Zweizeilige Kompaktanzeige", target: nil, action: nil)
    private let stackedDetachedButton = NSButton(checkboxWithTitle: "Abgedockte Leiste: Kompaktanzeige", target: nil, action: nil)
    private let detachedIconButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let detachedLabelsButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let detachedSymbolsButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let detachedArrowsButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let showLabelsButton = NSButton(checkboxWithTitle: "Werte mit Bezeichnung anzeigen", target: nil, action: nil)
    private let showMetricSymbolsButton = NSButton(checkboxWithTitle: "Symbole vor den Werten anzeigen", target: nil, action: nil)
    private let showEnergyFlowArrowsButton = NSButton(checkboxWithTitle: "Flussrichtung anzeigen", target: nil, action: nil)
    private let showFlowColorsButton = NSButton(checkboxWithTitle: "Farbige Werte anzeigen", target: nil, action: nil)
    private let detachedFlowColorsButton = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let lockDetachedMenuBarButton = NSButton(checkboxWithTitle: "Abgedockte Leiste fixieren", target: nil, action: nil)
    private let scaleSlider = NSSlider(value: 1.0, minValue: 0.75, maxValue: 1.6, target: nil, action: nil)
    private let scaleValue = NSTextField(labelWithString: "100 %")
    private let detachedScaleSlider = NSSlider(value: 1.0, minValue: 0.75, maxValue: 1.9, target: nil, action: nil)
    private let detachedScaleValue = NSTextField(labelWithString: "100 %")
    private let appearancePopup = NSPopUpButton()
    private let languagePopup = NSPopUpButton()
    private let detachedLevelPopup = NSPopUpButton()
    private let dashboardLevelPopup = NSPopUpButton()
    private let graphLevelPopup = NSPopUpButton()
    private var metricButtons: [BarMetric: NSButton] = [:]
    private var detachedMetricButtons: [BarMetric: NSButton] = [:]
    private var originalSettings: AppSettingsSnapshot?
    private var originalAutostart = false
    private var isSaving = false
    private var isLoading = false
    private var previewDebounce: Timer?
    private let menuBarPreview = NSImageView()
    private let previewFormatter = MenuBarFormatter()

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
        appearancePopup.toolTip = "Wählt helle Darstellung, dunkle Darstellung oder automatisch passend zum macOS-System."
        languagePopup.toolTip = "Wählt die Sprache für sichtbare App-Texte."
        commandField.placeholderString = solixHelperCommand
        commandField.toolTip = "Führt einen lokalen Befehl aus und liest dessen JSON-Ausgabe."
        urlField.placeholderString = "http://127.0.0.1:8787/solix.json"
        urlField.toolTip = "Lädt die Werte von einer JSON-Adresse."
        intervalField.placeholderString = "300"
        let intervalNumbers = NumberFormatter()
        intervalNumbers.allowsFloats = false
        intervalNumbers.minimum = 60
        intervalNumbers.maximum = 86_400
        intervalField.formatter = intervalNumbers
        let rangeNumbers = NumberFormatter()
        rangeNumbers.allowsFloats = false
        rangeNumbers.minimum = 1
        rangeNumbers.maximum = 365
        customRangeField.formatter = rangeNumbers
        intervalField.toolTip = "Zeit zwischen zwei Aktualisierungen in Sekunden."
        solixEmailField.placeholderString = "mail@example.com"
        solixEmailField.toolTip = "E-Mail-Adresse deines Anker/SOLIX-Kontos."
        solixPasswordField.placeholderString = "Passwort"
        solixPasswordField.toolTip = "Passwort deines Anker/SOLIX-Kontos. Wird sicher im macOS-Schlüsselbund gespeichert und nie hochgeladen."
        solixCountryField.placeholderString = "DE"
        solixCountryField.toolTip = "Land deines Anker-Kontos, normalerweise DE."
        solixTodayBaseField.placeholderString = "z.B. 7.2"
        solixTodayBaseField.toolTip = "Optionaler Korrekturwert für den heutigen Ertrag in kWh, falls Anker heute 0 kWh meldet. SolixBar zählt ab diesem Wert weiter."
        solixTotalBaseField.placeholderString = "z.B. 427.8"
        solixTotalBaseField.toolTip = LocalizedText.text(
            "Optionaler Startwert für den Gesamtertrag. Ohne API-Gesamtwert kumuliert SolixBar alle fortlaufenden Solarmessungen lokal.",
            "Optional starting value for total yield. Without an API total, SolixBar locally accumulates all continuous solar measurements."
        )

        for textField in [commandField, urlField, intervalField, solixEmailField, solixPasswordField, solixCountryField, solixTodayBaseField, solixTotalBaseField] {
            textField.delegate = self
        }

        for control in [modePopup, appearancePopup, languagePopup, detachedLevelPopup, dashboardLevelPopup, graphLevelPopup, showIconButton, stackedButton, stackedDetachedButton, detachedIconButton, detachedLabelsButton, detachedSymbolsButton, detachedArrowsButton, detachedFlowColorsButton, graphFitButton, showLabelsButton, showMetricSymbolsButton, showEnergyFlowArrowsButton, showFlowColorsButton, lockDetachedMenuBarButton, scaleSlider, detachedScaleSlider] {
            control.target = self
            control.action = #selector(applyPreview)
        }
        autostartButton.target = self
        autostartButton.action = #selector(toggleAutostart)
        autostartButton.toolTip = "Startet SolixBar automatisch nach dem Anmelden."
        autostartStatus.textColor = .secondaryLabelColor
        autostartStatus.lineBreakMode = .byTruncatingMiddle
        showIconButton.toolTip = "Zeigt oder versteckt das SolixBar-Symbol in der Menüleiste."
        stackedButton.toolTip = "Zeigt die Werte in zwei kompakten Zeilen übereinander — halbe Breite bei gleicher Information, praktisch auf MacBooks mit Notch."
        stackedDetachedButton.toolTip = "Nutzt die zweizeilige Kompaktanzeige auch in der abgedockten Leiste — macht sie etwa halb so lang."
        graphFitButton.toolTip = "Blendet leere Zeiträume im Verlaufsgraphen aus: Die Zeitachse beginnt bei der ersten vorhandenen Messung statt beim Kalenderanfang des Zeitraums."
        showLabelsButton.toolTip = "Zeigt kurze Namen wie Akku oder Solar vor den Zahlen."
        showMetricSymbolsButton.toolTip = "Zeigt farbige Symbole direkt vor den Menüleistenwerten."
        showEnergyFlowArrowsButton.toolTip = "Zeigt Richtungspfeile und Begriffe wie Laden, Entladen, Bezug und Einspeisen; Wattwerte erscheinen dann ohne Vorzeichen."
        showFlowColorsButton.toolTip = "Färbt Werte und Symbole nach ihrer Bedeutung (Akku grün, Solar gelb, Netzbezug rot, Einspeisung violett). Ohne Farben bleibt die Anzeige einfarbig."
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
        tabs.addTabViewItem(tab(title: LocalizedText.text("Abgedockte Leiste", "Detached Bar"), view: detachedPane()))
        tabs.addTabViewItem(tab(title: LocalizedText.text("Datenquelle", "Data Source"), view: dataSourcePane()))
        tabs.addTabViewItem(tab(title: LocalizedText.text("App", "App"), view: appPane()))

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
        let modeIndex = modePopup.indexOfSelectedItem
        modePopup.removeAllItems()
        modePopup.addItems(withTitles: [
            "Demo",
            LocalizedText.text("Lokaler JSON-Befehl", "Local JSON command"),
            "JSON-URL"
        ])
        if modeIndex >= 0 { modePopup.selectItem(at: modeIndex) }
        let appearanceIndex = appearancePopup.indexOfSelectedItem
        appearancePopup.removeAllItems()
        appearancePopup.addItems(withTitles: [
            LocalizedText.text("Automatisch", "Automatic"),
            LocalizedText.text("Hell", "Light"),
            LocalizedText.text("Dunkel", "Dark")
        ])
        if appearanceIndex >= 0 { appearancePopup.selectItem(at: appearanceIndex) }
        showIconButton.title = LocalizedText.text("App-Symbol in der Menüleiste anzeigen", "Show app icon in the menu bar")
        stackedButton.title = LocalizedText.text("Zweizeilige Kompaktanzeige", "Two-line compact display")
        stackedDetachedButton.title = LocalizedText.text("Kompaktanzeige (zweizeilig)", "Compact display (two lines)")
        detachedIconButton.title = LocalizedText.text("App-Symbol anzeigen", "Show app glyph")
        detachedIconButton.toolTip = LocalizedText.text("Zeigt das Blitz-Symbol links in der Leiste.", "Shows the bolt glyph at the left of the bar.")
        detachedLabelsButton.title = LocalizedText.text("Werte mit Bezeichnung anzeigen", "Show labels next to values")
        detachedLabelsButton.toolTip = LocalizedText.text("Zeigt kurze Namen wie Akku oder Solar vor den Zahlen.", "Shows short names like Battery or Solar before the numbers.")
        detachedSymbolsButton.title = LocalizedText.text("Symbole vor den Werten anzeigen", "Show symbols before values")
        detachedSymbolsButton.toolTip = LocalizedText.text("Zeigt farbige Symbole direkt vor den Werten.", "Shows colored symbols right before the values.")
        detachedArrowsButton.title = LocalizedText.text("Flussrichtung anzeigen", "Show flow direction")
        detachedArrowsButton.toolTip = LocalizedText.text("Richtungspfeile und Begriffe wie Laden oder Bezug in der Leiste; Wattwerte ohne Vorzeichen.", "Direction arrows and terms like charging or import in the bar; watt values without sign.")
        detachedFlowColorsButton.title = LocalizedText.text("Farbige Werte anzeigen", "Show colored values")
        detachedFlowColorsButton.toolTip = LocalizedText.text("Färbt Werte und Symbole der Leiste nach ihrer Bedeutung.", "Colors the bar's values and symbols by meaning.")
        graphFitButton.title = LocalizedText.text("Graph an vorhandene Daten anpassen", "Fit graph to available data")
        showLabelsButton.title = LocalizedText.text("Werte mit Bezeichnung anzeigen", "Show labels next to values")
        showMetricSymbolsButton.title = LocalizedText.text("Symbole vor den Werten anzeigen", "Show symbols before values")
        showEnergyFlowArrowsButton.title = LocalizedText.text("Flussrichtung anzeigen", "Show flow direction")
        showFlowColorsButton.title = LocalizedText.text("Farbige Werte anzeigen", "Show colored values")
        lockDetachedMenuBarButton.title = LocalizedText.text("Abgedockte Leiste fixieren", "Lock detached slim bar")
        autostartButton.title = LocalizedText.text("Beim Login automatisch starten", "Start automatically at login")
        for popup in [detachedLevelPopup, dashboardLevelPopup, graphLevelPopup] {
            let index = popup.indexOfSelectedItem
            popup.removeAllItems()
            popup.addItems(withTitles: WindowLevelMode.allCases.map(\.title))
            if index >= 0 { popup.selectItem(at: index) }
        }
        detachedLevelPopup.toolTip = LocalizedText.text(
            "Legt fest, wo die Leiste im Fensterstapel liegt: über allen Fenstern, normal eingereiht oder auf dem Schreibtisch hinter allen Fenstern.",
            "Controls where the bar sits in the window stack: above all windows, ordered like a normal window, or on the desktop behind everything."
        )
        dashboardLevelPopup.toolTip = LocalizedText.text(
            "Gilt für das abgedockte Dashboard-Fenster: über allen Fenstern schwebend, normal eingereiht oder hinter allen Fenstern auf dem Schreibtisch.",
            "Applies to the detached dashboard window: floating above all windows, ordered like a normal window, or on the desktop behind everything."
        )
        graphLevelPopup.toolTip = LocalizedText.text(
            "Gilt für das abgedockte Verlaufsfenster: über allen Fenstern schwebend, normal eingereiht oder hinter allen Fenstern auf dem Schreibtisch.",
            "Applies to the detached history window: floating above all windows, ordered like a normal window, or on the desktop behind everything."
        )
    }

    private func menuBarPane() -> NSView {
        let container = NSView()
        let previewTitle = sectionTitle(LocalizedText.text("Vorschau", "Preview"))
        menuBarPreview.imageScaling = .scaleNone
        menuBarPreview.wantsLayer = true
        menuBarPreview.layer?.cornerRadius = Theme.radiusChip
        menuBarPreview.layer?.masksToBounds = true

        let metricTitle = sectionTitle(LocalizedText.text("Angezeigte Werte", "Visible Values"))
        let metricGrid = buildMetricGrid(for: .menuBar)
        let displayTitle = sectionTitle(LocalizedText.text("Darstellung", "Display"))
        let showIconRow = settingRow(showIconButton, help: showIconButton.toolTip ?? "")
        let stackedRow = settingRow(stackedButton, help: stackedButton.toolTip ?? "")
        let showLabelsRow = settingRow(showLabelsButton, help: showLabelsButton.toolTip ?? "")
        let showMetricSymbolsRow = settingRow(showMetricSymbolsButton, help: showMetricSymbolsButton.toolTip ?? "")
        let showFlowColorsRow = settingRow(showFlowColorsButton, help: showFlowColorsButton.toolTip ?? "")
        let showEnergyFlowArrowsRow = settingRow(showEnergyFlowArrowsButton, help: showEnergyFlowArrowsButton.toolTip ?? "")
        let scaleRow = NSStackView(views: [label(LocalizedText.text("Skalierung", "Scale")), scaleSlider, scaleValue, helpButton(labelTooltip("Skalierung"))])
        scaleRow.orientation = .horizontal
        scaleRow.spacing = 12
        scaleRow.alignment = .centerY
        scaleValue.alignment = .right
        scaleValue.widthAnchor.constraint(equalToConstant: 56).isActive = true

        for view in [previewTitle, menuBarPreview, metricTitle, metricGrid, displayTitle, showIconRow, stackedRow, showLabelsRow, showMetricSymbolsRow, showFlowColorsRow, showEnergyFlowArrowsRow, scaleRow] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }

        NSLayoutConstraint.activate([
            previewTitle.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            previewTitle.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            menuBarPreview.topAnchor.constraint(equalTo: previewTitle.bottomAnchor, constant: 8),
            menuBarPreview.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            menuBarPreview.heightAnchor.constraint(equalToConstant: 62),

            metricTitle.topAnchor.constraint(equalTo: menuBarPreview.bottomAnchor, constant: 18),
            metricTitle.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            metricGrid.topAnchor.constraint(equalTo: metricTitle.bottomAnchor, constant: 10),
            metricGrid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            metricGrid.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),

            displayTitle.topAnchor.constraint(equalTo: metricGrid.bottomAnchor, constant: 24),
            displayTitle.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            showIconRow.topAnchor.constraint(equalTo: displayTitle.bottomAnchor, constant: 10),
            showIconRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            stackedRow.topAnchor.constraint(equalTo: showIconRow.bottomAnchor, constant: 8),
            stackedRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            showLabelsRow.topAnchor.constraint(equalTo: stackedRow.bottomAnchor, constant: 8),
            showLabelsRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            showMetricSymbolsRow.topAnchor.constraint(equalTo: showLabelsRow.bottomAnchor, constant: 8),
            showMetricSymbolsRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            showFlowColorsRow.topAnchor.constraint(equalTo: showMetricSymbolsRow.bottomAnchor, constant: 8),
            showFlowColorsRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            showEnergyFlowArrowsRow.topAnchor.constraint(equalTo: showFlowColorsRow.bottomAnchor, constant: 8),
            showEnergyFlowArrowsRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            scaleRow.topAnchor.constraint(equalTo: showEnergyFlowArrowsRow.bottomAnchor, constant: 16),
            scaleRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            scaleRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24)
        ])

        return container
    }

    /// Eigener Tab für die abgedockte Leiste: eigene Werte-Auswahl,
    /// Kompaktanzeige, Fixieren und Skalierung.
    private func detachedPane() -> NSView {
        let container = NSView()
        let metricTitle = sectionTitle(LocalizedText.text("Angezeigte Werte", "Visible Values"))
        let metricGrid = buildMetricGrid(for: .detachedBar)
        let displayTitle = sectionTitle(LocalizedText.text("Darstellung", "Display"))
        let stackedDetachedRow = settingRow(stackedDetachedButton, help: stackedDetachedButton.toolTip ?? "")
        let iconRow = settingRow(detachedIconButton, help: detachedIconButton.toolTip ?? "")
        let labelsRow = settingRow(detachedLabelsButton, help: detachedLabelsButton.toolTip ?? "")
        let symbolsRow = settingRow(detachedSymbolsButton, help: detachedSymbolsButton.toolTip ?? "")
        let colorsRow = settingRow(detachedFlowColorsButton, help: detachedFlowColorsButton.toolTip ?? "")
        let arrowsRow = settingRow(detachedArrowsButton, help: detachedArrowsButton.toolTip ?? "")
        let lockRow = settingRow(lockDetachedMenuBarButton, help: lockDetachedMenuBarButton.toolTip ?? "")
        let levelRow = NSStackView(views: [
            label(LocalizedText.text("Fensterebene", "Window level")),
            detachedLevelPopup,
            helpButton(detachedLevelPopup.toolTip ?? "")
        ])
        levelRow.orientation = .horizontal
        levelRow.spacing = 12
        levelRow.alignment = .centerY
        let detachedScaleRow = NSStackView(views: [label(LocalizedText.text("Skalierung", "Scale")), detachedScaleSlider, detachedScaleValue, helpButton(labelTooltip("Abgedockt"))])
        detachedScaleRow.orientation = .horizontal
        detachedScaleRow.spacing = 12
        detachedScaleRow.alignment = .centerY
        detachedScaleValue.alignment = .right
        detachedScaleValue.widthAnchor.constraint(equalToConstant: 56).isActive = true
        let hint = NSTextField(wrappingLabelWithString: LocalizedText.text(
            "Die Leiste lässt sich frei verschieben: einfach am Hintergrund ziehen. Fixieren verhindert versehentliches Verschieben.",
            "Move the bar anywhere by dragging its background. Locking prevents accidental moves."
        ))
        hint.textColor = .secondaryLabelColor

        for view in [metricTitle, metricGrid, displayTitle, stackedDetachedRow, iconRow, labelsRow, symbolsRow, colorsRow, arrowsRow, lockRow, levelRow, detachedScaleRow, hint] {
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

            stackedDetachedRow.topAnchor.constraint(equalTo: displayTitle.bottomAnchor, constant: 10),
            stackedDetachedRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            iconRow.topAnchor.constraint(equalTo: stackedDetachedRow.bottomAnchor, constant: 8),
            iconRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            labelsRow.topAnchor.constraint(equalTo: iconRow.bottomAnchor, constant: 8),
            labelsRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            symbolsRow.topAnchor.constraint(equalTo: labelsRow.bottomAnchor, constant: 8),
            symbolsRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            colorsRow.topAnchor.constraint(equalTo: symbolsRow.bottomAnchor, constant: 8),
            colorsRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            arrowsRow.topAnchor.constraint(equalTo: colorsRow.bottomAnchor, constant: 8),
            arrowsRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            lockRow.topAnchor.constraint(equalTo: arrowsRow.bottomAnchor, constant: 8),
            lockRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            levelRow.topAnchor.constraint(equalTo: lockRow.bottomAnchor, constant: 12),
            levelRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            detachedScaleRow.topAnchor.constraint(equalTo: levelRow.bottomAnchor, constant: 12),
            detachedScaleRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            detachedScaleRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),

            hint.topAnchor.constraint(equalTo: detachedScaleRow.bottomAnchor, constant: 18),
            hint.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            hint.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24)
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

    /// Darstellung, Sprache und Startverhalten in einem Tab — der frühere
    /// eigene "Start"-Tab enthielt nur eine einzige Checkbox.
    private func appPane() -> NSView {
        let container = NSView()
        let title = sectionTitle(LocalizedText.text("App-Darstellung", "App Appearance"))
        let appearanceRow = formRow(labelText: LocalizedText.text("Design", "Theme"), control: appearancePopup)
        let languageRow = formRow(labelText: LocalizedText.text("Sprache", "Language"), control: languagePopup)
        let dashboardTitle = sectionTitle(LocalizedText.text("Dashboard", "Dashboard"))
        let graphFitRow = settingRow(graphFitButton, help: graphFitButton.toolTip ?? "")
        customRangeField.alignment = .center
        customRangeField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        customRangeField.target = self
        customRangeField.action = #selector(applyPreview)
        customRangeField.delegate = self
        customRangeField.toolTip = LocalizedText.text(
            "Dauer des eigenen Zeitraums (Chip \"Eig.\" im Verlauf).",
            "Duration of the custom range (chip \"Eig.\" in the history)."
        )
        customRangeUnitPopup.target = self
        customRangeUnitPopup.action = #selector(applyPreview)
        customRangeUnitPopup.addItems(withTitles: [
            LocalizedText.text("Stunden", "hours"),
            LocalizedText.text("Tage", "days"),
            LocalizedText.text("Wochen", "weeks"),
            LocalizedText.text("Monate", "months")
        ])
        let customRangeStack = NSStackView(views: [customRangeField, customRangeUnitPopup])
        customRangeStack.orientation = .horizontal
        customRangeStack.spacing = 8
        customRangeField.widthAnchor.constraint(equalToConstant: 64).isActive = true
        let customRangeRow = NSStackView(views: [
            label(LocalizedText.text("Eig. Zeitraum", "Custom range")),
            customRangeStack,
            helpButton(customRangeField.toolTip ?? "")
        ])
        customRangeRow.orientation = .horizontal
        customRangeRow.spacing = 12
        customRangeRow.alignment = .centerY
        let dashboardLevelRow = NSStackView(views: [
            label(LocalizedText.text("Fensterebene", "Window level")),
            dashboardLevelPopup,
            helpButton(dashboardLevelPopup.toolTip ?? "")
        ])
        dashboardLevelRow.orientation = .horizontal
        dashboardLevelRow.spacing = 12
        dashboardLevelRow.alignment = .centerY
        let graphLevelRow = NSStackView(views: [
            label(LocalizedText.text("Verlaufsfenster", "History window")),
            graphLevelPopup,
            helpButton(graphLevelPopup.toolTip ?? "")
        ])
        graphLevelRow.orientation = .horizontal
        graphLevelRow.spacing = 12
        graphLevelRow.alignment = .centerY
        let startTitle = sectionTitle(LocalizedText.text("Startverhalten", "Startup"))
        let autostartRow = settingRow(autostartButton, help: autostartButton.toolTip ?? "")
        let hint = NSTextField(wrappingLabelWithString: LocalizedText.text(
            "Änderungen wirken sofort als Vorschau. Erst Speichern macht sie dauerhaft.",
            "Changes apply immediately as a preview. Press Save to keep them."
        ))
        hint.textColor = .secondaryLabelColor

        for view in [title, appearanceRow, languageRow, dashboardTitle, graphFitRow, customRangeRow, dashboardLevelRow, graphLevelRow, startTitle, autostartRow, autostartStatus, hint] {
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

            dashboardTitle.topAnchor.constraint(equalTo: languageRow.bottomAnchor, constant: 24),
            dashboardTitle.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            graphFitRow.topAnchor.constraint(equalTo: dashboardTitle.bottomAnchor, constant: 10),
            graphFitRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            customRangeRow.topAnchor.constraint(equalTo: graphFitRow.bottomAnchor, constant: 10),
            customRangeRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            dashboardLevelRow.topAnchor.constraint(equalTo: customRangeRow.bottomAnchor, constant: 10),
            dashboardLevelRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            graphLevelRow.topAnchor.constraint(equalTo: dashboardLevelRow.bottomAnchor, constant: 10),
            graphLevelRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            startTitle.topAnchor.constraint(equalTo: graphLevelRow.bottomAnchor, constant: 24),
            startTitle.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            autostartRow.topAnchor.constraint(equalTo: startTitle.bottomAnchor, constant: 12),
            autostartRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),

            autostartStatus.topAnchor.constraint(equalTo: autostartRow.bottomAnchor, constant: 8),
            autostartStatus.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            autostartStatus.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),

            hint.topAnchor.constraint(equalTo: autostartStatus.bottomAnchor, constant: 18),
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


    private enum MetricGridTarget {
        case menuBar
        case detachedBar
    }

    private func buildMetricGrid(for target: MetricGridTarget) -> NSGridView {
        let rows = [
            [BarMetric.battery, .solar, .home],
            [BarMetric.grid, .batteryFlow, .today],
            [BarMetric.total, .status]
        ].map { metrics in
            metrics.map { metric in
                let button = NSButton(checkboxWithTitle: localizedMetricTitle(metric), target: self, action: #selector(applyPreview))
                button.toolTip = metricTooltip(metric)
                switch target {
                case .menuBar:
                    metricButtons[metric] = button
                case .detachedBar:
                    detachedMetricButtons[metric] = button
                }
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

    /// Dezentes, klickbares Hilfesymbol: öffnet ein Popover mit dem Hilfetext.
    /// Vorher: fettes "?"-Textlabel, das klickbar aussah, aber nur einen
    /// Hover-Tooltip hatte.
    private func helpButton(_ tooltip: String) -> NSButton {
        let button = NSButton(title: "", target: self, action: #selector(showHelpPopover(_:)))
        button.isBordered = false
        button.image = Self.helpGlyph
        button.contentTintColor = .tertiaryLabelColor
        button.toolTip = tooltip
        button.setButtonType(.momentaryChange)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 18).isActive = true
        button.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return button
    }

    private static let helpGlyph: NSImage? = {
        let image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: "Hilfe")
        return image?.withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
    }()

    @objc private func showHelpPopover(_ sender: NSButton) {
        guard let text = sender.toolTip, !text.isEmpty else { return }
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .labelColor
        label.preferredMaxLayoutWidth = 260
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 260)
        ])

        let controller = NSViewController()
        controller.view = container
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.contentSize = container.fittingSize
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
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
            return "Korrigiert den heutigen Ertrag in kWh, wenn Anker für heute 0 kWh liefert."
        case "Gesamtertrag", "Total yield":
            return LocalizedText.text(
                "Setzt optional den Gesamtertrag aus der Anker-App als Startwert. Ohne API-Gesamtwert zählt SolixBar alle fortlaufenden Messungen zusammen.",
                "Optionally sets the Anker app total as a starting value. Without an API total, SolixBar adds up all continuous measurements."
            )
        case "Befehl", "Command":
            return "Der lokale Befehl muss ein JSON-Objekt ausgeben."
        case "URL":
            return "Die Adresse muss ein JSON-Objekt liefern."
        case "Intervall", "Interval":
            return "Legt fest, wie oft neue Daten geholt werden."
        case "Design", "Theme":
            return "Wählt Hell, Dunkel oder Automatisch passend zum System."
        case "Sprache", "Language":
            return "Wählt Deutsch oder Englisch für sichtbare App-Texte."
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
        stackedButton.state = settings.menuBarStacked ? .on : .off
        stackedDetachedButton.state = settings.detachedBarStacked ? .on : .off
        graphFitButton.state = settings.graphFitsData ? .on : .off
        customRangeField.stringValue = String(
            HistoryGraphMenuView.customValue(days: settings.customHistoryDays, unit: settings.customHistoryUnit)
        )
        let unitIndex = ["hours", "days", "weeks", "months"].firstIndex(of: settings.customHistoryUnit) ?? 1
        customRangeUnitPopup.selectItem(at: unitIndex)
        detachedLevelPopup.selectItem(at: WindowLevelMode.allCases.firstIndex(of: settings.detachedBarLevel) ?? 0)
        dashboardLevelPopup.selectItem(at: WindowLevelMode.allCases.firstIndex(of: settings.dashboardWindowLevel) ?? 0)
        graphLevelPopup.selectItem(at: WindowLevelMode.allCases.firstIndex(of: settings.graphWindowLevel) ?? 0)
        detachedIconButton.state = settings.detachedShowIcon ? .on : .off
        detachedLabelsButton.state = settings.detachedShowLabels ? .on : .off
        detachedSymbolsButton.state = settings.detachedShowSymbols ? .on : .off
        detachedArrowsButton.state = settings.detachedShowArrows ? .on : .off
        showLabelsButton.state = settings.showMetricLabels ? .on : .off
        showMetricSymbolsButton.state = settings.showMenuBarMetricSymbols ? .on : .off
        showEnergyFlowArrowsButton.state = settings.showEnergyFlowArrows ? .on : .off
        showFlowColorsButton.state = settings.showFlowColors ? .on : .off
        detachedFlowColorsButton.state = settings.detachedShowFlowColors ? .on : .off
        lockDetachedMenuBarButton.state = settings.lockDetachedMenuBar ? .on : .off
        scaleSlider.doubleValue = settings.menuBarScale
        scaleValue.stringValue = "\(Int(round(scaleSlider.doubleValue * 100))) %"
        detachedScaleSlider.doubleValue = settings.detachedMenuBarScale
        detachedScaleValue.stringValue = "\(Int(round(detachedScaleSlider.doubleValue * 100))) %"

        let selected = Set(settings.barMetrics)
        for metric in BarMetric.allCases {
            metricButtons[metric]?.state = selected.contains(metric) ? .on : .off
        }
        let detachedSelected = Set(settings.detachedBarMetrics)
        for metric in BarMetric.allCases {
            detachedMetricButtons[metric]?.state = detachedSelected.contains(metric) ? .on : .off
        }
        refreshAutostartState()
        updateDataSourceFieldVisibility()
        updateMenuBarPreview()
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
        settings.detachedBarMetrics = BarMetric.allCases.filter { detachedMetricButtons[$0]?.state == .on }
        settings.showMenuBarIcon = showIconButton.state == .on
        settings.menuBarStacked = stackedButton.state == .on
        settings.detachedBarStacked = stackedDetachedButton.state == .on
        settings.graphFitsData = graphFitButton.state == .on
        let unitKeys = ["hours", "days", "weeks", "months"]
        let selectedUnit = unitKeys[max(0, min(unitKeys.count - 1, customRangeUnitPopup.indexOfSelectedItem))]
        settings.customHistoryUnit = selectedUnit
        let value = max(1, customRangeField.integerValue)
        settings.customHistoryDays = min(365, HistoryGraphMenuView.days(fromValue: value, unit: selectedUnit))
        let levelModes = WindowLevelMode.allCases
        settings.detachedBarLevel = levelModes[max(0, min(levelModes.count - 1, detachedLevelPopup.indexOfSelectedItem))]
        settings.dashboardWindowLevel = levelModes[max(0, min(levelModes.count - 1, dashboardLevelPopup.indexOfSelectedItem))]
        settings.graphWindowLevel = levelModes[max(0, min(levelModes.count - 1, graphLevelPopup.indexOfSelectedItem))]
        settings.detachedShowIcon = detachedIconButton.state == .on
        settings.detachedShowLabels = detachedLabelsButton.state == .on
        settings.detachedShowSymbols = detachedSymbolsButton.state == .on
        settings.detachedShowArrows = detachedArrowsButton.state == .on
        settings.showMetricLabels = showLabelsButton.state == .on
        settings.showMenuBarMetricSymbols = showMetricSymbolsButton.state == .on
        settings.showEnergyFlowArrows = showEnergyFlowArrowsButton.state == .on
        settings.showFlowColors = showFlowColorsButton.state == .on
        settings.detachedShowFlowColors = detachedFlowColorsButton.state == .on
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
        updateMenuBarPreview()
        onPreview()
    }

    /// Live-Vorschau der Menüleisten-Anzeige (Demo-Werte) in heller und
    /// dunkler Menüleiste — nutzt exakt dieselbe Formatter-Engine wie die App.
    private func updateMenuBarPreview() {
        let snapshot = SolixSnapshot.demo
        let options = MenuBarDisplayOptions(
            metrics: settings.barMetrics,
            showLabels: settings.showMetricLabels,
            showSymbols: settings.showMenuBarMetricSymbols,
            showArrows: settings.showEnergyFlowArrows,
            showColors: settings.showFlowColors
        )
        let stripWidth: CGFloat = 560
        let stripHeight: CGFloat = 28
        let image = NSImage(size: NSSize(width: stripWidth, height: stripHeight * 2 + 6), flipped: false) { [self] _ in
            let strips: [(NSAppearance.Name, NSColor, CGFloat)] = [
                (.darkAqua, NSColor(calibratedWhite: 0.13, alpha: 1), 0),
                (.aqua, NSColor(calibratedWhite: 0.93, alpha: 1), stripHeight + 6)
            ]
            for (appearanceName, background, y) in strips {
                NSAppearance(named: appearanceName)?.performAsCurrentDrawingAppearance {
                    let strip = NSRect(x: 0, y: y, width: stripWidth, height: stripHeight)
                    background.setFill()
                    NSBezierPath(roundedRect: strip, xRadius: 6, yRadius: 6).fill()
                    if settings.menuBarStacked {
                        let entries = previewFormatter.stackedEntries(for: snapshot, options: options)
                        if entries.count >= 2,
                           let stacked = StackedMenuBarRenderer.image(
                               entries: entries,
                               scale: settings.menuBarScale,
                               showWarning: false
                           ) {
                            stacked.draw(
                                in: NSRect(x: 12, y: y + (stripHeight - 22) / 2, width: stacked.size.width, height: 22),
                                from: .zero,
                                operation: .sourceOver,
                                fraction: 1
                            )
                            return
                        }
                    }
                    let text = previewFormatter.attributedTitle(for: snapshot, scale: settings.menuBarScale, options: options)
                    let size = text.size()
                    text.draw(at: NSPoint(x: 12, y: y + (stripHeight - size.height) / 2))
                }
            }
            return true
        }
        menuBarPreview.image = image
        menuBarPreview.widthAnchor.constraint(equalToConstant: stripWidth).isActive = true
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

    /// Textänderungen entprellen: Vorher schrieb jeder einzelne Tastendruck
    /// halbfertige URLs/Befehle live in die Settings (und störte laufende
    /// Refreshes).
    func controlTextDidChange(_ obj: Notification) {
        previewDebounce?.invalidate()
        previewDebounce = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.applyPreview()
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !isSaving, let originalSettings, settings.snapshot() != originalSettings else { return true }
        let alert = NSAlert()
        alert.messageText = LocalizedText.text("Änderungen speichern?", "Save changes?")
        alert.informativeText = LocalizedText.text(
            "Die Vorschau-Änderungen gehen sonst verloren.",
            "Otherwise the previewed changes will be lost."
        )
        alert.addButton(withTitle: LocalizedText.text("Speichern", "Save"))
        alert.addButton(withTitle: LocalizedText.text("Verwerfen", "Discard"))
        alert.addButton(withTitle: LocalizedText.text("Abbrechen", "Cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            saveSettings()
            return false
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
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
        // Passwort bevorzugt aus dem Schlüsselbund; Env-Eintrag ist Altbestand.
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

        // Passwort in den Schlüsselbund; die Env-Datei enthält keine Secrets.
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
