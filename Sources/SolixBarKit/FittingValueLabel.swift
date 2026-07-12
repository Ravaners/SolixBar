import AppKit

/// Wertelabel für die großen Dashboard-Kacheln, das seine Schriftgröße an die
/// verfügbare Breite anpasst und mehrzeilige Werte (PV-Eingänge) unterstützt.
///
/// Die Kacheln stehen paarweise nebeneinander und werden im abgedockten
/// Fenster mitgezogen; die Breite steht daher erst zur Layout-Zeit fest.
/// Darum wird die Schrift in `layout()` gewählt: die größte Größe zwischen
/// `minFontSize` und `baseFontSize`, bei der die breiteste Zeile noch passt.
/// Reicht selbst `minFontSize` nicht, kürzt macOS die Zeile am Ende (…).
final class FittingValueLabel: NSTextField {
    var baseFontSize: CGFloat = 23
    var minFontSize: CGFloat = 14
    var weight: NSFont.Weight = .bold

    private var lines: [String] = []

    convenience init() {
        self.init(labelWithString: "")
        isBordered = false
        isEditable = false
        isSelectable = false
        drawsBackground = false
        lineBreakMode = .byTruncatingTail
        cell?.truncatesLastVisibleLine = true
        // Zeilen liegen als \n im String vor; zwei Zeilen genügen (2×2-Raster
        // für bis zu vier PV-Eingänge).
        maximumNumberOfLines = 2
    }

    /// Setzt eine oder zwei Zeilen. Leere Eingabe zeigt "-".
    func setLines(_ newLines: [String]) {
        lines = newLines.isEmpty ? ["-"] : newLines
        stringValue = lines.joined(separator: "\n")
        maximumNumberOfLines = max(1, lines.count)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let available = bounds.width
        guard available > 1, !lines.isEmpty else { return }

        var size = baseFontSize
        while size > minFontSize {
            let candidate = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            let widest = lines
                .map { ($0 as NSString).size(withAttributes: [.font: candidate]).width }
                .max() ?? 0
            if widest <= available { break }
            size -= 1
        }
        // Nur bei echter Änderung setzen — sonst löst jedes layout() eine neue
        // Layout-Runde aus (Endlosschleife).
        if abs((font?.pointSize ?? 0) - size) > 0.1 {
            font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        }
    }
}
