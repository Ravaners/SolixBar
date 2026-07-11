import Foundation

/// Serialisiert die gespeicherte History für den Export — CSV für
/// Tabellenkalkulationen, JSON für Weiterverarbeitung/Backup.
enum HistoryExporter {
    static let csvHeader = "timestamp,batteryPercent,solarWatts,gridWatts,homeWatts,batteryWatts"

    private static func makeTimestampFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        return formatter
    }

    /// Eine Zeile pro Sample, älteste zuerst; fehlende Werte bleiben leere
    /// Zellen. Ist der aktuelle Snapshot neuer als das letzte Sample, kommt
    /// er als Abschlusszeile dazu.
    static func csv(samples: [SolixHistorySample], current: SolixSnapshot? = nil) -> String {
        let formatter = makeTimestampFormatter()
        var rows = [csvHeader]
        for sample in exportSamples(samples: samples, current: current) {
            var cells: [String] = []
            cells.append(formatter.string(from: sample.date))
            cells.append(sample.batteryPercent.map(String.init) ?? "")
            cells.append(sample.solarWatts.map(String.init) ?? "")
            cells.append(sample.gridWatts.map(String.init) ?? "")
            cells.append(sample.homeWatts.map(String.init) ?? "")
            cells.append(sample.batteryWatts.map(String.init) ?? "")
            rows.append(cells.joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    static func json(
        samples: [SolixHistorySample],
        current: SolixSnapshot? = nil,
        sourceKey: String,
        exportedAt: Date = Date()
    ) throws -> Data {
        struct Export: Encodable {
            let exportedAt: String
            let source: String
            let currentSnapshot: SolixSnapshot?
            let samples: [SolixHistorySample]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Export(
            exportedAt: makeTimestampFormatter().string(from: exportedAt),
            source: sourceKey,
            currentSnapshot: current,
            samples: samples
        ))
    }

    @MainActor
    static func defaultFilename(ext: String, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let word = LocalizedText.text("Verlauf", "History")
        return "SolixBar-\(word)-\(formatter.string(from: date)).\(ext)"
    }

    private static func exportSamples(
        samples: [SolixHistorySample],
        current: SolixSnapshot?
    ) -> [SolixHistorySample] {
        var result = samples.sorted { $0.date < $1.date }
        if let current, current.updatedAt > (result.last?.date ?? .distantPast) {
            result.append(SolixHistorySample(
                date: current.updatedAt,
                batteryPercent: current.batteryPercent,
                solarWatts: current.solarWatts,
                gridWatts: current.gridWatts,
                homeWatts: current.homeWatts,
                batteryWatts: current.batteryWatts
            ))
        }
        return result
    }
}
