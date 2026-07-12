import Foundation
import Testing
@testable import SolixBarKit

@Suite("BundledSolixDataProvider")
struct BundledProviderTests {
    @Test("Ohne Zugangsdaten wirft der Provider missingCredentials")
    func missingCredentials() async {
        let provider = BundledSolixDataProvider(
            credentials: .init(email: "", password: "", country: "DE", todayBaseKWh: nil, totalBaseKWh: nil)
        )
        await #expect(throws: SolixProviderError.self) {
            _ = try await provider.fetchSnapshot()
        }
    }

    @Test("Env-Werte werden vollständig übernommen")
    func credentialMapping() {
        let credentials = BundledSolixDataProvider.Credentials.from(
            values: [
                "ANKER_SOLIX_USER": "a@b.c",
                "ANKER_SOLIX_COUNTRY": "AT",
                "SOLIXBAR_TODAY_KWH_BASE": "1,5",
                "SOLIXBAR_TODAY_KWH_DATE": "2026-07-12",
                "SOLIXBAR_TOTAL_KWH_BASE": "427.8"
            ],
            password: "geheim",
            todayKey: "2026-07-12"
        )
        #expect(credentials.email == "a@b.c")
        #expect(credentials.password == "geheim")
        #expect(credentials.country == "AT")
        #expect(credentials.todayBaseKWh == 1.5)
        #expect(credentials.totalBaseKWh == 427.8)
    }

    @Test("Tages-Basiswert gilt nur an seinem Eintragedatum")
    func todayBaseExpires() {
        let credentials = BundledSolixDataProvider.Credentials.from(
            values: [
                "ANKER_SOLIX_USER": "a@b.c",
                "SOLIXBAR_TODAY_KWH_BASE": "7.2",
                "SOLIXBAR_TODAY_KWH_DATE": "2026-07-11",
                "SOLIXBAR_TOTAL_KWH_BASE": "427.8"
            ],
            password: "geheim",
            todayKey: "2026-07-12"
        )
        #expect(credentials.todayBaseKWh == nil)
        #expect(credentials.totalBaseKWh == 427.8)
    }

    @Test("Leeres Land fällt auf DE zurück")
    func countryDefault() {
        let credentials = BundledSolixDataProvider.Credentials.from(
            values: ["ANKER_SOLIX_USER": "a@b.c", "ANKER_SOLIX_COUNTRY": "  "],
            password: "geheim",
            todayKey: "2026-07-12"
        )
        #expect(credentials.country == "DE")
        #expect(credentials.todayBaseKWh == nil)
        #expect(credentials.totalBaseKWh == nil)
    }

    @Test("Tagesschlüssel ist ISO-Datum")
    func dayKeyFormat() {
        let date = Date(timeIntervalSince1970: 1_784_140_800) // 2026-07-15 UTC
        let key = BundledSolixDataProvider.Credentials.currentDayKey(for: date)
        #expect(key.count == 10)
        #expect(key.hasPrefix("2026-07-1"))
    }
}
