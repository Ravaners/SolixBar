# SolixBar 0.5.6

## Deutsch

SolixBar 0.5.6 korrigiert den Abruf des PV-Gesamtertrags und reduziert unnoetige Arbeit bei laufenden Aktualisierungen.

- Der fehlerhafte PV-Gesamtaufruf wurde korrigiert. SolixBar prueft nacheinander PV-Geraetejahre, Anlagenjahre und historische Tagesertraege. Der bisherige ungueltige Bibliotheksaufruf konnte keinen Gesamtwert liefern und liess die App unbemerkt beim lokalen Messwert bleiben.
- Verfuegbare Gesamtwerte sowie ein von Anker bestaetigtes Nichtverfuegbar werden sechs Stunden privat zwischengespeichert. Ohne API-Gesamtwert zaehlt SolixBar weiterhin fortlaufende Messungen; fuer zuvor fehlende Zeitraeume bleibt der manuelle Gesamtstartwert erforderlich. Das Log kennzeichnet die verwendete Quelle.
- Eine bereits aktive Echtzeit-Anforderung wird innerhalb ihres Fuenf-Minuten-Fensters weiterverwendet. Dadurch entfallen unnoetige MQTT-Verbindungen und doppelte Anlagenabrufe, waehrend Akku, PV, Hauslast, Netz und Fluss weiterhin gemeinsam aktualisiert werden.
- Ein aktivierter, aber veralteter Autostart-Eintrag wird automatisch auf die tatsaechlich laufende App korrigiert. Gleichzeitige macOS-Aufwachsignale starten nur noch eine Wiederherstellung.
- Layout, Farben, Symbole, Einstellungen und Bedienablauf bleiben unveraendert; neue Screenshots sind nicht erforderlich.

## English

SolixBar 0.5.6 corrects PV lifetime-yield retrieval and removes unnecessary work from ongoing refreshes.

- The faulty PV-total request has been corrected. SolixBar now checks PV-device years, site years, and historical daily yields in sequence. The previous invalid library call could not return a total and silently left the app on its local measurement.
- Available totals and a confirmed unavailable result from Anker are cached privately for six hours. Without an API total, SolixBar continues ongoing measurements; a manual total starting value remains necessary for previously missing periods. The log identifies the source used.
- An active real-time request is reused within its five-minute window. This avoids unnecessary MQTT connections and duplicate site requests while battery, solar, home load, grid, and flow continue to refresh together.
- An enabled but outdated autostart entry is automatically corrected to the app that is actually running. Simultaneous macOS wake signals now start only one recovery.
- Layout, colors, symbols, settings, and interaction flow remain unchanged; no new screenshots are required.

Download `SolixBar-0.5.6-macOS-arm64.zip`, unpack it, and move `SolixBar.app` to `Applications`.
