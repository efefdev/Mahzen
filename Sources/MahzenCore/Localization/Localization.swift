import Foundation

/// Arayüz dili. Kaynak metinler Türkçedir; İngilizce karşılıkları `englishStrings` tablosundadır.
public enum Language: String, CaseIterable, Sendable {
    case tr, en
}

public enum Localization {
    /// Kullanıcının Ayarlar'da elle seçtiği dil: "tr", "en" ya da kayıt yoksa sistem dili.
    public static let overrideKey = "language"

    /// Açılış anındaki elle seçim; Ayarlar, yeniden açma gerekip gerekmediğini bununla anlar.
    public static let overrideAtLaunch: String? = UserDefaults.standard.string(forKey: overrideKey)

    /// Etkin dil. Açılışta bir kez belirlenir; dil değişikliği uygulama yeniden açılınca geçerli olur.
    public static var language: Language = initialLanguage()

    /// Tarih ve göreli zaman metinleri için: dil etkin dilden, bölge ayarları sistemden.
    public static var locale: Locale {
        switch language {
        case .tr: return Locale(identifier: "tr_TR")
        case .en: return Locale(languageCode: .english, languageRegion: Locale.current.region)
        }
    }

    /// Sistem tercihlerine göre dil: Türkçe tercih ediliyorsa Türkçe, diğer her durumda İngilizce.
    public static func systemLanguage(preferences: [String] = Locale.preferredLanguages) -> Language {
        for identifier in preferences {
            let code = identifier.lowercased()
            if code == "tr" || code.hasPrefix("tr-") || code.hasPrefix("tr_") { return .tr }
            if code == "en" || code.hasPrefix("en-") || code.hasPrefix("en_") { return .en }
        }
        return .en
    }

    static func initialLanguage() -> Language {
        if let raw = overrideAtLaunch, let chosen = Language(rawValue: raw) {
            return chosen
        }
        return systemLanguage()
    }

    static func template(_ key: String, count: Int? = nil) -> String {
        guard language == .en, let value = englishStrings[key] else { return key }
        guard let count else { return value }
        let forms = value.components(separatedBy: "|")
        return forms.count == 2 ? forms[count == 1 ? 0 : 1] : value
    }

    static func fill(_ template: String, _ args: [Any]) -> String {
        guard !args.isEmpty else { return template }
        var out = template
        for (i, arg) in args.enumerated() {
            out = out.replacingOccurrences(of: "{\(i)}", with: String(describing: arg))
        }
        return out
    }
}

/// Türkçe kaynak metni etkin dile çevirir. Değişkenler `{0}`, `{1}`… yer tutucularına yerleştirilir.
public func L(_ key: String, _ args: Any...) -> String {
    Localization.fill(Localization.template(key), args)
}

/// Sayıya göre tekil/çoğul biçimi seçer; sayı `{0}` yer tutucusuna yerleştirilir.
public func LN(_ key: String, _ count: Int, _ args: Any...) -> String {
    Localization.fill(Localization.template(key, count: count), [count] + args)
}
