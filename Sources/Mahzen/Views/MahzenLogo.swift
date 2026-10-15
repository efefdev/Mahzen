import SwiftUI

/// Mahzen logosu: taş kemerli mahzen kapısı ve ışıyan anahtar deliği.
/// `Resources/Logo/mahzen-logo.svg` ile aynı çizim; 2000×2000'lik koordinatlarda tanımlanır, her boyutta keskindir.
/// `open` açıkken (kilit açılırken) anahtar deliğinin ışığı güçlenir.
struct MahzenLogo: View {
    var open = false
    var showsBackground = true

    static let background = Color(red: 0x11 / 255, green: 0x10 / 255, blue: 0x15 / 255)
    static let stone = Color(red: 0x25 / 255, green: 0x26 / 255, blue: 0x2B / 255)
    static let glowColor = Color(red: 0xF5 / 255, green: 0x9A / 255, blue: 0x55 / 255)

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 2000
            ctx.scaleBy(x: s, y: s)
            if showsBackground {
                ctx.fill(Path(roundedRect: CGRect(x: 166, y: 166, width: 1668, height: 1668), cornerRadius: 380, style: .continuous),
                         with: .color(Self.background))
            }
            // Kemer taşları: köşeleri yuvarlatılmış yedi dilim.
            let stones = Self.stonesPath
            ctx.fill(stones, with: .color(Self.stone))
            ctx.stroke(stones, with: .color(Self.stone), style: StrokeStyle(lineWidth: 24, lineJoin: .round))
            // Yan bloklar ve taban.
            for r in [CGRect(x: 518, y: 953, width: 200, height: 160), CGRect(x: 518, y: 1139, width: 200, height: 160),
                      CGRect(x: 518, y: 1325, width: 200, height: 160), CGRect(x: 1282, y: 953, width: 200, height: 160),
                      CGRect(x: 1282, y: 1139, width: 200, height: 160), CGRect(x: 1282, y: 1325, width: 200, height: 160),
                      CGRect(x: 458, y: 1446, width: 1084, height: 96)] {
                ctx.fill(Path(roundedRect: r, cornerRadius: 12), with: .color(Self.stone))
            }
            // İç karanlık ve ışıma.
            ctx.fill(Self.arch(left: 737, right: 1263, bottom: 1397), with: .color(Self.background))
            let glowRadius: CGFloat = open ? 330 : 250
            ctx.fill(Path(ellipseIn: CGRect(x: 1000 - glowRadius, y: 1060 - glowRadius, width: glowRadius * 2, height: glowRadius * 2)),
                     with: .radialGradient(Gradient(stops: [
                        .init(color: Self.glowColor.opacity(open ? 0.85 : 0.6), location: 0),
                        .init(color: Color(red: 0xE0 / 255, green: 0x7A / 255, blue: 0x3A / 255).opacity(open ? 0.35 : 0.22), location: 0.45),
                        .init(color: .clear, location: 1),
                     ]), center: CGPoint(x: 1000, y: 1060), startRadius: 0, endRadius: glowRadius))
            // Turuncu kemer çerçevesi.
            var frame = Self.arch(left: 661, right: 1339, bottom: 1494)
            frame.addPath(Self.arch(left: 737, right: 1263, bottom: 1397))
            ctx.fill(frame, with: .radialGradient(Gradient(stops: [
                .init(color: Color(red: 0xFB / 255, green: 0xB0 / 255, blue: 0x6E / 255), location: 0),
                .init(color: Color(red: 0xF3 / 255, green: 0x92 / 255, blue: 0x4D / 255), location: 0.55),
                .init(color: Color(red: 0xC5 / 255, green: 0x5F / 255, blue: 0x2A / 255), location: 1),
            ]), center: CGPoint(x: 1000, y: 1150), startRadius: 0, endRadius: 640), style: FillStyle(eoFill: true))
            // Eşik eğimi.
            var sill = Path()
            sill.addLines([CGPoint(x: 737, y: 1397), CGPoint(x: 1263, y: 1397), CGPoint(x: 1339, y: 1494), CGPoint(x: 661, y: 1494)])
            sill.closeSubpath()
            let edge = Color(red: 0xC9 / 255, green: 0x65 / 255, blue: 0x2E / 255)
            let mid = Color(red: 0xE9 / 255, green: 0x89 / 255, blue: 0x4A / 255)
            ctx.fill(sill, with: .linearGradient(Gradient(stops: [
                .init(color: edge, location: 0), .init(color: mid, location: 0.12),
                .init(color: Color(red: 0xF0 / 255, green: 0x9A / 255, blue: 0x5C / 255), location: 0.5),
                .init(color: mid, location: 0.88), .init(color: edge, location: 1),
            ]), startPoint: CGPoint(x: 661, y: 0), endPoint: CGPoint(x: 1339, y: 0)))
            // Anahtar deliği.
            let key = GraphicsContext.Shading.radialGradient(Gradient(colors: [
                Color(red: 0xFA / 255, green: 0xBB / 255, blue: 0x82 / 255),
                Color(red: 0xF3 / 255, green: 0x90 / 255, blue: 0x49 / 255),
            ]), center: CGPoint(x: 1000, y: 1010), startRadius: 0, endRadius: 210)
            ctx.fill(Path(ellipseIn: CGRect(x: 928, y: 917, width: 144, height: 144)), with: key)
            var stem = Path()
            stem.addLines([CGPoint(x: 972, y: 1040), CGPoint(x: 1028, y: 1040), CGPoint(x: 1047, y: 1191), CGPoint(x: 953, y: 1191)])
            stem.closeSubpath()
            ctx.fill(stem, with: key)
            ctx.stroke(stem, with: key, style: StrokeStyle(lineWidth: 28, lineJoin: .round))
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.smooth(duration: 0.35), value: open)
    }

    /// Yarım daire tepeli kemer: sol/sağ kenarlar ve taban; tepe merkezi y=963.
    static func arch(left: CGFloat, right: CGFloat, bottom: CGFloat) -> Path {
        let r = (right - left) / 2, cx = (left + right) / 2, cy: CGFloat = 963
        var p = Path()
        p.move(to: CGPoint(x: left, y: bottom))
        p.addLine(to: CGPoint(x: left, y: cy))
        for i in 1...48 {
            let t = CGFloat.pi * CGFloat(i) / 48
            p.addLine(to: CGPoint(x: cx - r * cos(t), y: cy - r * sin(t)))
        }
        p.addLine(to: CGPoint(x: right, y: bottom))
        p.closeSubpath()
        return p
    }

    /// Yedi kemer taşı; aralarda 24 birimlik boşluk, köşeler çizgi kalınlığıyla yuvarlatılır.
    static let stonesPath: Path = {
        let cx: CGFloat = 1000, cy: CGFloat = 927, rIn: CGFloat = 320, rOut: CGFloat = 474 - 12, halfGap: CGFloat = 12, round: CGFloat = 12
        let bounds: [CGFloat] = [-90, -65.5, -40.5, -15, 15, 40.5, 65.5, 90]
        func point(_ r: CGFloat, _ deg: CGFloat) -> CGPoint {
            let t = deg * .pi / 180
            return CGPoint(x: cx + r * sin(t), y: cy - r * cos(t))
        }
        var path = Path()
        for (a0, a1) in zip(bounds.dropLast(), bounds.dropFirst()) {
            let g0: CGFloat = a0 == -90 ? 0 : halfGap + round, g1: CGFloat = a1 == 90 ? 0 : halfGap + round
            let outer0 = a0 + g0 / rOut * 180 / .pi, outer1 = a1 - g1 / rOut * 180 / .pi
            let inner0 = a0 + g0 / rIn * 180 / .pi, inner1 = a1 - g1 / rIn * 180 / .pi
            var pts: [CGPoint] = (0...24).map { point(rOut, outer0 + (outer1 - outer0) * CGFloat($0) / 24) }
            pts += (0...24).map { point(rIn, inner1 - (inner1 - inner0) * CGFloat($0) / 24) }
            if a0 == -90 { pts[0].y = cy - round; pts[pts.count - 1].y = cy - round }
            if a1 == 90 { pts[24].y = cy - round; pts[25].y = cy - round }
            path.addLines(pts)
            path.closeSubpath()
        }
        return path
    }()
}
