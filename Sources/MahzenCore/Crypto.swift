import CArgon2
import CommonCrypto
import CryptoKit
import Foundation
import Security

/// Paroladan anahtar türetme ayarı.
public enum KDFSettings: Sendable, Equatable {
    case pbkdf2(iterations: UInt32)
    case argon2id(time: UInt32, memoryKiB: UInt32, parallelism: UInt32)

    /// Varsayılan: Argon2id, 1 GB bellek, 3 geçiş, 4 iş parçacığı (release derlemede Apple Silicon'da ~0,7 sn).
    public static let recommended = KDFSettings.argon2id(time: 3, memoryKiB: 1024 * 1024, parallelism: 4)

    func params(salt: Data) -> KDFParams {
        switch self {
        case .pbkdf2(let iterations):
            return KDFParams(algorithm: KDFParams.pbkdf2, iterations: iterations, salt: salt)
        case .argon2id(let time, let memory, let parallelism):
            return KDFParams(algorithm: KDFParams.argon2id, iterations: time, salt: salt, memoryKiB: memory, parallelism: parallelism)
        }
    }
}

/// Kasanın kullandığı ilkel şifreleme işlemleri.
///
/// - Paroladan anahtar: Argon2id (bellek yoğun; eski kasalarda PBKDF2-HMAC-SHA512), tuz 32 bayt.
/// - Ana anahtar: rastgele 256 bit; paroladan türetilen anahtarla AES-256-GCM ile sarılır.
/// - Alt anahtarlar: ana anahtardan HKDF-SHA256 ile (dizin, her dosya ve her küçük resim için ayrı).
public enum Crypto {
    public static let minimumIterations: UInt32 = 600_000

    public static func deriveKey(password: String, params: KDFParams) throws -> SymmetricKey {
        switch params.algorithm {
        case KDFParams.pbkdf2:
            return try deriveKey(password: password, salt: params.salt, iterations: params.iterations)
        case KDFParams.argon2id:
            guard let memory = params.memoryKiB, let parallelism = params.parallelism else {
                throw VaultError.corrupted("Argon2id ayarları eksik")
            }
            return try argon2id(password: password, salt: params.salt, time: params.iterations, memoryKiB: memory, parallelism: parallelism)
        default:
            throw VaultError.corrupted("bilinmeyen anahtar türetme yöntemi: \(params.algorithm)")
        }
    }

    public static func argon2id(password: String, salt: Data, time: UInt32, memoryKiB: UInt32, parallelism: UInt32) throws -> SymmetricKey {
        let pw = passwordBytes(password)
        var out = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltPtr in
            argon2id_hash_raw(time, memoryKiB, parallelism, pw, pw.count, saltPtr.baseAddress, salt.count, &out, out.count)
        }
        guard status == ARGON2_OK.rawValue else { throw VaultError.kdfFailed }
        return SymmetricKey(data: out)
    }

    public static func randomBytes(_ count: Int) -> Data {
        var data = Data(count: count)
        guard count > 0 else { return data }
        let status = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        precondition(status == errSecSuccess, "Güvenli rastgele sayı üreteci başarısız")
        return data
    }

    /// Parolayı Unicode NFC biçimine getirir; aynı parola farklı klavyelerde aynı baytlara dönüşür.
    static func passwordBytes(_ password: String) -> [CChar] {
        password.precomposedStringWithCanonicalMapping.utf8.map { CChar(bitPattern: $0) }
    }

    public static func deriveKey(password: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        let pw = passwordBytes(password)
        var out = Data(count: 32)
        let status = out.withUnsafeMutableBytes { outPtr in
            salt.withUnsafeBytes { saltPtr in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pw, pw.count,
                    saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512), iterations,
                    outPtr.bindMemory(to: UInt8.self).baseAddress, 32
                )
            }
        }
        guard status == kCCSuccess else { throw VaultError.kdfFailed }
        return SymmetricKey(data: out)
    }

    /// Bu cihazda yaklaşık `milliseconds` sürecek tur sayısı (en az `minimumIterations`).
    public static func calibrateIterations(milliseconds: UInt32 = 1000) -> UInt32 {
        let rounds = CCCalibratePBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2), 24, 32,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA512), 32, milliseconds
        )
        return max(rounds, minimumIterations)
    }

    public static func subkey(_ master: SymmetricKey, vaultID: UUID, info: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: master,
            salt: vaultID.data,
            info: Data(info.utf8),
            outputByteCount: 32
        )
    }

    public static func seal(_ data: Data, key: SymmetricKey, aad: Data) throws -> Data {
        // Varsayılan 12 baytlık rastgele nonce ile `combined` her zaman doludur.
        try AES.GCM.seal(data, using: key, authenticating: aad).combined!
    }

    public static func open(_ data: Data, key: SymmetricKey, aad: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key, authenticating: aad)
    }
}

extension UUID {
    var data: Data { withUnsafeBytes(of: uuid) { Data($0) } }
}

extension SymmetricKey {
    var rawData: Data { withUnsafeBytes { Data($0) } }
}
