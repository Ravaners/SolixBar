import Foundation

/// Ausführliche Hilfetexte für die ?-Knöpfe der Einstellungen.
///
/// Der Hover-Tooltip bleibt der kurze Hinweis; ein Klick auf das ?
/// zeigt den ausführlichen Text aus diesem Katalog. Nachgeschlagen wird
/// über den kurzen Text (deutsch oder englisch) — ändert sich ein
/// Tooltip, fällt der Knopf still auf den kurzen Text zurück, es geht
/// also nie Information verloren.
enum SettingsHelp {
    @MainActor
    static func extended(for shortText: String) -> String? {
        for entry in entries where entry.keys.contains(shortText) {
            return LocalizedText.text(entry.de, entry.en)
        }
        return nil
    }

    private struct Entry {
        let keys: [String]
        let de: String
        let en: String
    }

    private static let entries: [Entry] = [
        // MARK: Datenquelle
        Entry(
            keys: [
                "Legt fest, woher SolixBar die Werte lädt.",
                "Legt fest, woher SolixBar die Werte lädt. \"SOLIX-Konto (direkt)\" fragt Anker mit Mail und Passwort direkt ab. \"Demo (Warnungs-Test)\" spielt ein gerafftes Szenario ab (Akku fällt, PV-Eingang stirbt, kompletter Einbruch), damit aktivierte Warnungen innerhalb weniger Minuten wirklich feuern.",
                "Controls where SolixBar loads its values from. \"SOLIX account (direct)\" queries Anker directly with email and password. \"Demo (warning test)\" plays an accelerated scenario (battery drops, one PV input dies, full collapse) so enabled warnings actually fire within a few minutes."
            ],
            de: """
            Hier wählst du, woher SolixBar seine Werte bekommt:

            • SOLIX-Konto (direkt) — der empfohlene Weg. SolixBar fragt Anker direkt mit deiner Mail und deinem Passwort ab. Es muss nichts installiert werden.
            • Demo — erfundene Beispielwerte, um die Anzeige gefahrlos auszuprobieren.
            • Demo (Warnungs-Test) — spielt in wenigen Minuten ein Szenario durch (Akku fällt, ein PV-Eingang stirbt, kompletter Einbruch), damit du aktivierte Warnungen wirklich einmal feuern siehst.
            • Lokaler JSON-Befehl — für Fortgeschrittene: ein eigenes Programm liefert die Werte.
            • JSON-URL — die Werte kommen von einer Web-Adresse, z. B. aus deiner Hausautomation.
            """,
            en: """
            This selects where SolixBar gets its values from:

            • SOLIX account (direct) — the recommended way. SolixBar queries Anker directly with your email and password. Nothing needs to be installed.
            • Demo — made-up sample values to safely explore the display.
            • Demo (warning test) — plays through a scenario within minutes (battery drops, one PV input dies, full collapse) so you can watch enabled warnings actually fire.
            • Local JSON command — for advanced users: your own program supplies the values.
            • JSON URL — values come from a web address, e.g. your home automation.
            """
        ),
        Entry(
            keys: ["E-Mail-Adresse deines Anker/SOLIX-Kontos."],
            de: "Die Mail-Adresse, mit der du dich auch in der Anker-App anmeldest. Sie wird nur auf deinem Mac gespeichert (in einer lokalen Datei mit strengen Dateirechten) und ausschliesslich an Anker übertragen, um deine Werte abzurufen.",
            en: "The email address you also use to sign in to the Anker app. It is stored only on your Mac (in a local file with strict permissions) and transmitted exclusively to Anker to fetch your values."
        ),
        Entry(
            keys: ["Passwort deines Anker/SOLIX-Kontos. Wird sicher im macOS-Schlüsselbund gespeichert und nie hochgeladen."],
            de: "Das Passwort deines Anker-Kontos. Es landet ausschliesslich im macOS-Schlüsselbund — dort, wo macOS auch deine anderen Passwörter schützt — und wird nur zur Anmeldung an Anker geschickt, nie an andere Server. Wenn du das Passwort in der Anker-App änderst, trage es hier neu ein.",
            en: "Your Anker account password. It is kept exclusively in the macOS Keychain — where macOS protects your other passwords too — and is only sent to Anker to sign in, never to any other server. If you change the password in the Anker app, re-enter it here."
        ),
        Entry(
            keys: ["Land deines Anker-Kontos, normalerweise DE."],
            de: "Der Zwei-Buchstaben-Ländercode deines Anker-Kontos, z. B. DE für Deutschland oder AT für Österreich. Anker betreibt je Region eigene Server — mit dem falschen Land schlägt die Anmeldung fehl. Im Zweifel: das Land, in dem du das Konto angelegt hast.",
            en: "The two-letter country code of your Anker account, e.g. DE for Germany or AT for Austria. Anker runs separate servers per region — the wrong country makes the sign-in fail. When in doubt: the country where you created the account."
        ),
        Entry(
            keys: ["Optionaler Korrekturwert für den heutigen Ertrag in kWh, falls Anker heute 0 kWh meldet. SolixBar zählt ab diesem Wert weiter."],
            de: "Normalerweise leer lassen. Nur wenn Anker für heute fälschlich 0 kWh meldet (das passiert bei manchen Anlagen), kannst du hier den echten heutigen Ertrag aus der Anker-App eintragen. SolixBar zählt dann ab diesem Wert weiter. Der Wert gilt nur für den heutigen Tag und läuft danach automatisch aus.",
            en: "Normally leave this empty. Only if Anker wrongly reports 0 kWh for today (this happens with some systems), enter today's real yield from the Anker app here. SolixBar then keeps counting from that value. It only applies to today and expires automatically afterwards."
        ),
        Entry(
            keys: [
                "Optionaler Startwert für den Gesamtertrag. Ohne API-Gesamtwert kumuliert SolixBar alle fortlaufenden Solarmessungen lokal.",
                "Optional starting value for total yield. Without an API total, SolixBar locally accumulates all continuous solar measurements.",
                "Setzt optional den Gesamtertrag aus der Anker-App als Startwert. Ohne API-Gesamtwert zählt SolixBar alle fortlaufenden Messungen zusammen.",
                "Optionally sets the Anker app total as a starting value. Without an API total, SolixBar adds up all continuous measurements."
            ],
            de: "Normalerweise leer lassen. Liefert Anker keinen Gesamtertrag über die Schnittstelle, summiert SolixBar deine Solarmessungen selbst auf — beginnend bei 0. Damit die Zählung nicht bei 0 startet, kannst du hier einmalig den Gesamtertrag aus der Anker-App als Startwert eintragen; SolixBar zählt dann dauerhaft ab diesem Wert weiter.",
            en: "Normally leave this empty. If Anker does not provide a total yield via its interface, SolixBar accumulates your solar measurements itself — starting at 0. To avoid starting at 0, you can enter the total from the Anker app once as a starting value; SolixBar then keeps counting from it permanently."
        ),
        Entry(
            keys: ["Führt einen lokalen Befehl aus und liest dessen JSON-Ausgabe."],
            de: "Für Fortgeschrittene: SolixBar führt bei jeder Aktualisierung diesen Shell-Befehl aus und liest die Werte aus seiner JSON-Ausgabe (Felder wie batteryPercent, solarWatts, homeWatts, updatedAt — das vollständige Format steht im README). So kannst du eigene Skripte oder andere Datenquellen anbinden. Für den normalen SOLIX-Abruf brauchst du das nicht — nimm dafür \"SOLIX-Konto (direkt)\".",
            en: "For advanced users: on every refresh SolixBar runs this shell command and reads the values from its JSON output (fields like batteryPercent, solarWatts, homeWatts, updatedAt — the full format is in the README). This lets you hook up your own scripts or other data sources. For the normal SOLIX access you don't need this — use \"SOLIX account (direct)\" instead.",
        ),
        Entry(
            keys: ["Lädt die Werte von einer JSON-Adresse."],
            de: "SolixBar lädt die Werte bei jeder Aktualisierung von dieser HTTP-Adresse, z. B. von einer Bridge in deiner Hausautomation (Home Assistant, ioBroker …) oder einem eigenen kleinen Server. Die Antwort muss ein JSON-Objekt mit Feldern wie batteryPercent, solarWatts und updatedAt sein — das vollständige Format steht im README.",
            en: "SolixBar fetches the values from this HTTP address on every refresh, e.g. from a bridge in your home automation (Home Assistant, ioBroker …) or a small server of your own. The response must be a JSON object with fields like batteryPercent, solarWatts, and updatedAt — the full format is in the README."
        ),
        Entry(
            keys: ["Zeit zwischen zwei Aktualisierungen in Sekunden.", "Legt fest, wie oft neue Daten geholt werden."],
            de: "So viele Sekunden wartet SolixBar zwischen zwei Abrufen (mindestens 60). Kürzer heisst aktuellere Werte, aber mehr Anfragen an Anker. 300 Sekunden (5 Minuten) sind ein guter Alltagswert. Schlagen Abrufe fehl, verdoppelt SolixBar den Abstand automatisch bis maximal 30 Minuten und kehrt beim ersten Erfolg zu deinem Intervall zurück.",
            en: "How many seconds SolixBar waits between two refreshes (at least 60). Shorter means fresher values but more requests to Anker. 300 seconds (5 minutes) is a good everyday value. If refreshes fail, SolixBar automatically doubles the delay up to 30 minutes and returns to your interval on the first success."
        ),

        // MARK: Menüleiste
        Entry(
            keys: ["Zeigt oder versteckt das SolixBar-Symbol in der Menüleiste."],
            de: "Zeigt links neben den Werten das kleine Blitz-Symbol von SolixBar. Ausgeschaltet sparst du ein paar Pixel Platz in der Menüleiste — die Werte bleiben natürlich sichtbar.",
            en: "Shows SolixBar's small bolt icon to the left of the values. Turning it off saves a few pixels of menu bar space — the values of course stay visible."
        ),
        Entry(
            keys: ["Zeigt die Werte in zwei kompakten Zeilen übereinander — halbe Breite bei gleicher Information, praktisch auf MacBooks mit Notch."],
            de: "Ordnet die Werte in zwei kleinen Zeilen übereinander statt nebeneinander. Die Anzeige wird dadurch nur halb so breit — bei gleicher Information. Besonders praktisch auf MacBooks mit Notch, wo Platz in der Menüleiste knapp ist. Welche Werte in der Kompaktansicht erscheinen, stellst du in der Liste darunter ein.",
            en: "Arranges the values in two small stacked lines instead of side by side. The display becomes only half as wide — with the same information. Especially handy on MacBooks with a notch, where menu bar space is tight. Which values appear in the compact view is configured in the list below."
        ),
        Entry(
            keys: ["Zeigt kurze Namen wie Akku oder Solar vor den Zahlen.", "Shows short names like Battery or Solar before the numbers."],
            de: "Stellt kurze Namen wie \"Akku\" oder \"PV\" vor die Zahlen, damit sofort klar ist, was welcher Wert bedeutet. Ausgeschaltet stehen nur die Zahlen da — schmaler, aber du musst die Reihenfolge im Kopf haben.",
            en: "Puts short names like \"Akku\" or \"PV\" in front of the numbers so it's immediately clear what each value means. Turned off, only the numbers remain — narrower, but you need to remember the order."
        ),
        Entry(
            keys: ["Zeigt farbige Symbole direkt vor den Menüleistenwerten."],
            de: "Zeigt vor jedem Wert ein kleines farbiges Symbol (Batterie, Sonne, Haus, Netz). Die Werte lassen sich damit auf einen Blick zuordnen, ohne Text lesen zu müssen — eine gute platzsparende Alternative zu den Bezeichnungen.",
            en: "Shows a small colored symbol (battery, sun, house, grid) before each value. You can identify the values at a glance without reading text — a good space-saving alternative to the labels."
        ),
        Entry(
            keys: ["Färbt Werte und Symbole nach ihrer Bedeutung (Akku grün, Solar gelb, Netzbezug rot, Einspeisung violett). Ohne Farben bleibt die Anzeige einfarbig."],
            de: "Färbt die Werte nach ihrer Bedeutung: Akku grün, Solar gelb, Netzbezug rot, Einspeisung violett. So erkennst du z. B. teuren Netzbezug sofort an der Farbe. Ausgeschaltet bleibt alles dezent einfarbig wie die übrige Menüleiste.",
            en: "Colors the values by meaning: battery green, solar yellow, grid import red, feed-in purple. That way you spot e.g. expensive grid import instantly by color. Turned off, everything stays subtly monochrome like the rest of the menu bar."
        ),
        Entry(
            keys: ["Zeigt Richtungspfeile und Begriffe wie Laden, Entladen, Bezug und Einspeisen; Wattwerte erscheinen dann ohne Vorzeichen."],
            de: "Zeigt zu Akku und Netz die Richtung des Energieflusses: Pfeile und Begriffe wie \"Laden\", \"Entladen\", \"Bezug\" oder \"Einspeisen\". Die Wattwerte erscheinen dann ohne Plus/Minus — die Richtung steckt ja schon im Begriff. Ausgeschaltet zeigen Vorzeichen die Richtung an (z. B. -86 W = Einspeisung).",
            en: "Shows the direction of energy flow for battery and grid: arrows and terms like \"charging\", \"discharging\", \"import\", or \"feed-in\". Watt values then appear without plus/minus — the direction is already in the term. Turned off, signs indicate the direction (e.g. -86 W = feed-in)."
        ),
        Entry(
            keys: [
                "PV-Wert in der Menüleiste: Summe (\"642W\"), Einzelwerte (\"438·204W\") oder beides (\"642W (438·204)\") — gilt für einzeilige und Kompaktansicht. Einzelwerte brauchen Kanal-Reporting (Solarbank 2/3).",
                "PV value in the menu bar: total (\"642W\"), individual inputs (\"438·204W\"), or both (\"642W (438·204)\") — applies to single-line and compact views. Individual values require channel reporting (Solarbank 2/3)."
            ],
            de: "Bestimmt, wie der Solarwert in der Menüleiste erscheint:\n\n• Gesamt — nur die Summe, z. B. \"642W\".\n• Einzeln — jeder Modul-Eingang für sich, z. B. \"438·204W\". So siehst du sofort, wenn ein Modul schwächelt.\n• Beides — Summe plus Einzelwerte, z. B. \"642W (438·204)\".\n\nEinzelwerte gibt es nur, wenn deine Solarbank die Eingänge einzeln meldet (Solarbank 2 und 3); ältere Modelle zeigen immer die Summe.",
            en: "Determines how the solar value appears in the menu bar:\n\n• Total — just the sum, e.g. \"642W\".\n• Individual — each panel input separately, e.g. \"438·204W\". You instantly see when one panel underperforms.\n• Both — sum plus individual values, e.g. \"642W (438·204)\".\n\nIndividual values are only available if your Solarbank reports its inputs separately (Solarbank 2 and 3); older models always show the total."
        ),
        Entry(
            keys: ["Passt die Größe der Menüleistenanzeige an."],
            de: "Vergrössert oder verkleinert Text und Symbole der Menüleistenanzeige stufenlos. Kleiner spart Platz neben der Notch, grösser liest sich leichter — probiere es einfach aus, die Vorschau unten zeigt sofort das Ergebnis.",
            en: "Scales the menu bar display's text and symbols up or down continuously. Smaller saves space next to the notch, larger is easier to read — just try it, the preview below shows the result immediately."
        ),

        // MARK: Abgedockte Leiste
        Entry(
            keys: ["Nutzt die zweizeilige Kompaktanzeige auch in der abgedockten Leiste — macht sie etwa halb so lang."],
            de: "Ordnet die Werte auch in der abgedockten Leiste in zwei kompakten Zeilen übereinander — die Leiste wird dadurch etwa halb so lang. Welche Werte dort erscheinen, stellst du in der Liste darunter ein.",
            en: "Arranges the values in the detached bar in two compact stacked lines as well — making the bar roughly half as long. Which values appear there is configured in the list below."
        ),
        Entry(
            keys: ["Zeigt das Blitz-Symbol links in der Leiste.", "Shows the bolt glyph at the left of the bar."],
            de: "Zeigt das kleine Blitz-Symbol von SolixBar am linken Rand der abgedockten Leiste. Ausgeschaltet beginnt die Leiste direkt mit den Werten.",
            en: "Shows SolixBar's small bolt glyph at the left edge of the detached bar. Turned off, the bar starts directly with the values."
        ),
        Entry(
            keys: ["Zeigt farbige Symbole direkt vor den Werten.", "Shows colored symbols right before the values."],
            de: "Zeigt vor jedem Wert der abgedockten Leiste ein kleines farbiges Symbol (Batterie, Sonne, Haus, Netz) — so ordnest du die Werte auf einen Blick zu.",
            en: "Shows a small colored symbol (battery, sun, house, grid) before each value in the detached bar — so you can identify the values at a glance."
        ),
        Entry(
            keys: ["Richtungspfeile und Begriffe wie Laden oder Bezug in der Leiste; Wattwerte ohne Vorzeichen.", "Direction arrows and terms like charging or import in the bar; watt values without sign."],
            de: "Zeigt in der abgedockten Leiste die Richtung des Energieflusses mit Pfeilen und Begriffen wie \"Laden\" oder \"Bezug\". Die Wattwerte erscheinen dann ohne Plus/Minus. Ausgeschaltet zeigen Vorzeichen die Richtung an.",
            en: "Shows the direction of energy flow in the detached bar with arrows and terms like \"charging\" or \"import\". Watt values then appear without plus/minus. Turned off, signs indicate the direction."
        ),
        Entry(
            keys: ["Färbt Werte und Symbole der Leiste nach ihrer Bedeutung.", "Colors the bar's values and symbols by meaning."],
            de: "Färbt die Werte der abgedockten Leiste nach ihrer Bedeutung: Akku grün, Solar gelb, Netzbezug rot, Einspeisung violett. Ausgeschaltet bleibt die Leiste dezent einfarbig.",
            en: "Colors the detached bar's values by meaning: battery green, solar yellow, grid import red, feed-in purple. Turned off, the bar stays subtly monochrome."
        ),
        Entry(
            keys: ["Fixiert die abgedockte Leiste, damit sie nicht versehentlich verschoben wird."],
            de: "Verankert die abgedockte Leiste an ihrer Position, damit du sie beim Klicken nicht versehentlich verschiebst. Solange die Leiste fixiert ist, wird auch ihr Schliesskreuz ausgeblendet; zum Verschieben oder Schliessen einfach kurz wieder entfixieren.",
            en: "Anchors the detached bar in place so you don't accidentally drag it while clicking. While the bar is locked its close button is hidden as well; to move or close it, simply unlock it again briefly."
        ),
        Entry(
            keys: [
                "PV-Wert der abgedockten Leiste: Summe, Einzelwerte oder beides — gilt für einzeilige und Kompaktansicht. Einzelwerte brauchen Kanal-Reporting (Solarbank 2/3).",
                "PV value in the detached bar: total, individual inputs, or both — applies to single-line and compact views. Individual values require channel reporting (Solarbank 2/3)."
            ],
            de: "Bestimmt, wie der Solarwert in der abgedockten Leiste erscheint: nur die Summe, jeder Modul-Eingang einzeln (z. B. \"438·204W\") oder beides zusammen. Einzelwerte gibt es nur, wenn deine Solarbank die Eingänge einzeln meldet (Solarbank 2 und 3). Die Einstellung ist unabhängig von der Menüleiste.",
            en: "Determines how the solar value appears in the detached bar: just the total, each panel input separately (e.g. \"438·204W\"), or both together. Individual values are only available if your Solarbank reports its inputs separately (Solarbank 2 and 3). The setting is independent of the menu bar."
        ),
        Entry(
            keys: [
                "Legt fest, wo die Leiste im Fensterstapel liegt: über allen Fenstern, normal eingereiht oder auf dem Schreibtisch hinter allen Fenstern.",
                "Controls where the bar sits in the window stack: above all windows, ordered like a normal window, or on the desktop behind everything."
            ],
            de: "Bestimmt, wo die abgedockte Leiste im Fensterstapel liegt:\n\n• Immer vorn — schwebt über allen Fenstern und bleibt ständig sichtbar.\n• Normal — verhält sich wie ein gewöhnliches Fenster und kann verdeckt werden.\n• Hinten — liegt auf dem Schreibtisch hinter allen Fenstern, wie ein Widget.",
            en: "Controls where the detached bar sits in the window stack:\n\n• Always front — floats above all windows and stays permanently visible.\n• Normal — behaves like an ordinary window and can be covered.\n• Behind — sits on the desktop behind all windows, like a widget."
        ),
        Entry(
            keys: ["Passt nur die Größe der abgedockten Menüleistenleiste an."],
            de: "Vergrössert oder verkleinert nur die abgedockte Leiste — unabhängig von der Anzeige in der Menüleiste. Praktisch, wenn die Leiste z. B. auf dem Schreibtisch grösser lesbar sein soll.",
            en: "Scales only the detached bar — independent of the menu bar display. Handy if you want the bar to be more readable e.g. on the desktop."
        ),

        // MARK: App / Dashboard
        Entry(
            keys: ["Wählt helle Darstellung, dunkle Darstellung oder automatisch passend zum macOS-System."],
            de: "Bestimmt das Erscheinungsbild der SolixBar-Fenster (Dashboard, Verlauf, Einstellungen): hell, dunkel oder automatisch passend zur macOS-Systemeinstellung. \"Automatisch\" wechselt mit, wenn macOS abends in den Dunkelmodus geht.",
            en: "Determines the appearance of SolixBar's windows (dashboard, history, settings): light, dark, or automatically matching the macOS system setting. \"Automatic\" follows along when macOS switches to dark mode in the evening."
        ),
        Entry(
            keys: ["Wählt die Sprache für sichtbare App-Texte."],
            de: "Stellt die Sprache aller sichtbaren SolixBar-Texte um: Deutsch oder Englisch. Einzelne Fenster übernehmen die neue Sprache spätestens nach einem Neustart der App.",
            en: "Switches the language of all visible SolixBar texts: German or English. Individual windows pick up the new language at the latest after restarting the app."
        ),
        Entry(
            keys: ["Startet SolixBar automatisch nach dem Anmelden."],
            de: "Startet SolixBar automatisch, sobald du dich an deinem Mac anmeldest — die Werte sind dann immer da, ohne dass du an die App denken musst. Der Eintrag erscheint auch unter Systemeinstellungen → Allgemein → Anmeldeobjekte und lässt sich dort ebenfalls verwalten.",
            en: "Starts SolixBar automatically as soon as you sign in to your Mac — the values are always there without you having to think about the app. The entry also appears under System Settings → General → Login Items and can be managed there as well."
        ),
        Entry(
            keys: [
                "Fragt einmal täglich die GitHub-Releases ab. Bei einer neueren Version erscheint eine Mitteilung und ein Eintrag im Menü — installiert wird nichts automatisch.",
                "Checks the GitHub releases once a day. A newer version shows a notification and a menu entry — nothing is installed automatically."
            ],
            de: "SolixBar schaut einmal täglich auf GitHub nach, ob es eine neuere Version gibt. Falls ja, bekommst du einmalig eine macOS-Mitteilung und im Menü erscheint der Eintrag \"Update verfügbar\" mit Link zum Download. Es wird nichts automatisch installiert und ausser der Versionsabfrage nichts übertragen.",
            en: "Once a day SolixBar checks GitHub for a newer version. If there is one, you get a single macOS notification and the menu shows an \"Update available\" entry linking to the download. Nothing is installed automatically and nothing is transmitted beyond the version query."
        ),
        Entry(
            keys: ["Blendet leere Zeiträume im Verlaufsgraphen aus: Die Zeitachse beginnt bei der ersten vorhandenen Messung statt beim Kalenderanfang des Zeitraums."],
            de: "Passt die Zeitachse des Verlaufsgraphen an deine tatsächlichen Daten an: Sie beginnt bei der ersten vorhandenen Messung statt beim Kalenderanfang. Nutzt du SolixBar z. B. erst seit drei Tagen, zeigt die Wochenansicht keine vier leeren Tage davor.",
            en: "Fits the history graph's time axis to your actual data: it starts at the first recorded measurement instead of the calendar start. If you've only used SolixBar for three days, the week view won't show four empty days before that."
        ),
        Entry(
            keys: [
                "Zeichnet die Verlaufskurven weich statt eckig — die Kurve läuft weiter exakt durch alle Messpunkte.",
                "Draws the history curves smoothly instead of angular — the curve still passes exactly through every measurement."
            ],
            de: "Zeichnet die Linien im Verlaufsgraphen als weiche, fliessende Kurven statt als eckige Geradenzüge — das Auge folgt dem Verlauf dann leichter. Die Kurve läuft weiterhin durch jeden Messpunkt; zwischen zwei Punkten darf sie für den weichen Schwung leicht ausholen, bleibt dabei aber immer innerhalb des Diagramms (also z. B. nie unter der Nulllinie mit scheinbar negativen Watt). Deine gespeicherten Daten ändern sich nicht; ausgeschaltet siehst du wieder die rohen Geradenzüge.",
            en: "Draws the lines in the history graph as soft, flowing curves instead of angular straight segments — the eye follows the trend more easily. The curve still runs through every measurement; between two points it may bow slightly for the smooth flow, but always stays within the chart (so e.g. never below the zero line with seemingly negative watts). Your stored data does not change; turned off you see the raw straight segments again."
        ),
        Entry(
            keys: [
                "Füllt die Fläche unter der jeweiligen Kurve dezent ein — je Kurve wählbar.",
                "Subtly fills the area under the respective curve — selectable per curve."
            ],
            de: "Hinterlegt die Fläche unter der jeweiligen Kurve mit einem dezenten Farbschimmer — das betont den Verlauf und lässt den Graphen ruhiger wirken. Du kannst die Füllung für Akku, Solar und Netzbezug einzeln an- und abschalten; ab Werk ist nur Solar gefüllt. Die Füllungen sind bewusst blass, damit sie sich bei mehreren aktiven Kurven nicht zu einem Farbbrei mischen — bei allen dreien wird es trotzdem lebhaft, probiere einfach aus, was dir gefällt.",
            en: "Backs the area under the respective curve with a subtle color tint — emphasizing the trend and making the graph feel calmer. You can toggle the fill for battery, solar, and grid import individually; by default only solar is filled. The fills are deliberately pale so several active curves don't blend into a color mush — with all three it still gets lively, so just try what you like."
        ),
        Entry(
            keys: [
                "Dauer des eigenen Zeitraums (Chip \"Eig.\" im Verlauf).",
                "Duration of the custom range (chip \"Eig.\" in the history)."
            ],
            de: "Legt die Dauer des eigenen Zeitraums fest, den du im Verlaufsgraphen über den Chip \"Eig.\" auswählst — zusätzlich zu den festen Zeiträumen wie Tag, Woche oder Monat. Beispiel: 3 Tage oder 2 Wochen, ganz wie es zu deinem Blick auf die Anlage passt.",
            en: "Sets the duration of the custom range you select in the history graph via the \"Eig.\" chip — in addition to the fixed ranges like day, week, or month. Example: 3 days or 2 weeks, whatever fits how you look at your system."
        ),
        Entry(
            keys: [
                "Gilt für das abgedockte Dashboard-Fenster: über allen Fenstern schwebend, normal eingereiht oder hinter allen Fenstern auf dem Schreibtisch.",
                "Applies to the detached dashboard window: floating above all windows, ordered like a normal window, or on the desktop behind everything."
            ],
            de: "Bestimmt, wo das abgedockte Dashboard-Fenster im Fensterstapel liegt: immer vorn über allen Fenstern schwebend, normal eingereiht wie ein gewöhnliches Fenster, oder hinten auf dem Schreibtisch wie ein Widget.",
            en: "Controls where the detached dashboard window sits in the window stack: always in front floating above all windows, ordered normally like an ordinary window, or at the back on the desktop like a widget."
        ),
        Entry(
            keys: [
                "Gilt für das abgedockte Verlaufsfenster: über allen Fenstern schwebend, normal eingereiht oder hinter allen Fenstern auf dem Schreibtisch.",
                "Applies to the detached history window: floating above all windows, ordered like a normal window, or on the desktop behind everything."
            ],
            de: "Bestimmt, wo das abgedockte Verlaufsfenster im Fensterstapel liegt: immer vorn über allen Fenstern schwebend, normal eingereiht wie ein gewöhnliches Fenster, oder hinten auf dem Schreibtisch wie ein Widget.",
            en: "Controls where the detached history window sits in the window stack: always in front floating above all windows, ordered normally like an ordinary window, or at the back on the desktop like a widget."
        ),
        Entry(
            keys: [
                "PV-Wert im Dashboard des Menüs: nur die Summe, nur die Eingänge einzeln (\"438 · 204 W\" in der Kachel) oder Summe in der Kachel plus eigene Einzelwerte-Zeile. Einzelwerte brauchen eine Solarbank mit Kanal-Reporting (Solarbank 2/3), sonst bleibt es bei der Summe.",
                "PV value in the menu's dashboard: total only, individual inputs only (\"438 · 204 W\" in the tile), or the total in the tile plus a separate per-input row. Individual values require a Solarbank with channel reporting (Solarbank 2/3); otherwise the total is shown."
            ],
            de: "Bestimmt, wie der Solarwert im Dashboard (im Menü) erscheint: nur die Summe in der Kachel, nur die Modul-Eingänge einzeln (\"438 · 204 W\"), oder die Summe plus eine eigene Zeile mit den Einzelwerten. Mit den Einzelwerten erkennst du sofort, wenn ein Modul schwächelt. Sie brauchen eine Solarbank, die ihre Eingänge einzeln meldet (Solarbank 2 und 3) — sonst bleibt es automatisch bei der Summe.",
            en: "Determines how the solar value appears in the dashboard (in the menu): just the total in the tile, only the panel inputs individually (\"438 · 204 W\"), or the total plus a separate row with the individual values. With individual values you instantly spot an underperforming panel. They require a Solarbank that reports its inputs separately (Solarbank 2 and 3) — otherwise the total is shown automatically."
        ),
        Entry(
            keys: [
                "PV-Wert im abgedockten Dashboard-Fenster: Gesamtwert, Einzelwerte oder beides — unabhängig vom Menü-Dashboard einstellbar.",
                "PV value in the detached dashboard window: total, individual inputs, or both — configurable independently of the menu dashboard."
            ],
            de: "Bestimmt, wie der Solarwert im abgedockten Dashboard-Fenster erscheint: Gesamtwert, Einzelwerte je Modul-Eingang oder beides. Die Einstellung ist unabhängig vom Dashboard im Menü — du kannst also z. B. im Fenster die Einzelwerte beobachten und im Menü bei der Summe bleiben.",
            en: "Determines how the solar value appears in the detached dashboard window: total, individual values per panel input, or both. The setting is independent of the menu dashboard — so you can e.g. watch the individual values in the window while keeping the total in the menu."
        ),

        // MARK: Warnungen
        Entry(
            keys: [
                "Meldet sich einmal, wenn der Akku unter die Schwelle fällt. Erst wenn er wieder 5 Punkte darüber liegt, wird die Warnung neu scharf geschaltet.",
                "Fires once when the battery drops below the threshold. It re-arms only after climbing 5 points above it again."
            ],
            de: "Schickt dir eine macOS-Mitteilung, sobald der Akku unter die eingestellte Schwelle fällt — zusätzlich erscheint ein ⚠-Eintrag im Menü, solange der Stand niedrig bleibt. Die Warnung kommt bewusst nur einmal: Erst wenn der Akku wieder 5 Punkte über der Schwelle war, wird sie neu scharf geschaltet. So gibt es kein Mitteilungs-Gewitter, wenn der Stand um die Schwelle pendelt.",
            en: "Sends you a macOS notification as soon as the battery drops below the set threshold — plus a ⚠ entry in the menu while the level stays low. The warning deliberately fires only once: it re-arms only after the battery has been 5 points above the threshold again. That way there is no notification storm when the level hovers around the threshold."
        ),
        Entry(
            keys: ["Warnschwelle in Prozent (5–95).", "Warning threshold in percent (5–95)."],
            de: "Die Akkustand-Schwelle in Prozent (5–95), unter der die Warnung ausgelöst wird. Ein typischer Wert ist 20 %: tief genug, um nicht ständig zu warnen, früh genug, um noch reagieren zu können.",
            en: "The battery level threshold in percent (5–95) below which the warning fires. A typical value is 20%: low enough not to warn constantly, early enough to still react."
        ),
        Entry(
            keys: [
                "Warnt, wenn die Solarmodule auf 0 W fallen, obwohl sie in der letzten Stunde noch nennenswert erzeugt haben. Nachts bleibt es dadurch still.",
                "Warns when the panels drop to 0 W although they produced meaningfully within the last hour. Stays silent at night as a result."
            ],
            de: "Warnt dich, wenn deine Solarmodule plötzlich 0 W liefern, obwohl sie in der letzten Stunde noch nennenswert erzeugt haben — das deutet auf ein echtes Problem hin (Stecker, Kabel, Wechselrichter) statt auf eine Wolke. Weil die Warnung vorherige Erzeugung voraussetzt, bleibt sie nachts automatisch still. Wie lange 0 W anliegen müssen und was als \"nennenswert\" gilt, stellst du daneben ein.",
            en: "Warns you when your panels suddenly deliver 0 W although they produced meaningfully within the last hour — pointing to a real problem (connector, cable, inverter) rather than a cloud. Because the warning requires prior production, it automatically stays silent at night. How long 0 W must persist and what counts as \"meaningful\" is configured next to it."
        ),
        Entry(
            keys: [
                "So viele Minuten muss die PV durchgehend 0 W liefern, bevor gewarnt wird (5–120).",
                "How many minutes PV must stay at 0 W before warning (5–120)."
            ],
            de: "So viele Minuten muss die Anlage durchgehend 0 W liefern, bevor die Warnung ausgelöst wird (5–120). Kürzere Zeiten melden schneller, können aber bei kurzen Aussetzern falschen Alarm geben; 15 Minuten sind ein guter Kompromiss.",
            en: "How many minutes the system must stay at 0 W before the warning fires (5–120). Shorter times report faster but can false-alarm on brief dropouts; 15 minutes is a good compromise."
        ),
        Entry(
            keys: [
                "Ab dieser Leistung gilt die Anlage als \"hat kürzlich erzeugt\" (10–2000 W).",
                "Output at or above this counts as \"was recently producing\" (10–2000 W)."
            ],
            de: "Erst ab dieser Leistung (10–2000 W) zählt die Anlage als \"hat kürzlich erzeugt\" — und nur dann kann die Einbruch-Warnung auslösen. Ein höherer Wert verhindert Fehlalarme in der Dämmerung, wenn ohnehin fast nichts erzeugt wird.",
            en: "Only at or above this output (10–2000 W) does the system count as \"was recently producing\" — and only then can the collapse warning fire. A higher value prevents false alarms at dusk when hardly anything is produced anyway."
        ),
        Entry(
            keys: [
                "Meldet 0 W auch ohne vorherige Erzeugung, solange die Uhrzeit im angegebenen Fenster liegt — z. B. wenn die Anlage schon morgens nicht anläuft.",
                "Also reports 0 W without prior production while the time of day is inside the window — e.g. when the system never starts up in the morning."
            ],
            de: "Ergänzt die Einbruch-Warnung um ein festes Tagesfenster: Innerhalb dieser Stunden wird 0 W auch dann gemeldet, wenn vorher gar nichts erzeugt wurde — zum Beispiel wenn die Anlage morgens gar nicht erst anläuft. Wähle das Fenster so, dass deine Anlage darin normalerweise sicher erzeugt (z. B. 10 bis 16 Uhr), sonst gibt es an trüben Wintertagen Fehlalarme.",
            en: "Extends the collapse warning with a fixed daytime window: within these hours, 0 W is reported even without any prior production — for example when the system never starts up in the morning. Choose the window so your system normally produces reliably within it (e.g. 10:00 to 16:00), otherwise gloomy winter days will cause false alarms."
        ),
        Entry(
            keys: ["Beginn des Zeitfensters (Stunde, 0–23).", "Window start (hour, 0–23)."],
            de: "Die Stunde (0–23), ab der das Tagesfenster gilt. Beispiel: 10 bedeutet ab 10:00 Uhr.",
            en: "The hour (0–23) from which the daytime window applies. Example: 10 means from 10:00."
        ),
        Entry(
            keys: ["Ende des Zeitfensters (Stunde, 1–24).", "Window end (hour, 1–24)."],
            de: "Die Stunde (1–24), bis zu der das Tagesfenster gilt. Beispiel: 16 bedeutet bis 16:00 Uhr.",
            en: "The hour (1–24) until which the daytime window applies. Example: 16 means until 16:00."
        ),
        Entry(
            keys: [
                "Warnt, wenn ein PV-Eingang dauerhaft 0 W liefert, während die anderen Eingänge erzeugen. Braucht eine Solarbank, die ihre MPPT-Kanäle einzeln meldet (Solarbank 2/3).",
                "Warns when one PV input stays at 0 W while the other inputs are producing. Requires a Solarbank that reports its MPPT channels individually (Solarbank 2/3)."
            ],
            de: "Überwacht jeden Modul-Eingang einzeln: Liefert ein Eingang dauerhaft 0 W, während die anderen munter erzeugen, bekommst du eine Mitteilung — typisch für einen gezogenen Stecker oder ein defektes Modul, das im Gesamtwert sonst kaum auffällt. Braucht eine Solarbank, die ihre Eingänge einzeln meldet (Solarbank 2 und 3).",
            en: "Monitors each panel input individually: if one input stays at 0 W while the others are happily producing, you get a notification — typical for a pulled connector or a defective panel that would barely show in the total. Requires a Solarbank that reports its inputs individually (Solarbank 2 and 3)."
        ),
        Entry(
            keys: [
                "Warnt, wenn ein Eingang einbricht, der kurz zuvor selbst noch erzeugt hat — auch ohne Vergleich mit den anderen Eingängen. So fällt ein defektes Modul oder Kabel auf, selbst wenn mehrere Eingänge gleichzeitig betroffen sind. Nachts still.",
                "Warns when an input collapses after it was recently producing itself — without comparing to the other inputs. Catches a defective panel or cable even when several inputs are affected at once. Silent at night."
            ],
            de: "Vergleicht jeden Modul-Eingang mit seiner eigenen jüngsten Erzeugung: Bricht ein Eingang auf 0 W ein, der kurz zuvor selbst noch erzeugt hat, wird gewarnt — unabhängig davon, was die anderen Eingänge tun. Das erkennt defekte Module oder Kabel auch dann, wenn mehrere Eingänge gleichzeitig ausfallen (wo der reine Vergleich mit den Nachbarn stumm bliebe). Nachts bleibt die Warnung automatisch still.",
            en: "Compares each panel input with its own recent production: if an input collapses to 0 W after it was recently producing itself, you get warned — regardless of what the other inputs do. This catches defective panels or cables even when several inputs fail at once (where the pure neighbor comparison would stay silent). At night the warning automatically stays silent."
        )
    ]
}
