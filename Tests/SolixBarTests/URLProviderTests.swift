import Foundation
import Testing
@testable import SolixBarKit

/// Testet den JSON-URL-Modus gegen einen lokalen HTTP-Server — deckt den
/// kompletten App-seitigen Datenweg ab (Request, Statuspruefung, Decoding).
@Suite("URLSolixDataProvider", .serialized)
struct URLProviderTests {
    private static func startServer(directory: URL, port: Int) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-m", "http.server", String(port), "--directory", directory.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    private static func waitUntilReachable(port: Int) async throws {
        let url = URL(string: "http://127.0.0.1:\(port)/")!
        for _ in 0..<50 {
            if (try? await URLSession.shared.data(from: url)) != nil { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        Issue.record("local http server did not come up")
    }

    @Test("fetches and decodes a realistic payload over HTTP")
    func fetchesPayload() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("solixbar-url-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload = """
        {"siteName":"Balkonkraftwerk","batteryPercent":76,"solarWatts":512,"homeWatts":301,
         "gridWatts":-45,"batteryWatts":180,"todayKWh":2.41,"totalKWh":390.2,
         "status":"Online","updatedAt":"2026-07-11T10:00:00Z"}
        """
        try payload.write(to: dir.appendingPathComponent("solix.json"), atomically: true, encoding: .utf8)

        let port = 18987
        let server = try Self.startServer(directory: dir, port: port)
        defer { server.terminate() }
        try await Self.waitUntilReachable(port: port)

        let provider = URLSolixDataProvider(urlString: "http://127.0.0.1:\(port)/solix.json")
        let snapshot = try await provider.fetchSnapshot()
        #expect(snapshot.siteName == "Balkonkraftwerk")
        #expect(snapshot.batteryPercent == 76)
        #expect(snapshot.gridWatts == -45)
    }

    @Test("non-2xx responses produce a clear HTTP error")
    func httpErrorSurfaces() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("solixbar-url-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let port = 18988
        let server = try Self.startServer(directory: dir, port: port)
        defer { server.terminate() }
        try await Self.waitUntilReachable(port: port)

        let provider = URLSolixDataProvider(urlString: "http://127.0.0.1:\(port)/missing.json")
        do {
            _ = try await provider.fetchSnapshot()
            Issue.record("expected httpError")
        } catch let SolixProviderError.httpError(status) {
            #expect(status == 404)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
}
