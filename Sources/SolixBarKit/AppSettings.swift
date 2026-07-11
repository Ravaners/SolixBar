import Foundation

enum DataSourceMode: String {
    case demo
    /// Gerafftes Test-Szenario, damit aktivierte Warnungen innerhalb
    /// weniger Minuten wirklich feuern.
    case demoWarnings = "demo-warnings"
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

/// Fensterebene der frei platzierbaren Fenster (Slim-Bar, abgedocktes
/// Dashboard): immer vorn, normal im Fensterstapel oder immer hinten.
/// Darstellung des PV-Werts, wenn die Solarbank ihre MPPT-Kanäle einzeln
/// meldet: nur Summe, nur Einzelwerte oder beides.
enum PVDisplayMode: String, CaseIterable, Sendable {
    case total
    case perInput
    case both

    @MainActor var title: String {
        switch self {
        case .total:
            return LocalizedText.text("Gesamtwert", "Total")
        case .perInput:
            return LocalizedText.text("Einzelwerte", "Individual inputs")
        case .both:
            return LocalizedText.text("Gesamt + Einzelwerte", "Total + individual")
        }
    }
}

enum WindowLevelMode: String, CaseIterable {
    case alwaysOnTop
    case normal
    case alwaysBehind

    @MainActor var title: String {
        switch self {
        case .alwaysOnTop:
            return LocalizedText.text("Immer im Vordergrund", "Always on top")
        case .normal:
            return LocalizedText.text("Normal (wie andere Fenster)", "Normal (like other windows)")
        case .alwaysBehind:
            return LocalizedText.text("Immer im Hintergrund", "Always behind")
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
    var stackedBarMetrics: [BarMetric]
    var detachedStackedBarMetrics: [BarMetric]
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
    var showFlowColors: Bool
    var detachedShowFlowColors: Bool
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
    var detachedBarLevel: WindowLevelMode
    var dashboardWindowLevel: WindowLevelMode
    var graphWindowLevel: WindowLevelMode
    var updateCheckEnabled: Bool
    var dashboardPVDisplay: PVDisplayMode
    var detachedDashboardPVDisplay: PVDisplayMode
    var menuBarPVDisplay: PVDisplayMode
    var detachedPVDisplay: PVDisplayMode
    var warnBatteryLowEnabled: Bool
    var warnBatteryLowThreshold: Int
    var warnPVStallEnabled: Bool
    var warnPVStallMinutes: Int
    var warnPVStallMinRecentWatts: Int
    var warnPVWindowEnabled: Bool
    var warnPVWindowStart: Int
    var warnPVWindowEnd: Int
    var warnPerPVEnabled: Bool
    var warnPerPVDipEnabled: Bool
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

    /// Werte der Kompaktansicht (Menüleiste); leer = folgt der einzeiligen
    /// Liste, bis der Nutzer sie in den Einstellungen entkoppelt.
    var stackedBarMetrics: [BarMetric] {
        get {
            guard let values = defaults.array(forKey: "stackedBarMetrics") as? [String] else { return [] }
            return values.compactMap(BarMetric.init(rawValue:))
        }
        set { defaults.set(newValue.map(\.rawValue), forKey: "stackedBarMetrics") }
    }

    var effectiveStackedBarMetrics: [BarMetric] {
        let stacked = stackedBarMetrics
        return stacked.isEmpty ? barMetrics : stacked
    }

    /// Werte der Kompaktansicht der abgedockten Leiste; leer = folgt deren
    /// einzeiliger Liste (die ihrerseits der Menüleiste folgen kann).
    var detachedStackedBarMetrics: [BarMetric] {
        get {
            guard let values = defaults.array(forKey: "detachedStackedBarMetrics") as? [String] else { return [] }
            return values.compactMap(BarMetric.init(rawValue:))
        }
        set { defaults.set(newValue.map(\.rawValue), forKey: "detachedStackedBarMetrics") }
    }

    var effectiveDetachedStackedBarMetrics: [BarMetric] {
        let stacked = detachedStackedBarMetrics
        return stacked.isEmpty ? detachedBarMetrics : stacked
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

    /// Der Sammelwert "Energiefluss" zeigte dieselben Pfeile und Begriffe wie
    /// die Option "Farben und Flussrichtung" ein zweites Mal — er entfällt.
    /// Wer ihn aktiv hatte, behält die Information über die Pfeil-Option.
    func migrateFlowMetricIfNeeded() {
        let key = "didMigrateFlowMetric040"
        guard defaults.bool(forKey: key) == false else { return }
        defaults.set(true, forKey: key)
        if let stored = defaults.array(forKey: "barMetrics") as? [String], stored.contains("flow") {
            defaults.set(stored.filter { $0 != "flow" }, forKey: "barMetrics")
            showEnergyFlowArrows = true
        }
        if let stored = defaults.array(forKey: "detachedBarMetrics") as? [String], stored.contains("flow") {
            defaults.set(stored.filter { $0 != "flow" }, forKey: "detachedBarMetrics")
            detachedShowArrows = true
        }
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

    /// Rollenfarben getrennt von der Flussrichtung — die frühere Option
    /// schaltete beides gemeinsam. Standard an: entspricht der farbigen
    /// Kompaktanzeige.
    var showFlowColors: Bool {
        get { followBool("showFlowColors", fallback: true) }
        set { defaults.set(newValue, forKey: "showFlowColors") }
    }

    var detachedShowFlowColors: Bool {
        get { followBool("detachedShowFlowColors", fallback: showFlowColors) }
        set { defaults.set(newValue, forKey: "detachedShowFlowColors") }
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

    /// Standardwerte entsprechen dem bisherigen festen Verhalten:
    /// Slim-Bar hinten (Schreibtisch-Ebene), Dashboard immer vorn.
    var detachedBarLevel: WindowLevelMode {
        get { WindowLevelMode(rawValue: defaults.string(forKey: "detachedBarLevel") ?? "") ?? .alwaysBehind }
        set { defaults.set(newValue.rawValue, forKey: "detachedBarLevel") }
    }

    var dashboardWindowLevel: WindowLevelMode {
        get { WindowLevelMode(rawValue: defaults.string(forKey: "dashboardWindowLevel") ?? "") ?? .alwaysOnTop }
        set { defaults.set(newValue.rawValue, forKey: "dashboardWindowLevel") }
    }

    /// Abgedocktes Verlaufsfenster: verhält sich standardmäßig wie ein
    /// normales Fenster (vorn wenn aktiv, sonst dahinter).
    var graphWindowLevel: WindowLevelMode {
        get { WindowLevelMode(rawValue: defaults.string(forKey: "graphWindowLevel") ?? "") ?? .normal }
        set { defaults.set(newValue.rawValue, forKey: "graphWindowLevel") }
    }

    var isLargeGraphActive: Bool {
        get { defaults.bool(forKey: "isLargeGraphActive") }
        set { defaults.set(newValue, forKey: "isLargeGraphActive") }
    }

    var updateCheckEnabled: Bool {
        get { followBool("updateCheckEnabled", fallback: true) }
        set { defaults.set(newValue, forKey: "updateCheckEnabled") }
    }

    /// PV-Anzeige je Fläche (Summe/Einzelwerte/beides). Die kurzlebigen
    /// Bool-Vorgänger aus der 0.4.2-Testphase werden als Fallback gelesen.
    var dashboardPVDisplay: PVDisplayMode {
        get { pvDisplayMode(forKey: "dashboardPVDisplay", legacyBoolKey: "showPerPVValues") }
        set { defaults.set(newValue.rawValue, forKey: "dashboardPVDisplay") }
    }

    /// Abgedocktes Dashboard-Fenster; folgt dem Menü-Dashboard, bis explizit gesetzt.
    var detachedDashboardPVDisplay: PVDisplayMode {
        get {
            if let raw = defaults.string(forKey: "detachedDashboardPVDisplay"),
               let mode = PVDisplayMode(rawValue: raw) {
                return mode
            }
            return dashboardPVDisplay
        }
        set { defaults.set(newValue.rawValue, forKey: "detachedDashboardPVDisplay") }
    }

    var menuBarPVDisplay: PVDisplayMode {
        get { pvDisplayMode(forKey: "menuBarPVDisplay", legacyBoolKey: "menuBarPerPVWatts") }
        set { defaults.set(newValue.rawValue, forKey: "menuBarPVDisplay") }
    }

    /// Abgedockte Leiste; folgt der Menüleisten-Option, bis explizit gesetzt.
    var detachedPVDisplay: PVDisplayMode {
        get {
            if let raw = defaults.string(forKey: "detachedPVDisplay"),
               let mode = PVDisplayMode(rawValue: raw) {
                return mode
            }
            if defaults.object(forKey: "detachedPerPVWatts") != nil {
                return defaults.bool(forKey: "detachedPerPVWatts") ? .perInput : .total
            }
            return menuBarPVDisplay
        }
        set { defaults.set(newValue.rawValue, forKey: "detachedPVDisplay") }
    }

    private func pvDisplayMode(forKey key: String, legacyBoolKey: String) -> PVDisplayMode {
        if let raw = defaults.string(forKey: key), let mode = PVDisplayMode(rawValue: raw) {
            return mode
        }
        return defaults.bool(forKey: legacyBoolKey) ? .perInput : .total
    }

    // MARK: Warnungen (alle opt-in — ein Update darf nicht unaufgefordert
    // Mitteilungen schicken)

    var warnBatteryLowEnabled: Bool {
        get { followBool("warnBatteryLowEnabled", fallback: false) }
        set { defaults.set(newValue, forKey: "warnBatteryLowEnabled") }
    }

    var warnBatteryLowThreshold: Int {
        get {
            let value = defaults.integer(forKey: "warnBatteryLowThreshold")
            return value > 0 ? min(95, max(5, value)) : 20
        }
        set { defaults.set(min(95, max(5, newValue)), forKey: "warnBatteryLowThreshold") }
    }

    var warnPVStallEnabled: Bool {
        get { followBool("warnPVStallEnabled", fallback: false) }
        set { defaults.set(newValue, forKey: "warnPVStallEnabled") }
    }

    var warnPVStallMinutes: Int {
        get {
            let value = defaults.integer(forKey: "warnPVStallMinutes")
            return value > 0 ? min(120, max(5, value)) : 15
        }
        set { defaults.set(min(120, max(5, newValue)), forKey: "warnPVStallMinutes") }
    }

    var warnPVStallMinRecentWatts: Int {
        get {
            let value = defaults.integer(forKey: "warnPVStallMinRecentWatts")
            return value > 0 ? min(2000, max(10, value)) : 50
        }
        set { defaults.set(min(2000, max(10, newValue)), forKey: "warnPVStallMinRecentWatts") }
    }

    var warnPVWindowEnabled: Bool {
        get { followBool("warnPVWindowEnabled", fallback: false) }
        set { defaults.set(newValue, forKey: "warnPVWindowEnabled") }
    }

    var warnPVWindowStart: Int {
        get {
            guard defaults.object(forKey: "warnPVWindowStart") != nil else { return 9 }
            return min(23, max(0, defaults.integer(forKey: "warnPVWindowStart")))
        }
        set { defaults.set(min(23, max(0, newValue)), forKey: "warnPVWindowStart") }
    }

    var warnPVWindowEnd: Int {
        get {
            guard defaults.object(forKey: "warnPVWindowEnd") != nil else { return 17 }
            return min(24, max(1, defaults.integer(forKey: "warnPVWindowEnd")))
        }
        set { defaults.set(min(24, max(1, newValue)), forKey: "warnPVWindowEnd") }
    }

    var warnPerPVEnabled: Bool {
        get { followBool("warnPerPVEnabled", fallback: false) }
        set { defaults.set(newValue, forKey: "warnPerPVEnabled") }
    }

    var warnPerPVDipEnabled: Bool {
        get { followBool("warnPerPVDipEnabled", fallback: false) }
        set { defaults.set(newValue, forKey: "warnPerPVDipEnabled") }
    }

    func warningConfig() -> WarningEngine.Config {
        WarningEngine.Config(
            batteryLowEnabled: warnBatteryLowEnabled,
            batteryLowThreshold: warnBatteryLowThreshold,
            pvStallEnabled: warnPVStallEnabled,
            pvStallMinutes: warnPVStallMinutes,
            pvStallMinRecentWatts: warnPVStallMinRecentWatts,
            pvWindowEnabled: warnPVWindowEnabled,
            pvWindowStartHour: warnPVWindowStart,
            pvWindowEndHour: warnPVWindowEnd,
            perPVEnabled: warnPerPVEnabled,
            perPVDipEnabled: warnPerPVDipEnabled
        )
    }

    /// Zuletzt gemeldete Update-Version — Zustand, keine Einstellung: bewusst
    /// nicht im Snapshot, damit "Abbrechen" im Einstellungsfenster keine
    /// bereits gezeigte Benachrichtigung wieder scharf schaltet.
    var lastNotifiedUpdateVersion: String? {
        get { defaults.string(forKey: "lastNotifiedUpdateVersion") }
        set { defaults.set(newValue, forKey: "lastNotifiedUpdateVersion") }
    }

    func snapshot() -> AppSettingsSnapshot {
        AppSettingsSnapshot(
            dataSourceMode: dataSourceMode,
            command: command,
            urlString: urlString,
            refreshInterval: refreshInterval,
            barMetrics: barMetrics,
            detachedBarMetrics: detachedBarMetrics,
            stackedBarMetrics: stackedBarMetrics,
            detachedStackedBarMetrics: detachedStackedBarMetrics,
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
            showFlowColors: showFlowColors,
            detachedShowFlowColors: detachedShowFlowColors,
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
            detachedMenuBarFrame: detachedMenuBarFrame,
            detachedBarLevel: detachedBarLevel,
            dashboardWindowLevel: dashboardWindowLevel,
            graphWindowLevel: graphWindowLevel,
            updateCheckEnabled: updateCheckEnabled,
            dashboardPVDisplay: dashboardPVDisplay,
            detachedDashboardPVDisplay: detachedDashboardPVDisplay,
            menuBarPVDisplay: menuBarPVDisplay,
            detachedPVDisplay: detachedPVDisplay,
            warnBatteryLowEnabled: warnBatteryLowEnabled,
            warnBatteryLowThreshold: warnBatteryLowThreshold,
            warnPVStallEnabled: warnPVStallEnabled,
            warnPVStallMinutes: warnPVStallMinutes,
            warnPVStallMinRecentWatts: warnPVStallMinRecentWatts,
            warnPVWindowEnabled: warnPVWindowEnabled,
            warnPVWindowStart: warnPVWindowStart,
            warnPVWindowEnd: warnPVWindowEnd,
            warnPerPVEnabled: warnPerPVEnabled,
            warnPerPVDipEnabled: warnPerPVDipEnabled
        )
    }

    func apply(_ snapshot: AppSettingsSnapshot) {
        dataSourceMode = snapshot.dataSourceMode
        command = snapshot.command
        urlString = snapshot.urlString
        refreshInterval = snapshot.refreshInterval
        barMetrics = snapshot.barMetrics
        detachedBarMetrics = snapshot.detachedBarMetrics
        stackedBarMetrics = snapshot.stackedBarMetrics
        detachedStackedBarMetrics = snapshot.detachedStackedBarMetrics
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
        showFlowColors = snapshot.showFlowColors
        detachedShowFlowColors = snapshot.detachedShowFlowColors
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
        detachedBarLevel = snapshot.detachedBarLevel
        dashboardWindowLevel = snapshot.dashboardWindowLevel
        graphWindowLevel = snapshot.graphWindowLevel
        updateCheckEnabled = snapshot.updateCheckEnabled
        dashboardPVDisplay = snapshot.dashboardPVDisplay
        detachedDashboardPVDisplay = snapshot.detachedDashboardPVDisplay
        menuBarPVDisplay = snapshot.menuBarPVDisplay
        detachedPVDisplay = snapshot.detachedPVDisplay
        warnBatteryLowEnabled = snapshot.warnBatteryLowEnabled
        warnBatteryLowThreshold = snapshot.warnBatteryLowThreshold
        warnPVStallEnabled = snapshot.warnPVStallEnabled
        warnPVStallMinutes = snapshot.warnPVStallMinutes
        warnPVStallMinRecentWatts = snapshot.warnPVStallMinRecentWatts
        warnPVWindowEnabled = snapshot.warnPVWindowEnabled
        warnPVWindowStart = snapshot.warnPVWindowStart
        warnPVWindowEnd = snapshot.warnPVWindowEnd
        warnPerPVEnabled = snapshot.warnPerPVEnabled
        warnPerPVDipEnabled = snapshot.warnPerPVDipEnabled
    }
}
