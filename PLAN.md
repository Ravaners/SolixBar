# SolixBar — Implementierungsplan (Review-Fixes & Design)

Basis: Code-Review + Live-UI-Review vom 2026-07-11 (Fork `itsab1989/SolixBar`, Branch `review-fixes`).
Jede Phase endet mit: `swift build` grün, Tests grün, Offscreen-Renders aktualisiert, Commit.

Stand: Phasen 0–4 umgesetzt (25 Tests grün, CI grün). Offen: Phase 5 nach
visueller Abnahme.

## Phase 0 — Infrastruktur ✅

- [x] Package-Umbau: Library `SolixBarKit` + dünnes Executable (Tests brauchen ein Library-Target).
- [x] Test-Target `SolixBarTests` (swift-testing; läuft mit reinen Command Line Tools).
- [x] Render-Snapshots als Tests: Dashboard, Graph, Slim-Bar, alle Settings-Tabs als PNG (hell/dunkel) nach `.build/renders` bzw. `$SOLIXBAR_RENDER_DIR` — visuelle Verifikation ohne Screen-Recording-Berechtigung.
- [x] `.gitignore`.

## Phase 1 — P0 ✅

1. [x] **Notch-Ausweichen:** Anzeige verdichtet sich stufenweise (ohne Labels → ohne Symbole → 2 Metriken → minimal), bis das Item nicht mehr mit der Notch-Zone kollidiert; Messung über Button→Screen-Konvertierung nach Layout-Delay; Start-Diagnose im Log. Live verifiziert (Level 0→3, landet rechts der Notch).
2. [x] **Pfade:** Env-Datei unter `~/Library/Application Support/SolixBar/` (0600); Helper-Script aus Repo/Bundle mit `SOLIXBAR_ENV_FILE`; README korrigiert.
3. [x] **Snapshot bei Fehlern behalten** + ⚠-Indikator.

## Phase 2 — P1 ✅

- [x] Passwort im Schlüsselbund, Injektion als Env-Variable (Env-Datei ohne Secrets).
- [x] HTTP-Statusprüfung (Integrationstests gegen lokalen HTTP-Server, inkl. 404).
- [x] Decoder tolerant (`siteName`/`updatedAt` optional mit Defaults).
- [x] Pipe-Drain-Threads (kein 64-KB-Deadlock, per Test mit 200-KB-Ausgabe belegt), SIGTERM→SIGKILL-Eskalation (Test mit `trap '' TERM`).
- [x] History pro Datenquelle als Datei; Cap folgt dem Intervall (30-Tage-Ansicht füllbar); Migration des alten UserDefaults-Blobs.

## Phase 3 — Design ✅

- [x] `Theme.swift` (semantische Rollen, hell/dunkel inkl. Menüleisten-Luminanz; Netzbezug rot = Kosten, Einspeisung violett).
- [x] Slim-Bar: Farben über `.solixRole`-Attribut statt ~180 Zeilen Text-Parsing; Zwei-Stopp-Akzent.
- [x] Graph: Header über Plotfläche, runde Zeitticks mit Overlap-Schutz vor "Jetzt", nur Solar gefüllt, %-Achse in Akku-Farbe, Legende/Ticks lokalisiert.
- [x] Dashboard: Radius-Skala 16/12/8, Demo-Badge, Tage-Feld nur bei "Eig.", Checkboxen als farbige Legende, kein unbelegtes "Online" mehr.
- [x] Dark-Mode-Fix: dynamische Panel-Farben + Layer-Refresh bei Appearance-Wechsel.
- [x] Menüleiste: Template-Glyph statt 1,5-MB-PNG-Downscale.

## Phase 4 — Wartbarkeit ✅ (Teilumfang)

- [x] Logging: os.Logger (Subsystem `local.codex.SolixBar`) + Datei-Spiegel, offenes FileHandle, gecachter Formatter, `#function`-Kontext, DecodingError/URLError-Details, DEBUG via `defaults write local.codex.SolixBar verboseLogging -bool true`.
- [x] Settings: Tabs "App"+"Start" zusammengelegt; Text-Preview entprellt (0,4 s); Popups lokalisiert.
- [x] `SMAppService` statt LaunchAgent-Plist (inkl. Aufräumen des Alt-Plists).
- [x] CI: GitHub Actions (macos-15) — Tests, Universal-Build, ad-hoc-signiertes App-Bundle als Artifact, Release-Upload bei `v*`-Tags, Render-PNGs als Artifact.
- [x] CHANGELOG/VERSION → 0.4.0.
- [x] Nachgezogen (2026-07-11, Runde 2): `MenuBarFormatter` aus dem StatusController extrahiert (~470 Zeilen; Controller jetzt ~770); Metrik-Namen zentral in `MetricLocalization.swift` (echter String-Katalog folgt der System-Locale und kollidiert mit dem In-App-Sprachschalter — bewusst dagegen entschieden); Live-Vorschau der Menüleiste in den Einstellungen (hell+dunkel, echte Engine); Trend-Pfeile (▲/▼) im Dashboard; Hover-Inspektor im großen Graphen; Doppelstart-Schutz; Speichern-Nachfrage beim Schließen ungespeicherter Einstellungen; NumberFormatter-Validierung (Intervall, eig. Zeitraum); toter Code entfernt (energyFlowArrow-Kette, CenteredTextFieldCell).

## Unterwegs gefunden (Selbst-Checks)

- Graph-Container im Dropdown hatte keine Höhen-Constraint → Layout kollabierte, Plot überdeckte den eigenen Header (Ursache der "Header-Kollision"; gefixt).
- Erste Notch-Messung über `window.frame` war stale → Button→Screen-Konvertierung + 100 ms Layout-Delay (gefixt, live belegt).
- Zeittick konnte mit "Jetzt"-Label überlappen → 60%-Schrittweiten-Puffer (gefixt).
- Demo-Daten waren nicht als Demo erkennbar → Demo-Badge (gefixt).
- `swift test` funktioniert mit reinen CLT (kein Xcode nötig) — gut für Contributor.
- Schema-Vertrag `solix_snapshot.py` ↔ Decoder verifiziert (alle 10 Felder). End-to-End mit echter Anker-Cloud bleibt ohne Gerät unverifizierbar → Bitte an Maintainer.

## Design-Runde 2 (Nutzer-Feedback vom 2026-07-11, umgesetzt)

- [x] Abgedocktes Dashboard: eigener Fensterrahmen (Panel = Fenster, transparente Titelleiste, schwebende Ampeln) statt doppelter Ecken; keine Konturlinie.
- [x] Zweizeilige Kompaktanzeige (Menüleiste, Default an; abgedockte Leiste separat schaltbar), Bright-Palette + dynamische Höhe für die dunkle Leiste, Glyphen mit korrektem Seitenverhältnis.
- [x] Eigener Settings-Tab "Abgedockte Leiste" mit unabhängiger Werte-Auswahl; klickbare Hilfe-Popovers statt toter "?"-Labels.
- [x] Notch-Regression behoben (Preview-Reset + unbrauchbare Frames versteckter Items) — per App-Log diagnostiziert.
- [x] Graph: Innen-Box aufgelöst (nur Grundlinie), kräftigere Rasterlinien in beiden Modi; kartenweite Konturen entfernt (Tiefe über Flächen).
- [x] Slim-Bar: einheitliche Schriftgröße, dezentes Bolt-Glyph statt App-Icon-PNG, Symbol-Close-Button, magnetisches Kanten-Einrasten, lockere Positions-Klemmung.
- [x] Dashboard: Zeitstempel färbt sich orange bei überfälligen Daten.
- [x] App-Icon-Vorschlag (weißer Blitz auf Bernstein→Grün-Verlauf) als Bilder generiert — Entscheidung offen (Original behalten / ersetzen / beides ins Issue).

## Optionale visuelle Ideen (für Maintainer-Issue, nicht umgesetzt)

- Live-Vorschau der Menüleisten-Anzeige in den Einstellungen (braucht Extraktion des Formatters aus StatusController).
- Trend-Indikatoren (▲▼) in den Dashboard-Karten.
- Hover-Tooltip mit exakten Werten im großen Graphen.

## Phase 5 — Abschluss ✅ (2026-07-11)

- [x] Nutzer hat App + Renders visuell abgenommen (mehrere Iterationsrunden, siehe Design-Runde 2/3).
- [x] PR im Fork mit Vorher/Nachher-Bildern: https://github.com/itsab1989/SolixBar/pull/1
- [x] Upstream-Issue: https://github.com/Ravaners/SolixBar/issues/3 (Arbeitspakete mit Datei:Zeile, Repro, Akzeptanzkriterien, Referenz-Commits, Demo-Renders, Icon-Vorschlag, Hardware-Test-Bitte, Optionen-Frage).

## Teststrategie (Querschnitt)

| Ebene | Werkzeug | Deckt ab |
|---|---|---|
| Unit | swift-testing | Decoder, History (Energie, Cap, Migration, Quellentrennung), Env-Datei (Quoting, 0600), Display-Stufen, Notch-Prädikat |
| Integration | Provider gegen echte Prozesse/lokalen HTTP-Server | Pipe-Deadlock, SIGKILL, stderr, Env-Injektion, HTTP 2xx/404 |
| Visuell | Offscreen-Render-PNGs (hell/dunkel) | Dashboard, Graph, Slim-Bar, Settings |
| On-Screen | AX/AppleScript (Freigabe erteilt) | Statusitem sichtbar & notch-frei, Menü öffnet |
