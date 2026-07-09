import AppKit

final class CenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var drawingRect = super.drawingRect(forBounds: rect)
        let textSize = cellSize(forBounds: rect)
        drawingRect.origin.y += max(0, (rect.height - textSize.height) / 2)
        drawingRect.size.height = min(textSize.height, rect.height)
        return drawingRect
    }
}
