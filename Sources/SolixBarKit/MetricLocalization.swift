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
        case .flow: LocalizedText.text("Energiefluss", "Energy Flow")
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
        case .flow: "Flow"
        case .today: LocalizedText.text("Ertrag", "Yield")
        case .total: LocalizedText.text("Gesamt", "Total")
        case .status: "Status"
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
