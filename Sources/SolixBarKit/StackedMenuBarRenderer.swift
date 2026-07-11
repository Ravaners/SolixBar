import AppKit

/// Zweizeilige Kompaktanzeige für die Menüleiste: zwei Reihen à 9 pt
/// Monospace-Ziffern mit kleinen Metrik-Glyphen — halbiert die Breite bei
/// gleicher oder höherer Informationsdichte (bewährtes Muster, vgl. iStat
/// Menus). Gezeichnet über einen NSImage-DrawingHandler, damit dynamische
/// Theme-Farben zur Zeichenzeit gegen die tatsächliche Menüleisten-Appearance
/// aufgelöst werden.
@MainActor
enum StackedMenuBarRenderer {
    struct Entry {
        let symbolName: String
        let text: String
        let role: ColorRole
    }

    /// - Parameters:
    ///   - brightPalette: feste helle Farben für dauerhaft dunkle Flächen
    ///     (abgedockte Leiste) statt der System-adaptiven Menüleistenfarben.
    ///   - height: Gesamthöhe; die Schriftgröße wird darauf gedeckelt, damit
    ///     zwei Zeilen nie überlappen (Menüleiste: 22 pt).
    static func image(
        entries: [Entry],
        scale: Double,
        showWarning: Bool,
        brightPalette: Bool = false,
        height: CGFloat = 22
    ) -> NSImage? {
        guard !entries.isEmpty else { return nil }
        let half = (entries.count + 1) / 2
        let rows = [Array(entries.prefix(half)), Array(entries.dropFirst(half))]
            .filter { !$0.isEmpty }

        let fontSize = min(round(9 * scale), floor(height / 2) - 2)
        let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold)
        let glyphHeight = round(fontSize * 0.9)
        let entryGap = round(7 * scale)
        let glyphGap = round(2 * scale)

        // Glyphenbreite folgt dem natürlichen Seitenverhältnis des Symbols —
        // ein Batteriesymbol (~1,7:1) in ein Quadrat zu zeichnen staucht es.
        func glyphSize(for symbolName: String) -> NSSize {
            guard let glyph = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: glyphHeight, weight: .bold)),
                  glyph.size.height > 0 else {
                return NSSize(width: glyphHeight, height: glyphHeight)
            }
            let aspect = glyph.size.width / glyph.size.height
            return NSSize(width: round(glyphHeight * aspect), height: glyphHeight)
        }

        func rowWidth(_ row: [Entry]) -> CGFloat {
            var width: CGFloat = 0
            for (index, entry) in row.enumerated() {
                if index > 0 { width += entryGap }
                width += glyphSize(for: entry.symbolName).width + glyphGap
                width += ceil((entry.text as NSString).size(withAttributes: [.font: font]).width)
            }
            return width
        }

        let warningWidth: CGFloat = showWarning ? round(11 * scale) : 0
        let width = ceil((rows.map(rowWidth).max() ?? 0) + warningWidth) + 2

        let size = NSSize(width: width, height: height)
        return NSImage(size: size, flipped: false) { _ in
            let rowHeight = height / CGFloat(rows.count)
            for (rowIndex, row) in rows.enumerated() {
                // Reihen von oben nach unten, vertikal in ihrer Hälfte zentriert.
                let rowCenterY = height - rowHeight * (CGFloat(rowIndex) + 0.5)
                var x: CGFloat = 1
                for (index, entry) in row.enumerated() {
                    if index > 0 { x += entryGap }
                    let color = brightPalette ? Theme.hud(entry.role) : Theme.color(entry.role)
                    if let glyph = NSImage(systemSymbolName: entry.symbolName, accessibilityDescription: nil)?
                        .withSymbolConfiguration(.init(pointSize: glyphHeight, weight: .bold)) {
                        let tinted = glyph.tinted(color)
                        let drawSize = glyphSize(for: entry.symbolName)
                        let glyphRect = NSRect(
                            x: x,
                            y: rowCenterY - drawSize.height / 2,
                            width: drawSize.width,
                            height: drawSize.height
                        )
                        tinted.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: 1)
                        x += drawSize.width + glyphGap
                    }
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: color
                    ]
                    let textSize = (entry.text as NSString).size(withAttributes: attributes)
                    (entry.text as NSString).draw(
                        at: NSPoint(x: x, y: rowCenterY - textSize.height / 2),
                        withAttributes: attributes
                    )
                    x += ceil(textSize.width)
                }
            }
            if showWarning {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: round(9 * scale), weight: .bold),
                    .foregroundColor: brightPalette ? Theme.hud(.batteryMedium) : Theme.color(.batteryMedium)
                ]
                ("⚠" as NSString).draw(
                    at: NSPoint(x: width - warningWidth, y: height / 2 - round(6 * scale)),
                    withAttributes: attributes
                )
            }
            return true
        }
    }
}
