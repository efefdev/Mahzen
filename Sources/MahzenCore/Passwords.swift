import Foundation

public enum PasswordGenerator {
    static let upper = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    static let lower = Array("abcdefghijklmnopqrstuvwxyz")
    static let digits = Array("0123456789")
    static let symbols = Array("!@#$%^&*()-_=+[]{};:,.<>?/~")
    static let ambiguous = Set("O0oIl1|`'\"")

    /// Seçilen her karakter sınıfından en az bir karakter içeren, CSPRNG ile üretilmiş parola.
    public static func generate(_ options: GeneratorOptions) -> String {
        var classes: [[Character]] = []
        if options.uppercase { classes.append(upper) }
        if options.lowercase { classes.append(lower) }
        if options.digits { classes.append(digits) }
        if options.symbols { classes.append(symbols) }
        if classes.isEmpty { classes = [lower] }
        if options.avoidAmbiguous {
            classes = classes.map { $0.filter { !ambiguous.contains($0) } }
        }
        let length = max(options.length, classes.count)
        var rng = SystemRandomNumberGenerator()
        var chars = classes.map { $0.randomElement(using: &rng)! }
        let all = classes.flatMap { $0 }
        while chars.count < length { chars.append(all.randomElement(using: &rng)!) }
        chars.shuffle(using: &rng)
        return String(chars)
    }
}

public struct PasswordStrength: Equatable, Sendable {
    /// 0 (çok zayıf) … 4 (çok güçlü)
    public let score: Int
    public let bits: Double

    public var label: String {
        ["Çok zayıf", "Zayıf", "Orta", "Güçlü", "Çok güçlü"][score]
    }

    static let common = ["password", "parola", "sifre", "şifre", "123456", "qwerty", "asdf", "abc123", "111111", "admin", "letmein", "iloveyou"]

    public static func evaluate(_ password: String) -> PasswordStrength {
        guard !password.isEmpty else { return PasswordStrength(score: 0, bits: 0) }
        var pool = 0
        if password.contains(where: { $0.isLowercase && $0.isASCII }) { pool += 26 }
        if password.contains(where: { $0.isUppercase && $0.isASCII }) { pool += 26 }
        if password.contains(where: \.isNumber) { pool += 10 }
        if password.contains(where: { $0.isASCII && !$0.isLetter && !$0.isNumber }) { pool += 33 }
        if password.contains(where: { !$0.isASCII }) { pool += 60 }
        // Tekrarlayan karakterler etkin uzunluğu düşürür ("aaaaaaaaaa" uzun ama zayıf).
        let effectiveLength = Double(min(password.count, Set(password).count * 2))
        var bits = effectiveLength * log2(Double(max(pool, 2)))
        let lowered = password.lowercased()
        if common.contains(where: lowered.contains) { bits = min(bits, 30) }
        let score: Int
        switch bits {
        case ..<36: score = 0
        case ..<50: score = 1
        case ..<64: score = 2
        case ..<90: score = 3
        default: score = 4
        }
        return PasswordStrength(score: score, bits: bits)
    }
}
