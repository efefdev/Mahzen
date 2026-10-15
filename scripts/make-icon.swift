// Uygulama simgesini (1024 px PNG) Resources/Logo/mahzen-logo.svg'den çizer.
// Kullanım: swift scripts/make-icon.swift çıktı.png
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
guard let logo = NSImage(contentsOf: root.appendingPathComponent("Resources/Logo/mahzen-logo.svg")) else {
    fatalError("Resources/Logo/mahzen-logo.svg okunamadı")
}
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS simge ızgarası: 1024 içinde 824'lük kare. SVG'de kare-daire 2000'lik tuvalin 1668'ini kaplar.
let scale = 824.0 / 1668.0
let drawn = 2000.0 * scale
let rect = NSRect(x: (Double(size) - drawn) / 2, y: (Double(size) - drawn) / 2 - 6, width: drawn, height: drawn)

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
logo.draw(in: rect)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
