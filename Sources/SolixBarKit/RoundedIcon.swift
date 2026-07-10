import AppKit

func roundedIconImage(_ image: NSImage, size: CGFloat, radius: CGFloat? = nil) -> NSImage {
    let targetSize = NSSize(width: size, height: size)
    let output = NSImage(size: targetSize)
    output.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    let rect = NSRect(origin: .zero, size: targetSize)
    let path = NSBezierPath(roundedRect: rect, xRadius: radius ?? size * 0.22, yRadius: radius ?? size * 0.22)
    path.addClip()
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    output.unlockFocus()
    output.isTemplate = false
    return output
}
