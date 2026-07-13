# SolixBar 0.4.1

## Deutsch

- SolixBar erkennt jetzt, wenn der Mac aus dem Ruhezustand aufwacht.
- Der erste Abruf wartet drei Sekunden auf die Netzwerkverbindung.
- Falls WLAN noch nicht bereit ist, folgen automatische Wiederholungen nach 8 und 20 Sekunden.
- Während der automatischen Wake-Wiederholungen bleiben die letzten gültigen Messwerte sichtbar; erst wenn alle Versuche scheitern, wird ein echter Offline-Zustand angezeigt.
- Aktualisierungswünsche während eines laufenden Abrufs werden automatisch nachgeholt.

## English

- SolixBar now detects when the Mac wakes from sleep.
- The first fetch waits three seconds for networking.
- If Wi-Fi is not ready, automatic retries follow after 8 and 20 seconds.
- During the automatic wake retries, the last valid measurements remain visible; a genuine offline state appears only after every attempt fails.
- Refresh requests received during an active fetch are automatically performed afterwards.

Download `SolixBar-0.4.1-macOS-arm64.zip`, unpack it, and move `SolixBar.app` to `Applications`.
