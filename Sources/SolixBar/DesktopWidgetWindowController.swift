import AppKit

@MainActor
final class DesktopWidgetWindowController: NSWindowController {
    private let snapshotProvider: () -> SolixSnapshot?
    private let graphProvider: () -> [SolixHistorySample]

    init(snapshotProvider: @escaping () -> SolixSnapshot?, graphProvider: @escaping () -> [SolixHistorySample]) {
        self.snapshotProvider = snapshotProvider
        self.graphProvider = graphProvider
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "SOLIX Widget"
        window.minSize = NSSize(width: 380, height: 560)
        window.contentMinSize = NSSize(width: 380, height: 560)
        window.maxSize = NSSize(width: 920, height: 1160)
        window.contentResizeIncrements = NSSize(width: 1, height: 1)
        window.showsResizeIndicator = true
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.setFrameAutosaveName("SolixBarDesktopWidget")
        window.center()
        super.init(window: window)
        rebuild()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func rebuild() {
        guard let window else { return }
        let oldFrame = window.frame
        let contentSize = window.contentView?.bounds.size ?? window.contentLayoutRect.size
        let widgetView = DesktopWidgetView(snapshot: snapshotProvider(), samples: graphProvider())
        widgetView.frame = NSRect(origin: .zero, size: contentSize)
        widgetView.autoresizingMask = [.width, .height]
        window.contentView = widgetView
        window.setFrame(oldFrame, display: true)
    }
}

final class DesktopWidgetView: NSView {
    private let snapshot: SolixSnapshot?
    private let samples: [SolixHistorySample]
    private let sizeSlider = NSSlider(value: 1.0, minValue: 0.85, maxValue: 1.8, target: nil, action: nil)
    private let sizeValue = NSTextField(labelWithString: "100 %")
    private var activeResizeZone: WidgetResizeZone?
    private var resizeStartMouseLocation = NSPoint.zero
    private var resizeStartFrame = NSRect.zero

    init(snapshot: SolixSnapshot?, samples: [SolixHistorySample]) {
        self.snapshot = snapshot
        self.samples = samples
        super.init(frame: NSRect(x: 0, y: 0, width: 430, height: 680))
        wantsLayer = true
        layer?.cornerRadius = 20
        layer?.backgroundColor = widgetBackground.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.7).cgColor
        buildView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        addCursorRect(NSRect(x: bounds.maxX - 28, y: 0, width: 28, height: bounds.height), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: 0, y: 0, width: bounds.width, height: 28), cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        guard let zone = resizeZone(at: convert(event.locationInWindow, from: nil)) else {
            super.mouseDown(with: event)
            return
        }
        activeResizeZone = zone
        resizeStartMouseLocation = NSEvent.mouseLocation
        resizeStartFrame = window?.frame ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let activeResizeZone, let window else {
            super.mouseDragged(with: event)
            return
        }
        DesktopWidgetView.resize(
            window: window,
            from: resizeStartFrame,
            mouseStart: resizeStartMouseLocation,
            zone: activeResizeZone
        )
    }

    override func mouseUp(with event: NSEvent) {
        activeResizeZone = nil
        super.mouseUp(with: event)
    }

    private func buildView() {
        let title = NSTextField(labelWithString: snapshot?.siteName ?? "Anker SOLIX")
        title.font = .boldSystemFont(ofSize: 23)
        title.textColor = .labelColor
        title.toolTip = "Name deiner SOLIX-Anlage."

        let subtitle = NSTextField(labelWithString: snapshot.map { "Aktualisiert \(RelativeDateTimeFormatter().localizedString(for: $0.updatedAt, relativeTo: Date()))" } ?? "Warte auf Daten")
        subtitle.textColor = .secondaryLabelColor
        subtitle.font = .systemFont(ofSize: 12, weight: .medium)
        subtitle.toolTip = "Wann die Werte zuletzt aktualisiert wurden."

        let statusPill = statusBadge()
        let scaleControls = widgetScaleControls()
        let sizeControls = widgetSizeSlider()

        let battery = bigMetric(
            title: "Akku",
            value: snapshot?.batteryPercent.map { "\($0) %" } ?? "-",
            symbol: "battery.100percent",
            color: .systemGreen
        )
        let solar = bigMetric(
            title: "Solar",
            value: snapshot?.solarWatts.map { "\($0) W" } ?? "-",
            symbol: "sun.max.fill",
            color: solarColor
        )

        let grid = NSGridView(views: [
            [smallMetric("Haus", snapshot?.homeWatts.map { "\($0) W" }, "house.fill", .systemBlue),
             smallMetric("Netzbezug", signedWatts(snapshot?.gridWatts), "powerplug.fill", gridColor())],
            [smallMetric("Batteriefluss", signedWatts(snapshot?.batteryWatts), "bolt.fill", batteryFlowColor()),
             smallMetric("Heutiger Ertrag", snapshot?.todayKWh.map { String(format: "%.2f kWh", $0) }, "chart.bar.fill", .systemPurple)],
            [smallMetric("Gesamtertrag", snapshot?.totalKWh.map { String(format: "%.1f kWh", $0) }, "sum", .systemIndigo),
             smallMetric("Status", snapshot?.status, "checkmark.circle.fill", statusColor)]
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 10
        grid.column(at: 0).width = 160
        grid.column(at: 1).width = 160

        let graph = HistoryGraphView(
            samples: samples,
            rangeTitle: AppSettings.shared.historyRange.title,
            range: AppSettings.shared.historyRange,
            rangeDuration: AppSettings.shared.historyDuration,
            visibleMetrics: AppSettings.shared.graphMetrics,
            size: NSSize(width: 342, height: 150)
        )
        let rightResizeHandle = WidgetResizeHandleView(zone: .right)
        let bottomResizeHandle = WidgetResizeHandleView(zone: .bottom)
        let cornerResizeHandle = WidgetResizeHandleView(zone: .bottomRight)

        for view in [title, subtitle, statusPill, scaleControls, sizeControls, battery, solar, grid, graph, rightResizeHandle, bottomResizeHandle, cornerResizeHandle] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: 28),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            title.trailingAnchor.constraint(lessThanOrEqualTo: statusPill.leadingAnchor, constant: -12),

            statusPill.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            statusPill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            statusPill.heightAnchor.constraint(equalToConstant: 26),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),

            scaleControls.centerYAnchor.constraint(equalTo: subtitle.centerYAnchor),
            scaleControls.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            scaleControls.heightAnchor.constraint(equalToConstant: 26),

            sizeControls.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 12),
            sizeControls.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            sizeControls.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            sizeControls.heightAnchor.constraint(equalToConstant: 28),

            battery.topAnchor.constraint(equalTo: sizeControls.bottomAnchor, constant: 14),
            battery.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            battery.trailingAnchor.constraint(equalTo: centerXAnchor, constant: -6),
            battery.heightAnchor.constraint(equalToConstant: 92),

            solar.topAnchor.constraint(equalTo: battery.topAnchor),
            solar.leadingAnchor.constraint(equalTo: centerXAnchor, constant: 6),
            solar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            solar.heightAnchor.constraint(equalToConstant: 92),

            grid.topAnchor.constraint(equalTo: battery.bottomAnchor, constant: 12),
            grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            graph.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 16),
            graph.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            graph.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            graph.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -28),

            rightResizeHandle.topAnchor.constraint(equalTo: topAnchor, constant: 72),
            rightResizeHandle.trailingAnchor.constraint(equalTo: trailingAnchor),
            rightResizeHandle.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -34),
            rightResizeHandle.widthAnchor.constraint(equalToConstant: 30),

            bottomResizeHandle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            bottomResizeHandle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -34),
            bottomResizeHandle.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomResizeHandle.heightAnchor.constraint(equalToConstant: 30),

            cornerResizeHandle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            cornerResizeHandle.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            cornerResizeHandle.widthAnchor.constraint(equalToConstant: 28),
            cornerResizeHandle.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    private func widgetScaleControls() -> NSStackView {
        let shrink = scaleButton(title: "-", action: #selector(shrinkWidget))
        shrink.toolTip = "Widget kleiner skalieren."

        let grow = scaleButton(title: "+", action: #selector(growWidget))
        grow.toolTip = "Widget größer skalieren."

        let stack = NSStackView(views: [shrink, grow])
        stack.orientation = .horizontal
        stack.spacing = 6
        return stack
    }

    private func widgetSizeSlider() -> NSStackView {
        let label = NSTextField(labelWithString: "Widget-Größe")
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.toolTip = "Skaliert das Widget wie ein Fenster. Alternativ kannst du rechts oder unten ziehen."

        sizeSlider.target = self
        sizeSlider.action = #selector(changeWidgetSize)
        sizeSlider.toolTip = "Vergrößert oder verkleinert das Widget."
        sizeValue.alignment = .right
        sizeValue.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        sizeValue.textColor = .secondaryLabelColor
        sizeValue.widthAnchor.constraint(equalToConstant: 56).isActive = true

        if let window {
            let ratio = window.frame.width / 430
            sizeSlider.doubleValue = min(1.8, max(0.85, Double(ratio)))
            sizeValue.stringValue = "\(Int(round(sizeSlider.doubleValue * 100))) %"
        }

        let stack = NSStackView(views: [label, sizeSlider, sizeValue])
        stack.orientation = .horizontal
        stack.spacing = 10
        return stack
    }

    private func scaleButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 12, weight: .bold)
        button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        return button
    }

    @objc private func growWidget() {
        resizeWidget(deltaWidth: 90, deltaHeight: 120)
    }

    @objc private func shrinkWidget() {
        resizeWidget(deltaWidth: -90, deltaHeight: -120)
    }

    private func resizeWidget(deltaWidth: CGFloat, deltaHeight: CGFloat) {
        guard let window else { return }
        let minSize = window.minSize
        let maxSize = window.maxSize
        var frame = window.frame
        let newWidth = min(maxSize.width, max(minSize.width, frame.width + deltaWidth))
        let newHeight = min(maxSize.height, max(minSize.height, frame.height + deltaHeight))
        let heightDelta = newHeight - frame.height
        frame.size.width = newWidth
        frame.size.height = newHeight
        frame.origin.y -= heightDelta
        window.setFrame(frame, display: true, animate: true)
    }

    @objc private func changeWidgetSize() {
        guard let window else { return }
        let scale = CGFloat(sizeSlider.doubleValue)
        sizeValue.stringValue = "\(Int(round(sizeSlider.doubleValue * 100))) %"
        let targetWidth = 430 * scale
        let targetHeight = 680 * scale
        var frame = window.frame
        let newWidth = min(window.maxSize.width, max(window.minSize.width, targetWidth))
        let newHeight = min(window.maxSize.height, max(window.minSize.height, targetHeight))
        let heightDelta = newHeight - frame.height
        frame.size = NSSize(width: newWidth, height: newHeight)
        frame.origin.y -= heightDelta
        window.setFrame(frame, display: true, animate: false)
    }

    fileprivate static func resize(
        window: NSWindow,
        from startFrame: NSRect,
        mouseStart: NSPoint,
        zone: WidgetResizeZone
    ) {
        let current = NSEvent.mouseLocation
        let deltaX = current.x - mouseStart.x
        let deltaY = current.y - mouseStart.y
        let minSize = window.minSize
        let maxSize = window.maxSize

        var frame = startFrame
        if zone.includesRight {
            frame.size.width = min(maxSize.width, max(minSize.width, startFrame.width + deltaX))
        }
        if zone.includesBottom {
            frame.size.height = min(maxSize.height, max(minSize.height, startFrame.height - deltaY))
            frame.origin.y = startFrame.maxY - frame.height
        }
        window.setFrame(frame, display: true, animate: false)
    }

    private func resizeZone(at point: NSPoint) -> WidgetResizeZone? {
        let edge: CGFloat = 30
        let right = point.x >= bounds.maxX - edge
        let bottom = point.y <= bounds.minY + edge
        if right && bottom { return .bottomRight }
        if right { return .right }
        if bottom { return .bottom }
        return nil
    }

    private func bigMetric(title: String, value: String, symbol: String, color: NSColor) -> NSView {
        metricPanel(title: title, value: value, symbol: symbol, color: color, valueSize: 26)
    }

    private func smallMetric(_ title: String, _ value: String?, _ symbol: String, _ color: NSColor) -> NSView {
        metricPanel(title: title, value: value ?? "-", symbol: symbol, color: color, valueSize: 16)
    }

    private func metricPanel(title: String, value: String, symbol: String, color: NSColor, valueSize: CGFloat) -> NSView {
        let panel = AnimatedPanelView()
        panel.toolTip = tooltip(for: title, value: value)
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 12
        panel.baseColor = metricBackground(for: color, strength: 0.16)
        panel.highlightColor = metricBackground(for: color, strength: 0.25)
        panel.layer?.borderWidth = 1
        panel.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor

        let imageView = NSImageView(image: coloredSymbol(symbol, color: color) ?? NSImage())
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.textColor = .labelColor
        titleLabel.font = .systemFont(ofSize: valueSize > 20 ? 15 : 13, weight: .bold)
        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: valueSize, weight: .semibold)
        valueLabel.textColor = .labelColor
        valueLabel.lineBreakMode = .byTruncatingTail

        for view in [imageView, titleLabel, valueLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            panel.addSubview(view)
        }

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: panel.topAnchor, constant: 12),
            imageView.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
            imageView.widthAnchor.constraint(equalToConstant: 20),
            imageView.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -10),

            valueLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 8),
            valueLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12),
            valueLabel.bottomAnchor.constraint(lessThanOrEqualTo: panel.bottomAnchor, constant: -10)
        ])
        return panel
    }

    private func coloredSymbol(_ symbol: String, color: NSColor) -> NSImage? {
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else { return nil }
        let configured = image.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)) ?? image
        let copy = configured.copy() as? NSImage ?? configured
        copy.isTemplate = false
        copy.lockFocus()
        color.set()
        NSRect(origin: .zero, size: copy.size).fill(using: .sourceAtop)
        copy.unlockFocus()
        return copy
    }

    private func signedWatts(_ value: Int?) -> String? {
        guard let value else { return nil }
        return value > 0 ? "+\(value) W" : "\(value) W"
    }

    private func statusBadge() -> NSView {
        let badge = AnimatedPanelView()
        badge.toolTip = "Zeigt, ob die Datenquelle online ist."
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 13
        badge.baseColor = statusColor.withAlphaComponent(0.18)
        badge.highlightColor = statusColor.withAlphaComponent(0.28)
        badge.layer?.borderWidth = 1
        badge.layer?.borderColor = statusColor.withAlphaComponent(0.45).cgColor

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = statusColor.cgColor

        let label = NSTextField(labelWithString: snapshot?.status ?? "Bereit")
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .labelColor

        for view in [dot, label] {
            view.translatesAutoresizingMaskIntoConstraints = false
            badge.addSubview(view)
        }

        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 10),
            dot.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),

            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: badge.centerYAnchor)
        ])
        return badge
    }

    private var widgetBackground: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.10, alpha: 0.98)
                : NSColor(calibratedRed: 0.97, green: 0.98, blue: 0.98, alpha: 0.98)
        }
    }

    private var panelBackground: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.24, green: 0.25, blue: 0.26, alpha: 1)
                : NSColor(calibratedRed: 0.995, green: 0.998, blue: 1, alpha: 1)
        }
    }

    private var isDarkMode: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func tooltip(for title: String, value: String) -> String {
        switch title {
        case "Akku":
            return "Hier wird angezeigt, wie voll der Speicher aktuell geladen ist: \(value)."
        case "Solar":
            return "Hier wird angezeigt, wie viel Leistung die Solarmodule gerade erzeugen: \(value)."
        case "Haus":
            return "Hier wird angezeigt, wie viel Leistung dein Haus gerade verbraucht: \(value)."
        case "Netzbezug":
            return "Hier wird angezeigt, wie viel Leistung aus dem Netz bezogen wird. Negative Werte bedeuten Einspeisung: \(value)."
        case "Batteriefluss":
            return "Hier wird angezeigt, ob und mit welcher Leistung der Akku lädt oder entlädt: \(value)."
        case "Heutiger Ertrag":
            return "Hier wird angezeigt, wie viel Solarenergie heute bereits erzeugt wurde: \(value)."
        case "Gesamtertrag":
            return "Hier wird angezeigt, wie viel Solarenergie insgesamt bisher erfasst wurde: \(value)."
        case "Status":
            return "Hier wird angezeigt, ob die Datenquelle aktuell erreichbar ist: \(value)."
        default:
            return "\(title): \(value)."
        }
    }

    private var statusColor: NSColor {
        snapshot?.status?.localizedCaseInsensitiveContains("offline") == true ? .systemRed : .systemGreen
    }

    private var solarColor: NSColor {
        NSColor(calibratedRed: 0.93, green: 0.66, blue: 0.08, alpha: 1)
    }

    private func gridColor() -> NSColor {
        guard let watts = snapshot?.gridWatts else { return .systemGray }
        if watts > 0 { return .systemRed }
        if watts < 0 { return .systemGreen }
        return .systemGray
    }

    private func batteryFlowColor() -> NSColor {
        guard let watts = snapshot?.batteryWatts else { return .systemGray }
        if watts > 0 { return .systemGreen }
        if watts < 0 { return .systemRed }
        return .systemGray
    }

    private func metricBackground(for color: NSColor, strength: CGFloat) -> NSColor {
        let adjustedStrength = isDarkMode ? strength * 0.8 : strength
        return color.withAlphaComponent(adjustedStrength)
            .blended(withFraction: isDarkMode ? 0.72 : 0.80, of: panelBackground) ?? panelBackground
    }
}

fileprivate enum WidgetResizeZone {
    case right
    case bottom
    case bottomRight

    var includesRight: Bool {
        self == .right || self == .bottomRight
    }

    var includesBottom: Bool {
        self == .bottom || self == .bottomRight
    }
}

fileprivate final class WidgetResizeHandleView: NSView {
    private let zone: WidgetResizeZone
    private var startMouseLocation = NSPoint.zero
    private var startFrame = NSRect.zero

    init(zone: WidgetResizeZone) {
        self.zone = zone
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        toolTip = WidgetResizeHandleView.tooltip(for: zone)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: zone.includesRight && !zone.includesBottom ? .resizeLeftRight : .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        startMouseLocation = NSEvent.mouseLocation
        startFrame = window?.frame ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        DesktopWidgetView.resize(
            window: window,
            from: startFrame,
            mouseStart: startMouseLocation,
            zone: zone
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let color = NSColor.secondaryLabelColor.withAlphaComponent(0.72)
        color.setStroke()
        switch zone {
        case .right:
            drawRightGrip(color: color)
        case .bottom:
            drawBottomGrip(color: color)
        case .bottomRight:
            drawCornerGrip(color: color)
        }
    }

    private func drawRightGrip(color: NSColor) {
        color.setStroke()
        for offset in stride(from: CGFloat(7), through: bounds.height - 7, by: 8) {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: bounds.midX - 2, y: offset))
            path.line(to: NSPoint(x: bounds.midX + 2, y: offset))
            path.lineWidth = 1.4
            path.stroke()
        }
    }

    private func drawBottomGrip(color: NSColor) {
        color.setStroke()
        let center = bounds.midX
        for offset in stride(from: CGFloat(-18), through: CGFloat(18), by: 8) {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: center + offset, y: bounds.midY - 2))
            path.line(to: NSPoint(x: center + offset, y: bounds.midY + 2))
            path.lineWidth = 1.4
            path.stroke()
        }
    }

    private func drawCornerGrip(color: NSColor) {
        color.setStroke()
        for offset in stride(from: CGFloat(7), through: CGFloat(19), by: 5) {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: bounds.maxX - offset, y: bounds.minY + 4))
            path.line(to: NSPoint(x: bounds.maxX - 4, y: bounds.minY + offset))
            path.lineWidth = 1.2
            path.stroke()
        }
    }

    private static func tooltip(for zone: WidgetResizeZone) -> String {
        switch zone {
        case .right:
            "Hier ziehen, um das Widget breiter zu machen."
        case .bottom:
            "Hier ziehen, um das Widget höher zu machen."
        case .bottomRight:
            "Hier ziehen, um das Widget größer zu machen."
        }
    }
}
