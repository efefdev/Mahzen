import AppKit
import MahzenCore
import SwiftUI

enum AccentChoice: String, CaseIterable, Identifiable {
    case orange, indigo, blue, teal, green, pink, red, purple, graphite

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .indigo: return .indigo
        case .blue: return .blue
        case .teal: return .teal
        case .green: return .green
        case .orange: return .orange
        case .pink: return .pink
        case .red: return .red
        case .purple: return .purple
        case .graphite: return .gray
        }
    }

    var title: String {
        switch self {
        case .indigo: return L("Çivit")
        case .blue: return L("Mavi")
        case .teal: return L("Turkuaz")
        case .green: return L("Yeşil")
        case .orange: return L("Turuncu")
        case .pink: return L("Pembe")
        case .red: return L("Kırmızı")
        case .purple: return L("Mor")
        case .graphite: return L("Grafit")
        }
    }

    init(_ raw: String?) { self = AccentChoice(rawValue: raw ?? "") ?? .orange }
}

/// Ayarlarda seçilen vurgu rengi. `Color.accentColor` sistem rengini döndürdüğü için görünümler bunu kullanır.
private struct VaultAccentKey: EnvironmentKey {
    static let defaultValue = Color.orange
}

extension EnvironmentValues {
    var vaultAccent: Color {
        get { self[VaultAccentKey.self] }
        set { self[VaultAccentKey.self] = newValue }
    }
}

enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return L("Sistem")
        case .light: return L("Açık")
        case .dark: return L("Koyu")
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum NoteFontDesign: String, CaseIterable, Identifiable {
    case `default`, serif, rounded, monospaced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .default: return L("Sistem")
        case .serif: return "Serif"
        case .rounded: return L("Yuvarlak")
        case .monospaced: return L("Eş aralıklı")
        }
    }

    var design: Font.Design {
        switch self {
        case .default: return .default
        case .serif: return .serif
        case .rounded: return .rounded
        case .monospaced: return .monospaced
        }
    }
}

extension SecretCategory {
    var title: String {
        switch self {
        case .login: return L("Hesap")
        case .card: return L("Kart")
        case .wifi: return "Wi-Fi"
        case .server: return L("Sunucu")
        case .note: return L("Gizli not")
        case .other: return L("Diğer")
        }
    }

    var symbol: String {
        switch self {
        case .login: return "person.crop.circle.fill"
        case .card: return "creditcard.fill"
        case .wifi: return "wifi"
        case .server: return "server.rack"
        case .note: return "lock.doc.fill"
        case .other: return "key.fill"
        }
    }
}

enum Format {
    static let bytes: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    static func size(_ bytes: Int64) -> String { self.bytes.string(fromByteCount: bytes) }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(Localization.locale))
    }

    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Localization.locale
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
