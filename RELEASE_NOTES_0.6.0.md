# SolixBar 0.6.0

## Deutsch

SolixBar 0.6.0 erweitert die App ohne Aenderungen an Messung, Darstellung oder Bedienablauf um eine vollstaendige Mehrsprachigkeit.

- Die gesamte sichtbare App ist jetzt in 20 Sprachen verfuegbar: Deutsch, Englisch, Franzoesisch, Spanisch, Italienisch, Niederlaendisch, Polnisch, Portugiesisch, Tschechisch, Daenisch, Schwedisch, Norwegisch, Finnisch, Russisch, vereinfachtes und traditionelles Chinesisch, Japanisch, Koreanisch, Tuerkisch und Rumaenisch.
- Menues, Einstellungen, Warnungen, Hilfetexte, Vorschauen, Diagramme, Statusangaben, Benachrichtigungen und Zeitangaben verwenden einen gemeinsamen zentralen Sprachkatalog.
- Datumsformate folgen der gewaehlten Sprache. Dynamische Werte in Benachrichtigungen und Hilfetexten bleiben in jeder Uebersetzung korrekt erhalten.
- Eine automatische Vollstaendigkeitspruefung kontrolliert 213 Textschluessel, alle Sprachspalten und dynamische Platzhalter.
- Die gebuendelte Python-Laufzeit erzeugt beim Abruf keine Cache-Dateien mehr im signierten App-Bundle; die Signatur bleibt nach echten SOLIX-Aktualisierungen gueltig.
- Authentifizierungs- und MQTT-Laufzeitdaten bleiben im privaten Application-Support-Ordner. Die Release-Pruefung blockiert solche Daten im App-Bundle und ZIP.
- Messwerte, Aktualisierungslogik, Farben, Symbole, Anordnung und Bedienablauf bleiben unveraendert.

## English

SolixBar 0.6.0 adds complete multilingual support without changing measurements, appearance, or interaction flow.

- The entire visible app is now available in 20 languages: German, English, French, Spanish, Italian, Dutch, Polish, Portuguese, Czech, Danish, Swedish, Norwegian, Finnish, Russian, Simplified and Traditional Chinese, Japanese, Korean, Turkish, and Romanian.
- Menus, settings, warnings, help text, previews, graphs, status values, notifications, and time labels share one central language catalog.
- Date formats follow the selected language. Dynamic values in notifications and help text remain intact in every translation.
- An automated completeness check validates 213 text keys, every language column, and dynamic placeholders.
- The bundled Python runtime no longer creates cache files inside the signed app bundle during refreshes, so the signature remains valid after real SOLIX updates.
- Authentication and MQTT runtime data remain in the private Application Support folder. Release verification blocks such data from the app bundle and ZIP.
- Readings, refresh logic, colors, symbols, layout, and interaction flow remain unchanged.
