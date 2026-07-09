import AppKit

@MainActor
final class DetachedMenuBarWindowController: NSWindowController, NSWindowDelegate {
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
        window.level = .normal
        window.isMovableByWindowBackground = true
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
            label.attributedStringValue = attributedText
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            stack.addArrangedSubview(label)
        } else {
            let label = NSTextField(labelWithString: "SOLIX wartet auf Daten")
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            label.textColor = .secondaryLabelColor
            stack.addArrangedSubview(label)
        }

        let closeButton = NSButton(title: "×", target: self, action: #selector(close))
        closeButton.isBordered = false
        closeButton.font = .systemFont(ofSize: round(18 * settings.detachedMenuBarScale), weight: .bold)
        closeButton.contentTintColor = .secondaryLabelColor
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
        image?.size = NSSize(width: size, height: size)
        return image
    }

    @objc private func close() {
        onClose()
    }

    private var readableBackground: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.13, alpha: 0.94)
                : NSColor(calibratedRed: 0.96, green: 0.98, blue: 0.97, alpha: 0.92)
        }
    }

    private var accentColors: [NSColor] {
        let metrics = settings.barMetrics.isEmpty ? [BarMetric.battery, .solar] : settings.barMetrics
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
