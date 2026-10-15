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
        case .indigo: return "Çivit"
        case .blue: return "Mavi"
        case .teal: return "Turkuaz"
        case .green: return "Yeşil"
        case .orange: return "Turuncu"
        case .pink: return "Pembe"
        case .red: return "Kırmızı"
        case .purple: return "Mor"
        case .graphite: return "Grafit"
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
        case .system: return "Sistem"
        case .light: return "Açık"
        case .dark: return "Koyu"
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
        case .default: return "Sistem"
        case .serif: return "Serif"
        case .rounded: return "Yuvarlak"
        case .monospaced: return "Eş aralıklı"
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
        case .login: return "Hesap"
        case .card: return "Kart"
        case .wifi: return "Wi-Fi"
        case .server: return "Sunucu"
        case .note: return "Gizli not"
        case .other: return "Diğer"
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
        date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(Locale(identifier: "tr_TR")))
    }

    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }
}
