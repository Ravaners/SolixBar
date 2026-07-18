import Darwin
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
    case helperTimedOut(TimeInterval)
    case invalidHTTPStatus(Int)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "SOLIX-Mail und Passwort fehlen. / SOLIX email and password are missing."
        case .missingBundledHelper:
            "Der gebündelte SOLIX-Helper fehlt. / The bundled SOLIX helper is missing."
        case .missingCommand:
            "Kein JSON-Befehl konfiguriert. / No JSON command is configured."
        case .missingURL:
            "Keine gültige HTTP(S)-JSON-URL konfiguriert. / No valid HTTP(S) JSON URL is configured."
        case .commandFailed(let message):
            message
        case .commandTimedOut(let seconds):
            "JSON-Befehl nach \(Int(seconds)) Sekunden abgebrochen. / JSON command stopped after \(Int(seconds)) seconds."
        case .helperTimedOut(let seconds):
            "SOLIX-Aktualisierung nach \(Int(seconds)) Sekunden abgebrochen. / SOLIX refresh stopped after \(Int(seconds)) seconds."
        case .invalidHTTPStatus(let status):
            "JSON-URL antwortete mit HTTP \(status). / JSON URL returned HTTP \(status)."
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
        let credentials = EncryptedCredentialStore.load()
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
            let capture = try ProcessOutputCapture.create()
            defer { capture.remove() }
            process.standardInput = input
            process.standardOutput = capture.standardOutput
            process.standardError = capture.standardError

            try FileManager.default.createDirectory(
                at: runtime.applicationSupport,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: runtime.applicationSupport.path
            )
            try process.run()
            try input.fileHandleForWriting.write(contentsOf: inputData)
            try input.fileHandleForWriting.close()

            guard try await waitForExit(process, timeout: timeout) else {
                throw SolixProviderError.helperTimedOut(timeout)
            }

            let (data, errorData) = try capture.read()
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

            let capture = try ProcessOutputCapture.create()
            defer { capture.remove() }
            process.standardOutput = capture.standardOutput
            process.standardError = capture.standardError

            try process.run()
            guard try await waitForExit(process, timeout: timeout) else {
                throw SolixProviderError.commandTimedOut(timeout)
            }

            let (data, errorData) = try capture.read()

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
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              !urlString.isEmpty else {
            throw SolixProviderError.missingURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SolixProviderError.invalidHTTPStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try SnapshotDecoder.decode(data)
    }
}

private struct ProcessOutputCapture {
    let directory: URL
    let outputURL: URL
    let errorURL: URL
    let standardOutput: FileHandle
    let standardError: FileHandle

    static func create() throws -> ProcessOutputCapture {
        let fileManager = FileManager.default
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SolixBar-process-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        let outputURL = directory.appendingPathComponent("stdout")
        let errorURL = directory.appendingPathComponent("stderr")
        try Data().write(to: outputURL, options: .atomic)
        try Data().write(to: errorURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outputURL.path)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: errorURL.path)
        return ProcessOutputCapture(
            directory: directory,
            outputURL: outputURL,
            errorURL: errorURL,
            standardOutput: try FileHandle(forWritingTo: outputURL),
            standardError: try FileHandle(forWritingTo: errorURL)
        )
    }

    func read() throws -> (Data, Data) {
        try standardOutput.close()
        try standardError.close()
        return (try Data(contentsOf: outputURL), try Data(contentsOf: errorURL))
    }

    func remove() {
        try? standardOutput.close()
        try? standardError.close()
        try? FileManager.default.removeItem(at: directory)
    }
}

private func waitForExit(_ process: Process, timeout: TimeInterval) async throws -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    do {
        while process.isRunning && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    } catch {
        await terminate(process)
        throw error
    }
    guard process.isRunning else { return true }
    await terminate(process)
    return false
}

private func terminate(_ process: Process) async {
    guard process.isRunning else { return }
    process.terminate()
    let deadline = Date().addingTimeInterval(2)
    while process.isRunning && Date() < deadline {
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    if process.isRunning {
        Darwin.kill(process.processIdentifier, SIGKILL)
    }
    process.waitUntilExit()
}

enum SnapshotDecoder {
    static func decode(_ data: Data) throws -> SolixSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SolixSnapshot.self, from: data)
    }
}
