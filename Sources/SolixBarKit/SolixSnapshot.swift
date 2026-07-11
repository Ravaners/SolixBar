import Foundation

struct SolixSnapshot: Codable, Sendable {
    var siteName: String
    var batteryPercent: Int?
    var solarWatts: Int?
    var homeWatts: Int?
    var gridWatts: Int?
    var batteryWatts: Int?
    var todayKWh: Double?
    var totalKWh: Double?
    var status: String?
    var updatedAt: Date
    /// Leistung je PV-Eingang (MPPT-Kanal); nur bei Modellen mit
    /// Kanal-Reporting vorhanden (Solarbank 2/3), sonst nil.
    var pvWatts: [Int]?

    init(
        siteName: String,
        batteryPercent: Int? = nil,
        solarWatts: Int? = nil,
        homeWatts: Int? = nil,
        gridWatts: Int? = nil,
        batteryWatts: Int? = nil,
        todayKWh: Double? = nil,
        totalKWh: Double? = nil,
        status: String? = nil,
        updatedAt: Date,
        pvWatts: [Int]? = nil
    ) {
        self.siteName = siteName
        self.batteryPercent = batteryPercent
        self.solarWatts = solarWatts
        self.homeWatts = homeWatts
        self.gridWatts = gridWatts
        self.batteryWatts = batteryWatts
        self.todayKWh = todayKWh
        self.totalKWh = totalKWh
        self.status = status
        self.updatedAt = updatedAt
        self.pvWatts = pvWatts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        siteName = try container.decodeIfPresent(String.self, forKey: .siteName) ?? "Anker SOLIX"
        batteryPercent = try container.decodeIfPresent(Int.self, forKey: .batteryPercent)
        solarWatts = try container.decodeIfPresent(Int.self, forKey: .solarWatts)
        homeWatts = try container.decodeIfPresent(Int.self, forKey: .homeWatts)
        gridWatts = try container.decodeIfPresent(Int.self, forKey: .gridWatts)
        batteryWatts = try container.decodeIfPresent(Int.self, forKey: .batteryWatts)
        todayKWh = try container.decodeIfPresent(Double.self, forKey: .todayKWh)
        totalKWh = try container.decodeIfPresent(Double.self, forKey: .totalKWh)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        pvWatts = try container.decodeIfPresent([Int].self, forKey: .pvWatts)
    }

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
        updatedAt: Date(),
        pvWatts: [438, 204]
    )
}
