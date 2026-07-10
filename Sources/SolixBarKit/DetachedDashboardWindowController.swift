import AppKit

@MainActor
final class DetachedDashboardWindowController: NSWindowController {
    private let snapshotProvider: () -> SolixSnapshot?
    private let graphProvider: () -> [SolixHistorySample]
    private let onRangeChange: () -> Void
    private let onOpenLarge: () -> Void

    init(
        snapshotProvider: @escaping () -> SolixSnapshot?,
        graphProvider: @escaping () -> [SolixHistorySample],
        onRangeChange: @escaping () -> Void,
        onOpenLarge: @escaping () -> Void
    ) {
        self.snapshotProvider = snapshotProvider
        self.graphProvider = graphProvider
        self.onRangeChange = onRangeChange
        self.onOpenLarge = onOpenLarge
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 622),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SOLIX Dashboard"
        window.minSize = NSSize(width: 430, height: 560)
        window.contentMinSize = NSSize(width: 430, height: 560)
        window.maxSize = NSSize(width: 760, height: 980)
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.setFrameAutosaveName("SolixBarDetachedDashboard")
        super.init(window: window)
        rebuild()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showBelowMenuBar(anchor: NSRect?) {
        if let window, !window.isVisible {
            positionBelowMenuBar(anchor: anchor)
        }
        rebuild()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func rebuild() {
        guard let window else { return }
        let oldFrame = window.frame
        let contentSize = window.contentView?.bounds.size ?? window.contentLayoutRect.size
        let view: NSView

        if let snapshot = snapshotProvider() {
            view = SolixMenuDashboardView(
                snapshot: snapshot,
                graphProvider: graphProvider,
                onRangeChange: onRangeChange,
                onOpenLarge: onOpenLarge
            )
        } else {
            view = DetachedDashboardPlaceholderView()
        }

        view.frame = NSRect(origin: .zero, size: contentSize)
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        window.setFrame(oldFrame, display: true)
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
        frame.origin.y = visible.maxY - frame.height - 8
        window.setFrame(frame, display: true)
    }
}

private final class DetachedDashboardPlaceholderView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let label = NSTextField(wrappingLabelWithString: "Noch keine SOLIX-Daten geladen.")
        label.alignment = .center
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
