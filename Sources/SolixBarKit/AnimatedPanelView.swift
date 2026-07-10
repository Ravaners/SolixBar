import AppKit
import QuartzCore

final class AnimatedPanelView: NSView {
    var baseColor: NSColor = .controlBackgroundColor {
        didSet {
            layer?.backgroundColor = baseColor.cgColor
        }
    }

    var highlightColor: NSColor = .controlBackgroundColor

    init() {
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            layer?.removeAnimation(forKey: "softPanelGlow")
        } else {
            startSoftAnimation()
        }
    }

    private func startSoftAnimation() {
        guard let layer else { return }
        layer.backgroundColor = baseColor.cgColor
        let animation = CABasicAnimation(keyPath: "backgroundColor")
        animation.fromValue = baseColor.cgColor
        animation.toValue = highlightColor.cgColor
        animation.duration = 3.8
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(animation, forKey: "softPanelGlow")
    }
}
