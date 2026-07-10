import AppKit

@MainActor
final class DetachedMenuBarWindowController: NSWindowController, NSWindowDelegate {
    private static let desktopAccessoryLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
    private let settings = AppSettings.shared
    private let attributedBarProvider: () -> NSAttributedString?
    private let onClose: () -> Void
    private var didNotifyClose = false
    private var wantsVisible = false

    init(
        attributedBarProvider: @escaping () -> NSAttributedString?,
        onClose: @escaping () -> Void
    ) {
        self.attributedBarProvider = attributedBarProvider
        self.onClose = onClose
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 44),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "SOLIX Leiste"
        window.level = Self.desktopAccessoryLevel
        window.isMovableByWindowBackground = !settings.lockDetachedMenuBar
        window.collectionBehavior = [.canJoinAllSpaces]
        window.hasShadow = true
        window.backgroundColor = .clear
        window.isOpaque = false
        super.init(window: window)
        window.delegate = self
        observeSpaceChanges()
        rebuild()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func showBelowMenuBar(anchor: NSRect?) {
        wantsVisible = true
        rebuild()
        if let window, !window.isVisible {
            if !restoreSavedPosition() {
                positionBelowMenuBar(anchor: anchor)
            }
        }
        updateVisibilityForCurrentSpace()
    }

    func rebuild() {
        guard let window else { return }
        window.isMovableByWindowBackground = !settings.lockDetachedMenuBar
        let attributedText = attributedBarProvider()
        let oldFrame = window.frame
        let targetSize = targetSize(for: attributedText, screen: window.screen)
        let view = DetachedMenuBarView(attributedText: attributedText, onClose: { [weak self] in
            self?.closeFromButton()
        })
        view.frame = NSRect(origin: .zero, size: targetSize)
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        var frame = oldFrame
        frame.size = targetSize
        if let screen = window.screen {
            frame.origin.x = min(screen.visibleFrame.maxX - targetSize.width - 8, max(screen.visibleFrame.minX + 8, frame.origin.x))
            frame.origin.y = min(screen.visibleFrame.maxY - targetSize.height - 6, max(screen.visibleFrame.minY + 8, frame.origin.y))
        }
        window.setFrame(frame, display: true)
    }

    func windowWillClose(_ notification: Notification) {
        saveCurrentPosition()
        notifyCloseIfNeeded()
    }

    func windowDidMove(_ notification: Notification) {
        saveCurrentPosition()
    }

    func windowDidResize(_ notification: Notification) {
        saveCurrentPosition()
    }

    func closeFromOwner() {
        closeFromButton()
    }

    private func closeFromButton() {
        wantsVisible = false
        notifyCloseIfNeeded()
        close()
    }

    private func notifyCloseIfNeeded() {
        guard !didNotifyClose else { return }
        didNotifyClose = true
        onClose()
    }

    private func saveCurrentPosition() {
        guard let window else { return }
        settings.detachedMenuBarFrame = NSStringFromRect(window.frame)
    }

    private func restoreSavedPosition() -> Bool {
        guard let window, !settings.detachedMenuBarFrame.isEmpty else { return false }
        let saved = NSRectFromString(settings.detachedMenuBarFrame)
        guard saved.width > 0, saved.height > 0 else { return false }
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(saved) }) ?? NSScreen.main else { return false }
        var frame = saved
        frame.size = targetSize(for: attributedBarProvider(), screen: screen)
        frame.origin.x = min(screen.visibleFrame.maxX - frame.width - 8, max(screen.visibleFrame.minX + 8, frame.origin.x))
        frame.origin.y = min(screen.visibleFrame.maxY - frame.height - 6, max(screen.visibleFrame.minY + 8, frame.origin.y))
        window.setFrame(frame, display: true)
        return true
    }

    private func targetSize(for attributedText: NSAttributedString?, screen: NSScreen?) -> NSSize {
        let textWidth = ceil(attributedText?.size().width ?? 152)
        let scale = AppSettings.shared.detachedMenuBarScale
        let iconWidth: CGFloat = AppSettings.shared.showMenuBarIcon ? round(34 * scale) : 0
        let closeWidth: CGFloat = round(44 * scale)
        let horizontalPadding: CGFloat = round(34 * scale)
        let width = textWidth + iconWidth + closeWidth + horizontalPadding
        let visibleWidth = screen?.visibleFrame.width ?? 900
        let height = min(68, max(44, round(44 * scale)))
        return NSSize(width: min(max(width, 260), visibleWidth - 24), height: height)
    }

    private func positionBelowMenuBar(anchor: NSRect?) {
        guard let window else { return }
        let screen = anchor.flatMap { rect in NSScreen.screens.first { $0.frame.intersects(rect) } } ?? NSScreen.main
        guard let screen else { return }

        var frame = window.frame
        let visible = screen.visibleFrame
        if let anchor {
            frame.origin.x = anchor.midX - frame.width / 2
        } else {
            frame.origin.x = visible.maxX - frame.width - 24
        }
        frame.origin.x = min(visible.maxX - frame.width - 8, max(visible.minX + 8, frame.origin.x))
        frame.origin.y = visible.maxY - frame.height - 6
        window.setFrame(frame, display: true)
    }

    private func observeSpaceChanges() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(workspaceVisibilityChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(workspaceVisibilityChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func workspaceVisibilityChanged() {
        updateVisibilityForCurrentSpace()
    }

    private func updateVisibilityForCurrentSpace() {
        guard wantsVisible, let window else { return }

        if activeSpaceLooksFullscreen() {
            if window.isVisible {
                AppLogger.info("Detached slim bar hidden on fullscreen space.")
                window.orderOut(nil)
            }
            return
        }

        if !window.isVisible {
            AppLogger.info("Detached slim bar restored on normal desktop.")
            window.orderFront(nil)
        }
    }

    private func activeSpaceLooksFullscreen() -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return false }
        guard frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return false }
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        let screenSizes = NSScreen.screens.map(\.frame.size)
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == frontmost.processIdentifier,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? CGFloat,
                  let height = bounds["Height"] as? CGFloat else {
                continue
            }

            if screenSizes.contains(where: { abs($0.width - width) < 3 && abs($0.height - height) < 3 }) {
                return true
            }
        }
        return false
    }
}

private final class DetachedMenuBarView: NSView {
    private let attributedText: NSAttributedString?
    private let onClose: () -> Void
    private let settings = AppSettings.shared

    init(attributedText: NSAttributedString?, onClose: @escaping () -> Void) {
        self.attributedText = attributedText
        self.onClose = onClose
        super.init(frame: NSRect(x: 0, y: 0, width: 640, height: 44))
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
        buildView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildView() {
        let glass = NSVisualEffectView()
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 16
        glass.layer?.masksToBounds = true
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)

        let fill = NSView()
        fill.wantsLayer = true
        fill.layer?.cornerRadius = 16
        fill.layer?.masksToBounds = true
        fill.layer?.backgroundColor = readableBackground.cgColor
        fill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fill)

        let accent = AccentGradientView(colors: accentColors)
        accent.translatesAutoresizingMaskIntoConstraints = false
        addSubview(accent)

        let border = NSView()
        border.wantsLayer = true
        border.layer?.cornerRadius = 16
        border.layer?.borderWidth = 1
        border.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.62).cgColor
        border.layer?.backgroundColor = NSColor.clear.cgColor
        border.translatesAutoresizingMaskIntoConstraints = false
        addSubview(border)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = round(10 * settings.detachedMenuBarScale)

        if settings.showMenuBarIcon, let image = appIcon() {
            let imageView = NSImageView(image: image)
            let iconSize = round(24 * settings.detachedMenuBarScale)
            imageView.widthAnchor.constraint(equalToConstant: iconSize).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: iconSize).isActive = true
            stack.addArrangedSubview(imageView)
        }

        if let attributedText, attributedText.length > 0 {
            let label = NSTextField(labelWithString: "")
            label.attributedStringValue = readableDetachedText(attributedText)
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            stack.addArrangedSubview(label)
        } else {
            let label = NSTextField(labelWithString: "SOLIX wartet auf Daten")
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            label.textColor = .white
            stack.addArrangedSubview(label)
        }

        let closeButton = NSButton(title: "×", target: self, action: #selector(close))
        closeButton.isBordered = false
        closeButton.font = .systemFont(ofSize: round(18 * settings.detachedMenuBarScale), weight: .bold)
        closeButton.contentTintColor = .white
        closeButton.toolTip = "Abgedockte Leiste schließen."
        let closeSize = round(28 * settings.detachedMenuBarScale)
        closeButton.widthAnchor.constraint(equalToConstant: closeSize).isActive = true
        closeButton.heightAnchor.constraint(equalToConstant: closeSize).isActive = true

        for view in [stack, closeButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),

            fill.leadingAnchor.constraint(equalTo: leadingAnchor),
            fill.trailingAnchor.constraint(equalTo: trailingAnchor),
            fill.topAnchor.constraint(equalTo: topAnchor),
            fill.bottomAnchor.constraint(equalTo: bottomAnchor),

            accent.leadingAnchor.constraint(equalTo: leadingAnchor),
            accent.trailingAnchor.constraint(equalTo: trailingAnchor),
            accent.topAnchor.constraint(equalTo: topAnchor),
            accent.bottomAnchor.constraint(equalTo: bottomAnchor),

            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.topAnchor.constraint(equalTo: topAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: round(14 * settings.detachedMenuBarScale)),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -10),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -round(8 * settings.detachedMenuBarScale)),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    private func appIcon() -> NSImage? {
        let image = Bundle.main.url(forResource: "SolixBar", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
        let size = round(24 * settings.detachedMenuBarScale)
        return image.map { roundedIconImage($0, size: size) }
    }

    private func readableDetachedText(_ attributedText: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: attributedText)
        let brightText = NSColor.white
        let mutedText = NSColor(calibratedWhite: 0.86, alpha: 1)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.92)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        let fullRange = NSRange(location: 0, length: result.length)
        result.addAttributes(
            [
                .shadow: shadow,
                .strokeColor: NSColor.black.withAlphaComponent(0.70),
                .strokeWidth: -1.5
            ],
            range: fullRange
        )
        result.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: result.length)) { value, range, _ in
            let substring = (result.string as NSString).substring(with: range)
            guard let color = value as? NSColor else {
                result.addAttribute(.foregroundColor, value: brightText, range: range)
                return
            }
            if color == NSColor.labelColor || color == NSColor.secondaryLabelColor || color.isNearlyWhite {
                result.addAttribute(.foregroundColor, value: substring.trimmingCharacters(in: .whitespaces) == "•" ? mutedText : brightText, range: range)
            } else {
                result.addAttribute(.foregroundColor, value: brightDetachedColor(for: color, text: substring), range: range)
            }
        }
        makeAttachmentsReadable(in: result)
        return result
    }

    private func brightDetachedColor(for color: NSColor, text: String) -> NSColor {
        let normalized = text.lowercased()
        if normalized.contains("einspeis") || normalized.contains("export") {
            return NSColor(calibratedRed: 0.84, green: 0.69, blue: 1.00, alpha: 1)
        }
        if normalized.contains("bezug") || normalized.contains("import") || normalized.contains("last") || normalized.contains("home") {
            return NSColor(calibratedRed: 0.46, green: 0.86, blue: 1.00, alpha: 1)
        }
        if normalized.contains("entladen") || normalized.contains("discharging") {
            return NSColor(calibratedRed: 1.00, green: 0.58, blue: 0.36, alpha: 1)
        }
        if normalized.contains("laden") || normalized.contains("charging") {
            return NSColor(calibratedRed: 0.49, green: 1.00, blue: 0.60, alpha: 1)
        }
        if normalized.contains("erzeugt") || normalized.contains("producing") || normalized.contains("pv") || normalized.contains("solar") {
            return NSColor(calibratedRed: 1.00, green: 0.85, blue: 0.30, alpha: 1)
        }
        if normalized.contains("akku"), let percent = percentage(in: normalized) {
            if percent <= 20 {
                return NSColor(calibratedRed: 1.00, green: 0.42, blue: 0.46, alpha: 1)
            }
            if percent <= 60 {
                return NSColor(calibratedRed: 1.00, green: 0.85, blue: 0.30, alpha: 1)
            }
            return NSColor(calibratedRed: 0.49, green: 1.00, blue: 0.60, alpha: 1)
        }

        guard let rgb = color.usingColorSpace(.deviceRGB) else { return NSColor.white }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        if saturation < 0.16 { return NSColor.white }
        switch hue {
        case 0..<0.05, 0.95...1:
            return NSColor(calibratedRed: 1.00, green: 0.42, blue: 0.46, alpha: 1)
        case 0.05..<0.12:
            return NSColor(calibratedRed: 1.00, green: 0.58, blue: 0.36, alpha: 1)
        case 0.12..<0.20:
            return NSColor(calibratedRed: 1.00, green: 0.85, blue: 0.30, alpha: 1)
        case 0.20..<0.48:
            return NSColor(calibratedRed: 0.49, green: 1.00, blue: 0.60, alpha: 1)
        case 0.48..<0.72:
            return NSColor(calibratedRed: 0.46, green: 0.86, blue: 1.00, alpha: 1)
        default:
            return NSColor(calibratedRed: 0.84, green: 0.69, blue: 1.00, alpha: 1)
        }
    }

    private func percentage(in text: String) -> Int? {
        let digits = text.split { !$0.isNumber }
        return digits.compactMap { Int($0) }.first
    }

    private func makeAttachmentsReadable(in text: NSMutableAttributedString) {
        var replacements: [(NSRange, NSTextAttachment)] = []
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let attachment = value as? NSTextAttachment, let image = attachment.image else { return }
            let readableImage = image.copy() as? NSImage ?? image
            readableImage.isTemplate = false
            let beforeStart = max(0, range.location - 32)
            let beforeRange = NSRange(location: beforeStart, length: range.location - beforeStart)
            let afterEnd = min(text.length, NSMaxRange(range) + 32)
            let afterRange = NSRange(location: NSMaxRange(range), length: afterEnd - NSMaxRange(range))
            let before = (text.string as NSString).substring(with: beforeRange)
            let after = (text.string as NSString).substring(with: afterRange)
            let tint = brightAttachmentColor(
                description: image.accessibilityDescription ?? "",
                before: before,
                after: after
            )
            readableImage.lockFocus()
            tint.set()
            NSRect(origin: .zero, size: readableImage.size).fill(using: .sourceAtop)
            readableImage.unlockFocus()
            let replacement = NSTextAttachment()
            replacement.image = readableImage
            replacement.bounds = attachment.bounds
            replacements.append((range, replacement))
        }
        for (range, attachment) in replacements {
            text.addAttribute(.attachment, value: attachment, range: range)
        }
    }

    private func brightAttachmentColor(description: String, before: String, after: String) -> NSColor {
        let description = description.lowercased()
        let before = before.lowercased()
        let after = after.lowercased()
        let context = before + " " + after
        if after.contains("akku") || after.contains("battery") || after.contains("batt") {
            if let percent = percentage(in: after) {
                if percent <= 20 {
                    return NSColor(calibratedRed: 1.00, green: 0.42, blue: 0.46, alpha: 1)
                }
                if percent <= 60 {
                    return NSColor(calibratedRed: 1.00, green: 0.85, blue: 0.30, alpha: 1)
                }
            }
            return NSColor(calibratedRed: 0.49, green: 1.00, blue: 0.60, alpha: 1)
        }
        if after.contains("pv") || after.contains("solar") {
            return NSColor(calibratedRed: 1.00, green: 0.85, blue: 0.30, alpha: 1)
        }
        if after.contains("last") || after.contains("home") || after.contains("haus") {
            return NSColor(calibratedRed: 0.46, green: 0.86, blue: 1.00, alpha: 1)
        }
        if after.contains("netz") || after.contains("grid") {
            return before.contains("einspeis") || before.contains("export")
                ? NSColor(calibratedRed: 0.84, green: 0.69, blue: 1.00, alpha: 1)
                : NSColor(calibratedRed: 0.46, green: 0.86, blue: 1.00, alpha: 1)
        }
        if after.contains("fluss") || after.contains("flow") {
            return before.contains("entladen") || before.contains("discharging")
                ? NSColor(calibratedRed: 1.00, green: 0.58, blue: 0.36, alpha: 1)
                : NSColor(calibratedRed: 0.49, green: 1.00, blue: 0.60, alpha: 1)
        }
        if after.contains("ertrag") || after.contains("yield") || after.contains("gesamt") || after.contains("total") {
            return NSColor(calibratedRed: 0.84, green: 0.69, blue: 1.00, alpha: 1)
        }
        if description.contains("battery") || description.contains("batterie") || description.contains("akku") {
            if description.contains("flow") || description.contains("fluss") {
                return context.contains("entladen") || context.contains("discharging")
                    ? NSColor(calibratedRed: 1.00, green: 0.58, blue: 0.36, alpha: 1)
                    : NSColor(calibratedRed: 0.49, green: 1.00, blue: 0.60, alpha: 1)
            }
            if let percent = percentage(in: context) {
                if percent <= 20 {
                    return NSColor(calibratedRed: 1.00, green: 0.42, blue: 0.46, alpha: 1)
                }
                if percent <= 60 {
                    return NSColor(calibratedRed: 1.00, green: 0.85, blue: 0.30, alpha: 1)
                }
            }
            return NSColor(calibratedRed: 0.49, green: 1.00, blue: 0.60, alpha: 1)
        }
        if description.contains("pv") || description.contains("solar") {
            return NSColor(calibratedRed: 1.00, green: 0.85, blue: 0.30, alpha: 1)
        }
        if description.contains("home") || description.contains("haus") || description.contains("last") {
            return NSColor(calibratedRed: 0.46, green: 0.86, blue: 1.00, alpha: 1)
        }
        if description.contains("grid") || description.contains("netz") {
            return context.contains("einspeis") || context.contains("export")
                ? NSColor(calibratedRed: 0.84, green: 0.69, blue: 1.00, alpha: 1)
                : NSColor(calibratedRed: 0.46, green: 0.86, blue: 1.00, alpha: 1)
        }
        if description.contains("flow") || description.contains("fluss") {
            return context.contains("entladen") || context.contains("discharging")
                ? NSColor(calibratedRed: 1.00, green: 0.58, blue: 0.36, alpha: 1)
                : NSColor(calibratedRed: 0.49, green: 1.00, blue: 0.60, alpha: 1)
        }
        if description.contains("yield") || description.contains("ertrag") {
            return NSColor(calibratedRed: 0.84, green: 0.69, blue: 1.00, alpha: 1)
        }
        return NSColor.white
    }

    @objc private func close() {
        onClose()
    }

    private var readableBackground: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.11, alpha: 0.90)
                : NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.13, alpha: 0.82)
        }
    }

    private var accentColors: [NSColor] {
        let metrics = settings.barMetrics.isEmpty ? [BarMetric.battery, .solar, .grid] : settings.barMetrics
        let colors = metrics.map(accentColor)
        return Array(colors.prefix(5))
    }

    private func accentColor(for metric: BarMetric) -> NSColor {
        switch metric {
        case .battery:
            return NSColor(calibratedRed: 0.17, green: 0.78, blue: 0.36, alpha: 1)
        case .solar, .today:
            return NSColor(calibratedRed: 1.00, green: 0.68, blue: 0.03, alpha: 1)
        case .home:
            return NSColor(calibratedRed: 0.16, green: 0.50, blue: 0.96, alpha: 1)
        case .grid:
            return NSColor(calibratedRed: 0.95, green: 0.18, blue: 0.22, alpha: 1)
        case .batteryFlow, .flow:
            return NSColor(calibratedRed: 0.00, green: 0.70, blue: 0.46, alpha: 1)
        case .total:
            return NSColor(calibratedRed: 0.48, green: 0.35, blue: 0.95, alpha: 1)
        case .status:
            return NSColor(calibratedRed: 0.12, green: 0.72, blue: 0.38, alpha: 1)
        }
    }
}

private final class AccentGradientView: NSView {
    private let colors: [NSColor]

    init(colors: [NSColor]) {
        self.colors = colors
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func makeBackingLayer() -> CALayer {
        let layer = CAGradientLayer()
        layer.startPoint = CGPoint(x: 0, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 0.5)
        layer.cornerRadius = 16
        layer.masksToBounds = true
        layer.colors = gradientColors
        layer.locations = gradientLocations
        return layer
    }

    private var gradientColors: [CGColor] {
        let base = colors.isEmpty
            ? [
                NSColor(calibratedRed: 0.17, green: 0.78, blue: 0.36, alpha: 1),
                NSColor(calibratedRed: 1.00, green: 0.68, blue: 0.03, alpha: 1)
            ]
            : colors
        return base.map { $0.withAlphaComponent(0.18).cgColor }
    }

    private var gradientLocations: [NSNumber] {
        guard gradientColors.count > 1 else { return [0, 1] }
        return (0..<gradientColors.count).map { NSNumber(value: Double($0) / Double(gradientColors.count - 1)) }
    }
}

private extension NSColor {
    var isNearlyWhite: Bool {
        guard let rgb = usingColorSpace(.deviceRGB) else { return false }
        return rgb.redComponent > 0.82 && rgb.greenComponent > 0.82 && rgb.blueComponent > 0.82
    }
}
