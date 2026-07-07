import AppKit

final class HistoryGraphView: NSView {
    private let samples: [SolixHistorySample]
    private let rangeTitle: String
    private var animationProgress: CGFloat = 0
    private var animationTimer: Timer?
    private let animationStart = Date()
    var onClick: (() -> Void)?

    private let batteryColor = NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.46, alpha: 1)
    private let solarColor = NSColor(calibratedRed: 0.96, green: 0.67, blue: 0.16, alpha: 1)
    private let gridColor = NSColor(calibratedRed: 0.25, green: 0.58, blue: 0.95, alpha: 1)

    init(samples: [SolixHistorySample], rangeTitle: String, size: NSSize = NSSize(width: 320, height: 170)) {
        self.samples = samples.sorted { $0.date < $1.date }
        self.rangeTitle = rangeTitle
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = graphBackground.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        toolTip = "Zeigt Akku, Solar und Netzbezug im gewählten Zeitraum. Klick öffnet die große Ansicht."
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
        drawHeader()
        drawLegend()

        guard samples.count >= 2 else {
            drawEmptyState()
            return
        }

        let plot = NSRect(x: 44, y: 40, width: bounds.width - 92, height: bounds.height - 82)
        let maxPower = maxPowerValue()
        drawGrid(in: plot, maxPower: maxPower)
        drawAxes(in: plot)
        drawTimeLabels(in: plot)
        drawLine(values: animatedPoints(batteryPoints(in: plot)), color: batteryColor, width: 2.8)
        drawLine(values: animatedPoints(solarPoints(in: plot, maxPower: maxPower)), color: solarColor, width: 2.8)
        drawLine(values: animatedPoints(gridPoints(in: plot, maxPower: maxPower)), color: gridColor, width: 2.8)
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
        graphBackground.setFill()
        bounds.fill()
    }

    private func drawHeader() {
        drawText(
            "Verlauf \(rangeTitle)",
            at: NSPoint(x: 16, y: bounds.maxY - 25),
            font: .boldSystemFont(ofSize: 13),
            color: .labelColor
        )
    }

    private func drawEmptyState() {
        drawText(
            "Noch nicht genug Messpunkte",
            at: NSPoint(x: 18, y: bounds.midY - 6),
            font: .systemFont(ofSize: 13, weight: .medium),
            color: .secondaryLabelColor
        )
    }

    private func drawGrid(in rect: NSRect, maxPower: Int) {
        let gridPath = NSBezierPath()
        for index in 0...4 {
            let y = rect.minY + (rect.height / 4) * CGFloat(index)
            gridPath.move(to: NSPoint(x: rect.minX, y: y))
            gridPath.line(to: NSPoint(x: rect.maxX, y: y))

            let percent = index * 25
            drawText(
                "\(percent)%",
                at: NSPoint(x: 12, y: y - 7),
                font: .monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                color: .secondaryLabelColor
            )

            let watts = Int(round(Double(maxPower) * Double(index) / 4.0))
            drawText(
                "\(watts)W",
                at: NSPoint(x: rect.maxX + 7, y: y - 7),
                font: .monospacedDigitSystemFont(ofSize: 10, weight: .medium),
                color: .secondaryLabelColor
            )
        }
        gridLineColor.setStroke()
        gridPath.lineWidth = 0.8
        gridPath.stroke()
    }

    private func drawAxes(in rect: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.move(to: NSPoint(x: rect.maxX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.move(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        axisColor.setStroke()
        path.lineWidth = 1.1
        path.stroke()
    }

    private func drawTimeLabels(in rect: NSRect) {
        guard let first = samples.first?.date, let last = samples.last?.date else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = last.timeIntervalSince(first) <= 30 * 60 * 60 ? "HH:mm" : "dd.MM"

        drawText(formatter.string(from: first), at: NSPoint(x: rect.minX, y: 17), font: .systemFont(ofSize: 10, weight: .medium), color: .secondaryLabelColor)
        let lastText = formatter.string(from: last)
        let width = (lastText as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 10, weight: .medium)]).width
        drawText(lastText, at: NSPoint(x: rect.maxX - width, y: 17), font: .systemFont(ofSize: 10, weight: .medium), color: .secondaryLabelColor)
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
        guard let first = samples.first?.date.timeIntervalSince1970,
              let last = samples.last?.date.timeIntervalSince1970,
              last > first else {
            return []
        }

        return samples.compactMap { sample in
            guard let normalized = value(sample) else { return nil }
            let timestamp = sample.date.timeIntervalSince1970
            let x = rect.minX + rect.width * CGFloat((timestamp - first) / (last - first))
            let y = rect.minY + rect.height * CGFloat(normalized)
            return NSPoint(x: x, y: y)
        }
    }

    private func drawLine(values points: [NSPoint], color: NSColor, width: CGFloat) {
        guard points.count >= 2 else { return }
        let path = NSBezierPath()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.line(to: point)
        }
        color.setStroke()
        path.lineWidth = width
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.stroke()

        if let point = points.last {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7)).fill()
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
        let y = bounds.maxY - 25
        drawLegendItem(title: "Akku", color: batteryColor, x: max(120, bounds.width - 225), y: y)
        drawLegendItem(title: "Solar", color: solarColor, x: max(178, bounds.width - 162), y: y)
        drawLegendItem(title: "Netz", color: gridColor, x: max(238, bounds.width - 96), y: y)
    }

    private func drawLegendItem(title: String, color: NSColor, x: CGFloat, y: CGFloat) {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: y + 2, width: 8, height: 8)).fill()
        drawText(title, at: NSPoint(x: x + 12, y: y - 1), font: .systemFont(ofSize: 11, weight: .semibold), color: .secondaryLabelColor)
    }

    private func maxPowerValue() -> Int {
        let values = samples.flatMap { sample -> [Int] in
            [sample.solarWatts ?? 0, max(0, sample.gridWatts ?? 0)]
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

    private var gridLineColor: NSColor {
        NSColor.separatorColor.withAlphaComponent(0.45)
    }

    private var axisColor: NSColor {
        NSColor.separatorColor.withAlphaComponent(0.8)
    }
}
