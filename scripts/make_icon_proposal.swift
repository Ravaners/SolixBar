import AppKit

// SolixBar App-Icon-Entwürfe: "Panel als Diagramm" (A) und ruhige Variante (B).
// Ausgabe: icon-a-1024.png, icon-b-1024.png, Vorschau-Kontaktbogen.

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func renderPNG(size: Int, _ draw: (CGFloat) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    draw(CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func squirclePath(canvas: CGFloat) -> (NSBezierPath, NSRect) {
    // Big-Sur-Raster: Kachel 824/1024 des Canvas, zentriert.
    let side = canvas * 824 / 1024
    let rect = NSRect(x: (canvas - side) / 2, y: (canvas - side) / 2, width: side, height: side)
    let radius = side * 0.225
    return (NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius), rect)
}

struct PanelSpec {
    var skewDegrees: CGFloat   // Neigung des Panels
    var risingFill: Bool       // true: Säulen füllen sich wie ein Diagramm
}

func drawIcon(canvas: CGFloat, spec: PanelSpec) {
    let (squircle, tile) = squirclePath(canvas: canvas)
    let s = tile.width / 824    // Skala relativ zum 824er-Raster

    // Schatten der Kachel
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
    shadow.shadowBlurRadius = 36 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    color(0x171A2B).setFill()
    squircle.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // Hintergrund: Abendhimmel-Verlauf
    NSGraphicsContext.current?.saveGraphicsState()
    squircle.addClip()
    NSGradient(colors: [color(0x39406B), color(0x232746), color(0x14172A)], atLocations: [0, 0.55, 1], colorSpace: .deviceRGB)!
        .draw(in: tile, angle: -90)

    // Warmes Streulicht hinter der Sonne
    let sunCenter = NSPoint(x: tile.midX + 272 * s, y: tile.midY + 262 * s)
    let glow = NSGradient(colors: [color(0xFFB84D, 0.45), color(0xFFB84D, 0.0)])!
    glow.draw(
        fromCenter: sunCenter, radius: 0,
        toCenter: sunCenter, radius: 430 * s,
        options: []
    )

    // Sonne
    let sunRadius = 132 * s
    let sunRect = NSRect(x: sunCenter.x - sunRadius, y: sunCenter.y - sunRadius, width: sunRadius * 2, height: sunRadius * 2)
    NSGradient(colors: [color(0xFFEBA1), color(0xFFC24E)])!
        .draw(in: NSBezierPath(ovalIn: sunRect), angle: -90)

    // Panel: leichte Scherung = Balkon-Neigung, ohne die Lesbarkeit zu brechen
    let panelSide = 520 * s
    let panelRect = NSRect(
        x: tile.midX - panelSide / 2 - 30 * s,
        y: tile.midY - panelSide / 2 - 28 * s,
        width: panelSide, height: panelSide
    )
    let transform = NSAffineTransform()
    transform.translateX(by: panelRect.midX, yBy: panelRect.midY)
    if spec.skewDegrees != 0 {
        let shear = tan(spec.skewDegrees * .pi / 180)
        transform.transformStruct = NSAffineTransformStruct(
            m11: 1, m12: 0, m21: shear, m22: 1,
            tX: transform.transformStruct.tX, tY: transform.transformStruct.tY
        )
    }
    transform.translateX(by: -panelRect.midX, yBy: -panelRect.midY)
    NSGraphicsContext.current?.saveGraphicsState()
    transform.concat()

    // Rahmen
    NSGraphicsContext.current?.saveGraphicsState()
    let frameShadow = NSShadow()
    frameShadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    frameShadow.shadowBlurRadius = 30 * s
    frameShadow.shadowOffset = NSSize(width: -6 * s, height: -10 * s)
    frameShadow.set()
    let frame = NSBezierPath(roundedRect: panelRect, xRadius: 44 * s, yRadius: 44 * s)
    color(0x0D1020).setFill()
    frame.fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    frame.lineWidth = 3 * s
    color(0x4A5478, 0.8).setStroke()
    frame.stroke()

    // Zellen: 4 Spalten x 5 Reihen
    let pad = 40 * s
    let gap = 16 * s
    let cols = 4, rows = 5
    let cellW = (panelRect.width - pad * 2 - gap * CGFloat(cols - 1)) / CGFloat(cols)
    let cellH = (panelRect.height - pad * 2 - gap * CGFloat(rows - 1)) / CGFloat(rows)
    let filledRows = spec.risingFill ? [2, 3, 4, 5] : [5, 5, 5, 5]

    for col in 0..<cols {
        for row in 0..<rows {
            let rect = NSRect(
                x: panelRect.minX + pad + CGFloat(col) * (cellW + gap),
                y: panelRect.minY + pad + CGFloat(row) * (cellH + gap),
                width: cellW, height: cellH
            )
            let cell = NSBezierPath(roundedRect: rect, xRadius: 12 * s, yRadius: 12 * s)
            if row < filledRows[col] {
                // Gefüllt: Bernstein-Verlauf, oben in der Spalte heller
                let brightness = 0.72 + 0.28 * CGFloat(row + 1) / CGFloat(rows)
                let top = color(0xFFE083).blended(withFraction: 1 - brightness, of: color(0xB86A14))!
                let bottom = color(0xF5A623).blended(withFraction: 1 - brightness, of: color(0x8A4E0E))!
                NSGraphicsContext.current?.saveGraphicsState()
                let cellGlow = NSShadow()
                cellGlow.shadowColor = color(0xFFB84D, 0.35)
                cellGlow.shadowBlurRadius = 14 * s
                cellGlow.set()
                NSGradient(colors: [top, bottom])!.draw(in: cell, angle: -90)
                NSGraphicsContext.current?.restoreGraphicsState()
            } else {
                color(0x232A44).setFill()
                cell.fill()
                cell.lineWidth = 2 * s
                color(0x3B4468, 0.9).setStroke()
                cell.stroke()
            }
        }
    }
    NSGraphicsContext.current?.restoreGraphicsState() // Scherung

    // Zarte Lichtkante oben auf der Kachel
    let topEdge = NSBezierPath(roundedRect: tile.insetBy(dx: 2 * s, dy: 2 * s), xRadius: tile.width * 0.222, yRadius: tile.width * 0.222)
    topEdge.lineWidth = 3 * s
    color(0xFFFFFF, 0.10).setStroke()
    topEdge.stroke()

    NSGraphicsContext.current?.restoreGraphicsState() // Clip
}

func writePNG(_ rep: NSBitmapImageRep, _ name: String) {
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: out.appendingPathComponent(name))
    print("wrote \(name)")
}

let variantA = PanelSpec(skewDegrees: 7, risingFill: true)
let variantB = PanelSpec(skewDegrees: 0, risingFill: false)

let iconA = renderPNG(size: 1024) { drawIcon(canvas: $0, spec: variantA) }
let iconB = renderPNG(size: 1024) { drawIcon(canvas: $0, spec: variantB) }
writePNG(iconA, "icon-a-1024.png")
writePNG(iconB, "icon-b-1024.png")

// Kontaktbogen: beide Varianten auf hellem und dunklem Desktop, Größenleiter.
func contactSheet(icons: [(String, NSBitmapImageRep)]) -> NSBitmapImageRep {
    let width = 1480, height = 1060
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high

    let half = CGFloat(height) / 2
    color(0xE9EAF0).setFill()
    NSRect(x: 0, y: half, width: CGFloat(width), height: half).fill()
    color(0x131419).setFill()
    NSRect(x: 0, y: 0, width: CGFloat(width), height: half).fill()

    let sizes: [CGFloat] = [320, 128, 64, 32, 16]
    let baseYs: [CGFloat] = [half + 60, 60]
    for (index, entry) in icons.enumerated() {
        let (title, rep0) = entry
        let image = NSImage(size: NSSize(width: rep0.pixelsWide, height: rep0.pixelsHigh))
        image.addRepresentation(rep0)
        let originX: CGFloat = 70 + CGFloat(index) * 720
        for (bgIndex, baseY) in baseYs.enumerated() {
            var x = originX
            for size in sizes {
                let y = baseY + (320 - size) / 2
                image.draw(
                    in: NSRect(x: x, y: y, width: size, height: size),
                    from: .zero, operation: .sourceOver, fraction: 1
                )
                x += size + 34
            }
            let labelColor = bgIndex == 0 ? color(0x30323C) : color(0xC7CAD6)
            let label = NSAttributedString(string: title, attributes: [
                .font: NSFont.systemFont(ofSize: 26, weight: .semibold),
                .foregroundColor: labelColor
            ])
            label.draw(at: NSPoint(x: originX, y: baseY + 340))
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let sheet = contactSheet(icons: [("Variante A - Panel als Diagramm", iconA), ("Variante B - ruhig", iconB)])
writePNG(sheet, "icon-preview.png")
