import Foundation

protocol SolixDataProvider: Sendable {
    func fetchSnapshot() async throws -> SolixSnapshot
}

enum SolixProviderError: LocalizedError, Sendable {
    case missingCredentials
    case missingBundledRuntime
    case missingCommand
    case missingURL
    case commandFailed(String)
    case commandTimedOut(TimeInterval)
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "SOLIX-Mail und Passwort fehlen."
        case .missingBundledRuntime:
            "Die mitgelieferte SOLIX-Laufzeit fehlt in diesem Build."
        case .missingCommand:
            "Kein JSON-Befehl konfiguriert."
        case .missingURL:
            "Keine JSON-URL konfiguriert."
        case .commandFailed(let message):
            message
        case .commandTimedOut(let seconds):
            "JSON-Befehl nach \(Int(seconds)) Sekunden abgebrochen."
        case .httpError(let status):
            "Server antwortete mit HTTP \(status)."
        }
    }
}

final class DemoSolixDataProvider: SolixDataProvider {
    /// Akkustand als langsamer, stetiger Lade-/Entladezyklus (~3 h): der
    /// frühere Minuten-Sägezahn (65 + minute % 25) sprang alle 25 Minuten
    /// um 24 Punkte und machte die Akku-Kurve im Verlaufsgraphen zackig —
    /// echte Akkus driften langsam.
    static func demoBatteryPercent(at date: Date = Date()) -> Int {
        let cycle: Double = 3 * 60 * 60
        let phase = date.timeIntervalSince1970.truncatingRemainder(dividingBy: cycle) / cycle
        return 62 + Int((20 * sin(phase * 2 * .pi)).rounded())
    }

    func fetchSnapshot() async throws -> SolixSnapshot {
        var snapshot = SolixSnapshot.demo
        let minute = Calendar.current.component(.minute, from: Date())
        snapshot.solarWatts = 400 + ((minute * 37) % 420)
        snapshot.homeWatts = 220 + ((minute * 19) % 260)
        snapshot.batteryPercent = Self.demoBatteryPercent()
        snapshot.batteryWatts = (snapshot.solarWatts ?? 0) - (snapshot.homeWatts ?? 0)
        snapshot.updatedAt = Date()
        // Zwei simulierte MPPT-Eingänge. Nur wenn die Pro-PV-Warnung aktiv
        // ist, fällt Kanal 2 in den Minuten 40–45 auf 0 (Warnungs-Test ohne
        // Hardware) — sonst wirkt das wie ein Anzeigefehler ("Summe und 0").
        let solar = snapshot.solarWatts ?? 0
        let simulateOutage = await MainActor.run { AppSettings.shared.warnPerPVEnabled }
        if simulateOutage, (40...45).contains(minute) {
            snapshot.pvWatts = [solar, 0]
        } else {
            let first = Int(Double(solar) * 0.62)
            snapshot.pvWatts = [first, solar - first]
        }
        return snapshot
    }
}

/// Warnungs-Test: spielt ab Aktivierung ein gerafftes Szenario ab (Zeit
/// läuft 10-fach), damit aktivierte Warnungen innerhalb weniger Minuten
/// wirklich feuern — mit den Standard-Einstellungen (Schwelle 20 %,
/// Einbruch-Dauer 15 min):
///   Demo-Minute  0–9: normale Erzeugung (Akku 42 %, PV 385+235 W)
///   Demo-Minute 10–29: Akku fällt auf 16 % (→ Akku-Warnung),
///                       Eingang 2 fällt auf 0 W (→ Pro-PV ab Minute 25)
///   ab Demo-Minute 30: kompletter PV-Einbruch (→ PV-Warnung ab Minute 45)
/// Bei 30-Sekunden-Abruf entspricht das real ca. 1 / 2,5 / 4,5 Minuten.
final class DemoWarningsSolixDataProvider: SolixDataProvider {
    private let start: Date
    /// Eine reale Sekunde = zehn Szenario-Sekunden.
    private static let timeCompression: Double = 10

    init(start: Date) {
        self.start = start
    }

    func fetchSnapshot() async throws -> SolixSnapshot {
        let demoMinute = Date().timeIntervalSince(start) * Self.timeCompression / 60
        let updatedAt = start.addingTimeInterval(demoMinute * 60)

        var snapshot = SolixSnapshot.demo
        snapshot.siteName = "Anker SOLIX"
        snapshot.status = await MainActor.run { LocalizedText.text("Warnungs-Test", "Warning test") }
        snapshot.updatedAt = updatedAt
        snapshot.homeWatts = 310
        snapshot.gridWatts = 0
        switch demoMinute {
        case ..<10:
            snapshot.batteryPercent = 42
            snapshot.pvWatts = [385, 235]
        case ..<30:
            snapshot.batteryPercent = 16
            snapshot.pvWatts = [385, 0]
        default:
            snapshot.batteryPercent = 16
            snapshot.pvWatts = [0, 0]
        }
        snapshot.solarWatts = snapshot.pvWatts?.reduce(0, +)
        snapshot.batteryWatts = (snapshot.solarWatts ?? 0) - (snapshot.homeWatts ?? 0)
        return snapshot
    }
}

/// Liest eine Pipe auf einem eigenen Thread leer, damit der Kindprozess bei
/// grosser Ausgabe (>64 KB Pipe-Puffer) nicht blockiert.
private final class PipeDrain: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private var collected = Data()

    init(_ handle: FileHandle) {
        Thread.detachNewThread { [self] in
            collected = (try? handle.readToEnd()) ?? Data()
            semaphore.signal()
        }
    }

    func data() -> Data {
        semaphore.wait()
        return collected
    }
}

final class CommandSolixDataProvider: SolixDataProvider {
    private let command: String
    private let extraEnvironment: [String: String]
    private let timeout: TimeInterval

    init(command: String, extraEnvironment: [String: String] = [:], timeout: TimeInterval = 45) {
        self.command = command
        self.extraEnvironment = extraEnvironment
        self.timeout = timeout
    }

    func fetchSnapshot() async throws -> SolixSnapshot {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SolixProviderError.missingCommand
        }

        let command = command
        let extraEnvironment = extraEnvironment
        let timeout = timeout
        return try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            if !extraEnvironment.isEmpty {
                process.environment = ProcessInfo.processInfo.environment
                    .merging(extraEnvironment) { _, new in new }
            }

            let output = Pipe()
            let error = Pipe()
            process.standardOutput = output
            process.standardError = error

            try process.run()
            let outputDrain = PipeDrain(output.fileHandleForReading)
            let errorDrain = PipeDrain(error.fileHandleForReading)

            if await !Self.waitForExit(process, timeout: timeout) {
                process.terminate()
                if await !Self.waitForExit(process, timeout: 2) {
                    kill(process.processIdentifier, SIGKILL)
                    _ = await Self.waitForExit(process, timeout: 2)
                }
                throw SolixProviderError.commandTimedOut(timeout)
            }

            let data = outputDrain.data()
            let errorData = errorDrain.data()

            guard process.terminationStatus == 0 else {
                let message = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw SolixProviderError.commandFailed(
                    message.isEmpty ? "Befehl fehlgeschlagen (Exit-Code \(process.terminationStatus))." : message
                )
            }

            return try SnapshotDecoder.decode(data)
        }.value
    }

    private static func waitForExit(_ process: Process, timeout: TimeInterval) async -> Bool {
        await waitForProcessExit(process, timeout: timeout)
    }
}

private func waitForProcessExit(_ process: Process, timeout: TimeInterval) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning && Date() < deadline {
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
    return !process.isRunning
}

/// Fundorte der SOLIX-Laufzeit: zuerst das App-Bundle (Release mit
/// eingebetteter Python-Laufzeit), dann das Arbeitsverzeichnis für die
/// Entwicklung (`swift run`) — portabel oder klassisches venv.
struct SolixHelperRuntime: Sendable {
    var python: URL
    var script: URL
    var sitePackages: URL?

    static func locate(fileManager: FileManager = .default) -> SolixHelperRuntime? {
        var candidates: [SolixHelperRuntime] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(
                SolixHelperRuntime(
                    python: resources.appendingPathComponent("python/bin/python3.12"),
                    script: resources.appendingPathComponent("solix_snapshot.py"),
                    sitePackages: resources.appendingPathComponent("site-packages")
                )
            )
        }
        let root = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        candidates.append(
            SolixHelperRuntime(
                python: root.appendingPathComponent("work/python/bin/python3.12"),
                script: root.appendingPathComponent("scripts/solix_snapshot.py"),
                sitePackages: root.appendingPathComponent("work/solix-venv312/lib/python3.12/site-packages")
            )
        )
        candidates.append(
            SolixHelperRuntime(
                python: root.appendingPathComponent("work/solix-venv312/bin/python"),
                script: root.appendingPathComponent("scripts/solix_snapshot.py"),
                sitePackages: nil
            )
        )
        return candidates.first { $0.isComplete(fileManager) }
    }

    private func isComplete(_ fileManager: FileManager) -> Bool {
        guard fileManager.isExecutableFile(atPath: python.path),
              fileManager.fileExists(atPath: script.path) else { return false }
        guard let sitePackages else { return true }
        return fileManager.fileExists(atPath: sitePackages.path)
    }
}

/// Direkter SOLIX-Abruf über die mitgelieferte Python-Laufzeit — ohne
/// konfigurierten Befehl und ohne lokale Installation. Die Zugangsdaten
/// gehen als eine JSON-Zeile über stdin an den Helper; Umgebungsvariablen
/// wären für andere Prozesse desselben Nutzers via `ps -E` sichtbar.
final class BundledSolixDataProvider: SolixDataProvider {
    struct Credentials: Sendable {
        var email: String
        var password: String
        var country: String
        var todayBaseKWh: Double?
        var totalBaseKWh: Double?
    }

    private struct HelperRequest: Encodable {
        var email: String
        var password: String
        var country: String
        var todayBaseKWh: Double?
        var totalBaseKWh: Double?
    }

    private let credentials: Credentials
    private let timeout: TimeInterval

    init(credentials: Credentials, timeout: TimeInterval = 45) {
        self.credentials = credentials
        self.timeout = timeout
    }

    func fetchSnapshot() async throws -> SolixSnapshot {
        guard !credentials.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !credentials.password.isEmpty else {
            throw SolixProviderError.missingCredentials
        }
        guard let runtime = SolixHelperRuntime.locate() else {
            throw SolixProviderError.missingBundledRuntime
        }

        let request = HelperRequest(
            email: credentials.email,
            password: credentials.password,
            country: credentials.country,
            todayBaseKWh: credentials.todayBaseKWh,
            totalBaseKWh: credentials.totalBaseKWh
        )
        let inputData = try JSONEncoder().encode(request) + Data([0x0A])
        let timeout = timeout
        let supportDirectory = SolixPaths.appSupportDirectory
        let statePath = SolixPaths.energyStateFileURL.path
        let cachePath = SolixPaths.apiCacheFileURL.path

        return try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = runtime.python
            process.arguments = [runtime.script.path, "--stdin-config"]

            var environment = ProcessInfo.processInfo.environment
            if let sitePackages = runtime.sitePackages {
                environment["PYTHONPATH"] = sitePackages.path
            }
            // Kein __pycache__ ins signierte Bundle schreiben.
            environment["PYTHONDONTWRITEBYTECODE"] = "1"
            environment["SOLIXBAR_STATE_PATH"] = statePath
            environment["SOLIXBAR_CACHE_PATH"] = cachePath
            process.environment = environment

            let input = Pipe()
            let output = Pipe()
            let error = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = error

            try? FileManager.default.createDirectory(
                at: supportDirectory,
                withIntermediateDirectories: true
            )
            try process.run()
            let outputDrain = PipeDrain(output.fileHandleForReading)
            let errorDrain = PipeDrain(error.fileHandleForReading)
            // Fehler beim Schreiben ignorieren (Helper könnte schon tot
            // sein) — der Exit-Status liefert dann die eigentliche Meldung.
            try? input.fileHandleForWriting.write(contentsOf: inputData)
            try? input.fileHandleForWriting.close()

            if await !waitForProcessExit(process, timeout: timeout) {
                process.terminate()
                if await !waitForProcessExit(process, timeout: 2) {
                    kill(process.processIdentifier, SIGKILL)
                    _ = await waitForProcessExit(process, timeout: 2)
                }
                throw SolixProviderError.commandTimedOut(timeout)
            }

            let data = outputDrain.data()
            let errorData = errorDrain.data()

            guard process.terminationStatus == 0 else {
                let message = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw SolixProviderError.commandFailed(
                    message.isEmpty ? "SOLIX-Helper fehlgeschlagen (Exit-Code \(process.terminationStatus))." : message
                )
            }

            return try SnapshotDecoder.decode(data)
        }.value
    }
}

final class URLSolixDataProvider: SolixDataProvider {
    private let urlString: String
    private let timeout: TimeInterval = 45

    init(urlString: String) {
        self.urlString = urlString
    }

    func fetchSnapshot() async throws -> SolixSnapshot {
        guard let url = URL(string: urlString), !urlString.isEmpty else {
            throw SolixProviderError.missingURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw SolixProviderError.httpError(http.statusCode)
        }
        return try SnapshotDecoder.decode(data)
    }
}

extension BundledSolixDataProvider.Credentials {
    /// Liest Mail/Land/Basiswerte aus der Env-Datei und das Passwort aus dem
    /// Schlüsselbund — derselbe Speicher, den die Einstellungen beschreiben.
    @MainActor
    static func stored() -> Self {
        let values = SolixEnvFile.read(from: SolixPaths.envFileURL)
        let email = values["ANKER_SOLIX_USER"] ?? ""
        let password = email.isEmpty ? "" : (KeychainStore.password(account: email) ?? "")
        return from(values: values, password: password, todayKey: currentDayKey())
    }

    /// Reine Abbildung Env-Werte → Zugangsdaten. Der Tages-Basiswert gilt
    /// nur an dem Tag, an dem er eingetragen wurde (SOLIXBAR_TODAY_KWH_DATE).
    static func from(values: [String: String], password: String, todayKey: String) -> Self {
        func number(_ key: String) -> Double? {
            guard let raw = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                return nil
            }
            return Double(raw.replacingOccurrences(of: ",", with: "."))
        }
        let todayBase = values["SOLIXBAR_TODAY_KWH_DATE"] == todayKey
            ? number("SOLIXBAR_TODAY_KWH_BASE")
            : nil
        let country = values["ANKER_SOLIX_COUNTRY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self(
            email: values["ANKER_SOLIX_USER"] ?? "",
            password: password,
            country: (country?.isEmpty == false ? country! : "DE"),
            todayBaseKWh: todayBase,
            totalBaseKWh: number("SOLIXBAR_TOTAL_KWH_BASE")
        )
    }

    static func currentDayKey(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

enum SnapshotDecoder {
    static func decode(_ data: Data) throws -> SolixSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SolixSnapshot.self, from: data)
    }
}
