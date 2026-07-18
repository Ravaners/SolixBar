import Foundation
import SolixBarCore

struct SolixHistorySample: Codable, Sendable, Equatable {
    var date: Date
    var batteryPercent: Int?
    var solarWatts: Int?
    var gridWatts: Int?
}

typealias SolixEnergyAccumulator = SolixCumulativeEnergyState

@MainActor
final class SolixHistoryStore {
    static let shared = SolixHistoryStore()

    private let defaults = UserDefaults.standard
    private let legacyHistoryKey = "solixHistorySamples"
    private let legacyAccumulatorKey = "solixEnergyAccumulators"
    private let maxAge: TimeInterval = 31 * 24 * 60 * 60
    private let fullResolutionAge: TimeInterval = 24 * 60 * 60
    private let olderSampleInterval: TimeInterval = 5 * 60
    private let maximumSamples = 12_000
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

    func cumulativeSolarKWh(
        recording snapshot: SolixSnapshot,
        sourceKey: String,
        configuredManualBaseKWh: Double?
    ) -> Double {
        let accumulatorKey = sourceKey == DataSourceMode.demo.rawValue ? "demo" : "live"
        var accumulator = migratedAccumulator(
            forKey: accumulatorKey,
            sourceKey: sourceKey,
            configuredManualBaseKWh: configuredManualBaseKWh
        )
        accumulator = SolixCumulativeEnergyCalculator.recording(
            state: accumulator,
            solarWatts: snapshot.solarWatts,
            providerTotalKWh: snapshot.totalKWh,
            providerTotalIsAuthoritative: snapshot.totalKWhIsAuthoritative == true,
            configuredManualBaseKWh: configuredManualBaseKWh,
            tracksManualBase: sourceKey == DataSourceMode.solix.rawValue,
            sourceKey: sourceKey,
            date: snapshot.updatedAt
        )
        cachedAccumulators[accumulatorKey] = accumulator
        save(cachedAccumulators, to: accumulatorsURL)
        return accumulator.totalKWh
    }

    private func migratedAccumulator(
        forKey accumulatorKey: String,
        sourceKey: String,
        configuredManualBaseKWh: Double?
    ) -> SolixEnergyAccumulator {
        if let existing = cachedAccumulators[accumulatorKey] {
            return existing
        }

        let legacyKeys = accumulatorKey == "demo" ? ["demo"] : ["solix", "command", "url"]
        let legacy = legacyKeys.compactMap { key in
            cachedAccumulators[key].map { (key: key, value: $0) }
        }
        guard !legacy.isEmpty else {
            return SolixEnergyAccumulator()
        }

        var migrated = SolixCumulativeEnergyCalculator.mergingLegacyStates(
            legacy.map { (sourceKey: $0.key, state: $0.value) }
        )
        if accumulatorKey == "live",
           legacy.count > 1,
           let firstSourceTransition = legacy.compactMap({ $0.value.lastDate }).min() {
            migrated.totalKWh += recoveredSolarGapKWh(since: firstSourceTransition)
        }
        if sourceKey == DataSourceMode.solix.rawValue,
           migrated.manualBaseKWh == nil,
           let configuredManualBaseKWh {
            // Existing installations already applied this base before the state gained a marker.
            migrated.manualBaseKWh = configuredManualBaseKWh
        }
        legacyKeys.filter { $0 != accumulatorKey }.forEach { cachedAccumulators.removeValue(forKey: $0) }
        cachedAccumulators[accumulatorKey] = migrated
        return migrated
    }

    private func recoveredSolarGapKWh(since startDate: Date) -> Double {
        let samples = cachedSamples.filter { $0.date >= startDate }.sorted { $0.date < $1.date }
        return zip(samples, samples.dropFirst()).reduce(0) { total, pair in
            guard let firstWatts = pair.0.solarWatts,
                  let secondWatts = pair.1.solarWatts,
                  Calendar.current.isDate(pair.0.date, inSameDayAs: pair.1.date) else {
                return total
            }
            let seconds = pair.1.date.timeIntervalSince(pair.0.date)
            guard seconds > 30 * 60 else { return total }
            return total + SolixEnergyCalculator.cumulativeKWh(
                from: firstWatts,
                to: secondWatts,
                seconds: seconds,
                maximumGap: 8 * 60 * 60
            )
        }
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
            let isSameDay = Calendar.current.isDate(pair.0.date, inSameDayAs: pair.1.date)
            return total + SolixEnergyCalculator.cumulativeKWh(
                from: firstWatts,
                to: secondWatts,
                seconds: pair.1.date.timeIntervalSince(pair.0.date),
                maximumGap: isSameDay ? 8 * 60 * 60 : 30 * 60
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
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
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
        let fullResolutionCutoff = date.addingTimeInterval(-fullResolutionAge)
        let filtered = samples.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
        var compacted: [SolixHistorySample] = []
        compacted.reserveCapacity(min(maximumSamples, filtered.count))
        var lastOlderBucket: Int?

        for sample in filtered {
            guard sample.date < fullResolutionCutoff else {
                compacted.append(sample)
                continue
            }
            let bucket = Int(sample.date.timeIntervalSince1970 / olderSampleInterval)
            if bucket == lastOlderBucket, !compacted.isEmpty {
                compacted[compacted.count - 1] = sample
            } else {
                compacted.append(sample)
                lastOlderBucket = bucket
            }
        }
        return compacted.count > maximumSamples ? Array(compacted.suffix(maximumSamples)) : compacted
    }
}
