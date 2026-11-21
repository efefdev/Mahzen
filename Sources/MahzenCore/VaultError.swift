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
            return L("Parola yanlış.")
        case .corrupted(let detail):
            return L("Kasa verisi doğrulanamadı: {0}", detail)
        case .notAVault:
            return L("Bu klasör bir Mahzen kasası değil.")
        case .alreadyExists:
            return L("Bu konumda zaten bir kasa var.")
        case .unsupportedVersion(let v):
            return L("Bu kasa daha yeni bir Mahzen sürümüyle oluşturulmuş (biçim {0}).", v)
        case .kdfFailed:
            return L("Anahtar türetilemedi.")
        case .passwordTooShort(let min):
            return L("Parola en az {0} karakter olmalı.", min)
        }
    }
}
