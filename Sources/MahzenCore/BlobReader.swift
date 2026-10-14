import CryptoKit
import Foundation

/// Şifreli bir dosyanın istenen bayt aralığını, yalnızca ilgili parçaları çözerek okur.
/// Video/ses oynatma ve önizleme için: düz içerik diske hiç yazılmaz.
public final class BlobReader: @unchecked Sendable {
    public let plainSize: Int64
    let chunkSize: Int
    let chunkCount: Int
    private let handle: FileHandle
    private let key: SymmetricKey
    private let header: Data
    private let blobSize: Int64
    private let lock = NSLock()
    private var cachedIndex = -1
    private var cachedChunk = Data()

    public init(url: URL, key: SymmetricKey) throws {
        handle = try FileHandle(forReadingFrom: url)
        self.key = key
        header = Data(try handle.read(upToCount: BlobCrypto.headerSize) ?? Data())
        guard header.count == BlobCrypto.headerSize, header.prefix(4) == BlobCrypto.magic else {
            throw VaultError.corrupted("dosya başlığı geçersiz")
        }
        chunkSize = header.suffix(4).reduce(0) { ($0 << 8) | Int($1) }
        guard (4096...(64 << 20)).contains(chunkSize) else { throw VaultError.corrupted("parça boyutu geçersiz") }
        blobSize = Int64(try handle.seekToEnd())
        let body = blobSize - Int64(BlobCrypto.headerSize)
        let full = Int64(chunkSize + BlobCrypto.tagSize)
        guard body >= Int64(BlobCrypto.tagSize) else { throw VaultError.corrupted("dosya kesik") }
        chunkCount = Int((body + full - 1) / full)
        plainSize = body - Int64(chunkCount * BlobCrypto.tagSize)
    }

    deinit { try? handle.close() }

    /// `offset`'ten başlayarak en fazla `length` bayt döndürür (dosya sonunda daha az).
    public func read(offset: Int64, length: Int) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard offset >= 0, offset < plainSize, length > 0 else { return Data() }
        let end = min(offset + Int64(length), plainSize)
        var out = Data(capacity: Int(end - offset))
        var position = offset
        while position < end {
            let index = Int(position / Int64(chunkSize))
            let chunk = try decryptChunk(index)
            let start = Int(position - Int64(index) * Int64(chunkSize))
            let take = min(chunk.count - start, Int(end - position))
            guard take > 0 else { throw VaultError.corrupted("beklenmeyen dosya sonu") }
            out.append(chunk[(chunk.startIndex + start)..<(chunk.startIndex + start + take)])
            position += Int64(take)
        }
        return out
    }

    private func decryptChunk(_ index: Int) throws -> Data {
        if index == cachedIndex { return cachedChunk }
        let full = chunkSize + BlobCrypto.tagSize
        let start = Int64(BlobCrypto.headerSize) + Int64(index) * Int64(full)
        let length = Int(min(Int64(full), blobSize - start))
        try handle.seek(toOffset: UInt64(start))
        let raw = try handle.read(upToCount: length) ?? Data()
        guard raw.count == length, length >= BlobCrypto.tagSize else { throw VaultError.corrupted("dosya kesik") }
        let isFinal = index == chunkCount - 1
        let box = try AES.GCM.SealedBox(
            nonce: BlobCrypto.nonce(index: UInt64(index), isFinal: isFinal),
            ciphertext: raw.prefix(raw.count - BlobCrypto.tagSize),
            tag: raw.suffix(BlobCrypto.tagSize)
        )
        do {
            cachedChunk = try AES.GCM.open(box, using: key, authenticating: header)
        } catch {
            throw VaultError.corrupted("içerik doğrulanamadı")
        }
        cachedIndex = index
        return cachedChunk
    }
}
