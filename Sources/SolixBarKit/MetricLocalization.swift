import Foundation

/// Zentrale, sprachbewusste Namen für Metriken — ersetzt vier verstreute
/// switch-Blöcke (StatusController, Settings, Header, Tooltips), die bei
/// jeder Textänderung einzeln nachgezogen werden mussten.
/// Hinweis: Ein Apple String Catalog folgt der System-Locale; SolixBar hat
/// einen eigenen In-App-Sprachschalter, daher bleibt dieses Modell.
@MainActor
extension BarMetric {
    var localizedTitle: String {
        switch self {
        case .battery: LocalizedText.text("Batterie", "Battery")
        case .solar: "PV"
        case .home: LocalizedText.text("Hauslast", "Home Load")
        case .grid: LocalizedText.text("Netzbezug", "Grid Import")
        case .batteryFlow: LocalizedText.text("Akku-Fluss", "Battery Flow")
        case .today: LocalizedText.text("Heutiger Ertrag", "Today's Yield")
        case .total: LocalizedText.text("Gesamtertrag", "Total Yield")
        case .status: "Status"
        }
    }

    var localizedShortTitle: String {
        switch self {
        case .battery: LocalizedText.text("Akku", "Batt")
        case .solar: "PV"
        case .home: LocalizedText.text("Last", "Load")
        case .grid: LocalizedText.text("Netz", "Grid")
        case .batteryFlow: LocalizedText.text("Fluss", "Flow")
        case .today: LocalizedText.text("Ertrag", "Yield")
        case .total: LocalizedText.text("Gesamt", "Total")
        case .status: "Status"
        }
    }

    var localizedTooltip: String {
        switch self {
        case .battery: LocalizedText.text(
            "Zeigt den aktuellen Akkustand in Prozent.",
            "Shows the current battery level in percent.")
        case .solar: LocalizedText.text(
            "Zeigt die aktuelle Solarleistung in Watt.",
            "Shows the current solar output in watts.")
        case .home: LocalizedText.text(
            "Zeigt die aktuelle echte Hauslast in Watt.",
            "Shows the current real home load in watts.")
        case .grid: LocalizedText.text(
            "Zeigt den aktuellen Netzbezug oder die Einspeisung in Watt.",
            "Shows current grid import or export in watts.")
        case .batteryFlow: LocalizedText.text(
            "Zeigt, ob der Akku gerade lädt oder entlädt.",
            "Shows whether the battery is charging or discharging.")
        case .today: LocalizedText.text(
            "Zeigt den heutigen Solarertrag in kWh.",
            "Shows today's solar yield in kWh.")
        case .total: LocalizedText.text(
            "Zeigt den gesamten bisher gemessenen Solarertrag in kWh.",
            "Shows the total measured solar yield in kWh.")
        case .status: LocalizedText.text(
            "Zeigt den aktuellen Status der Datenquelle.",
            "Shows the current data-source status.")
        }
    }
}

@MainActor
extension GraphMetric {
    var localizedTitle: String {
        switch self {
        case .battery: LocalizedText.text("Akku", "Battery")
        case .solar: "Solar"
        case .grid: LocalizedText.text("Netzbezug", "Grid import")
        }
    }

    var localizedShortTitle: String {
        switch self {
        case .battery: LocalizedText.text("Akku", "Battery")
        case .solar: "Solar"
        case .grid: LocalizedText.text("Netz", "Grid")
        }
    }
}
