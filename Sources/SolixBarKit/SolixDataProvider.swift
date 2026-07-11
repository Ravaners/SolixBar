import Foundation

protocol SolixDataProvider: Sendable {
    func fetchSnapshot() async throws -> SolixSnapshot
}

enum SolixProviderError: LocalizedError, Sendable {
    case missingCommand
    case missingURL
    case commandFailed(String)
    case commandTimedOut(TimeInterval)
    case httpError(Int)

    var errorDescription: String? {
        switch self {
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
    func fetchSnapshot() async throws -> SolixSnapshot {
        var snapshot = SolixSnapshot.demo
        let minute = Calendar.current.component(.minute, from: Date())
        snapshot.solarWatts = 400 + ((minute * 37) % 420)
        snapshot.homeWatts = 220 + ((minute * 19) % 260)
        snapshot.batteryPercent = 65 + (minute % 25)
        snapshot.batteryWatts = (snapshot.solarWatts ?? 0) - (snapshot.homeWatts ?? 0)
        snapshot.updatedAt = Date()
        // Zwei simulierte MPPT-Eingänge. In den Minuten 40–45 fällt Kanal 2
        // auf 0 — damit lassen sich Pro-PV-Anzeige und -Warnung ohne
        // Hardware ausprobieren.
        let solar = snapshot.solarWatts ?? 0
        if (40...45).contains(minute) {
            snapshot.pvWatts = [solar, 0]
        } else {
            let first = Int(Double(solar) * 0.62)
            snapshot.pvWatts = [first, solar - first]
        }
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
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return !process.isRunning
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

enum SnapshotDecoder {
    static func decode(_ data: Data) throws -> SolixSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SolixSnapshot.self, from: data)
    }
}
