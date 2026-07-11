import AppKit

extension NSImage {
    /// Auflösungsunabhängiges Tinting: zeichnet per DrawingHandler im
    /// Zielkontext (Retina-scharf). Das frühere lockFocus-Tinting rasterte
    /// mit 1x und wirkte skaliert unscharf.
    func tinted(_ color: NSColor) -> NSImage {
        let base = self
        let result = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        result.isTemplate = false
        result.accessibilityDescription = accessibilityDescription
        return result
    }
}
