# SolixBar 0.5.3

## Deutsch

SolixBar 0.5.3 ist ein Zuverlaessigkeits- und Datenschutzupdate ohne Layout- oder Farbaenderungen.

- Voruebergehende Abruffehler lassen die letzten gueltigen Werte waehrend der ersten beiden automatischen Wiederholungen sichtbar. Erst anhaltende Fehler fuehren zum Offline-Zustand.
- Direkter SOLIX-Abruf und lokale JSON-Befehle koennen nicht mehr an einem vollen Ausgabepuffer haengen. Timeouts beenden festhaengende Prozesse verlaesslich und zeigen die passende Fehlermeldung.
- Bei mehreren PV-Wechselrichtern werden deren echte Gesamtwerte addiert. Numerische Statuswerte aus der API koennen die Aktualisierung nicht mehr abbrechen.
- Die Verlaufshistorie behaelt 24 Stunden in voller Aufloesung und verdichtet aeltere Daten auf Fuenf-Minuten-Punkte, damit 7- und 30-Tage-Bereiche voll nutzbar bleiben.
- Ein manueller Wert fuer „Heute“ laeuft am Tagesende ab; negative oder ungueltige Korrekturwerte werden verworfen.
- Lokale Logs, Verlauf, Cache und Ertragsdaten erhalten private Dateirechte. Die Bundle-Pruefung schliesst Zugangsdaten, Schluessel, Logs und lokale Laufzeitdaten ausdruecklich aus.
- Layout, Farben, Symbole und Screenshots sind unveraendert.

## English

SolixBar 0.5.3 is a reliability and privacy update with no layout or color changes.

- Temporary fetch failures keep the latest valid readings visible during the first two automatic retries. Only persistent failures switch the app to offline state.
- Direct SOLIX refreshes and local JSON commands can no longer hang on a full output buffer. Timeouts reliably stop stuck processes and show the correct error.
- Real lifetime totals from multiple PV inverters are added together. Numeric API status values can no longer abort a refresh.
- History keeps 24 hours at full resolution and compacts older data into five-minute samples, keeping 7- and 30-day ranges usable.
- A manual “Today” value expires at the end of the day; negative or invalid correction values are discarded.
- Local logs, history, cache, and yield state use private permissions. Bundle verification explicitly excludes credentials, keys, logs, and local runtime state.
- Layout, colors, symbols, and screenshots are unchanged.

Download `SolixBar-0.5.3-macOS-arm64.zip`, unpack it, and move `SolixBar.app` to `Applications`.
