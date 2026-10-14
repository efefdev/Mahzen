import Foundation

public enum VaultError: LocalizedError, Equatable {
    case wrongPassword
    case corrupted(String)
    case notAVault
    case alreadyExists
    case unsupportedVersion(Int)
    case kdfFailed
    case passwordTooShort(Int)

    public var errorDescription: String? {
        switch self {
        case .wrongPassword:
            return "Parola yanlış."
        case .corrupted(let detail):
            return "Kasa verisi doğrulanamadı: \(detail)"
        case .notAVault:
            return "Bu klasör bir Mahzen kasası değil."
        case .alreadyExists:
            return "Bu konumda zaten bir kasa var."
        case .unsupportedVersion(let v):
            return "Bu kasa daha yeni bir Mahzen sürümüyle oluşturulmuş (biçim \(v))."
        case .kdfFailed:
            return "Anahtar türetilemedi."
        case .passwordTooShort(let min):
            return "Parola en az \(min) karakter olmalı."
        }
    }
}
