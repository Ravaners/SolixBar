# SolixBar 0.5.5

## Deutsch

SolixBar 0.5.5 sorgt dafuer, dass die gesamte Anzeige dauerhaft aktuell bleibt.

- Der direkte SOLIX-Abruf fordert jetzt fuer alle unterstuetzten Geraete der Anlage Echtzeitdaten an und liest danach die gemeinsame Anlagenansicht erneut.
- Akku, PV, Hauslast, Netz und Akku-Fluss werden dadurch zusammen aktualisiert, auch wenn die normale Anker-Cloud-Uebersicht zuvor alte Werte geliefert hat.
- Der direkt empfangene Echtzeit-Akkustand hat Vorrang vor einem aelteren Cloudwert. Ohne Echtzeitunterstuetzung bleibt der bisherige Cloud-Abruf als Rueckfall erhalten.
- Eine unabhaengige Ueberwachung erkennt ausgebliebene Zeitgeber und Abrufe, die laenger als 60 Sekunden festhaengen.
- Manuelles Aktualisieren bricht einen festhaengenden Abruf jetzt wirklich ab und startet mit einer frischen Verbindung neu.
- SolixBar reagiert auf vollstaendiges Aufwachen, Bildschirm-Aufwachen und eine wieder aktive macOS-Sitzung.
- Layout, Farben, Symbole, Reihenfolge und Screenshots wurden nicht veraendert.

## English

SolixBar 0.5.5 keeps the complete display current over long-running sessions.

- Direct SOLIX refreshes now request real-time data from every supported system device and then reload the combined system view.
- Battery, solar, home load, grid, and battery flow therefore update together even when the regular Anker cloud overview previously returned stale values.
- A directly received real-time battery level takes precedence over an older cloud value. The existing cloud retrieval remains available as a fallback without real-time support.
- An independent watchdog detects missed timers and fetches stuck for more than 60 seconds.
- Manual refresh now actually cancels a stuck fetch and restarts it with a fresh connection.
- SolixBar reacts to full system wake, screen wake, and a reactivated macOS session.
- Layout, colors, symbols, ordering, and screenshots are unchanged.

Download `SolixBar-0.5.5-macOS-arm64.zip`, unpack it, and move `SolixBar.app` to `Applications`.
