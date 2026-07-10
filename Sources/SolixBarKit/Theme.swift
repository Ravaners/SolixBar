import AppKit

/// Semantische Farbrolle eines dargestellten Werts. Jede Stelle, die Energiewerte
/// einfaerbt, waehlt eine Rolle statt einer konkreten Farbe.
enum ColorRole: String {
    case solar
    case load
    case gridImport
    case gridExport
    case batteryLow
    case batteryMedium
    case batteryHigh
    case batteryCharging
    case batteryDischarging
    case yieldToday
    case yieldTotal
    case status
    case refresh
    case neutral
}

extension NSAttributedString.Key {
    /// Markiert einen Textlauf mit seiner Farbrolle (rawValue von ColorRole),
    /// damit abgeleitete Darstellungen (z. B. die abgedockte Leiste) die Farbe
    /// semantisch neu aufloesen koennen statt Text zu parsen.
    static let solixRole = NSAttributedString.Key("solixColorRole")
}

/// Zentrale Design-Token: Farben, Radien, Abstaende.
/// Menueleiste/Dashboard nutzen `color(_:)` (hell/dunkel adaptiv),
/// die dunkle abgedockte Leiste `bright(_:)`, Legenden/Akzente `accent(_:)`.
@MainActor
enum Theme {
    // MARK: Radien
    static let radiusPanel: CGFloat = 16
    static let radiusCard: CGFloat = 12
    static let radiusChip: CGFloat = 8

    // MARK: Adaptive Wertfarben (hell, dunkel)
    static func color(_ role: ColorRole) -> NSColor {
        switch role {
        case .solar:
            adaptive(light: (0.48, 0.22, 0.00), dark: (1.00, 0.82, 0.30))
        case .load:
            adaptive(light: (0.10, 0.34, 0.78), dark: (0.40, 0.78, 1.00))
        case .gridImport:
            adaptive(light: (0.72, 0.10, 0.12), dark: (1.00, 0.48, 0.44))
        case .gridExport:
            adaptive(light: (0.34, 0.10, 0.58), dark: (0.82, 0.65, 1.00))
        case .batteryLow:
            adaptive(light: (0.69, 0.00, 0.13), dark: (1.00, 0.42, 0.46))
        case .batteryMedium:
            adaptive(light: (0.54, 0.35, 0.00), dark: (1.00, 0.85, 0.30))
        case .batteryHigh:
            adaptive(light: (0.00, 0.36, 0.12), dark: (0.42, 1.00, 0.58))
        case .batteryCharging:
            adaptive(light: (0.00, 0.36, 0.12), dark: (0.42, 1.00, 0.58))
        case .batteryDischarging:
            adaptive(light: (0.55, 0.12, 0.00), dark: (1.00, 0.55, 0.32))
        case .yieldToday:
            adaptive(light: (0.45, 0.18, 0.62), dark: (0.85, 0.62, 1.00))
        case .yieldTotal:
            adaptive(light: (0.26, 0.26, 0.66), dark: (0.72, 0.70, 1.00))
        case .status:
            adaptive(light: (0.00, 0.42, 0.18), dark: (0.42, 1.00, 0.58))
        case .refresh:
            adaptive(light: (0.10, 0.34, 0.78), dark: (0.40, 0.78, 1.00))
        case .neutral:
            .labelColor
        }
    }

    // MARK: Helle Varianten fuer die dunkle abgedockte Leiste
    static func bright(_ role: ColorRole) -> NSColor {
        switch role {
        case .solar:
            rgb(1.00, 0.85, 0.30)
        case .load:
            rgb(0.46, 0.86, 1.00)
        case .gridImport:
            rgb(1.00, 0.52, 0.48)
        case .gridExport:
            rgb(0.84, 0.69, 1.00)
        case .batteryLow:
            rgb(1.00, 0.42, 0.46)
        case .batteryMedium:
            rgb(1.00, 0.85, 0.30)
        case .batteryHigh, .batteryCharging, .status:
            rgb(0.49, 1.00, 0.60)
        case .batteryDischarging:
            rgb(1.00, 0.58, 0.36)
        case .yieldToday:
            rgb(0.84, 0.69, 1.00)
        case .yieldTotal:
            rgb(0.76, 0.74, 1.00)
        case .refresh:
            rgb(0.46, 0.86, 1.00)
        case .neutral:
            .white
        }
    }

    // MARK: Gesaettigte Akzente fuer Legenden, Plates und Gradienten
    static func accent(_ role: ColorRole) -> NSColor {
        switch role {
        case .solar:
            rgb(1.00, 0.68, 0.03)
        case .load:
            rgb(0.16, 0.50, 0.96)
        case .gridImport:
            rgb(0.90, 0.20, 0.22)
        case .gridExport:
            rgb(0.48, 0.35, 0.95)
        case .batteryLow:
            rgb(0.90, 0.20, 0.22)
        case .batteryMedium:
            rgb(0.95, 0.72, 0.10)
        case .batteryHigh, .batteryCharging, .status:
            rgb(0.17, 0.78, 0.36)
        case .batteryDischarging:
            rgb(0.96, 0.52, 0.16)
        case .yieldToday:
            rgb(0.69, 0.32, 0.87)
        case .yieldTotal:
            rgb(0.35, 0.34, 0.84)
        case .refresh:
            rgb(0.16, 0.50, 0.96)
        case .neutral:
            .systemGray
        }
    }

    static func battery(percent: Int?) -> ColorRole {
        guard let percent else { return .neutral }
        if percent <= 20 { return .batteryLow }
        if percent <= 60 { return .batteryMedium }
        return .batteryHigh
    }

    static func grid(watts: Int?) -> ColorRole {
        guard let watts, watts != 0 else { return .neutral }
        return watts > 0 ? .gridImport : .gridExport
    }

    static func batteryFlow(watts: Int?) -> ColorRole {
        guard let watts, watts != 0 else { return .neutral }
        return watts > 0 ? .batteryCharging : .batteryDischarging
    }

    // MARK: Hilfen
    private static func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> NSColor {
        NSColor(name: nil) { appearance in
            let c = usesDarkBackground(appearance) ? dark : light
            return NSColor(calibratedRed: c.0, green: c.1, blue: c.2, alpha: 1)
        }
    }

    /// Erkennt dunkle Hintergruende auch im Menueleisten-Kontext, wo die
    /// Appearance nicht dem Systemthema folgt (dunkles Wallpaper -> helle Schrift).
    static func usesDarkBackground(_ appearance: NSAppearance) -> Bool {
        var label: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            label = NSColor.labelColor.usingColorSpace(.deviceRGB)
        }
        if let label {
            let luminance = 0.2126 * label.redComponent
                + 0.7152 * label.greenComponent
                + 0.0722 * label.blueComponent
            return luminance > 0.55
        }
        let match = appearance.bestMatch(from: [.vibrantDark, .darkAqua, .vibrantLight, .aqua])
        return match == .vibrantDark || match == .darkAqua
    }

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
        NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
    }
}
