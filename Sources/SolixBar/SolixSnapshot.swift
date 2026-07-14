import Foundation

struct SolixSnapshot: Codable, Sendable {
    var siteName: String
    var batteryPercent: Int?
    var solarWatts: Int?
    var homeWatts: Int?
    var gridWatts: Int?
    var batteryWatts: Int?
    var todayKWh: Double?
    var todayKWhIsAuthoritative: Bool? = nil
    var totalKWh: Double?
    var totalKWhIsAuthoritative: Bool? = nil
    var status: String?
    var updatedAt: Date

    static let demo = SolixSnapshot(
        siteName: "Anker SOLIX",
        batteryPercent: 82,
        solarWatts: 642,
        homeWatts: 318,
        gridWatts: -86,
        batteryWatts: 238,
        todayKWh: 3.74,
        totalKWh: 427.8,
        status: "Online",
        updatedAt: Date()
    )
}
