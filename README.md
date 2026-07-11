# SolixBar

SolixBar ist eine native macOS-Menueleisten-App fuer Anker SOLIX Uebersichtsdaten.

Sie zeigt Akku, PV, Hauslast, Netzbezug, Energiefluss und Ertrag direkt in der Menueleiste, mit modernem Dashboard, abgedockter schmaler Leiste und Verlaufsgraf.

English: SolixBar is a native macOS menu bar app for Anker SOLIX overview data. It provides a compact menu bar readout, a modern dropdown dashboard, a detachable slim bar, and a history graph.

Die Projekt-Homepage liegt in [`docs/`](docs/) und kann mit GitHub Pages veroeffentlicht werden.

English: Project homepage files are in [`docs/`](docs/) and can be published with GitHub Pages.

## Screenshots / Screenshots

Alle Bilder zeigen Demo-Daten. / All images show demo data.

| Dashboard | Verlaufsfenster / History window |
|---|---|
| ![Dashboard](docs/review-assets/after-dashboard-dark.png) | ![Verlaufsfenster](docs/review-assets/after-graph-large-dark.png) |

Zweizeilige Kompaktanzeige in der Menüleiste und abgedockte schmale Leiste: / Two-line compact menu bar display and detached slim bar:

![Kompaktanzeige](docs/review-assets/menubar-stacked-dark.png)
![Abgedockte Leiste](docs/review-assets/after-detached-bar-dark.png)

Einstellungen mit sortierbarer Werte-Auswahl und optionalen Warnungen: / Settings with sortable value lists and optional warnings:

| Menüleiste / Menu bar | Warnungen / Warnings |
|---|---|
| ![Einstellungen Menüleiste](docs/review-assets/settings-menubar-dark.png) | ![Einstellungen Warnungen](docs/review-assets/settings-warnings-dark.png) |

## Funktionen / Features

- Native AppKit-Menueleisten-App. / Native AppKit menu bar app.
- Demo-Modus zum Testen ohne Zugangsdaten. / Demo data mode for testing without credentials.
- Live-Daten ueber lokalen JSON-Befehl oder JSON-URL. / Live data via local JSON command or JSON URL.
- Frei waehlbare Menueleistenwerte, Bezeichnungen, Symbole, App-Symbol und Skalierung. / Configurable menu bar values, labels, symbols, app icon visibility, and scaling.
- Optionale farbige Energiefluss-Pfeile in der Menueleiste. / Optional colored energy-flow arrows in the menu bar.
- Abgedockte schmale Leiste mit Andocken-Funktion, Fixieren gegen versehentliches Verschieben und gespeichertem Zustand. / Detachable slim bar with dock action, optional movement lock, and restored state.
- Hell, Dunkel oder automatisch passend zum System. / Light, dark, or automatic system appearance.
- Deutsche oder englische sichtbare App-Texte. / German or English visible app text.
- Login-Autostart. / Login autostart support.
- Aufklapp-Dashboard mit Akku, PV, Hauslast, Netzbezug, Akku-Fluss, Tagesertrag, Gesamtertrag und Status. / Dropdown dashboard with battery, solar, home load, grid import, battery flow, daily yield, total yield, and status.
- Animierter Verlaufsgraf fuer Akku, Solar und Netzbezug. / Animated history graph for battery, solar, and grid import.
- Zeitraeume: Aktuell, 24 Stunden, 7 Tage, 30 Tage und individuell. / Graph ranges: current, 24 hours, 7 days, 30 days, and custom.
- Sichtbare Fragezeichen-Hilfen in den Einstellungen. / Visible question-mark help controls in settings.
- Lokale Logdatei fuer Fehleranalyse: `~/Library/Application Support/SolixBar/SolixBar.log`. / Local log file for troubleshooting.
- Werte-Auswahl als sortierbare Listen: Häkchen wählt, Ziehen ordnet — je Leiste und je Ansicht (einzeilig/kompakt) unabhängig. / Value selection as sortable lists: checkboxes select, dragging reorders — independent per bar and per view (single-line/compact).
- Verlaufsgraph als eigenes Fenster abdockbar; Fensterebene (vorn/normal/hinten) für Leiste, Dashboard und Verlaufsfenster getrennt wählbar. / History graph detachable as its own window; window level (front/normal/behind) selectable separately for bar, dashboard, and history window.
- Datenexport als CSV oder JSON direkt aus dem Menü. / Data export as CSV or JSON right from the menu.
- Optionale Warnungen: Akku niedrig, PV-Einbruch (nachts still), Zeitfenster, tote oder eingebrochene einzelne PV-Eingänge (Defekt-Erkennung) — als macOS-Mitteilung plus Menü-Hinweis. / Optional warnings: battery low, PV collapse (silent at night), time window, dead or dipped individual PV inputs (defect detection) — as macOS notifications plus a menu indicator.
- Datenquelle "Demo (Warnungs-Test)": gerafftes Szenario, mit dem alle aktivierten Warnungen in wenigen Minuten wirklich feuern. / "Demo (warning test)" data source: an accelerated scenario that makes all enabled warnings actually fire within minutes.
- Leistung je PV-Eingang (Solarbank 2/3): "PV-Anzeige" wählbar als Gesamtwert, Einzelwerte oder beides — getrennt für Dashboard im Menü, abgedocktes Fenster, Menüleiste und abgedockte Leiste. / Per-PV-input power (Solarbank 2/3): "PV display" selectable as total, individual inputs, or both — separately per surface.
- Täglicher Update-Hinweis auf neue GitHub-Releases (abschaltbar, installiert nichts). / Daily update notice for new GitHub releases (can be disabled, installs nothing).

## Version / Version

Aktuelle Version / Current version: `0.4.2`

Versionshinweise stehen in [CHANGELOG.md](CHANGELOG.md). / See [CHANGELOG.md](CHANGELOG.md) for release notes.

## Voraussetzungen / Requirements

- macOS 14 oder neuer. / macOS 14 or newer.
- Swift-Toolchain oder Xcode Command Line Tools fuer lokale Builds. / Swift toolchain or Xcode command line tools for building locally.
- Optional: Anker SOLIX Hilfsbefehl mit JSON-Ausgabe oder lokaler JSON-Endpunkt fuer Live-Daten. / Optional: a JSON-producing Anker SOLIX helper command or local JSON endpoint for live data.

## Bauen und Starten / Build and Run

Direkt mit SwiftPM starten. / Run directly from SwiftPM:

```bash
swift run SolixBar
```

App-Bundle zum Doppelklicken erstellen. / Create a double-clickable app bundle:

```bash
sh scripts/package_app.sh
open outputs/SolixBar.app
```

## Datenquellen / Data Source Modes

SolixBar unterstuetzt drei Modi. / SolixBar supports three modes:

- `Demo`: erzeugte Beispieldaten zum Testen der Oberflaeche. / Generated sample data for testing the UI.
- `Lokaler JSON-Befehl`: fuehrt einen lokalen Befehl aus und liest JSON aus stdout. / Runs a local command and reads JSON from stdout.
- `JSON-URL`: laedt JSON von einer lokalen oder entfernten HTTP-Adresse. / Fetches JSON from a local or remote HTTP endpoint.

Das JSON sollte so aussehen. / The JSON should look like this:

```json
{
  "siteName": "Anker SOLIX",
  "batteryPercent": 82,
  "solarWatts": 642,
  "homeWatts": 318,
  "gridWatts": -86,
  "batteryWatts": 238,
  "todayKWh": 3.74,
  "totalKWh": 427.8,
  "status": "Online",
  "updatedAt": "2026-07-06T19:30:00Z"
}
```

## Live SOLIX Daten / Live SOLIX Data

Anker stellt keine stabile oeffentliche SOLIX API bereit. Dieses Projekt enthaelt ein vorbereitetes Hilfsscript fuer die inoffizielle Community-Bibliothek `thomluther/anker-solix-api`.

English: Anker does not provide a stable public SOLIX API. This project includes a helper script prepared for the unofficial community library `thomluther/anker-solix-api`.

Empfohlener lokaler Befehl fuer SolixBar (wird von der App automatisch vorgeschlagen; das Script liegt im Repo und in der gepackten App). / Recommended local command (suggested automatically by the app; the script ships in the repo and the packaged app):

```bash
scripts/run_solix_snapshot.sh
```

Die App kann die lokale ignorierte Zugangsdaten-Datei fuer dich erstellen. Oeffne
`Einstellungen` -> `Datenquelle`, waehle `Lokaler JSON-Befehl`, trage Mail,
Passwort und Land unter `SOLIX Login` ein und druecke `Speichern`.

English: The app can create the local ignored credentials file for you. Open
`Einstellungen` -> `Datenquelle`, choose `Lokaler JSON-Befehl`, enter email,
password, and country under `SOLIX Login`, then press `Speichern`.

Du kannst jederzeit zu `Demo` oder `JSON-URL` wechseln; SolixBar zeigt nur die
Felder an, die fuer den gewaehlten Modus notwendig sind.

English: You can still switch back to `Demo` or `JSON-URL`; SolixBar only shows
the fields needed for the selected mode.

Das Passwort liegt im macOS-Schluesselbund. SolixBar schreibt zusaetzlich diese lokale Datei (`~/Library/Application Support/SolixBar/solixbar.env`, Rechte 0600, ohne Secrets) und uebergibt das Passwort dem Befehl nur als Umgebungsvariable. / The password lives in the macOS Keychain. SolixBar additionally writes this local file (mode 0600, no secrets) and passes the password to the command only as an environment variable:

```bash
ANKER_SOLIX_USER='you@example.com'
ANKER_SOLIX_COUNTRY='DE'
```

Manueller Beispielbefehl (Passwort dann selbst als Umgebungsvariable setzen). / Manual example command (set the password env var yourself):

```bash
ANKER_SOLIX_USER="you@example.com" \
ANKER_SOLIX_PASSWORD="..." \
ANKER_SOLIX_COUNTRY="DE" \
scripts/run_solix_snapshot.sh
```

Trage den Befehl nur dann unter `Lokaler JSON-Befehl` ein, wenn du die eingebauten SOLIX-Login-Felder nicht nutzt.

English: Put the command into SolixBar settings under `Lokaler JSON-Befehl` only if you do not use the built-in SOLIX login fields.

## Repository-Hinweise / Repository Notes

Das Repository schliesst lokale Build-Produkte, gepackte Apps, Python-Laufzeiten und heruntergeladene API-Checkouts bewusst aus.

English: The repository intentionally excludes local build products, packaged apps, Python runtimes, and downloaded API checkouts.
