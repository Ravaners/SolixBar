import Foundation
import Testing
@testable import SolixBarKit

@Suite("CommandSolixDataProvider")
struct CommandProviderTests {
    @Test("output larger than the 64KB pipe buffer does not deadlock")
    func largeOutput() async throws {
        // 200 KB Statusfeld: hätte den alten readDataToEndOfFile-nach-Exit-Code
        // blockiert (Pipe-Puffer voll -> Prozess hängt -> falscher Timeout).
        let provider = CommandSolixDataProvider(
            command: #"printf '{"status":"%s","updatedAt":"2026-01-01T00:00:00Z"}' "$(head -c 200000 /dev/zero | tr '\0' 'x')""#,
            timeout: 15
        )
        let snapshot = try await provider.fetchSnapshot()
        #expect(snapshot.status?.count == 200_000)
    }

    @Test("a process ignoring SIGTERM is killed and reported as timeout")
    func stubbornTimeout() async {
        let provider = CommandSolixDataProvider(
            command: "trap '' TERM; sleep 60",
            timeout: 1
        )
        let start = Date()
        await #expect(throws: SolixProviderError.self) {
            _ = try await provider.fetchSnapshot()
        }
        // 1s Timeout + 2s SIGTERM-Frist + Puffer: deutlich unter den 60s des sleep
        #expect(Date().timeIntervalSince(start) < 10)
    }

    @Test("stderr output becomes the error message")
    func stderrMessage() async {
        let provider = CommandSolixDataProvider(command: "echo kaputt >&2; exit 3", timeout: 10)
        do {
            _ = try await provider.fetchSnapshot()
            Issue.record("expected commandFailed")
        } catch let SolixProviderError.commandFailed(message) {
            #expect(message.contains("kaputt"))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("extra environment variables reach the command")
    func environmentInjection() async throws {
        let provider = CommandSolixDataProvider(
            command: #"printf '{"status":"%s","updatedAt":"2026-01-01T00:00:00Z"}' "$SOLIX_TEST_VALUE""#,
            extraEnvironment: ["SOLIX_TEST_VALUE": "aus-dem-schlüsselbund"],
            timeout: 10
        )
        let snapshot = try await provider.fetchSnapshot()
        #expect(snapshot.status == "aus-dem-schlüsselbund")
    }

    @Test("empty command reports missing configuration")
    func emptyCommand() async {
        let provider = CommandSolixDataProvider(command: "   ", timeout: 1)
        await #expect(throws: SolixProviderError.self) {
            _ = try await provider.fetchSnapshot()
        }
    }
}
