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
- [ ] Offen (bewusst verschoben): String-Katalog statt `LocalizedText`-Paare; Zerlegung des `StatusController` (~1200 Zeilen) in Formatter/MenuBuilder/WindowCoordinator; klickbare "?"-Popovers; Eingabevalidierung mit Feedback.

## Unterwegs gefunden (Selbst-Checks)

- Graph-Container im Dropdown hatte keine Höhen-Constraint → Layout kollabierte, Plot überdeckte den eigenen Header (Ursache der "Header-Kollision"; gefixt).
- Erste Notch-Messung über `window.frame` war stale → Button→Screen-Konvertierung + 100 ms Layout-Delay (gefixt, live belegt).
- Zeittick konnte mit "Jetzt"-Label überlappen → 60%-Schrittweiten-Puffer (gefixt).
- Demo-Daten waren nicht als Demo erkennbar → Demo-Badge (gefixt).
- `swift test` funktioniert mit reinen CLT (kein Xcode nötig) — gut für Contributor.
- Schema-Vertrag `solix_snapshot.py` ↔ Decoder verifiziert (alle 10 Felder). End-to-End mit echter Anker-Cloud bleibt ohne Gerät unverifizierbar → Bitte an Maintainer.

## Phase 5 — Abschluss (wartet auf visuelle Abnahme)

- [ ] Nutzer prüft App + Renders visuell.
- [ ] PR im Fork (Vorher/Nachher-Bilder).
- [ ] Upstream-Issue bei `Ravaners/SolixBar`: KI-freundlich strukturiert (Datei:Zeile, Repro, Akzeptanzkriterien je Paket), freundlich und ausführlich; verweist auf Branch/Commits im Fork, damit der Maintainer je Befund wählen kann: übernehmen / selbst anders umsetzen / verwerfen; Demo-Render-Screenshots (auch Design-Varianten, falls vorhanden); Bitte um Live-Test mit echtem Gerät; keinerlei private Daten.

## Teststrategie (Querschnitt)

| Ebene | Werkzeug | Deckt ab |
|---|---|---|
| Unit | swift-testing | Decoder, History (Energie, Cap, Migration, Quellentrennung), Env-Datei (Quoting, 0600), Display-Stufen, Notch-Prädikat |
| Integration | Provider gegen echte Prozesse/lokalen HTTP-Server | Pipe-Deadlock, SIGKILL, stderr, Env-Injektion, HTTP 2xx/404 |
| Visuell | Offscreen-Render-PNGs (hell/dunkel) | Dashboard, Graph, Slim-Bar, Settings |
| On-Screen | AX/AppleScript (Freigabe erteilt) | Statusitem sichtbar & notch-frei, Menü öffnet |
