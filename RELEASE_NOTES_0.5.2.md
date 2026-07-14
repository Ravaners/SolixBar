# SolixBar 0.5.2

## Deutsch

SolixBar 0.5.2 korrigiert die Berechnung von „Heute“ und „Gesamt“.

- „Heute“ verwendet vorrangig den echten Tagesertrag aus der SOLIX-Energieanalyse. Eine API-Null wird nicht mehr zwischengespeichert und verdeckt keine spaeteren gueltigen Werte.
- „Gesamt“ fragt jetzt den passenden PV-Gesamt-Endpunkt ab. Ein erstmals gelieferter echter Gesamtwert darf einen zu hohen lokalen Schätzwert auch nach unten korrigieren.
- Direkter SOLIX-Login, lokaler JSON-Befehl und JSON-URL setzen denselben realen Gesamtzaehler fort. Nacheinander entstandene Zaehlersegmente und eindeutige Luecken seit dem Datenquellenwechsel werden beim Update sicher zusammengefuehrt; Demo-Daten bleiben getrennt.
- Ein manuell eingetragener Tages- oder Gesamtstartwert bleibt vorrangig und kann nun auch exakt auf einen niedrigeren Wert korrigiert werden.
- Eindeutige Solarmessluecken innerhalb desselben Tages werden bis maximal acht Stunden vorsichtig aus dem Verlauf rekonstruiert. Nacht- und unklare Luecken werden nicht geschaetzt.
- Oberflaeche und Farben wurden nicht veraendert. Deshalb bleiben die aktuellen Screenshots gueltig.

## English

SolixBar 0.5.2 corrects the “Today” and “Total” yield calculations.

- “Today” prioritizes the real daily yield from SOLIX energy analysis. An API zero is no longer cached or allowed to mask later valid values.
- “Total” now queries the matching PV lifetime-total endpoint. A first real provider total may correct an overly high local estimate downward.
- Direct SOLIX login, local JSON command, and JSON URL continue the same real total counter. Consecutive counter segments and unambiguous gaps since the data-source transition are migrated safely, while demo data remains separate.
- An explicitly entered daily or total starting value continues to take priority and can now correct the counter exactly to a lower value.
- Unambiguous solar gaps within the same day are conservatively reconstructed from history for up to eight hours. Overnight and uncertain gaps are not estimated.
- The interface and colors are unchanged, so the existing screenshots remain current.

Download `SolixBar-0.5.2-macOS-arm64.zip`, unpack it, and move `SolixBar.app` to `Applications`.
