import Foundation
import Testing
@testable import SolixBarKit

@Suite("UpdateChecker")
struct UpdateCheckerTests {
    @Test("newer tags are recognized across formats")
    func newerTags() {
        #expect(UpdateChecker.isNewer("v0.4.3", than: "0.4.2"))
        #expect(UpdateChecker.isNewer("0.4.3", than: "v0.4.2"))
        #expect(UpdateChecker.isNewer("v0.5", than: "0.4.9"))
        #expect(UpdateChecker.isNewer("v1.0.0", than: "0.4.2"))
        #expect(UpdateChecker.isNewer("v0.4.2.1", than: "0.4.2"))
    }

    @Test("equal or older tags never count as updates")
    func equalOrOlder() {
        #expect(!UpdateChecker.isNewer("v0.4.2", than: "0.4.2"))
        #expect(!UpdateChecker.isNewer("v0.4.1", than: "0.4.2"))
        #expect(!UpdateChecker.isNewer("0.4", than: "0.4.0"))
        #expect(!UpdateChecker.isNewer("v0.9.9", than: "1.0"))
    }

    @Test("dev builds are never outdated")
    func devBuilds() {
        #expect(!UpdateChecker.isNewer("v99.0", than: "dev"))
    }

    @Test("unparsable tags never count as updates")
    func garbageTags() {
        #expect(!UpdateChecker.isNewer("latest", than: "0.4.2"))
        #expect(!UpdateChecker.isNewer("v0.4-beta", than: "0.4.2"))
        #expect(!UpdateChecker.isNewer("", than: "0.4.2"))
        #expect(!UpdateChecker.isNewer("v9.9", than: "unbekannt"))
    }
}
