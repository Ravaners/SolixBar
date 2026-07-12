import Foundation
import SolixBarCore

struct SolixHistorySample: Codable, Sendable, Equatable {
    var date: Date
    var batteryPercent: Int?
    var solarWatts: Int?
    var gridWatts: Int?
}

struct SolixEnergyAccumulator: Codable, Sendable, Equatable {
    var totalKWh: Double = 0
    var lastDate: Date?
    var lastSolarWatts: Int?
}

@MainActor
final class SolixHistoryStore {
    static let shared = SolixHistoryStore()

    private let defaults = UserDefaults.standard
    private let legacyHistoryKey = "solixHistorySamples"
    private let legacyAccumulatorKey = "solixEnergyAccumulators"
    private let maxAge: TimeInterval = 31 * 24 * 60 * 60
    private let directoryURL: URL
    private let historyURL: URL
    private let accumulatorsURL: URL
    private var cachedSamples: [SolixHistorySample]
    private var cachedAccumulators: [String: SolixEnergyAccumulator]

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directoryURL = base.appendingPathComponent("SolixBar", isDirectory: true)
        historyURL = directoryURL.appendingPathComponent("history.json")
        accumulatorsURL = directoryURL.appendingPathComponent("energy-accumulators.json")
        cachedSamples = Self.decode([SolixHistorySample].self, from: historyURL) ?? []
        cachedAccumulators = Self.decode([String: SolixEnergyAccumulator].self, from: accumulatorsURL) ?? [:]
        migrateLegacyDefaultsIfNeeded()
    }

    func cumulativeSolarKWh(recording snapshot: SolixSnapshot, sourceKey: String) -> Double {
        var accumulator = cachedAccumulators[sourceKey] ?? SolixEnergyAccumulator()
        if let lastDate = accumulator.lastDate,
           let lastSolarWatts = accumulator.lastSolarWatts,
           let solarWatts = snapshot.solarWatts {
            accumulator.totalKWh += SolixEnergyCalculator.measuredKWh(
                from: lastSolarWatts,
                to: solarWatts,
                seconds: snapshot.updatedAt.timeIntervalSince(lastDate)
            )
        }
        if let providerTotal = snapshot.totalKWh, providerTotal > accumulator.totalKWh {
            accumulator.totalKWh = providerTotal
        }
        accumulator.lastDate = snapshot.updatedAt
        accumulator.lastSolarWatts = snapshot.solarWatts
        cachedAccumulators[sourceKey] = accumulator
        save(cachedAccumulators, to: accumulatorsURL)
        return accumulator.totalKWh
    }

    func record(_ snapshot: SolixSnapshot) {
        cachedSamples.append(
            SolixHistorySample(
                date: snapshot.updatedAt,
                batteryPercent: snapshot.batteryPercent,
                solarWatts: snapshot.solarWatts,
                gridWatts: snapshot.gridWatts
            )
        )
        cachedSamples = pruned(cachedSamples, from: Date())
        save(cachedSamples, to: historyURL)
    }

    func samples(duration: TimeInterval) -> [SolixHistorySample] {
        let cutoff = Date().addingTimeInterval(-duration)
        return cachedSamples.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
    }

    func estimatedSolarKWh(since startDate: Date? = nil) -> Double {
        let samples = cachedSamples
            .filter { sample in
                guard let startDate else { return true }
                return sample.date >= startDate
            }
            .sorted { $0.date < $1.date }
        guard samples.count >= 2 else { return 0 }
        return zip(samples, samples.dropFirst()).reduce(0) { total, pair in
            guard let firstWatts = pair.0.solarWatts, let secondWatts = pair.1.solarWatts else { return total }
            return total + SolixEnergyCalculator.measuredKWh(
                from: firstWatts,
                to: secondWatts,
                seconds: pair.1.date.timeIntervalSince(pair.0.date)
            )
        }
    }

    private func migrateLegacyDefaultsIfNeeded() {
        var migrated = false
        if cachedSamples.isEmpty,
           let data = defaults.data(forKey: legacyHistoryKey),
           let samples = try? JSONDecoder().decode([SolixHistorySample].self, from: data) {
            cachedSamples = pruned(samples, from: Date())
            save(cachedSamples, to: historyURL)
            migrated = true
        }
        if cachedAccumulators.isEmpty,
           let data = defaults.data(forKey: legacyAccumulatorKey),
           let accumulators = try? JSONDecoder().decode([String: SolixEnergyAccumulator].self, from: data) {
            cachedAccumulators = accumulators
            save(cachedAccumulators, to: accumulatorsURL)
            migrated = true
        }
        if migrated {
            defaults.removeObject(forKey: legacyHistoryKey)
            defaults.removeObject(forKey: legacyAccumulatorKey)
        }
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            AppLogger.error("Could not save history data: \(error.localizedDescription)")
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func pruned(_ samples: [SolixHistorySample], from date: Date) -> [SolixHistorySample] {
        let cutoff = date.addingTimeInterval(-maxAge)
        let filtered = samples.filter { $0.date >= cutoff }
        return filtered.count > 2000 ? Array(filtered.suffix(2000)) : filtered
    }
}
