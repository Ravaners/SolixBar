import AppKit

extension WindowLevelMode {
    /// "Immer hinten" nutzt die Schreibtischsymbol-Ebene: sichtbar auf dem
    /// Desktop, aber unter allen normalen Fenstern.
    var nsWindowLevel: NSWindow.Level {
        switch self {
        case .alwaysOnTop: return .floating
        case .normal: return .normal
        case .alwaysBehind: return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
        }
    }
}

@MainActor
final class DetachedMenuBarWindowController: NSWindowController, NSWindowDelegate {
    private let settings = AppSettings.shared
    private let attributedBarProvider: () -> NSAttributedString?
    private let stackedImageProvider: () -> NSImage?
    private let onClose: () -> Void
    private var didNotifyClose = false
    private var wantsVisible = false
    private var snapDebounce: Timer?

    init(
        attributedBarProvider: @escaping () -> NSAttributedString?,
        stackedImageProvider: @escaping () -> NSImage? = { nil },
        onClose: @escaping () -> Void
    ) {
        self.attributedBarProvider = attributedBarProvider
        self.stackedImageProvider = stackedImageProvider
        self.onClose = onClose
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 44),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "SOLIX Leiste"
        window.level = settings.detachedBarLevel.nsWindowLevel
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
        window.level = settings.detachedBarLevel.nsWindowLevel
        let attributedText = attributedBarProvider()
        let stackedImage = stackedImageProvider()
        let oldFrame = window.frame
        let targetSize = targetSize(for: attributedText, stackedImage: stackedImage, screen: window.screen)
        let view = DetachedMenuBarView(attributedText: attributedText, stackedImage: stackedImage, onClose: { [weak self] in
            self?.closeFromButton()
        })
        view.frame = NSRect(origin: .zero, size: targetSize)
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        var frame = oldFrame
        frame.size = targetSize
        if let screen = window.screen {
            // Position des Nutzers respektieren: nur sicherstellen, dass ein
            // greifbarer Teil (60 pt) sichtbar bleibt, statt die Leiste hart
            // an den Rand zu klemmen.
            let visible = screen.visibleFrame
            frame.origin.x = min(visible.maxX - 60, max(visible.minX + 60 - targetSize.width, frame.origin.x))
            frame.origin.y = min(visible.maxY - targetSize.height, max(visible.minY, frame.origin.y))
        }
        window.setFrame(frame, display: true)
    }

    func windowWillClose(_ notification: Notification) {
        saveCurrentPosition()
        notifyCloseIfNeeded()
    }

    func windowDidMove(_ notification: Notification) {
        saveCurrentPosition()
        scheduleEdgeSnap()
    }

    /// Magnetisches Einrasten an Bildschirmkanten (8 pt Abstand), entprellt,
    /// damit es erst nach dem Loslassen greift und nicht am Cursor klebt.
    private func scheduleEdgeSnap() {
        guard !settings.lockDetachedMenuBar else { return }
        snapDebounce?.invalidate()
        snapDebounce = Timer.scheduledTimer(withTimeInterval: 0.30, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.snapToNearbyEdge()
            }
        }
    }

    private func snapToNearbyEdge() {
        guard let window, let screen = window.screen else { return }
        let threshold: CGFloat = 18
        let margin: CGFloat = 8
        let visible = screen.visibleFrame
        var frame = window.frame
        var snapped = false

        if abs(frame.minX - visible.minX) < threshold {
            frame.origin.x = visible.minX + margin
            snapped = true
        } else if abs(frame.maxX - visible.maxX) < threshold {
            frame.origin.x = visible.maxX - frame.width - margin
            snapped = true
        }
        if abs(frame.minY - visible.minY) < threshold {
            frame.origin.y = visible.minY + margin
            snapped = true
        } else if abs(frame.maxY - visible.maxY) < threshold {
            frame.origin.y = visible.maxY - frame.height - margin
            snapped = true
        }
        guard snapped, frame != window.frame else { return }
        window.setFrame(frame, display: true, animate: true)
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
        frame.size = targetSize(for: attributedBarProvider(), stackedImage: stackedImageProvider(), screen: screen)
        let visible = screen.visibleFrame
        frame.origin.x = min(visible.maxX - 60, max(visible.minX + 60 - frame.width, frame.origin.x))
        frame.origin.y = min(visible.maxY - frame.height, max(visible.minY, frame.origin.y))
        window.setFrame(frame, display: true)
        return true
    }

    /// Breite aus den echten Layout-Maßen von DetachedMenuBarView ableiten —
    /// die frühere Schätzung (plus 260-pt-Mindestbreite) ließ rechts sichtbar
    /// Leerraum stehen.
    private func targetSize(for attributedText: NSAttributedString?, stackedImage: NSImage?, screen: NSScreen?) -> NSSize {
        let textWidth = ceil(stackedImage?.size.width ?? attributedText?.size().width ?? 152)
        let scale = AppSettings.shared.detachedMenuBarScale
        let iconWidth: CGFloat = AppSettings.shared.detachedShowIcon
            ? round(24 * scale) + round(10 * scale)   // Icon + Stack-Abstand
            : 0
        let leading = round(14 * scale)
        // Rechts: fixiert nur Randabstand; sonst Lücke + Hover-Schließknopf + Rand.
        let trailing: CGFloat = AppSettings.shared.lockDetachedMenuBar
            ? round(14 * scale)
            : 10 + round(28 * scale) + round(8 * scale)
        let width = leading + iconWidth + textWidth + trailing
        let visibleWidth = screen?.visibleFrame.width ?? 900
        let height = min(68, max(44, round(44 * scale)))
        return NSSize(width: min(max(width, 200), visibleWidth - 24), height: height)
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
    private let stackedImage: NSImage?
    private let onClose: () -> Void
    private let settings = AppSettings.shared
    private weak var closeButton: NSButton?

    init(attributedText: NSAttributedString?, stackedImage: NSImage?, onClose: @escaping () -> Void) {
        self.attributedText = attributedText
        self.stackedImage = stackedImage
        self.onClose = onClose
        super.init(frame: NSRect(x: 0, y: 0, width: 640, height: 44))
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
        effectiveAppearance.performAsCurrentDrawingAppearance {
            buildView()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildView() {
        let glass = NSVisualEffectView()
        // .hudWindow erzwingt dunkle Vibrancy für alle Subviews — dadurch
        // wurden im Light Mode die Dunkelmodus-Farben aufgelöst. .popover
        // ist adaptiv und folgt der echten Appearance.
        glass.material = .popover
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

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = round(10 * settings.detachedMenuBarScale)

        if settings.detachedShowIcon, let image = appIcon() {
            let imageView = NSImageView(image: image)
            let iconSize = round(24 * settings.detachedMenuBarScale)
            imageView.widthAnchor.constraint(equalToConstant: iconSize).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: iconSize).isActive = true
            stack.addArrangedSubview(imageView)
        }

        if let stackedImage {
            // Kompaktanzeige: identisches zweizeiliges Bild wie in der
            // Menüleiste — halbiert die Leistenlänge.
            let imageView = NSImageView(image: stackedImage)
            imageView.imageScaling = .scaleNone
            stack.addArrangedSubview(imageView)
        } else if let attributedText, attributedText.length > 0 {
            let label = NSTextField(labelWithString: "")
            label.attributedStringValue = readableDetachedText(attributedText)
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            stack.addArrangedSubview(label)
        } else {
            let label = NSTextField(labelWithString: LocalizedText.text("SOLIX wartet auf Daten", "SOLIX waiting for data"))
            label.font = .systemFont(ofSize: 13, weight: .semibold)
            label.textColor = .labelColor
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

            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: round(14 * settings.detachedMenuBarScale)),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        if settings.lockDetachedMenuBar {
            stack.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor,
                constant: -round(14 * settings.detachedMenuBarScale)
            ).isActive = true
        } else {
            let closeButton = NSButton(title: "", target: self, action: #selector(close))
            closeButton.isBordered = false
            closeButton.image = NSImage(
                systemSymbolName: "xmark.circle.fill",
                accessibilityDescription: LocalizedText.text("Schließen", "Close")
            )?.withSymbolConfiguration(.init(pointSize: round(13 * settings.detachedMenuBarScale), weight: .semibold))
            closeButton.contentTintColor = NSColor.secondaryLabelColor
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

            // Erst bei Maus über der Leiste einblenden: im Ruhezustand soll
            // die Leiste nur Werte zeigen, kein Bedien-Element. Der Platz
            // bleibt reserviert, damit beim Hover nichts umbricht.
            closeButton.alphaValue = 0
            self.closeButton = closeButton
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Die Leiste wird bei jedem Refresh neu aufgebaut; steht der Zeiger
        // dabei bereits über ihr, käme sonst kein mouseEntered mehr.
        guard let window else { return }
        closeButton?.alphaValue = window.frame.contains(NSEvent.mouseLocation) ? 1 : 0
    }

    override func mouseEntered(with event: NSEvent) {
        setCloseButtonVisible(true)
    }

    override func mouseExited(with event: NSEvent) {
        setCloseButtonVisible(false)
    }

    private func setCloseButtonVisible(_ visible: Bool) {
        guard let closeButton else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            closeButton.animator().alphaValue = visible ? 1 : 0
        }
    }

    /// Dezentes Bolt-Glyph wie in der Menüleiste — das bunte App-Icon-PNG
    /// wirkte auf dem dunklen HUD grell und fremd.
    private func appIcon() -> NSImage? {
        let image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "SOLIX")?
            .withSymbolConfiguration(.init(pointSize: round(14 * settings.detachedMenuBarScale), weight: .semibold))
        guard let image else { return nil }
        return image.tinted(NSColor.labelColor.withAlphaComponent(0.85))
    }

    /// Löst Farben über das semantische Rollen-Attribut (.solixRole) auf,
    /// das die Menüleisten-Formatierung an jeden Lauf hängt — früher wurde
    /// hier der gerenderte Text nach Schlüsselwörtern durchsucht, was bei
    /// jeder Textänderung brach.
    private func readableDetachedText(_ attributedText: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: attributedText)
        let fullRange = NSRange(location: 0, length: result.length)
        // Kontur- und Schatteneffekte entfernen: Auf dem satten dunklen
        // Hintergrund der Leiste erzeugten sie Doppelkanten an den Glyphen
        // (zulaufende "e", doppelt gerändertes "P"); der geerbte
        // Menüleisten-Schatten fliegt ebenfalls raus.
        result.removeAttribute(.shadow, range: fullRange)
        result.removeAttribute(.strokeColor, range: fullRange)
        result.removeAttribute(.strokeWidth, range: fullRange)

        result.enumerateAttributes(in: fullRange) { attributes, range, _ in
            let role = (attributes[.solixRole] as? String).flatMap(ColorRole.init(rawValue:))
            if let attachment = attributes[.attachment] as? NSTextAttachment, let image = attachment.image {
                let tinted = image.tinted(Theme.hud(role ?? .neutral))
                let replacement = NSTextAttachment()
                replacement.image = tinted
                replacement.bounds = attachment.bounds
                result.addAttribute(.attachment, value: replacement, range: range)
                return
            }
            let substring = (result.string as NSString).substring(with: range)
            let color: NSColor
            if let role {
                color = Theme.hud(role)
            } else if substring.trimmingCharacters(in: .whitespaces) == "•" {
                color = .secondaryLabelColor
            } else {
                color = .labelColor
            }
            result.addAttribute(.foregroundColor, value: color, range: range)
        }
        return result
    }

    @objc private func close() {
        onClose()
    }

    /// Dunkles HUD im Dark Mode, helles Milchglas im Light Mode — vorher
    /// war die Leiste in beiden Modi dunkel.
    private var readableBackground: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.11, alpha: 0.90)
                : NSColor(calibratedRed: 0.97, green: 0.98, blue: 0.985, alpha: 0.88)
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
        case .batteryFlow:
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
