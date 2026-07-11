import Foundation
import Testing
@testable import SolixBarKit

@Suite("SnapshotDecoder")
struct SnapshotDecoderTests {
    @Test("decodes the full README example")
    func decodesFullExample() throws {
        let json = """
        {
          "siteName": "Anker SOLIX",
          "batteryPercent": 82,
          "solarWatts": 642,
          "homeWatts": 318,
          "gridWatts": -86,
          "batteryWatts": 238,
          "todayKWh": 3.74,
          "totalKWh": 427.8,
          "status": "Online",
          "updatedAt": "2026-07-06T19:30:00Z"
        }
        """
        let snapshot = try SnapshotDecoder.decode(Data(json.utf8))
        #expect(snapshot.batteryPercent == 82)
        #expect(snapshot.solarWatts == 642)
        #expect(snapshot.gridWatts == -86)
        #expect(snapshot.status == "Online")
    }

    @Test("decodes a minimal payload with only measurements")
    func decodesMinimalPayload() throws {
        let json = """
        { "batteryPercent": 50, "updatedAt": "2026-07-06T19:30:00Z" }
        """
        let snapshot = try SnapshotDecoder.decode(Data(json.utf8))
        #expect(snapshot.batteryPercent == 50)
        #expect(snapshot.solarWatts == nil)
        #expect(snapshot.pvWatts == nil)
    }

    @Test("decodes per-PV channel watts when present")
    func decodesPVChannels() throws {
        let json = """
        { "solarWatts": 642, "pvWatts": [438, 204], "updatedAt": "2026-07-06T19:30:00Z" }
        """
        let snapshot = try SnapshotDecoder.decode(Data(json.utf8))
        #expect(snapshot.pvWatts == [438, 204])
    }
}
