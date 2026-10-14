import CryptoKit
import Foundation

public struct KDFParams: Codable, Sendable, Equatable {
    public static let pbkdf2 = "PBKDF2-HMAC-SHA512"
    public static let argon2id = "Argon2id"

    public var algorithm: String
    /// PBKDF2'de tur sayısı, Argon2id'de geçiş (t) sayısı.
    public var iterations: UInt32
    public var salt: Data
    public var memoryKiB: UInt32?
    public var parallelism: UInt32?

    public init(algorithm: String, iterations: UInt32, salt: Data, memoryKiB: UInt32? = nil, parallelism: UInt32? = nil) {
        self.algorithm = algorithm
        self.iterations = iterations
        self.salt = salt
        self.memoryKiB = memoryKiB
        self.parallelism = parallelism
    }

    public var summary: String {
        if algorithm == Self.argon2id, let memoryKiB, let parallelism {
            return "Argon2id · \(memoryKiB / 1024) MB · \(iterations) geçiş · \(parallelism) iş parçacığı"
        }
        return "PBKDF2-HMAC-SHA512 · \(iterations.formatted()) tur"
    }
}

/// `vault.json`: şifrelenmemiş tek dosya. Yalnızca anahtarı açmak için gereken bilgileri içerir, sır içermez.
public struct VaultHeader: Codable, Sendable {
    public var format = "mahzen-vault"
    public var version = Vault.currentVersion
    public var vaultID: UUID
    public var createdAt: Date
    public var cipher = "AES-256-GCM"
    public var kdf: KDFParams
    public var wrappedMasterKey: Data
    // Bilerek anahtar dosyası alanı yok: başlıktan kasanın anahtar dosyası isteyip istemediği anlaşılamaz.
}

/// Açılmış bir kasa. Anahtarlar yalnızca bu nesne yaşadığı sürece bellekte durur.
///
/// Klasör düzeni:
/// ```
/// vault.json          başlık (tuz, tur sayısı, sarılmış ana anahtar)
/// index.enc           şifreli dizin (+ index.enc.bak bir önceki sürüm)
/// blobs/xx/<id>.mhz   şifreli dosya içerikleri
/// thumbs/<id>.mhz     şifreli küçük resimler
/// ```
public final class Vault: @unchecked Sendable {
    /// 2: Argon2id + klasör/etiket/çöp kutusu alanları. Sürüm 1 kasalar açılışta otomatik yükseltilir.
    /// Anahtar dosyalı kasalar da sürüm 2'dir; dışarıdan ayırt edilemezler.
    public static let currentVersion = 2
    public static let keyfileLength = 64
    public static let minimumPasswordLength = 10

    static let headerName = "vault.json"
    static let headerBackupName = "vault.json.bak"
    static let indexName = "index.enc"
    static let indexBackupName = "index.enc.bak"

    public let folder: URL
    public private(set) var header: VaultHeader
    private let master: SymmetricKey
    private var keyfile: Data?
    let indexKey: SymmetricKey

    private init(folder: URL, header: VaultHeader, master: SymmetricKey, keyfile: Data?) {
        self.folder = folder
        self.header = header
        self.master = master
        self.keyfile = keyfile
        self.indexKey = Crypto.subkey(master, vaultID: header.vaultID, info: "mahzen.index.v1")
    }

    public static func exists(at folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(headerName).path)
    }

    // MARK: - Oluşturma / açma

    /// Bu nesne bir anahtar dosyasıyla mı açıldı? (Yalnızca açık kasa bilir; başlık bunu söylemez.)
    public var requiresKeyfile: Bool { keyfile != nil }

    /// Kasayı açan anahtar dosyası (yedeğini dışa aktarmak için). Kasa kilitlenince bu nesneyle birlikte gider.
    public var keyfileData: Data? { keyfile }

    public static func generateKeyfile() -> Data { Crypto.randomBytes(keyfileLength) }

    /// Sarma anahtarı: Argon2id(parola); anahtar dosyası varsa ikisi HKDF ile birleştirilir.
    /// Anahtar dosyası eksik ya da yanlışsa sonuç yalnızca "yanlış parola"dır; ayrı bir hata yoktur.
    static func keyEncryptionKey(password: String, params: KDFParams, keyfile: Data?) throws -> SymmetricKey {
        let fromPassword = try Crypto.deriveKey(password: password, params: params)
        guard let keyfile else { return fromPassword }
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: fromPassword.rawData + keyfile),
            salt: params.salt,
            info: Data("mahzen.kek.keyfile.v1".utf8),
            outputByteCount: 32
        )
    }

    public static func create(at folder: URL, password: String, kdf: KDFSettings = .recommended, keyfile: Data? = nil) throws -> Vault {
        guard password.count >= minimumPasswordLength else { throw VaultError.passwordTooShort(minimumPasswordLength) }
        guard !exists(at: folder) else { throw VaultError.alreadyExists }
        let fm = FileManager.default
        try fm.createDirectory(at: folder.appendingPathComponent("blobs"), withIntermediateDirectories: true)
        try fm.createDirectory(at: folder.appendingPathComponent("thumbs"), withIntermediateDirectories: true)

        let vaultID = UUID()
        let salt = Crypto.randomBytes(32)
        let params = kdf.params(salt: salt)
        let kek = try keyEncryptionKey(password: password, params: params, keyfile: keyfile)
        let master = SymmetricKey(size: .bits256)
        let header = VaultHeader(
            vaultID: vaultID,
            createdAt: Date(),
            kdf: params,
            wrappedMasterKey: try Crypto.seal(master.rawData, key: kek, aad: wrapAAD(vaultID))
        )
        try writeHeader(header, to: folder)
        let vault = Vault(folder: folder, header: header, master: master, keyfile: keyfile)
        try vault.saveIndex(VaultIndex())
        try? readme.write(to: folder.appendingPathComponent("OKU-BENİ.txt"), atomically: true, encoding: .utf8)
        return vault
    }

    public static func readHeader(at folder: URL) throws -> VaultHeader {
        let url = folder.appendingPathComponent(headerName)
        guard let data = try? Data(contentsOf: url) else { throw VaultError.notAVault }
        let header: VaultHeader
        do {
            header = try decoder().decode(VaultHeader.self, from: data)
        } catch {
            throw VaultError.corrupted("vault.json okunamadı")
        }
        guard header.format == "mahzen-vault" else { throw VaultError.notAVault }
        guard header.version <= currentVersion else { throw VaultError.unsupportedVersion(header.version) }
        return header
    }

    public static func unlock(at folder: URL, password: String, keyfile: Data? = nil) throws -> Vault {
        let header = try readHeader(at: folder)
        let kek = try keyEncryptionKey(password: password, params: header.kdf, keyfile: keyfile)
        let masterData: Data
        do {
            masterData = try Crypto.open(header.wrappedMasterKey, key: kek, aad: wrapAAD(header.vaultID))
        } catch {
            throw VaultError.wrongPassword
        }
        return Vault(folder: folder, header: header, master: SymmetricKey(data: masterData), keyfile: keyfile)
    }

    /// Ana anahtar değişmez, yalnızca yeni parolayla yeniden sarılır; dosyaların yeniden şifrelenmesi gerekmez.
    public func changePassword(current: String, new: String, kdf: KDFSettings = .recommended) throws {
        guard new.count >= Self.minimumPasswordLength else { throw VaultError.passwordTooShort(Self.minimumPasswordLength) }
        _ = try Vault.unlock(at: folder, password: current, keyfile: keyfile)
        try rewrap(password: new, kdf: kdf, keyfile: keyfile)
    }

    /// Anahtar dosyası zorunluluğunu açar (`newKeyfile` dolu) veya kapatır (`nil`). Parola doğrulanır.
    /// Ana anahtar değişmez; dosyaların yeniden şifrelenmesi gerekmez.
    public func setKeyfile(_ newKeyfile: Data?, password: String, kdf: KDFSettings = .recommended) throws {
        if let newKeyfile, newKeyfile.count < 32 { throw VaultError.corrupted("anahtar dosyası çok kısa") }
        _ = try Vault.unlock(at: folder, password: password, keyfile: keyfile)
        try rewrap(password: password, kdf: kdf, keyfile: newKeyfile)
        keyfile = newKeyfile
    }

    /// Eski (PBKDF2) kasa mı? Doğru parolayla açıldıktan sonra `upgradeKDF` ile yükseltilir.
    public var needsKDFUpgrade: Bool { header.kdf.algorithm != KDFParams.argon2id || header.version < 2 }

    /// Yalnızca bu nesneyi açan parolayla çağrılmalıdır.
    public func upgradeKDF(password: String, kdf: KDFSettings = .recommended) throws {
        try rewrap(password: password, kdf: kdf, keyfile: keyfile)
    }

    private func rewrap(password: String, kdf: KDFSettings, keyfile: Data?) throws {
        let params = kdf.params(salt: Crypto.randomBytes(32))
        let kek = try Self.keyEncryptionKey(password: password, params: params, keyfile: keyfile)
        var updated = header
        updated.version = Self.currentVersion
        updated.kdf = params
        updated.wrappedMasterKey = try Crypto.seal(master.rawData, key: kek, aad: Self.wrapAAD(header.vaultID))
        // Yazmadan önce yeni başlığın gerçekten açılabildiğini doğrula.
        let check = try Crypto.open(updated.wrappedMasterKey, key: kek, aad: Self.wrapAAD(header.vaultID))
        guard check == master.rawData else { throw VaultError.kdfFailed }
        let fm = FileManager.default
        let headerURL = folder.appendingPathComponent(Self.headerName)
        let backupURL = folder.appendingPathComponent(Self.headerBackupName)
        try? fm.removeItem(at: backupURL)
        try? fm.copyItem(at: headerURL, to: backupURL)
        try Self.writeHeader(updated, to: folder)
        try? fm.removeItem(at: backupURL)
        header = updated
    }

    // MARK: - Dizin

    public func loadIndex() throws -> (index: VaultIndex, recoveredFromBackup: Bool) {
        do {
            return (try readIndex(folder.appendingPathComponent(Self.indexName)), false)
        } catch {
            if let backup = try? readIndex(folder.appendingPathComponent(Self.indexBackupName)) {
                return (backup, true)
            }
            throw error
        }
    }

    public func saveIndex(_ index: VaultIndex) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let sealed = try Crypto.seal(try encoder.encode(index), key: indexKey, aad: indexAAD)
        let fm = FileManager.default
        let url = folder.appendingPathComponent(Self.indexName)
        let backup = folder.appendingPathComponent(Self.indexBackupName)
        if fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: backup)
            try? fm.copyItem(at: url, to: backup)
        }
        try sealed.write(to: url, options: .atomic)
    }

    private func readIndex(_ url: URL) throws -> VaultIndex {
        guard let data = try? Data(contentsOf: url) else { throw VaultError.corrupted("dizin dosyası bulunamadı") }
        let plain: Data
        do {
            plain = try Crypto.open(data, key: indexKey, aad: indexAAD)
        } catch {
            throw VaultError.corrupted("dizin doğrulanamadı")
        }
        return try Self.decoder().decode(VaultIndex.self, from: plain)
    }

    // MARK: - Dosyalar

    public func blobURL(_ id: UUID) -> URL {
        let name = id.uuidString.lowercased()
        return folder.appendingPathComponent("blobs")
            .appendingPathComponent(String(name.prefix(2)))
            .appendingPathComponent(name + ".mhz")
    }

    public func thumbnailURL(_ id: UUID) -> URL {
        folder.appendingPathComponent("thumbs").appendingPathComponent(id.uuidString.lowercased() + ".mhz")
    }

    func fileKey(_ id: UUID) -> SymmetricKey {
        Crypto.subkey(master, vaultID: header.vaultID, info: "mahzen.file.v1|\(id.uuidString)")
    }

    private func thumbnailKey(_ id: UUID) -> SymmetricKey {
        Crypto.subkey(master, vaultID: header.vaultID, info: "mahzen.thumb.v1|\(id.uuidString)")
    }

    /// Dosyayı şifreleyip kasaya yazar; düz içeriğin SHA-256 özetini (onaltılık) döndürür.
    @discardableResult
    public func importFile(at source: URL, id: UUID, progress: ((Int) throws -> Void)? = nil) throws -> String {
        let dest = blobURL(id)
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        let digest = try BlobCrypto.encryptFile(at: source, to: dest, key: fileKey(id), progress: progress)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public func exportFile(_ id: UUID, to destination: URL, progress: ((Int) throws -> Void)? = nil) throws {
        try BlobCrypto.decryptFile(at: blobURL(id), to: destination, key: fileKey(id), progress: progress)
    }

    /// Dosyanın istenen aralıklarını belleğe çözerek okumak için (video/ses oynatma).
    public func openReader(_ id: UUID) throws -> BlobReader {
        try BlobReader(url: blobURL(id), key: fileKey(id))
    }

    public func readFile(_ id: UUID) throws -> Data {
        try BlobCrypto.decryptFileToData(at: blobURL(id), key: fileKey(id))
    }

    public func writeThumbnail(_ data: Data, id: UUID) throws {
        let sealed = try BlobCrypto.encrypt(data: data, key: thumbnailKey(id))
        try FileManager.default.createDirectory(at: thumbnailURL(id).deletingLastPathComponent(), withIntermediateDirectories: true)
        try sealed.write(to: thumbnailURL(id), options: .atomic)
    }

    public func readThumbnail(_ id: UUID) throws -> Data {
        try BlobCrypto.decrypt(data: Data(contentsOf: thumbnailURL(id)), key: thumbnailKey(id))
    }

    public func deleteFile(_ id: UUID) {
        try? FileManager.default.removeItem(at: blobURL(id))
        try? FileManager.default.removeItem(at: thumbnailURL(id))
    }

    // MARK: - Yardımcılar

    var indexAAD: Data { Data("mahzen.index.v1|\(header.vaultID.uuidString)".utf8) }

    static func wrapAAD(_ vaultID: UUID) -> Data {
        Data("mahzen.keywrap.v1|\(vaultID.uuidString)".utf8)
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func writeHeader(_ header: VaultHeader, to folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(header).write(to: folder.appendingPathComponent(headerName), options: .atomic)
    }

    static let readme = """
    Bu klasör bir Mahzen şifreli kasasıdır.

    • İçindeki her şey (dosyalar, dosya adları, notlar, parolalar) AES-256-GCM ile şifrelidir.
    • Açmak için Mahzen uygulamasını ve kasa parolasını kullanın.
    • Klasördeki dosyaları elle değiştirmeyin, silmeyin veya yeniden adlandırmayın.
    • Yedek almak için bu klasörün tamamını başka bir diske kopyalayın.
    • Parola unutulursa veriler kurtarılamaz; parolanın bir kopyasını güvenli bir yerde saklayın.
    """
}
