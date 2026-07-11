import Foundation
import Testing
@testable import SolixBarKit

@Suite("HistoryExporter")
struct HistoryExporterTests {
    private let date = Date(timeIntervalSince1970: 1_752_000_000)

    @Test("csv has the exact header and one row per sample")
    func csvShape() {
        let csv = HistoryExporter.csv(samples: [
            SolixHistorySample(date: date, batteryPercent: 73, solarWatts: 410, gridWatts: -20, homeWatts: 210, batteryWatts: 180)
        ])
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0] == "timestamp,batteryPercent,solarWatts,gridWatts,homeWatts,batteryWatts")
        #expect(lines[1].hasSuffix(",73,410,-20,210,180"))
        // ISO8601 mit Zeitzonen-Offset, maschinenlesbar
        #expect(lines[1].contains("T"))
        #expect(csv.hasSuffix("\n"))
    }

    @Test("missing values become empty cells")
    func emptyCells() {
        let csv = HistoryExporter.csv(samples: [
            SolixHistorySample(date: date, batteryPercent: nil, solarWatts: 410, gridWatts: nil, homeWatts: nil, batteryWatts: nil)
        ])
        let row = csv.split(separator: "\n")[1]
        #expect(row.hasSuffix(",,410,,,"))
    }

    @Test("a newer current snapshot is appended as the final row")
    func currentSnapshotRow() {
        let current = SolixSnapshot(
            siteName: "Test",
            batteryPercent: 80,
            solarWatts: 500,
            homeWatts: 200,
            gridWatts: 0,
            batteryWatts: 300,
            updatedAt: date.addingTimeInterval(600)
        )
        let csv = HistoryExporter.csv(
            samples: [SolixHistorySample(date: date, batteryPercent: 73, solarWatts: 410, gridWatts: -20)],
            current: current
        )
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 3)
        #expect(lines[2].hasSuffix(",80,500,0,200,300"))

        // Älterer Snapshot wird nicht doppelt angehängt.
        let stale = HistoryExporter.csv(
            samples: [SolixHistorySample(date: date, batteryPercent: 73, solarWatts: 410, gridWatts: -20)],
            current: SolixSnapshot(siteName: "Test", updatedAt: date.addingTimeInterval(-600))
        )
        #expect(stale.split(separator: "\n").count == 2)
    }

    @Test("json export round-trips its samples")
    func jsonRoundTrip() throws {
        let samples = [
            SolixHistorySample(date: date, batteryPercent: 73, solarWatts: 410, gridWatts: -20, homeWatts: 210, batteryWatts: 180)
        ]
        let data = try HistoryExporter.json(samples: samples, sourceKey: "demo", exportedAt: date)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["source"] as? String == "demo")

        struct Shape: Decodable {
            let samples: [SolixHistorySample]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Shape.self, from: data)
        #expect(decoded.samples.count == 1)
        #expect(decoded.samples.first?.homeWatts == 210)
    }

    @Test("default filename carries date and extension")
    @MainActor
    func filename() {
        let name = HistoryExporter.defaultFilename(ext: "csv", date: date)
        #expect(name.hasPrefix("SolixBar-"))
        #expect(name.hasSuffix(".csv"))
        #expect(name.contains("2026") || name.contains("2025"))
    }
}
