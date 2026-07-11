import AppKit

/// Stufenweise Verdichtung der Menüleisten-Anzeige, damit das Statusitem auf
/// MacBooks mit Notch nie in die Notch-Zone ragt (macOS blendet solche Items
/// komplett aus — das Item wäre unsichtbar).
enum MenuBarDisplayLevel: Int, CaseIterable, Sendable {
    /// Alle vom Nutzer gewählten Optionen.
    case full = 0
    /// Ohne Text-Bezeichnungen ("Akku", "PV", ...).
    case noLabels = 1
    /// Zusätzlich ohne Symbole und Flusspfeile — nur Werte.
    case valuesOnly = 2
    /// Nur die ersten zwei Metriken als Werte.
    case compact = 3
    /// Nur Icon bzw. "SOLIX".
    case minimal = 4

    var next: MenuBarDisplayLevel? {
        MenuBarDisplayLevel(rawValue: rawValue + 1)
    }
}

/// Anzeigeoptionen der Menüleiste, abgeleitet aus den Settings und pro
/// Verdichtungsstufe reduziert. Reine Wertstruktur -> unit-testbar.
struct MenuBarDisplayOptions: Sendable {
    var metrics: [BarMetric]
    var showLabels: Bool
    var showSymbols: Bool
    var showArrows: Bool
    /// Rollenfarben auf Werten/Symbolen — unabhängig von der Flussrichtung;
    /// Farben kosten keine Breite und bleiben daher auf allen Stufen erhalten.
    var showColors: Bool = true
    /// PV-Wert als Einzelwerte je Eingang ("438·204W") statt Summe — greift
    /// nur, wenn der Snapshot Kanalwerte enthält (Solarbank 2/3).
    var perPVWatts: Bool = false

    func applying(_ level: MenuBarDisplayLevel) -> MenuBarDisplayOptions {
        var result = self
        switch level {
        case .full:
            break
        case .noLabels:
            result.showLabels = false
        case .valuesOnly:
            result.showLabels = false
            result.showSymbols = false
            result.showArrows = false
        case .compact:
            result.showLabels = false
            result.showSymbols = false
            result.showArrows = false
            result.metrics = Array(metrics.prefix(2))
        case .minimal:
            result.showLabels = false
            result.showSymbols = false
            result.showArrows = false
            result.metrics = []
        }
        return result
    }
}

enum NotchGeometry {
    /// Die Notch-Zone eines Bildschirms in Bildschirmkoordinaten (nil ohne Notch).
    @MainActor
    static func notchRect(on screen: NSScreen?) -> NSRect? {
        guard let screen,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else {
            return nil
        }
        let height = screen.safeAreaInsets.top
        guard height > 0, right.minX > left.maxX else { return nil }
        return NSRect(
            x: left.maxX,
            y: screen.frame.maxY - height,
            width: right.minX - left.maxX,
            height: height
        )
    }

    /// Ragt das Item horizontal in die Notch-Zone?
    static func overlaps(itemMinX: CGFloat, itemMaxX: CGFloat, notchMinX: CGFloat, notchMaxX: CGFloat) -> Bool {
        itemMaxX > notchMinX && itemMinX < notchMaxX
    }
}
