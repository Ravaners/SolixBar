import Foundation

struct SolixHistorySample: Codable, Sendable {
    var date: Date
    var batteryPercent: Int?
    var solarWatts: Int?
    var gridWatts: Int?
}

private struct SolixEnergyAccumulator: Codable {
    var totalKWh: Double = 0
    var lastDate: Date?
    var lastSolarWatts: Int?
}

/// Verlaufsdatei: Samples getrennt pro Datenquelle, damit Demo-Daten den
/// Live-Graphen nicht verfälschen. Persistenz als JSON-Datei in Application
/// Support statt als UserDefaults-Blob.
private struct HistoryFile: Codable {
    var version = 1
    var samples: [String: [SolixHistorySample]] = [:]
}

@MainActor
final class SolixHistoryStore {
    static let shared = SolixHistoryStore()

    private let defaults: UserDefaults
    private let fileURL: URL
    private let legacyKey = "solixHistorySamples"
    private let accumulatorKey = "solixEnergyAccumulators"
    private let maxAge: TimeInterval = 366 * 24 * 60 * 60
    private let fineWindow: TimeInterval = 31 * 24 * 60 * 60
    private var cache: HistoryFile?

    init(defaults: UserDefaults = .standard, fileURL: URL = SolixPaths.historyFileURL) {
        self.defaults = defaults
        self.fileURL = fileURL
    }

    func cumulativeSolarKWh(recording snapshot: SolixSnapshot, sourceKey: String) -> Double {
        var accumulators = loadAccumulators()
        var accumulator = accumulators[sourceKey] ?? SolixEnergyAccumulator()

        if let lastDate = accumulator.lastDate,
           let lastSolarWatts = accumulator.lastSolarWatts,
           let solarWatts = snapshot.solarWatts {
            let seconds = snapshot.updatedAt.timeIntervalSince(lastDate)
            if seconds > 0, seconds <= 30 * 60 {
                let measuredKWh = Double(lastSolarWatts + solarWatts) / 2 * seconds / 3_600_000
                accumulator.totalKWh += max(0, measuredKWh)
            }
        }

        if let providerTotal = snapshot.totalKWh, providerTotal > accumulator.totalKWh {
            accumulator.totalKWh = providerTotal
        }

        accumulator.lastDate = snapshot.updatedAt
        accumulator.lastSolarWatts = snapshot.solarWatts
        accumulators[sourceKey] = accumulator
        saveAccumulators(accumulators)
        return accumulator.totalKWh
    }

    func record(_ snapshot: SolixSnapshot, sourceKey: String, refreshInterval: TimeInterval) {
        var file = loadFile()
        var samples = file.samples[sourceKey] ?? []
        samples.append(
            SolixHistorySample(
                date: snapshot.updatedAt,
                batteryPercent: snapshot.batteryPercent,
                solarWatts: snapshot.solarWatts,
                gridWatts: snapshot.gridWatts
            )
        )
        file.samples[sourceKey] = pruned(samples, from: Date(), refreshInterval: refreshInterval)
        saveFile(file)
    }

    func samples(duration: TimeInterval, sourceKey: String) -> [SolixHistorySample] {
        let cutoff = Date().addingTimeInterval(-duration)
        return (loadFile().samples[sourceKey] ?? [])
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
    }

    /// Cap für das Feinfenster (31 Tage volle Auflösung) so, dass es beim
    /// konfigurierten Intervall vollständig gefüllt werden kann.
    static func maxSamples(refreshInterval: TimeInterval) -> Int {
        let interval = max(60, refreshInterval)
        let thirtyDays = 30.0 * 24 * 60 * 60
        return max(2000, Int(thirtyDays / interval) + 100)
    }

    /// Zweistufige Aufbewahrung: 31 Tage in voller Aufloesung, danach bis zu
    /// 366 Tage auf Stundenaufloesung ausgeduennt — Jahresansichten ohne
    /// Multi-Megabyte-Datei.
    private func pruned(_ samples: [SolixHistorySample], from date: Date, refreshInterval: TimeInterval) -> [SolixHistorySample] {
        let ageCutoff = date.addingTimeInterval(-maxAge)
        let fineCutoff = date.addingTimeInterval(-fineWindow)
        let kept = samples.filter { $0.date >= ageCutoff }

        var hourly: [Int: SolixHistorySample] = [:]
        var fine: [SolixHistorySample] = []
        for sample in kept {
            if sample.date >= fineCutoff {
                fine.append(sample)
            } else {
                // letztes Sample je Stunde gewinnt
                hourly[Int(sample.date.timeIntervalSince1970 / 3600)] = sample
            }
        }
        let cap = Self.maxSamples(refreshInterval: refreshInterval)
        if fine.count > cap {
            fine = Array(fine.suffix(cap))
        }
        let coarse = hourly.values.sorted { $0.date < $1.date }
        return coarse + fine
    }

    // MARK: Persistenz

    private func loadFile() -> HistoryFile {
        if let cache { return cache }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        if let data = try? Data(contentsOf: fileURL),
           let file = try? decoder.decode(HistoryFile.self, from: data) {
            cache = file
            return file
        }
        // Migration: alter UserDefaults-Blob (Quelle unbekannt, stammt praktisch
        // immer aus dem Demo-Modus) wandert unter den Demo-Schlüssel.
        var file = HistoryFile()
        if let legacyData = defaults.data(forKey: legacyKey),
           let legacy = try? JSONDecoder().decode([SolixHistorySample].self, from: legacyData) {
            file.samples[DataSourceMode.demo.rawValue] = legacy
            defaults.removeObject(forKey: legacyKey)
            AppLogger.info("Migrated \(legacy.count) legacy history samples to per-source history file.")
        }
        cache = file
        return file
    }

    private func saveFile(_ file: HistoryFile) {
        cache = file
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(file) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    private func loadAccumulators() -> [String: SolixEnergyAccumulator] {
        guard let data = defaults.data(forKey: accumulatorKey) else { return [:] }
        return (try? JSONDecoder().decode([String: SolixEnergyAccumulator].self, from: data)) ?? [:]
    }

    private func saveAccumulators(_ accumulators: [String: SolixEnergyAccumulator]) {
        guard let data = try? JSONEncoder().encode(accumulators) else { return }
        defaults.set(data, forKey: accumulatorKey)
    }
}
