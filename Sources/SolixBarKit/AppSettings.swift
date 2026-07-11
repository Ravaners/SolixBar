import Foundation

enum DataSourceMode: String {
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

struct AppSettingsSnapshot: Equatable {
    var dataSourceMode: DataSourceMode
    var command: String
    var urlString: String
    var refreshInterval: TimeInterval
    var barMetrics: [BarMetric]
    var detachedBarMetrics: [BarMetric]
    var detachedShowLabels: Bool
    var detachedShowSymbols: Bool
    var detachedShowArrows: Bool
    var detachedShowIcon: Bool
    var menuBarStacked: Bool
    var detachedBarStacked: Bool
    var showMenuBarIcon: Bool
    var showMetricLabels: Bool
    var showMenuBarMetricSymbols: Bool
    var showEnergyFlowArrows: Bool
    var menuBarScale: Double
    var detachedMenuBarScale: Double
    var lockDetachedMenuBar: Bool
    var appearanceMode: AppAppearanceMode
    var appLanguage: AppLanguage
    var historyRange: HistoryRange
    var customHistoryDays: Double
    var customHistoryUnit: String
    var graphMetrics: [GraphMetric]
    var graphFitsData: Bool
    var isDetachedMenuBarActive: Bool
    var detachedMenuBarFrame: String
}

@MainActor
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard
    private let defaultBarMetrics: [BarMetric] = [.battery, .solar, .grid]

    var dataSourceMode: DataSourceMode {
        get { DataSourceMode(rawValue: defaults.string(forKey: "dataSourceMode") ?? "") ?? .demo }
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

    /// Werte der abgedockten Leiste; folgt der Menüleisten-Auswahl, bis der
    /// Nutzer sie explizit anpasst.
    var detachedBarMetrics: [BarMetric] {
        get {
            guard let values = defaults.array(forKey: "detachedBarMetrics") as? [String] else {
                return barMetrics
            }
            let metrics = values.compactMap(BarMetric.init(rawValue:))
            return metrics.isEmpty ? barMetrics : metrics
        }
        set {
            defaults.set(newValue.map(\.rawValue), forKey: "detachedBarMetrics")
        }
    }

    private func followBool(_ key: String, fallback: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.bool(forKey: key)
    }

    var detachedShowLabels: Bool {
        get { followBool("detachedShowLabels", fallback: showMetricLabels) }
        set { defaults.set(newValue, forKey: "detachedShowLabels") }
    }

    var detachedShowSymbols: Bool {
        get { followBool("detachedShowSymbols", fallback: showMenuBarMetricSymbols) }
        set { defaults.set(newValue, forKey: "detachedShowSymbols") }
    }

    var detachedShowArrows: Bool {
        get { followBool("detachedShowArrows", fallback: showEnergyFlowArrows) }
        set { defaults.set(newValue, forKey: "detachedShowArrows") }
    }

    var detachedShowIcon: Bool {
        get { followBool("detachedShowIcon", fallback: showMenuBarIcon) }
        set { defaults.set(newValue, forKey: "detachedShowIcon") }
    }

    func migrateMenuBarGridMetricIfNeeded() {
        let key = "didMigrateGridMetric033"
        guard defaults.bool(forKey: key) == false else { return }
        if !barMetrics.contains(.grid) {
            barMetrics.append(.grid)
        }
        defaults.set(true, forKey: key)
    }

    /// Kompaktanzeige ist Standard: informationsdicht und notch-sicher.
    var menuBarStacked: Bool {
        get {
            guard defaults.object(forKey: "menuBarStacked") != nil else { return true }
            return defaults.bool(forKey: "menuBarStacked")
        }
        set { defaults.set(newValue, forKey: "menuBarStacked") }
    }

    var detachedBarStacked: Bool {
        get { defaults.bool(forKey: "detachedBarStacked") }
        set { defaults.set(newValue, forKey: "detachedBarStacked") }
    }

    var showMenuBarIcon: Bool {
        get {
            guard defaults.object(forKey: "showMenuBarIcon") != nil else { return true }
            return defaults.bool(forKey: "showMenuBarIcon")
        }
        set { defaults.set(newValue, forKey: "showMenuBarIcon") }
    }

    var showMetricLabels: Bool {
        get {
            guard defaults.object(forKey: "showMetricLabels") != nil else { return true }
            return defaults.bool(forKey: "showMetricLabels")
        }
        set { defaults.set(newValue, forKey: "showMetricLabels") }
    }

    var showMenuBarMetricSymbols: Bool {
        get {
            guard defaults.object(forKey: "showMenuBarMetricSymbols") != nil else { return false }
            return defaults.bool(forKey: "showMenuBarMetricSymbols")
        }
        set { defaults.set(newValue, forKey: "showMenuBarMetricSymbols") }
    }

    var showEnergyFlowArrows: Bool {
        get {
            guard defaults.object(forKey: "showEnergyFlowArrows") != nil else { return false }
            return defaults.bool(forKey: "showEnergyFlowArrows")
        }
        set { defaults.set(newValue, forKey: "showEnergyFlowArrows") }
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

    /// Anzeigeeinheit des eigenen Zeitraums (hours/days/weeks); gespeichert
    /// wird immer in Tagen (customHistoryDays).
    var customHistoryUnit: String {
        get { defaults.string(forKey: "customHistoryUnit") ?? "days" }
        set { defaults.set(newValue, forKey: "customHistoryUnit") }
    }

    var historyDuration: TimeInterval {
        historyRange.duration(customDays: customHistoryDays)
    }

    /// Passt die Zeitachse an vorhandene Daten an, statt leere Zeiträume zu
    /// zeigen. Abschaltbar für den festen Kalenderblick.
    var graphFitsData: Bool {
        get {
            guard defaults.object(forKey: "graphFitsData") != nil else { return true }
            return defaults.bool(forKey: "graphFitsData")
        }
        set { defaults.set(newValue, forKey: "graphFitsData") }
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
            refreshInterval: refreshInterval,
            barMetrics: barMetrics,
            detachedBarMetrics: detachedBarMetrics,
            detachedShowLabels: detachedShowLabels,
            detachedShowSymbols: detachedShowSymbols,
            detachedShowArrows: detachedShowArrows,
            detachedShowIcon: detachedShowIcon,
            menuBarStacked: menuBarStacked,
            detachedBarStacked: detachedBarStacked,
            showMenuBarIcon: showMenuBarIcon,
            showMetricLabels: showMetricLabels,
            showMenuBarMetricSymbols: showMenuBarMetricSymbols,
            showEnergyFlowArrows: showEnergyFlowArrows,
            menuBarScale: menuBarScale,
            detachedMenuBarScale: detachedMenuBarScale,
            lockDetachedMenuBar: lockDetachedMenuBar,
            appearanceMode: appearanceMode,
            appLanguage: appLanguage,
            historyRange: historyRange,
            customHistoryDays: customHistoryDays,
            customHistoryUnit: customHistoryUnit,
            graphMetrics: graphMetrics,
            graphFitsData: graphFitsData,
            isDetachedMenuBarActive: isDetachedMenuBarActive,
            detachedMenuBarFrame: detachedMenuBarFrame
        )
    }

    func apply(_ snapshot: AppSettingsSnapshot) {
        dataSourceMode = snapshot.dataSourceMode
        command = snapshot.command
        urlString = snapshot.urlString
        refreshInterval = snapshot.refreshInterval
        barMetrics = snapshot.barMetrics
        detachedBarMetrics = snapshot.detachedBarMetrics
        detachedShowLabels = snapshot.detachedShowLabels
        detachedShowSymbols = snapshot.detachedShowSymbols
        detachedShowArrows = snapshot.detachedShowArrows
        detachedShowIcon = snapshot.detachedShowIcon
        menuBarStacked = snapshot.menuBarStacked
        detachedBarStacked = snapshot.detachedBarStacked
        showMenuBarIcon = snapshot.showMenuBarIcon
        showMetricLabels = snapshot.showMetricLabels
        showMenuBarMetricSymbols = snapshot.showMenuBarMetricSymbols
        showEnergyFlowArrows = snapshot.showEnergyFlowArrows
        menuBarScale = snapshot.menuBarScale
        detachedMenuBarScale = snapshot.detachedMenuBarScale
        lockDetachedMenuBar = snapshot.lockDetachedMenuBar
        appearanceMode = snapshot.appearanceMode
        appLanguage = snapshot.appLanguage
        historyRange = snapshot.historyRange
        customHistoryDays = snapshot.customHistoryDays
        customHistoryUnit = snapshot.customHistoryUnit
        graphMetrics = snapshot.graphMetrics
        graphFitsData = snapshot.graphFitsData
        isDetachedMenuBarActive = snapshot.isDetachedMenuBarActive
        detachedMenuBarFrame = snapshot.detachedMenuBarFrame
    }
}
