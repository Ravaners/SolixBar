import Foundation

enum DataSourceMode: String {
    case demo
    case command
    case url
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
            "Haus"
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
            "Haus"
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

struct AppSettingsSnapshot {
    var dataSourceMode: DataSourceMode
    var command: String
    var urlString: String
    var refreshInterval: TimeInterval
    var barMetrics: [BarMetric]
    var showMenuBarIcon: Bool
    var showMetricLabels: Bool
    var showMenuBarMetricSymbols: Bool
    var showEnergyFlowArrows: Bool
    var menuBarScale: Double
    var detachedMenuBarScale: Double
    var historyRange: HistoryRange
    var customHistoryDays: Double
    var graphMetrics: [GraphMetric]
    var isDetachedMenuBarActive: Bool
    var detachedMenuBarFrame: String
}

@MainActor
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

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
                return [.battery, .solar]
            }
            let metrics = values.compactMap(BarMetric.init(rawValue:))
            return metrics.isEmpty ? [.battery, .solar] : metrics
        }
        set {
            let metrics = newValue.isEmpty ? [BarMetric.battery, .solar] : newValue
            defaults.set(metrics.map(\.rawValue), forKey: "barMetrics")
        }
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
            showMenuBarIcon: showMenuBarIcon,
            showMetricLabels: showMetricLabels,
            showMenuBarMetricSymbols: showMenuBarMetricSymbols,
            showEnergyFlowArrows: showEnergyFlowArrows,
            menuBarScale: menuBarScale,
            detachedMenuBarScale: detachedMenuBarScale,
            historyRange: historyRange,
            customHistoryDays: customHistoryDays,
            graphMetrics: graphMetrics,
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
        showMenuBarIcon = snapshot.showMenuBarIcon
        showMetricLabels = snapshot.showMetricLabels
        showMenuBarMetricSymbols = snapshot.showMenuBarMetricSymbols
        showEnergyFlowArrows = snapshot.showEnergyFlowArrows
        menuBarScale = snapshot.menuBarScale
        detachedMenuBarScale = snapshot.detachedMenuBarScale
        historyRange = snapshot.historyRange
        customHistoryDays = snapshot.customHistoryDays
        graphMetrics = snapshot.graphMetrics
        isDetachedMenuBarActive = snapshot.isDetachedMenuBarActive
        detachedMenuBarFrame = snapshot.detachedMenuBarFrame
    }
}
