# SolixBar 0.4.2

## Deutsch

- Die macOS-Schlüsselbund-Abfrage wurde vollständig aus dem aktiven App-Code entfernt.
- SOLIX-Mail und Passwort werden jetzt AES-GCM-verschlüsselt im privaten Application-Support-Ordner gespeichert.
- Ordner und Zugangsdaten-Dateien sind auf den angemeldeten macOS-Benutzer beschränkt.
- Vorhandene Schlüsselbund-Einträge werden nicht mehr gelesen und lösen deshalb keine Abfrage mehr aus.
- Nach dem Update müssen Mail und Passwort einmal neu eingegeben und gespeichert werden.

## English

- The macOS Keychain prompt has been removed completely from the active app code.
- SOLIX email and password are now stored AES-GCM-encrypted in the private Application Support folder.
- The folder and credential files are restricted to the signed-in macOS user.
- Existing Keychain entries are no longer read and therefore no longer trigger a prompt.
- Email and password must be entered and saved once again after updating.

Download `SolixBar-0.4.2-macOS-arm64.zip`, unpack it, and move `SolixBar.app` to `Applications`.
