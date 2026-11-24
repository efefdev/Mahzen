import CryptoKit
import Foundation

/// Parça parça gelen düz içeriği doğrudan kasanın şifreli dosya biçimine (`BlobCrypto`) yazar.
///
/// Ağdan gelen dosyalar için ("Telefondan Ekle"): içerik bellekte en fazla bir parça kadar tutulur, diske
/// yalnızca şifreli bayt yazılır. Önce gizli bir geçici dosyaya yazılır; `finish()` başarılı olunca yerine
/// taşınır. `cancel()` (ya da bitmeden bırakılması) geçici dosyayı siler; yarım dosya kalmaz.
/// Çıktı, aynı içerikle `BlobCrypto.encrypt` çıktısıyla bayt bayt aynıdır.
public final class BlobWriter {
    public let destination: URL
    public private(set) var plainSize: Int64 = 0

    private let temporary: URL
    private let handle: FileHandle
    private let key: SymmetricKey
    private let chunkSize: Int
    private let header: Data
    private var buffer = Data()
    private var index: UInt64 = 0
    private var hasher = SHA256()
    private var closed = false

    public init(destination: URL, key: SymmetricKey, chunkSize: Int = BlobCrypto.defaultChunkSize) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        self.destination = destination
        temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        guard fm.createFile(atPath: temporary.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: temporary.path])
        }
        do {
            handle = try FileHandle(forWritingTo: temporary)
        } catch {
            try? fm.removeItem(at: temporary)
            throw error
        }
        self.key = key
        self.chunkSize = chunkSize
        header = BlobCrypto.header(chunkSize: chunkSize)
        do {
            try handle.write(contentsOf: header)
        } catch {
            cancel()
            throw error
        }
    }

    deinit { if !closed { cancel() } }

    /// Düz içeriğin bir sonraki bölümünü ekler. Dolan parçalar hemen şifrelenip yazılır; son parça
    /// (dosya sonu bayrağıyla) ancak `finish()` çağrılınca yazılır.
    public func append(_ data: Data) throws {
        precondition(!closed, "BlobWriter kapandı")
        hasher.update(data: data)
        plainSize += Int64(data.count)
        buffer.append(data)
        var offset = buffer.startIndex
        while buffer.endIndex - offset > chunkSize {
            try seal(buffer[offset..<offset + chunkSize], isFinal: false)
            offset += chunkSize
        }
        if offset != buffer.startIndex { buffer = Data(buffer[offset...]) }
    }

    /// Son parçayı yazar, dosyayı diske işler ve yerine taşır. Düz içeriğin SHA-256 özetini (onaltılık) döndürür.
    @discardableResult
    public func finish() throws -> String {
        precondition(!closed, "BlobWriter kapandı")
        do {
            try seal(buffer, isFinal: true)
            buffer = Data()
            try handle.synchronize()
            try handle.close()
            closed = true
            let fm = FileManager.default
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: temporary, to: destination)
        } catch {
            cancel()
            throw error
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Yazmayı bırakır ve geçici dosyayı siler. Birden çok kez çağrılabilir.
    public func cancel() {
        if !closed {
            closed = true
            try? handle.close()
        }
        buffer = Data()
        try? FileManager.default.removeItem(at: temporary)
    }

    private func seal(_ plain: Data, isFinal: Bool) throws {
        let box = try AES.GCM.seal(plain, using: key, nonce: BlobCrypto.nonce(index: index, isFinal: isFinal), authenticating: header)
        try handle.write(contentsOf: box.ciphertext + box.tag)
        index += 1
    }
}

extension Vault {
    /// Kasaya parça parça yazılacak yeni bir dosya başlatır ("Telefondan Ekle"). `finish()` düz içeriğin
    /// SHA-256 özetini döndürür; dizine kayıt eklemek çağıranın işidir.
    public func beginImport(id: UUID) throws -> BlobWriter {
        try BlobWriter(destination: blobURL(id), key: fileKey(id))
    }

    /// Kasa klasörünün bulunduğu diskte kullanılabilir alan (bayt); bilinmiyorsa nil.
    public func availableCapacity() -> Int64? {
        let values = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        if let important = values?.volumeAvailableCapacityForImportantUsage, important > 0 { return important }
        return values?.volumeAvailableCapacity.map(Int64.init)
    }
}
