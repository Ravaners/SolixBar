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
        let closeWidth: CGFloat = AppSettings.shared.lockDetachedMenuBar ? 0 : round(44 * scale)
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

        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

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
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        if settings.lockDetachedMenuBar {
            stack.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -round(14 * settings.detachedMenuBarScale)
            ).isActive = true
        } else {
            let closeButton = NSButton(title: "×", target: self, action: #selector(close))
            closeButton.isBordered = false
            closeButton.font = .systemFont(ofSize: round(18 * settings.detachedMenuBarScale), weight: .bold)
            closeButton.contentTintColor = .white
            closeButton.toolTip = LocalizedText.text(
                "Abgedockte Leiste schließen.",
                "Close detached slim bar."
            )
            closeButton.translatesAutoresizingMaskIntoConstraints = false
            addSubview(closeButton)

            let closeSize = round(28 * settings.detachedMenuBarScale)
            NSLayoutConstraint.activate([
                closeButton.widthAnchor.constraint(equalToConstant: closeSize),
                closeButton.heightAnchor.constraint(equalToConstant: closeSize),
                stack.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -10),
                closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -round(8 * settings.detachedMenuBarScale)),
                closeButton.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }
    }

    private func appIcon() -> NSImage? {
        let image = Bundle.main.url(forResource: "SolixBar", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
        let size = round(24 * settings.detachedMenuBarScale)
        return image.map { roundedIconImage($0, size: size) }
    }

    /// Löst Farben über das semantische Rollen-Attribut (.solixRole) auf,
    /// das die Menüleisten-Formatierung an jeden Lauf hängt — früher wurde
    /// hier der gerenderte Text nach Schlüsselwörtern durchsucht, was bei
    /// jeder Textänderung brach.
    private func readableDetachedText(_ attributedText: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: attributedText)
        let fullRange = NSRange(location: 0, length: result.length)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.92)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        result.addAttributes(
            [
                .shadow: shadow,
                .strokeColor: NSColor.black.withAlphaComponent(0.70),
                .strokeWidth: -1.5
            ],
            range: fullRange
        )

        result.enumerateAttributes(in: fullRange) { attributes, range, _ in
            let role = (attributes[.solixRole] as? String).flatMap(ColorRole.init(rawValue:))
            if let attachment = attributes[.attachment] as? NSTextAttachment, let image = attachment.image {
                let tinted = image.copy() as? NSImage ?? image
                tinted.isTemplate = false
                tinted.lockFocus()
                Theme.bright(role ?? .neutral).set()
                NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
                tinted.unlockFocus()
                let replacement = NSTextAttachment()
                replacement.image = tinted
                replacement.bounds = attachment.bounds
                result.addAttribute(.attachment, value: replacement, range: range)
                return
            }
            let substring = (result.string as NSString).substring(with: range)
            let color: NSColor
            if let role {
                color = Theme.bright(role)
            } else if substring.trimmingCharacters(in: .whitespaces) == "•" {
                color = NSColor(calibratedWhite: 0.86, alpha: 1)
            } else {
                color = .white
            }
            result.addAttribute(.foregroundColor, value: color, range: range)
        }
        return result
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

    /// Dezenter Zwei-Stopp-Akzent aus den ersten beiden Metrikfarben — die
    /// frühere Überlagerung von bis zu fünf Farben ergab ein schlammiges Braun.
    private var accentColors: [NSColor] {
        let metrics = settings.barMetrics.isEmpty ? [BarMetric.battery, .solar, .grid] : settings.barMetrics
        return metrics.prefix(2).map { Theme.accent(accentRole(for: $0)) }
    }

    private func accentRole(for metric: BarMetric) -> ColorRole {
        switch metric {
        case .battery:
            .batteryHigh
        case .solar, .today:
            .solar
        case .home:
            .load
        case .grid:
            .gridImport
        case .batteryFlow, .flow:
            .batteryCharging
        case .total:
            .yieldTotal
        case .status:
            .status
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
        let base = colors.count >= 2
            ? colors
            : [
                NSColor(calibratedRed: 0.17, green: 0.78, blue: 0.36, alpha: 1),
                NSColor(calibratedRed: 1.00, green: 0.68, blue: 0.03, alpha: 1)
            ]
        return base.map { $0.withAlphaComponent(0.12).cgColor }
    }

    private var gradientLocations: [NSNumber] {
        guard gradientColors.count > 1 else { return [0, 1] }
        return (0..<gradientColors.count).map { NSNumber(value: Double($0) / Double(gradientColors.count - 1)) }
    }
}
