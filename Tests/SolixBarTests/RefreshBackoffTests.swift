import Foundation
import Testing
@testable import SolixBarKit

@Suite("Refresh-Backoff")
struct RefreshBackoffTests {
    @Test("Ohne Fehler bleibt das Basisintervall")
    func noFailures() {
        #expect(StatusController.backoffInterval(base: 60, consecutiveFailures: 0) == 60)
        #expect(StatusController.backoffInterval(base: 300, consecutiveFailures: 0) == 300)
    }

    @Test("Jeder Fehler verdoppelt das Intervall")
    func doubling() {
        #expect(StatusController.backoffInterval(base: 60, consecutiveFailures: 1) == 120)
        #expect(StatusController.backoffInterval(base: 60, consecutiveFailures: 2) == 240)
        #expect(StatusController.backoffInterval(base: 60, consecutiveFailures: 3) == 480)
        #expect(StatusController.backoffInterval(base: 60, consecutiveFailures: 4) == 960)
    }

    @Test("Deckel bei 30 Minuten, auch bei vielen Fehlern")
    func cap() {
        #expect(StatusController.backoffInterval(base: 60, consecutiveFailures: 5) == 960)
        #expect(StatusController.backoffInterval(base: 60, consecutiveFailures: 100) == 960)
        #expect(StatusController.backoffInterval(base: 300, consecutiveFailures: 3) == 30 * 60)
        #expect(StatusController.backoffInterval(base: 30 * 60, consecutiveFailures: 4) == 30 * 60)
    }

    @Test("Negative Fehlerzahl wird wie 0 behandelt")
    func negative() {
        #expect(StatusController.backoffInterval(base: 60, consecutiveFailures: -3) == 60)
    }
}
