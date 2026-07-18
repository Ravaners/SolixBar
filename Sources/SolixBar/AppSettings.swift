import Foundation

enum DataSourceMode: String {
    case solix
    case demo
    case command
    case url
}

enum AppAppearanceMode: String {
    case system
    case light
    case dark
}

enum AppLanguage: String {
    case german
    case english
}

enum BarMetric: String, CaseIterable {
    case battery
    case solar
    case home
    case grid
    case batteryFlow
    case flow
    case today
    case total
    case status

    var title: String {
        switch self {
        case .battery:
            "Batterie"
        case .solar:
            "PV"
        case .home:
            "Hauslast"
        case .grid:
            "Netzbezug"
        case .batteryFlow:
            "Akku-Fluss"
        case .flow:
            "Energiefluss"
        case .today:
            "Heutiger Ertrag"
        case .total:
            "Gesamtertrag"
        case .status:
            "Status"
        }
    }

    var shortTitle: String {
        switch self {
        case .battery:
            "Akku"
        case .solar:
            "PV"
        case .home:
            "Last"
        case .grid:
            "Netz"
        case .batteryFlow:
            "Fluss"
        case .flow:
            "Flow"
        case .today:
            "Ertrag"
        case .total:
            "Gesamt"
        case .status:
            "Status"
        }
    }

    var symbolName: String {
        switch self {
        case .battery:
            "battery.75percent"
        case .solar:
            "sun.max.fill"
        case .home:
            "house.fill"
        case .grid:
            "powerplug.fill"
        case .batteryFlow:
            "bolt.fill"
        case .flow:
            "arrow.up.arrow.down.circle.fill"
        case .today:
            "chart.bar.fill"
        case .total:
            "sum"
        case .status:
            "checkmark.circle.fill"
        }
    }
}

enum HistoryRange: String, CaseIterable {
    case current
    case day
    case week
    case month
    case custom

    var title: String {
        switch self {
        case .current:
            "Aktuell"
        case .day:
            "24 Stunden"
        case .week:
            "7 Tage"
        case .month:
            "30 Tage"
        case .custom:
            "Individuell"
        }
    }

    var shortTitle: String {
        switch self {
        case .current:
            "Akt."
        case .day:
            "24h"
        case .week:
            "7T"
        case .month:
            "30T"
        case .custom:
            "Eig."
        }
    }

    func duration(customDays: Double) -> TimeInterval {
        switch self {
        case .current:
            3 * 60 * 60
        case .day:
            24 * 60 * 60
        case .week:
            7 * 24 * 60 * 60
        case .month:
            30 * 24 * 60 * 60
        case .custom:
            max(1, customDays) * 24 * 60 * 60
        }
    }
}

enum GraphMetric: String, CaseIterable {
    case battery
    case solar
    case grid

    var title: String {
        switch self {
        case .battery:
            "Akku"
        case .solar:
            "Solar"
        case .grid:
            "Netzbezug"
        }
    }
}

enum WarningKind: String, CaseIterable, Codable {
    case batteryLow
    case solarDrop
    case homeHigh
    case gridImportHigh
    case gridExportHigh
    case batteryChargeHigh
    case batteryDischargeHigh

    @MainActor var title: String {
        switch self {
        case .batteryLow: LocalizedText.text("Akku niedrig", "Battery low")
        case .solarDrop: LocalizedText.text("Solar-Einbruch", "Solar drop")
        case .homeHigh: LocalizedText.text("Hauslast hoch", "Home load high")
        case .gridImportHigh: LocalizedText.text("Netzbezug hoch", "Grid import high")
        case .gridExportHigh: LocalizedText.text("Einspeisung hoch", "Grid export high")
        case .batteryChargeHigh: LocalizedText.text("Akku-Ladung hoch", "Battery charging high")
        case .batteryDischargeHigh: LocalizedText.text("Akku-Entladung hoch", "Battery discharging high")
        }
    }

    var unit: String {
        switch self {
        case .batteryLow, .solarDrop: "%"
        default: "W"
        }
    }

    var defaultThreshold: Double {
        switch self {
        case .batteryLow: 20
        case .solarDrop: 60
        case .homeHigh: 1500
        case .gridImportHigh: 1000
        case .gridExportHigh: 1000
        case .batteryChargeHigh, .batteryDischargeHigh: 1000
        }
    }

    var defaultDurationMinutes: Double {
        switch self {
        case .batteryLow: 1
        case .solarDrop: 5
        default: 2
        }
    }
}

struct WarningRule: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var threshold: Double
    var durationMinutes: Double

    static func defaultRule(for kind: WarningKind) -> WarningRule {
        WarningRule(
            isEnabled: false,
            threshold: kind.defaultThreshold,
            durationMinutes: kind.defaultDurationMinutes
        )
    }
}

struct AppSettingsSnapshot {
    var dataSourceMode: DataSourceMode
    var command: String
    var urlString: String
    var solixCountry: String
    var solixTodayBaseKWh: Double?
    var solixTotalBaseKWh: Double?
    var refreshInterval: TimeInterval
    var barMetrics: [BarMetric]
    var detachedBarMetrics: [BarMetric]
    var showMenuBarIcon: Bool
    var showDetachedMenuBarIcon: Bool
    var showMetricLabels: Bool
    var showDetachedMetricLabels: Bool
    var showMenuBarMetricSymbols: Bool
    var showDetachedMetricSymbols: Bool
    var showEnergyFlowArrows: Bool
    var showDetachedEnergyFlowArrows: Bool
    var menuBarScale: Double
    var detachedMenuBarScale: Double
    var lockDetachedMenuBar: Bool
    var appearanceMode: AppAppearanceMode
    var appLanguage: AppLanguage
    var historyRange: HistoryRange
    var customHistoryDays: Double
    var graphMetrics: [GraphMetric]
    var warningRules: [WarningKind: WarningRule]
    var isDetachedMenuBarActive: Bool
    var detachedMenuBarFrame: String
}

@MainActor
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard
    private let defaultBarMetrics: [BarMetric] = [.battery, .solar, .grid]

    var dataSourceMode: DataSourceMode {
        get {
            let stored = DataSourceMode(rawValue: defaults.string(forKey: "dataSourceMode") ?? "") ?? .demo
            if stored == .command,
               command.contains("run_solix_snapshot.sh") {
                return .solix
            }
            return stored
        }
        set { defaults.set(newValue.rawValue, forKey: "dataSourceMode") }
    }

    var command: String {
        get { defaults.string(forKey: "command") ?? "" }
        set { defaults.set(newValue, forKey: "command") }
    }

    var urlString: String {
        get { defaults.string(forKey: "urlString") ?? "" }
        set { defaults.set(newValue, forKey: "urlString") }
    }

    var solixCountry: String {
        get {
            let value = defaults.string(forKey: "solixCountry")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? "DE" : value.uppercased()
        }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), forKey: "solixCountry") }
    }

    var solixTodayBaseKWh: Double? {
        get {
            guard let value = validNonnegativeDouble(forKey: "solixTodayBaseKWh") else {
                defaults.removeObject(forKey: "solixTodayBaseDate")
                return nil
            }

            let today = Self.localDayKey()
            if let savedDay = defaults.string(forKey: "solixTodayBaseDate") {
                guard savedDay == today else {
                    defaults.removeObject(forKey: "solixTodayBaseKWh")
                    defaults.removeObject(forKey: "solixTodayBaseDate")
                    return nil
                }
            } else {
                // Existing installations did not store the day alongside the correction.
                defaults.set(today, forKey: "solixTodayBaseDate")
            }
            return value
        }
        set {
            let previousValue = optionalDouble(forKey: "solixTodayBaseKWh")
            let value = newValue.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            setOptionalDouble(value, forKey: "solixTodayBaseKWh")
            if let value {
                if previousValue != value || defaults.string(forKey: "solixTodayBaseDate") == nil {
                    defaults.set(Self.localDayKey(), forKey: "solixTodayBaseDate")
                }
            } else {
                defaults.removeObject(forKey: "solixTodayBaseDate")
            }
        }
    }

    var solixTotalBaseKWh: Double? {
        get { validNonnegativeDouble(forKey: "solixTotalBaseKWh") }
        set {
            let value = newValue.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            setOptionalDouble(value, forKey: "solixTotalBaseKWh")
        }
    }

    var refreshInterval: TimeInterval {
        get {
            let value = defaults.double(forKey: "refreshInterval")
            return value > 0 ? max(60, value) : 300
        }
        set { defaults.set(max(60, newValue), forKey: "refreshInterval") }
    }

    var barMetrics: [BarMetric] {
        get {
            guard let values = defaults.array(forKey: "barMetrics") as? [String] else {
                return defaultBarMetrics
            }
            let metrics = values.compactMap(BarMetric.init(rawValue:))
            return metrics.isEmpty ? defaultBarMetrics : metrics
        }
        set {
            let metrics = newValue.isEmpty ? defaultBarMetrics : newValue
            defaults.set(metrics.map(\.rawValue), forKey: "barMetrics")
        }
    }

    var detachedBarMetrics: [BarMetric] {
        get {
            guard let values = defaults.array(forKey: "detachedBarMetrics") as? [String] else {
                return barMetrics
            }
            let metrics = values.compactMap(BarMetric.init(rawValue:))
            return metrics.isEmpty ? defaultBarMetrics : metrics
        }
        set {
            let metrics = newValue.isEmpty ? defaultBarMetrics : newValue
            defaults.set(metrics.map(\.rawValue), forKey: "detachedBarMetrics")
        }
    }

    func migrateMenuBarGridMetricIfNeeded() {
        let key = "didMigrateGridMetric033"
        guard defaults.bool(forKey: key) == false else { return }
        if !barMetrics.contains(.grid) {
            barMetrics.append(.grid)
        }
        defaults.set(true, forKey: key)
    }

    func migrateDetachedBarSettingsIfNeeded() {
        let key = "didMigrateDetachedBarSettings050"
        guard defaults.bool(forKey: key) == false else { return }
        detachedBarMetrics = barMetrics
        showDetachedMenuBarIcon = showMenuBarIcon
        showDetachedMetricLabels = showMetricLabels
        showDetachedMetricSymbols = showMenuBarMetricSymbols
        showDetachedEnergyFlowArrows = showEnergyFlowArrows
        defaults.set(true, forKey: key)
    }

    var showMenuBarIcon: Bool {
        get {
            guard defaults.object(forKey: "showMenuBarIcon") != nil else { return true }
            return defaults.bool(forKey: "showMenuBarIcon")
        }
        set { defaults.set(newValue, forKey: "showMenuBarIcon") }
    }

    var showDetachedMenuBarIcon: Bool {
        get {
            guard defaults.object(forKey: "showDetachedMenuBarIcon") != nil else { return showMenuBarIcon }
            return defaults.bool(forKey: "showDetachedMenuBarIcon")
        }
        set { defaults.set(newValue, forKey: "showDetachedMenuBarIcon") }
    }

    var showMetricLabels: Bool {
        get {
            guard defaults.object(forKey: "showMetricLabels") != nil else { return true }
            return defaults.bool(forKey: "showMetricLabels")
        }
        set { defaults.set(newValue, forKey: "showMetricLabels") }
    }

    var showDetachedMetricLabels: Bool {
        get {
            guard defaults.object(forKey: "showDetachedMetricLabels") != nil else { return showMetricLabels }
            return defaults.bool(forKey: "showDetachedMetricLabels")
        }
        set { defaults.set(newValue, forKey: "showDetachedMetricLabels") }
    }

    var showMenuBarMetricSymbols: Bool {
        get {
            guard defaults.object(forKey: "showMenuBarMetricSymbols") != nil else { return false }
            return defaults.bool(forKey: "showMenuBarMetricSymbols")
        }
        set { defaults.set(newValue, forKey: "showMenuBarMetricSymbols") }
    }

    var showDetachedMetricSymbols: Bool {
        get {
            guard defaults.object(forKey: "showDetachedMetricSymbols") != nil else { return showMenuBarMetricSymbols }
            return defaults.bool(forKey: "showDetachedMetricSymbols")
        }
        set { defaults.set(newValue, forKey: "showDetachedMetricSymbols") }
    }

    var showEnergyFlowArrows: Bool {
        get {
            guard defaults.object(forKey: "showEnergyFlowArrows") != nil else { return false }
            return defaults.bool(forKey: "showEnergyFlowArrows")
        }
        set { defaults.set(newValue, forKey: "showEnergyFlowArrows") }
    }

    var showDetachedEnergyFlowArrows: Bool {
        get {
            guard defaults.object(forKey: "showDetachedEnergyFlowArrows") != nil else { return showEnergyFlowArrows }
            return defaults.bool(forKey: "showDetachedEnergyFlowArrows")
        }
        set { defaults.set(newValue, forKey: "showDetachedEnergyFlowArrows") }
    }

    var menuBarScale: Double {
        get {
            let value = defaults.double(forKey: "menuBarScale")
            return value > 0 ? min(1.6, max(0.75, value)) : 1.0
        }
        set { defaults.set(min(1.6, max(0.75, newValue)), forKey: "menuBarScale") }
    }

    var detachedMenuBarScale: Double {
        get {
            let value = defaults.double(forKey: "detachedMenuBarScale")
            return value > 0 ? min(1.9, max(0.75, value)) : 1.0
        }
        set { defaults.set(min(1.9, max(0.75, newValue)), forKey: "detachedMenuBarScale") }
    }

    var lockDetachedMenuBar: Bool {
        get { defaults.bool(forKey: "lockDetachedMenuBar") }
        set { defaults.set(newValue, forKey: "lockDetachedMenuBar") }
    }

    var appearanceMode: AppAppearanceMode {
        get { AppAppearanceMode(rawValue: defaults.string(forKey: "appearanceMode") ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: "appearanceMode") }
    }

    var appLanguage: AppLanguage {
        get { AppLanguage(rawValue: defaults.string(forKey: "appLanguage") ?? "") ?? .german }
        set { defaults.set(newValue.rawValue, forKey: "appLanguage") }
    }

    var historyRange: HistoryRange {
        get { HistoryRange(rawValue: defaults.string(forKey: "historyRange") ?? "") ?? .day }
        set { defaults.set(newValue.rawValue, forKey: "historyRange") }
    }

    var customHistoryDays: Double {
        get {
            let value = defaults.double(forKey: "customHistoryDays")
            return value > 0 ? min(365, max(1, value)) : 14
        }
        set { defaults.set(min(365, max(1, newValue)), forKey: "customHistoryDays") }
    }

    var historyDuration: TimeInterval {
        historyRange.duration(customDays: customHistoryDays)
    }

    var graphMetrics: [GraphMetric] {
        get {
            guard let values = defaults.array(forKey: "graphMetrics") as? [String] else {
                return GraphMetric.allCases
            }
            let metrics = values.compactMap(GraphMetric.init(rawValue:))
            return metrics.isEmpty ? GraphMetric.allCases : metrics
        }
        set {
            let metrics = newValue.isEmpty ? GraphMetric.allCases : newValue
            defaults.set(metrics.map(\.rawValue), forKey: "graphMetrics")
        }
    }

    var warningRules: [WarningKind: WarningRule] {
        get {
            guard let data = defaults.data(forKey: "warningRules"),
                  let stored = try? JSONDecoder().decode([WarningKind: WarningRule].self, from: data) else {
                return Dictionary(uniqueKeysWithValues: WarningKind.allCases.map { ($0, .defaultRule(for: $0)) })
            }
            return Dictionary(uniqueKeysWithValues: WarningKind.allCases.map { kind in
                (kind, stored[kind] ?? .defaultRule(for: kind))
            })
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "warningRules")
            }
        }
    }

    var isDetachedMenuBarActive: Bool {
        get { defaults.bool(forKey: "isDetachedMenuBarActive") }
        set { defaults.set(newValue, forKey: "isDetachedMenuBarActive") }
    }

    var detachedMenuBarFrame: String {
        get { defaults.string(forKey: "detachedMenuBarFrame") ?? "" }
        set { defaults.set(newValue, forKey: "detachedMenuBarFrame") }
    }

    func snapshot() -> AppSettingsSnapshot {
        AppSettingsSnapshot(
            dataSourceMode: dataSourceMode,
            command: command,
            urlString: urlString,
            solixCountry: solixCountry,
            solixTodayBaseKWh: solixTodayBaseKWh,
            solixTotalBaseKWh: solixTotalBaseKWh,
            refreshInterval: refreshInterval,
            barMetrics: barMetrics,
            detachedBarMetrics: detachedBarMetrics,
            showMenuBarIcon: showMenuBarIcon,
            showDetachedMenuBarIcon: showDetachedMenuBarIcon,
            showMetricLabels: showMetricLabels,
            showDetachedMetricLabels: showDetachedMetricLabels,
            showMenuBarMetricSymbols: showMenuBarMetricSymbols,
            showDetachedMetricSymbols: showDetachedMetricSymbols,
            showEnergyFlowArrows: showEnergyFlowArrows,
            showDetachedEnergyFlowArrows: showDetachedEnergyFlowArrows,
            menuBarScale: menuBarScale,
            detachedMenuBarScale: detachedMenuBarScale,
            lockDetachedMenuBar: lockDetachedMenuBar,
            appearanceMode: appearanceMode,
            appLanguage: appLanguage,
            historyRange: historyRange,
            customHistoryDays: customHistoryDays,
            graphMetrics: graphMetrics,
            warningRules: warningRules,
            isDetachedMenuBarActive: isDetachedMenuBarActive,
            detachedMenuBarFrame: detachedMenuBarFrame
        )
    }

    func apply(_ snapshot: AppSettingsSnapshot) {
        dataSourceMode = snapshot.dataSourceMode
        command = snapshot.command
        urlString = snapshot.urlString
        solixCountry = snapshot.solixCountry
        solixTodayBaseKWh = snapshot.solixTodayBaseKWh
        solixTotalBaseKWh = snapshot.solixTotalBaseKWh
        refreshInterval = snapshot.refreshInterval
        barMetrics = snapshot.barMetrics
        detachedBarMetrics = snapshot.detachedBarMetrics
        showMenuBarIcon = snapshot.showMenuBarIcon
        showDetachedMenuBarIcon = snapshot.showDetachedMenuBarIcon
        showMetricLabels = snapshot.showMetricLabels
        showDetachedMetricLabels = snapshot.showDetachedMetricLabels
        showMenuBarMetricSymbols = snapshot.showMenuBarMetricSymbols
        showDetachedMetricSymbols = snapshot.showDetachedMetricSymbols
        showEnergyFlowArrows = snapshot.showEnergyFlowArrows
        showDetachedEnergyFlowArrows = snapshot.showDetachedEnergyFlowArrows
        menuBarScale = snapshot.menuBarScale
        detachedMenuBarScale = snapshot.detachedMenuBarScale
        lockDetachedMenuBar = snapshot.lockDetachedMenuBar
        appearanceMode = snapshot.appearanceMode
        appLanguage = snapshot.appLanguage
        historyRange = snapshot.historyRange
        customHistoryDays = snapshot.customHistoryDays
        graphMetrics = snapshot.graphMetrics
        warningRules = snapshot.warningRules
        isDetachedMenuBarActive = snapshot.isDetachedMenuBarActive
        detachedMenuBarFrame = snapshot.detachedMenuBarFrame
    }

    private func optionalDouble(forKey key: String) -> Double? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.double(forKey: key)
    }

    private func validNonnegativeDouble(forKey key: String) -> Double? {
        guard let value = optionalDouble(forKey: key), value.isFinite, value >= 0 else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return value
    }

    private func setOptionalDouble(_ value: Double?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func localDayKey(_ date: Date = Date()) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
