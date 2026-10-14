import Foundation

/// Yanlış parola sınırı: art arda belirli sayıda yanlış paroladan sonra kasanın anahtarları yok edilir.
///
/// Ayar ve sayaç kilitliyken de okunabilmesi için şifresiz başlıkta (`vault.json`) durur. Sınır aşılınca
/// sarılmış ana anahtarı taşıyan `vault.json` (ve varsa `vault.json.bak`) rastgele baytlarla ezilip silinir.
/// Ana anahtar başka hiçbir yerde olmadığından kasadaki dosyalar, notlar ve parolalar kalıcı olarak çözülemez.
///
/// Sınırlar: bu koruma Mahzen uygulamaları içindir. Kasa klasörünü önceden kopyalayan ya da `vault.json`'u
/// elle düzenleyen biri sayaçtan etkilenmez; alınmış yedekler de kendi başlıklarıyla açılmaya devam eder.
/// SSD'lerde ezilen baytların fiziksel kopyası denetleyicide bir süre kalabilir.
public enum FailedUnlockOutcome: Equatable, Sendable {
    /// Deneme sayıldı. `remaining`: anahtarlar yok edilmeden önce kalan deneme (sınır kapalıysa `nil`).
    case counted(remaining: Int?)
    /// Sınır aşıldı; anahtarlar yok edildi.
    case wiped
}

extension Vault {
    public static let autoWipeRange = 3...99
    public static let defaultAutoWipeAttempts = 5

    /// Yanlış bir parola denemesini kaydeder. Sınır açık ve aşıldıysa anahtarları yok eder.
    /// Sayaç yazılamazsa (ör. salt okunur disk) deneme sayılmaz, hata fırlatılmaz.
    public static func recordFailedAttempt(at folder: URL) throws -> FailedUnlockOutcome {
        var header = try readHeader(at: folder)
        guard let limit = header.wipeAfterFailedAttempts, limit > 0 else { return .counted(remaining: nil) }
        let count = (header.failedAttempts ?? 0) + 1
        if count >= limit {
            try destroyKeys(at: folder)
            return .wiped
        }
        header.failedAttempts = count
        try? writeHeader(header, to: folder)
        return .counted(remaining: limit - count)
    }

    /// Kalan deneme sayısı (sınır kapalıysa `nil`). Kilit ekranında göstermek için.
    public static func remainingAttempts(at folder: URL) -> Int? {
        guard let header = try? readHeader(at: folder), let limit = header.wipeAfterFailedAttempts, limit > 0 else { return nil }
        return max(limit - (header.failedAttempts ?? 0), 0)
    }

    /// Başarılı açılıştan sonra sayacı sıfırlar.
    public func clearFailedAttempts() {
        guard (header.failedAttempts ?? 0) > 0 else { return }
        var updated = header
        updated.failedAttempts = nil
        if (try? Self.writeHeader(updated, to: folder)) != nil { setHeader(updated) }
    }

    /// Sınırı açar (`attempts` dolu) veya kapatır (`nil`). Sayaç sıfırlanır.
    public func setAutoWipe(attempts: Int?) throws {
        if let attempts, !Self.autoWipeRange.contains(attempts) {
            throw VaultError.corrupted("deneme sınırı \(Self.autoWipeRange.lowerBound)–\(Self.autoWipeRange.upperBound) arasında olmalı")
        }
        var updated = header
        updated.wipeAfterFailedAttempts = attempts
        updated.failedAttempts = nil
        try Self.writeHeader(updated, to: folder)
        setHeader(updated)
    }

    /// Ana anahtarı taşıyan başlık dosyalarını rastgele baytlarla ezip siler. Geri alınamaz.
    public static func destroyKeys(at folder: URL) throws {
        let fm = FileManager.default
        var firstError: Error?
        for name in [headerName, headerBackupName] {
            let url = folder.appendingPathComponent(name)
            guard fm.fileExists(atPath: url.path) else { continue }
            do {
                let size = (try fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
                let handle = try FileHandle(forWritingTo: url)
                try handle.write(contentsOf: Crypto.randomBytes(max(size, 512)))
                try handle.synchronize()
                try handle.close()
                try fm.removeItem(at: url)
            } catch {
                // Ezilemese bile silmeyi dene.
                if (try? fm.removeItem(at: url)) == nil, firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }
}
