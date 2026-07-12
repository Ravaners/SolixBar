import Foundation

protocol SolixDataProvider: Sendable {
    func fetchSnapshot() async throws -> SolixSnapshot
}

enum SolixProviderError: LocalizedError, Sendable {
    case missingCredentials
    case missingBundledHelper
    case missingCommand
    case missingURL
    case commandFailed(String)
    case commandTimedOut(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "SOLIX-Mail und Passwort fehlen. / SOLIX email and password are missing."
        case .missingBundledHelper:
            "Der gebündelte SOLIX-Helper fehlt. / The bundled SOLIX helper is missing."
        case .missingCommand:
            "Kein JSON-Befehl konfiguriert."
        case .missingURL:
            "Keine JSON-URL konfiguriert."
        case .commandFailed(let message):
            message
        case .commandTimedOut(let seconds):
            "JSON-Befehl nach \(Int(seconds)) Sekunden abgebrochen."
        }
    }
}

final class BundledSolixDataProvider: SolixDataProvider {
    private let country: String
    private let todayBaseKWh: Double?
    private let totalBaseKWh: Double?
    private let timeout: TimeInterval = 45

    init(country: String, todayBaseKWh: Double?, totalBaseKWh: Double?) {
        self.country = country
        self.todayBaseKWh = todayBaseKWh
        self.totalBaseKWh = totalBaseKWh
    }

    func fetchSnapshot() async throws -> SolixSnapshot {
        let credentials = KeychainCredentialStore.load()
        guard credentials.isComplete else { throw SolixProviderError.missingCredentials }
        guard let runtime = Self.runtimeConfiguration() else {
            throw SolixProviderError.missingBundledHelper
        }

        let request = HelperRequest(
            email: credentials.email,
            password: credentials.password,
            country: country,
            todayBaseKWh: todayBaseKWh,
            totalBaseKWh: totalBaseKWh
        )
        let inputData = try JSONEncoder().encode(request) + Data([0x0A])
        let timeout = timeout

        return try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = runtime.python
            process.arguments = [runtime.script.path, "--stdin-config"]

            var environment = ProcessInfo.processInfo.environment
            environment["PYTHONPATH"] = runtime.sitePackages.path
            environment["SOLIXBAR_STATE_PATH"] = runtime.applicationSupport.appendingPathComponent("energy.json").path
            environment["SOLIXBAR_CACHE_PATH"] = runtime.applicationSupport.appendingPathComponent("api-cache.json").path
            process.environment = environment

            let input = Pipe()
            let output = Pipe()
            let error = Pipe()
            process.standardInput = input
            process.standardOutput = output
            process.standardError = error

            try FileManager.default.createDirectory(
                at: runtime.applicationSupport,
                withIntermediateDirectories: true
            )
            try process.run()
            try input.fileHandleForWriting.write(contentsOf: inputData)
            try input.fileHandleForWriting.close()

            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
                throw SolixProviderError.commandTimedOut(timeout)
            }

            let data = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = error.fileHandleForReading.readDataToEndOfFile()
            guard process.terminationStatus == 0 else {
                let message = String(data: errorData, encoding: .utf8) ?? "SOLIX helper failed."
                throw SolixProviderError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return try SnapshotDecoder.decode(data)
        }.value
    }

    private static func runtimeConfiguration() -> HelperRuntime? {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SolixBar", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SolixBar", isDirectory: true)

        if let resources = Bundle.main.resourceURL {
            let runtime = HelperRuntime(
                python: resources.appendingPathComponent("python/bin/python3.12"),
                script: resources.appendingPathComponent("solix_snapshot.py"),
                sitePackages: resources.appendingPathComponent("site-packages"),
                applicationSupport: support
            )
            if fileManager.isExecutableFile(atPath: runtime.python.path),
               fileManager.fileExists(atPath: runtime.script.path),
               fileManager.fileExists(atPath: runtime.sitePackages.path) {
                return runtime
            }
        }

        let root = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        let development = HelperRuntime(
            python: root.appendingPathComponent("work/python/bin/python3.12"),
            script: root.appendingPathComponent("scripts/solix_snapshot.py"),
            sitePackages: root.appendingPathComponent("work/solix-venv312/lib/python3.12/site-packages"),
            applicationSupport: support
        )
        guard fileManager.isExecutableFile(atPath: development.python.path),
              fileManager.fileExists(atPath: development.script.path),
              fileManager.fileExists(atPath: development.sitePackages.path) else {
            return nil
        }
        return development
    }
}

private struct HelperRequest: Codable {
    var email: String
    var password: String
    var country: String
    var todayBaseKWh: Double?
    var totalBaseKWh: Double?
}

private struct HelperRuntime: Sendable {
    var python: URL
    var script: URL
    var sitePackages: URL
    var applicationSupport: URL
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
        return snapshot
    }
}

final class CommandSolixDataProvider: SolixDataProvider {
    private let command: String
    private let timeout: TimeInterval = 45

    init(command: String) {
        self.command = command
    }

    func fetchSnapshot() async throws -> SolixSnapshot {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SolixProviderError.missingCommand
        }

        let command = command
        let timeout = timeout
        return try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]

            let output = Pipe()
            let error = Pipe()
            process.standardOutput = output
            process.standardError = error

            try process.run()
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                try await Task.sleep(nanoseconds: 100_000_000)
            }

            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
                throw SolixProviderError.commandTimedOut(timeout)
            }

            let data = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = error.fileHandleForReading.readDataToEndOfFile()

            guard process.terminationStatus == 0 else {
                let message = String(data: errorData, encoding: .utf8) ?? "Befehl fehlgeschlagen."
                throw SolixProviderError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
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
        let (data, _) = try await URLSession.shared.data(for: request)
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
