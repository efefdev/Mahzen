// Uygulama simgesini (1024 px PNG) çizer. Kullanım: swift scripts/make-icon.swift çıktı.png
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS simge ızgarası: 1024 içinde 824'lük yuvarlatılmış kare.
let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: rect, xRadius: 186, yRadius: 186)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
NSGraphicsContext.saveGraphicsState()
shadow.set()
NSColor.black.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(colors: [
    NSColor(srgbRed: 0.10, green: 0.07, blue: 0.30, alpha: 1),
    NSColor(srgbRed: 0.30, green: 0.24, blue: 0.82, alpha: 1),
    NSColor(srgbRed: 0.52, green: 0.42, blue: 1.00, alpha: 1),
])!.draw(in: shape, angle: 90)

// Üstte hafif parlama.
NSGraphicsContext.saveGraphicsState()
shape.addClip()
NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
    .draw(in: NSRect(x: 100, y: 560, width: 824, height: 364), angle: 270)
NSGraphicsContext.restoreGraphicsState()

func drawSymbol(_ name: String, pointSize: CGFloat, color: NSColor, yOffset: CGFloat) {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
    let s = symbol.size
    symbol.draw(in: NSRect(x: (CGFloat(size) - s.width) / 2, y: (CGFloat(size) - s.height) / 2 + yOffset, width: s.width, height: s.height))
}
drawSymbol("shield.fill", pointSize: 470, color: .white, yOffset: -4)
drawSymbol("lock.fill", pointSize: 190, color: NSColor(srgbRed: 0.27, green: 0.21, blue: 0.75, alpha: 1), yOffset: 10)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
