import AppKit

/// Formatierungs-Engine der Menüleisten-Anzeige: baut aus einem Snapshot und
/// Anzeigeoptionen die einzeilige (attributed) bzw. zweizeilige (gestapelte)
/// Darstellung. Aus dem StatusController herausgelöst, damit u. a. die
/// Live-Vorschau in den Einstellungen dieselbe Engine nutzen kann.
@MainActor
final class MenuBarFormatter {
    // MARK: Öffentliche API

    /// Einzeilige Darstellung mit Symbolen/Pfeilen/Rollen-Tags.
    func attributedTitle(
        for snapshot: SolixSnapshot,
        scale: Double,
        options: MenuBarDisplayOptions,
        showWarning: Bool = false
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: barAttributedText(for: snapshot, scale: scale, options: options))
        if showWarning {
            result.append(textAttachment(" ⚠", color: Theme.color(.batteryMedium), scale: scale))
        }
        return result
    }

    /// Reine Text-Darstellung (ohne Symbole/Pfeile); nil, wenn keine Metriken
    /// sichtbar sind.
    func plainTitle(for snapshot: SolixSnapshot, options: MenuBarDisplayOptions) -> String? {
        let parts = visibleBarMetrics(for: snapshot, options: options).map { metric in
            barText(for: metric, snapshot: snapshot, options: options)
        }
        return parts.isEmpty ? nil : parts.joined(separator: separator())
    }

    /// Einträge für die zweizeilige Kompaktanzeige.
    func stackedEntries(for snapshot: SolixSnapshot, options: MenuBarDisplayOptions) -> [StackedMenuBarRenderer.Entry] {
        visibleBarMetrics(for: snapshot, options: options)
            .filter { $0 != .flow && $0 != .status }
            .compactMap { metric -> StackedMenuBarRenderer.Entry? in
                guard let text = stackedText(for: metric, snapshot: snapshot) else { return nil }
                return StackedMenuBarRenderer.Entry(
                    symbolName: symbol(for: metric, snapshot: snapshot),
                    text: text,
                    role: roleTag(for: metric, snapshot: snapshot)
                )
            }
    }

    func symbol(for metric: BarMetric, snapshot: SolixSnapshot) -> String {
        switch metric {
        case .battery:
            batterySymbol(snapshot.batteryPercent)
        case .batteryFlow:
            batteryFlowSymbol(snapshot.batteryWatts)
        default:
            metric.symbolName
        }
    }

    func color(for metric: BarMetric, snapshot: SolixSnapshot) -> NSColor {
        Theme.color(roleTag(for: metric, snapshot: snapshot))
    }

    func roleTag(for metric: BarMetric, snapshot: SolixSnapshot) -> ColorRole {
        switch metric {
        case .battery:
            Theme.battery(percent: snapshot.batteryPercent)
        case .solar:
            .solar
        case .home:
            .load
        case .grid:
            Theme.grid(watts: snapshot.gridWatts)
        case .batteryFlow:
            Theme.batteryFlow(watts: snapshot.batteryWatts)
        case .flow:
            .batteryCharging
        case .today:
            .yieldToday
        case .total:
            .yieldTotal
        case .status:
            .status
        }
    }

    func coloredSymbol(_ symbol: String, color: NSColor, accessibilityDescription: String) -> NSImage? {
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibilityDescription) else {
            return nil
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let configured = image.withSymbolConfiguration(configuration) ?? image
        return configured.tinted(color)
    }

    var textShadow: NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(name: nil) { appearance in
            Theme.usesDarkBackground(appearance)
                ? NSColor.black.withAlphaComponent(0.85)
                : NSColor.white.withAlphaComponent(0.90)
        }
        shadow.shadowBlurRadius = 1.5
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        return shadow
    }

    // MARK: Aufbau der einzeiligen Darstellung

    private func barAttributedText(for snapshot: SolixSnapshot, scale: Double, options: MenuBarDisplayOptions) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let metrics = visibleBarMetrics(for: snapshot, options: options)
        for (index, metric) in metrics.enumerated() {
            let role = roleTag(for: metric, snapshot: snapshot)
            if index > 0 {
                result.append(textAttachment(separator(scale: scale), scale: scale))
            }
            if metric == .flow {
                appendFlowField(to: result, snapshot: snapshot, scale: scale, options: options)
                continue
            }
            if options.showArrows,
               let flow = energyFlowText(for: metric, snapshot: snapshot) {
                result.append(textAttachment(flow.text, color: Theme.color(flow.role), weight: .bold, scale: scale, role: flow.role))
                result.append(textAttachment(" ", scale: scale))
            }
            if options.showSymbols,
                let image = coloredSymbol(
                    symbol(for: metric, snapshot: snapshot),
                    color: (metric == .battery || options.showArrows)
                        ? color(for: metric, snapshot: snapshot)
                        : .labelColor,
                    accessibilityDescription: metric.localizedTitle
                ) {
                result.append(imageAttachment(image, scale: scale, role: role))
                result.append(textAttachment(" ", scale: scale))
            }
            result.append(textAttachment(
                barText(for: metric, snapshot: snapshot, options: options),
                color: valueColor(for: metric, snapshot: snapshot, options: options),
                scale: scale,
                role: role
            ))
        }
        return result
    }

    private func visibleBarMetrics(for snapshot: SolixSnapshot, options: MenuBarDisplayOptions) -> [BarMetric] {
        let metrics = options.metrics.isEmpty ? [BarMetric.battery, .solar, .grid] : options.metrics
        return metrics.filter { metric in
            metric != .total || snapshot.totalKWh != nil
        }
    }

    private func appendFlowField(to result: NSMutableAttributedString, snapshot: SolixSnapshot, scale: Double, options: MenuBarDisplayOptions) {
        if options.showLabels {
            result.append(textAttachment("\(BarMetric.flow.localizedShortTitle) ", color: .secondaryLabelColor, scale: scale))
        }

        guard options.showArrows else {
            result.append(textAttachment(LocalizedText.text("aus", "off"), color: .secondaryLabelColor, scale: scale))
            return
        }

        let flows: [BarMetric] = [.solar, .batteryFlow, .grid]
        var didAppend = false
        for metric in flows {
            guard let flow = energyFlowText(for: metric, snapshot: snapshot) else {
                continue
            }
            if didAppend {
                result.append(textAttachment(" ", scale: scale))
            }
            result.append(textAttachment(flow.text, color: Theme.color(flow.role), weight: .bold, scale: scale, role: flow.role))
            didAppend = true
        }

        if !didAppend {
            result.append(textAttachment("-", color: .secondaryLabelColor, scale: scale))
        }
    }

    private func energyFlowText(for metric: BarMetric, snapshot: SolixSnapshot) -> (text: String, role: ColorRole)? {
        switch metric {
        case .solar:
            guard let watts = snapshot.solarWatts else { return nil }
            return watts > 0
                ? (LocalizedText.text("↓ Erzeugt", "↓ Producing"), .solar)
                : ("•", .neutral)
        case .grid:
            guard let watts = snapshot.gridWatts else { return nil }
            if watts > 0 {
                return (LocalizedText.text("← Bezug", "← Import"), .gridImport)
            }
            if watts < 0 {
                return (LocalizedText.text("→ Einspeisen", "→ Export"), .gridExport)
            }
            return ("•", .neutral)
        case .batteryFlow:
            guard let watts = snapshot.batteryWatts else { return nil }
            if watts > 0 {
                return (LocalizedText.text("↓ Laden", "↓ Charging"), .batteryCharging)
            }
            if watts < 0 {
                return (LocalizedText.text("↑ Entladen", "↑ Discharging"), .batteryDischarging)
            }
            return ("•", .neutral)
        default:
            return nil
        }
    }

    // MARK: Texte und Werte

    private func barText(for metric: BarMetric, snapshot: SolixSnapshot, options: MenuBarDisplayOptions) -> String {
        switch metric {
        case .battery:
            formatBarMetric(metric, value: snapshot.batteryPercent.map { "\($0)%" } ?? "--%", options: options)
        case .solar:
            formatBarMetric(metric, value: snapshot.solarWatts.map { "\($0)W" } ?? "--W", options: options)
        case .home:
            formatBarMetric(metric, value: snapshot.homeWatts.map { "\($0)W" } ?? "--W", options: options)
        case .grid:
            formatBarMetric(metric, value: formatFlowWatts(snapshot.gridWatts, options: options) ?? "--W", options: options)
        case .batteryFlow:
            formatBarMetric(metric, value: formatFlowWatts(snapshot.batteryWatts, options: options) ?? "--W", options: options)
        case .flow:
            options.showLabels ? "\(metric.localizedShortTitle)" : "Flow"
        case .today:
            formatBarMetric(metric, value: snapshot.todayKWh.map { String(format: "%.2fkWh", $0) } ?? "--kWh", options: options)
        case .total:
            formatBarMetric(metric, value: snapshot.totalKWh.map { String(format: "%.1fkWh", $0) } ?? "--kWh", options: options)
        case .status:
            formatBarMetric(metric, value: snapshot.status ?? "-", options: options)
        }
    }

    private func formatBarMetric(_ metric: BarMetric, value: String, options: MenuBarDisplayOptions) -> String {
        options.showLabels ? "\(metric.localizedShortTitle) \(value)" : value
    }

    /// Kompaktwert für die zweizeilige Anzeige: nur Zahl + Einheit, die
    /// Metrik-Identität trägt das Glyph.
    private func stackedText(for metric: BarMetric, snapshot: SolixSnapshot) -> String? {
        switch metric {
        case .battery:
            return snapshot.batteryPercent.map { "\($0)%" } ?? "--%"
        case .solar:
            return snapshot.solarWatts.map { "\($0)W" } ?? "--W"
        case .home:
            return snapshot.homeWatts.map { "\($0)W" } ?? "--W"
        case .grid:
            return snapshot.gridWatts.map { "\($0)W" } ?? "--W"
        case .batteryFlow:
            return snapshot.batteryWatts.map { "\($0 > 0 ? "+" : "")\($0)W" } ?? "--W"
        case .today:
            return snapshot.todayKWh.map { String(format: "%.1fk", $0) }
        case .total:
            return snapshot.totalKWh.map { String(format: "%.0fk", $0) }
        case .flow, .status:
            return nil
        }
    }

    private func formatSignedWatts(_ value: Int?) -> String? {
        guard let value else { return nil }
        return value > 0 ? "+\(value) W" : "\(value) W"
    }

    private func formatFlowWatts(_ value: Int?, options: MenuBarDisplayOptions) -> String? {
        guard let value else { return nil }
        return options.showArrows ? "\(abs(value)) W" : formatSignedWatts(value)
    }

    // MARK: Symbole und Farben

    private func batterySymbol(_ percent: Int?) -> String {
        guard let percent else { return "battery.75percent" }
        if percent <= 20 { return "battery.25percent" }
        if percent <= 60 { return "battery.50percent" }
        return "battery.100percent"
    }

    private func batteryFlowSymbol(_ watts: Int?) -> String {
        guard let watts else { return "bolt.fill" }
        return watts >= 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill"
    }

    private func valueColor(for metric: BarMetric, snapshot: SolixSnapshot, options: MenuBarDisplayOptions) -> NSColor {
        if metric == .battery {
            guard snapshot.batteryPercent != nil else { return .secondaryLabelColor }
            return Theme.color(Theme.battery(percent: snapshot.batteryPercent))
        }
        guard options.showArrows else { return .labelColor }
        switch metric {
        case .solar:
            return snapshot.solarWatts == nil ? .secondaryLabelColor : Theme.color(.solar)
        case .home:
            return snapshot.homeWatts == nil ? .secondaryLabelColor : Theme.color(.load)
        case .grid:
            guard let watts = snapshot.gridWatts, watts != 0 else { return .secondaryLabelColor }
            return Theme.color(Theme.grid(watts: watts))
        case .batteryFlow:
            guard let watts = snapshot.batteryWatts, watts != 0 else { return .secondaryLabelColor }
            return Theme.color(Theme.batteryFlow(watts: watts))
        default:
            return .labelColor
        }
    }

    // MARK: Bausteine

    private func separator(scale: Double? = nil) -> String {
        (scale ?? AppSettings.shared.menuBarScale) < 0.95 ? " " : "  "
    }

    private func imageAttachment(_ image: NSImage, scale: Double, role: ColorRole? = nil) -> NSAttributedString {
        let attachment = NSTextAttachment()
        let height = round(13 * scale)
        // Seitenverhältnis erhalten: breite Symbole (Batterie) nicht ins
        // Quadrat stauchen.
        let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
        let width = round(height * aspect)
        image.size = NSSize(width: width, height: height)
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: -2, width: width, height: height)
        let result = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
        if let role {
            result.addAttribute(.solixRole, value: role.rawValue, range: NSRange(location: 0, length: result.length))
        }
        return result
    }

    private func textAttachment(_ string: String, color: NSColor = .labelColor, weight: NSFont.Weight = .medium, scale: Double, role: ColorRole? = nil) -> NSAttributedString {
        // Einheitliche Schriftgröße für alle Läufe.
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: round(13 * scale), weight: weight),
            .foregroundColor: color,
            .shadow: textShadow
        ]
        if let role {
            attributes[.solixRole] = role.rawValue
        }
        return NSAttributedString(string: string, attributes: attributes)
    }
}
