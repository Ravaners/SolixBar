import AppKit

final class HistoryGraphView: NSView {
    private let samples: [SolixHistorySample]
    private let rangeTitle: String
    private let range: HistoryRange
    private let rangeDuration: TimeInterval
    private let visibleMetrics: [GraphMetric]
    private let showsHeader: Bool
    private let fitsData: Bool
    private var animationProgress: CGFloat = 0
    private var animationTimer: Timer?
    private let animationStart = Date()
    var onClick: (() -> Void)?

    @MainActor private var batteryColor: NSColor { Theme.accent(.batteryHigh) }
    @MainActor private var solarColor: NSColor { Theme.accent(.solar) }
    @MainActor private var gridColor: NSColor { Theme.accent(.gridImport) }

    init(
        samples: [SolixHistorySample],
        rangeTitle: String,
        range: HistoryRange = AppSettings.shared.historyRange,
        rangeDuration: TimeInterval = AppSettings.shared.historyDuration,
        visibleMetrics: [GraphMetric] = AppSettings.shared.graphMetrics,
        showsHeader: Bool = true,
        fitsData: Bool = AppSettings.shared.graphFitsData,
        size: NSSize = NSSize(width: 320, height: 170)
    ) {
        self.samples = samples.sorted { $0.date < $1.date }
        self.rangeTitle = rangeTitle
        self.range = range
        self.rangeDuration = rangeDuration
        self.showsHeader = showsHeader
        self.fitsData = fitsData
        self.visibleMetrics = visibleMetrics.isEmpty ? GraphMetric.allCases : visibleMetrics
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        toolTip = LocalizedText.text(
            "Zeigt die aktivierten Werte im gewählten Zeitraum. Klick öffnet die große Ansicht.",
            "Shows the enabled values for the selected period. Click to open the large view."
        )
        startLineAnimation()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawBackground()
        let isCompact = bounds.height < 220

        // Ohne Innen-Header (Dashboard: Chips übernehmen Titel + Legende)
        // braucht der Plot oben nur minimalen Abstand.
        let topInset: CGFloat = showsHeader ? (isCompact ? 58 : 78) : 18
        let bottomInset: CGFloat = isCompact ? 42 : 48
        let leftInset: CGFloat = isCompact ? 64 : 70
        let rightInset: CGFloat = isCompact ? 70 : 82
        let plot = NSRect(
            x: leftInset,
            y: bottomInset,
            width: max(80, bounds.width - leftInset - rightInset),
            height: max(48, bounds.height - topInset - bottomInset)
        )
        let maxPower = maxPowerValue()
        drawPlotSurface(in: plot)
        drawGrid(in: plot, maxPower: maxPower)
        drawTimeLabels(in: plot)
        // Header/Legende nach der Plotfläche zeichnen, damit sie bei knapper
        // Höhe niemals unter der Fläche verschwinden.
        drawHeader()
        if !isCompact && showsHeader {
            drawLegend()
        }

        guard samples.count >= 2 else {
            drawEmptyState()
            return
        }

        // Nur Solar bekommt eine Flächenfüllung — mehrere überlagerte
        // Füllungen mischten sich zu einem undefinierbaren Oliv.
        if visibleMetrics.contains(.battery) {
            drawLine(values: animatedPoints(batteryPoints(in: plot)), color: batteryColor, width: 3.1, baseline: plot.minY, filled: false)
        }
        if visibleMetrics.contains(.solar) {
            drawLine(values: animatedPoints(solarPoints(in: plot, maxPower: maxPower)), color: solarColor, width: 3.1, baseline: plot.minY, filled: true)
        }
        if visibleMetrics.contains(.grid) {
            drawLine(values: animatedPoints(gridPoints(in: plot, maxPower: maxPower)), color: gridColor, width: 3.1, baseline: plot.minY, filled: false)
        }
        // Grundlinie zuletzt: Kurven auf 0 (z. B. Netz nachts) sollen die
        // Achse nicht verdecken.
        drawAxes(in: plot)
    }

    private func startLineAnimation() {
        animationTimer = Timer.scheduledTimer(
            timeInterval: 1.0 / 30.0,
            target: self,
            selector: #selector(tickLineAnimation(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func tickLineAnimation(_ timer: Timer) {
        let elapsed = Date().timeIntervalSince(animationStart)
        let progress = min(1, elapsed / 0.9)
        animationProgress = easeOutCubic(CGFloat(progress))
        needsDisplay = true
        if progress >= 1 {
            timer.invalidate()
            animationTimer = nil
        }
    }

    private func drawBackground() {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        if let gradient = NSGradient(colors: [graphBackgroundTop, graphBackground]) {
            gradient.draw(in: path, angle: -90)
        } else {
            graphBackground.setFill()
            path.fill()
        }
    }

    /// Dezente Toenung der Plotflaeche ohne eigenen Rahmen — die fruehere
    /// eckige Box kollidierte optisch mit den runden Ecken der Aussenkarte.
    private func drawPlotSurface(in rect: NSRect) {
        let plot = NSBezierPath(roundedRect: rect.insetBy(dx: -6, dy: -6), xRadius: 8, yRadius: 8)
        plotSurfaceColor.withAlphaComponent(0.4).setFill()
        plot.fill()
    }

    private func drawHeader() {
        guard showsHeader else { return }
        drawText(
            "\(LocalizedText.text("Verlauf", "History")) \(localizedRangeTitle(rangeTitle))",
            at: NSPoint(x: 16, y: bounds.maxY - 25),
            font: .boldSystemFont(ofSize: bounds.height < 180 ? 12 : 13),
            color: .labelColor
        )
    }

    private func drawEmptyState() {
        drawText(
            LocalizedText.text("Noch nicht genug Messpunkte", "Not enough measurements yet"),
            at: NSPoint(x: 18, y: bounds.midY - 6),
            font: .systemFont(ofSize: 13, weight: .medium),
            color: .secondaryLabelColor
        )
    }

    private func localizedRangeTitle(_ title: String) -> String {
        guard AppSettings.shared.appLanguage == .english else { return title }
        switch title {
        case "Aktuell":
            return "Current"
        case "24 Stunden":
            return "24 Hours"
        case "7 Tage":
            return "7 Days"
        case "30 Tage":
            return "30 Days"
        case "Individuell":
            return "Custom"
        default:
            return title
        }
    }

    private func drawGrid(in rect: NSRect, maxPower: Int) {
        let gridPath = NSBezierPath()
        for index in 0...4 {
            let y = rect.minY + (rect.height / 4) * CGFloat(index)
            gridPath.move(to: NSPoint(x: rect.minX, y: y))
            gridPath.line(to: NSPoint(x: rect.maxX, y: y))

            // %-Achse gehört zur Akku-Linie: gleiche Farbe stellt die Zuordnung
            // der beiden Y-Achsen klar (links %, rechts Watt).
            let percent = index * 25
            drawText(
                "\(percent)%",
                at: NSPoint(x: rect.minX - 50, y: y - 7),
                font: .monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                color: visibleMetrics.contains(.battery)
                    ? batteryColor.withAlphaComponent(0.85)
                    : .secondaryLabelColor
            )

            let watts = Int(round(Double(maxPower) * Double(index) / 4.0))
            drawText(
                "\(watts)W",
                at: NSPoint(x: rect.maxX + 10, y: y - 7),
                font: .monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                color: .secondaryLabelColor
            )
        }
        gridLineColor.setStroke()
        gridPath.lineWidth = 0.8
        gridPath.stroke()
    }

    /// Nur die Grundlinie als Achse — der komplette Kasten wirkte wie ein
    /// zweiter Rahmen im Rahmen.
    private func drawAxes(in rect: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        axisColor.setStroke()
        path.lineWidth = 1.1
        path.stroke()
    }

    private func drawTimeLabels(in rect: NSRect) {
        let domain = timeDomain()
        for tick in timeTicks(for: domain) {
            let progress = domain.end.timeIntervalSince(domain.start) > 0
                ? tick.date.timeIntervalSince(domain.start) / domain.end.timeIntervalSince(domain.start)
                : 0
            let date = domain.start.addingTimeInterval(domain.end.timeIntervalSince(domain.start) * progress)
            let text = tick.label ?? timeLabel(for: date, isLast: tick.isLast)
            let font = NSFont.systemFont(ofSize: 10, weight: .medium)
            let width = (text as NSString).size(withAttributes: [.font: font]).width
            let x = rect.minX + rect.width * CGFloat(progress)
            let clampedX = min(rect.maxX - width, max(rect.minX, x - width / 2))
            drawText(text, at: NSPoint(x: clampedX, y: max(13, rect.minY - 28)), font: font, color: .secondaryLabelColor)

            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: x, y: rect.minY))
            tick.line(to: NSPoint(x: x, y: rect.minY - 4))
            axisColor.setStroke()
            tick.lineWidth = 1
            tick.stroke()
        }
    }

    private func batteryPoints(in rect: NSRect) -> [NSPoint] {
        normalizedPoints(in: rect) { sample in
            guard let percent = sample.batteryPercent else { return nil }
            return min(1, max(0, Double(percent) / 100))
        }
    }

    private func solarPoints(in rect: NSRect, maxPower: Int) -> [NSPoint] {
        normalizedPoints(in: rect) { sample in
            guard let watts = sample.solarWatts else { return nil }
            return min(1, max(0, Double(watts) / Double(maxPower)))
        }
    }

    private func gridPoints(in rect: NSRect, maxPower: Int) -> [NSPoint] {
        normalizedPoints(in: rect) { sample in
            guard let watts = sample.gridWatts else { return nil }
            return min(1, max(0, Double(max(0, watts)) / Double(maxPower)))
        }
    }

    private func normalizedPoints(in rect: NSRect, value: (SolixHistorySample) -> Double?) -> [NSPoint] {
        let domain = timeDomain()
        let first = domain.start.timeIntervalSince1970
        let last = domain.end.timeIntervalSince1970
        guard last > first else { return [] }

        return samples.compactMap { sample in
            guard let normalized = value(sample) else { return nil }
            let timestamp = sample.date.timeIntervalSince1970
            guard timestamp >= first, timestamp <= last else { return nil }
            let x = rect.minX + rect.width * CGFloat((timestamp - first) / (last - first))
            let y = rect.minY + rect.height * CGFloat(normalized)
            return NSPoint(x: x, y: y)
        }
    }

    private func timeDomain() -> (start: Date, end: Date) {
        let now = Date()
        let end = max(samples.last?.date ?? now, now)
        let duration = max(60 * 60, rangeDuration)
        var start = end.addingTimeInterval(-duration)
        // Fit-to-Data: leere Zeiträume nicht anzeigen, wenn die Daten erst
        // deutlich später beginnen (mindestens 1 h Spannweite behalten).
        if fitsData, let first = samples.first?.date, first > start {
            let padded = first.addingTimeInterval(-duration * 0.03)
            start = min(max(padded, start), end.addingTimeInterval(-60 * 60))
        }
        return (start, end)
    }

    /// Ticks an runden Uhrzeit-/Tagesgrenzen statt an krummen Bruchteilen der
    /// Domäne (früher: 00:33, 06:33 ...). Der letzte Tick ist immer "Jetzt".
    private func timeTicks(for domain: (start: Date, end: Date)) -> [(date: Date, label: String?, isLast: Bool)] {
        let duration = domain.end.timeIntervalSince(domain.start)
        let step: TimeInterval
        if fitsData && duration < rangeDuration * 0.75 {
            // Gefittete (kürzere) Domäne: Schrittweite aus der echten Dauer.
            switch duration {
            case ..<(4 * 3600): step = 30 * 60
            case ..<(26 * 3600): step = bounds.width < 430 ? 6 * 3600 : 4 * 3600
            case ..<(8 * 24 * 3600): step = 24 * 3600
            default: step = max(1, ((duration / (24 * 3600)) / 6).rounded()) * 24 * 3600
            }
        } else {
            switch range {
            case .current:
                step = 30 * 60
            case .day:
                step = bounds.width < 430 ? 6 * 3600 : 4 * 3600
            case .week:
                step = 24 * 3600
            case .month:
                step = bounds.width < 430 ? 7 * 24 * 3600 : 5 * 24 * 3600
            case .custom:
                let days = max(1, (duration / (24 * 3600)).rounded())
                step = max(1, (days / 6).rounded()) * 24 * 3600
            }
        }

        var ticks: [(date: Date, label: String?, isLast: Bool)] = []
        let calendar = Calendar.current
        var boundary: Date
        if step < 24 * 3600 {
            let anchor = calendar.dateInterval(of: .hour, for: domain.start)?.end ?? domain.start
            boundary = anchor
            // auf ein Vielfaches der Schrittweite ab Mitternacht ausrichten
            while boundary.timeIntervalSince(calendar.startOfDay(for: boundary))
                .truncatingRemainder(dividingBy: step) != 0 {
                boundary.addTimeInterval(3600)
            }
        } else {
            boundary = calendar.startOfDay(for: domain.start.addingTimeInterval(24 * 3600))
        }
        // Puffer von 60% der Schrittweite vor "Jetzt", damit sich das letzte
        // Zeitlabel nie mit dem Jetzt-Label überlagert.
        while boundary < domain.end.addingTimeInterval(-step * 0.6) {
            ticks.append((date: boundary, label: nil, isLast: false))
            boundary.addTimeInterval(step)
        }
        ticks.append((date: domain.end, label: LocalizedText.text("Jetzt", "Now"), isLast: true))
        return ticks
    }

    private func timeLabel(for date: Date, isLast: Bool) -> String {
        if isLast { return LocalizedText.text("Jetzt", "Now") }
        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: AppSettings.shared.appLanguage == .english ? "en_US" : "de_DE"
        )
        let effectiveDuration = timeDomain().end.timeIntervalSince(timeDomain().start)
        if fitsData && effectiveDuration < 26 * 3600 {
            formatter.dateFormat = "HH:mm"
        } else {
            switch range {
            case .current, .day:
                formatter.dateFormat = "HH:mm"
            case .week:
                formatter.dateFormat = "dd.MM"
            case .month:
                formatter.dateFormat = "dd.MM"
            case .custom:
                formatter.dateFormat = rangeDuration <= 35 * 24 * 60 * 60 ? "dd.MM" : "MM/yy"
            }
        }
        return formatter.string(from: date)
    }

    private func drawLine(values points: [NSPoint], color: NSColor, width: CGFloat, baseline: CGFloat, filled: Bool) {
        guard points.count >= 2 else { return }
        if filled {
            let fillPath = NSBezierPath()
            fillPath.move(to: NSPoint(x: points[0].x, y: baseline))
            for point in points {
                fillPath.line(to: point)
            }
            if let last = points.last {
                fillPath.line(to: NSPoint(x: last.x, y: baseline))
            }
            fillPath.close()
            color.withAlphaComponent(0.12).setFill()
            fillPath.fill()
        }

        let path = NSBezierPath()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.line(to: point)
        }
        let shadow = NSShadow()
        shadow.shadowColor = color.withAlphaComponent(0.24)
        shadow.shadowBlurRadius = 5
        shadow.shadowOffset = NSSize(width: 0, height: -1)

        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        color.setStroke()
        path.lineWidth = width
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()

        if let point = points.last {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7)).fill()
            graphBackground.setFill()
            NSBezierPath(ovalIn: NSRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3)).fill()
        }
    }

    private func animatedPoints(_ points: [NSPoint]) -> [NSPoint] {
        guard points.count >= 2, animationProgress < 1 else { return points }
        let target = CGFloat(points.count - 1) * animationProgress
        let fullIndex = max(0, min(points.count - 1, Int(target.rounded(.down))))
        var visible = Array(points.prefix(fullIndex + 1))
        guard fullIndex < points.count - 1 else { return visible }
        let fraction = target - CGFloat(fullIndex)
        let start = points[fullIndex]
        let end = points[fullIndex + 1]
        visible.append(NSPoint(
            x: start.x + (end.x - start.x) * fraction,
            y: start.y + (end.y - start.y) * fraction
        ))
        return visible
    }

    private func drawLegend() {
        let y = bounds.maxY - (bounds.height < 180 ? 46 : 52)
        var x: CGFloat = 18
        let maxWidth = bounds.width - 36
        let compact = maxWidth < 310
        if visibleMetrics.contains(.battery) {
            drawLegendItem(title: LocalizedText.text("Akku", "Battery"), color: batteryColor, x: x, y: y, width: compact ? 50 : 58)
            x += compact ? 56 : 66
        }
        if visibleMetrics.contains(.solar) {
            drawLegendItem(title: "Solar", color: solarColor, x: x, y: y, width: compact ? 54 : 64)
            x += compact ? 60 : 72
        }
        if visibleMetrics.contains(.grid) {
            drawLegendItem(title: LocalizedText.text("Netz", "Grid"), color: gridColor, x: x, y: y, width: compact ? 50 : 58)
        }
    }

    private func drawLegendItem(title: String, color: NSColor, x: CGFloat, y: CGFloat, width: CGFloat) {
        let badgeRect = NSRect(x: x - 7, y: y - 5, width: width, height: 20)
        (color.withAlphaComponent(0.18).blended(withFraction: 0.20, of: graphBackground) ?? color.withAlphaComponent(0.18)).setFill()
        NSBezierPath(roundedRect: badgeRect, xRadius: 7, yRadius: 7).fill()

        color.withAlphaComponent(0.45).setStroke()
        let border = NSBezierPath(roundedRect: badgeRect, xRadius: 7, yRadius: 7)
        border.lineWidth = 1
        border.stroke()

        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: y + 1, width: 8, height: 8)).fill()
        drawText(title, at: NSPoint(x: x + 12, y: y - 2), font: .systemFont(ofSize: 11, weight: .bold), color: color)
    }

    private func maxPowerValue() -> Int {
        let values = samples.flatMap { sample -> [Int] in
            [
                visibleMetrics.contains(.solar) ? (sample.solarWatts ?? 0) : 0,
                visibleMetrics.contains(.grid) ? max(0, sample.gridWatts ?? 0) : 0
            ]
        }
        let rawMax = max(2000, values.max() ?? 2000)
        return Int(ceil(Double(rawMax) / 500.0) * 500)
    }

    private func easeOutCubic(_ value: CGFloat) -> CGFloat {
        1 - pow(1 - value, 3)
    }

    private func drawText(_ text: String, at point: NSPoint, font: NSFont, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        text.draw(at: point, withAttributes: attributes)
    }

    private var graphBackground: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.105, green: 0.115, blue: 0.125, alpha: 1)
                : NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 1)
        }
    }

    private var graphBackgroundTop: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.16, alpha: 1)
                : NSColor(calibratedRed: 0.96, green: 0.985, blue: 0.98, alpha: 1)
        }
    }

    private var plotSurfaceColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.09, alpha: 0.72)
                : NSColor(calibratedRed: 0.985, green: 0.995, blue: 1.0, alpha: 0.92)
        }
    }

    /// Etwas kräftiger als der Systemtrenner, damit die Rasterlinien in beiden
    /// Modi als Ablesehilfe taugen, ohne die Kurven zu stören.
    private var gridLineColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 1.0, alpha: 0.18)
                : NSColor(calibratedWhite: 0.0, alpha: 0.16)
        }
    }

    private var axisColor: NSColor {
        NSColor.separatorColor.withAlphaComponent(0.8)
    }
}
