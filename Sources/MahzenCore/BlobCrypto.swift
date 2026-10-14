import CryptoKit
import Foundation

/// Büyük dosyalar için parçalı AES-256-GCM akışı. Dosya belleğe tümüyle alınmadan şifrelenir/çözülür.
///
/// Biçim: `"MHZ1"` + parça boyutu (UInt32, big-endian), ardından her parça için `şifreli metin + 16 bayt etiket`.
/// Her dosyanın anahtarı kendine özeldir; nonce = parça sırası (8 bayt) + son parça bayrağı (4 bayt).
/// Böylece parçaların yer değiştirmesi, kesilmesi veya eklenmesi doğrulamada yakalanır.
public enum BlobCrypto {
    static let magic = Data("MHZ1".utf8)
    public static let defaultChunkSize = 1 << 20
    static let tagSize = 16
    static let headerSize = 8

    static func header(chunkSize: Int) -> Data {
        var h = magic
        withUnsafeBytes(of: UInt32(chunkSize).bigEndian) { h.append(contentsOf: $0) }
        return h
    }

    static func nonce(index: UInt64, isFinal: Bool) throws -> AES.GCM.Nonce {
        var d = Data()
        withUnsafeBytes(of: index.bigEndian) { d.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(isFinal ? 1 : 0).bigEndian) { d.append(contentsOf: $0) }
        return try AES.GCM.Nonce(data: d)
    }

    /// `read(n)` en fazla n bayt döndürür; yalnızca dosya sonunda n'den az döndürmelidir.
    public static func encrypt(
        read: (Int) throws -> Data,
        write: (Data) throws -> Void,
        key: SymmetricKey,
        chunkSize: Int = defaultChunkSize,
        progress: ((Int) throws -> Void)? = nil
    ) throws {
        let hdr = header(chunkSize: chunkSize)
        try write(hdr)
        var index: UInt64 = 0
        var current = try read(chunkSize)
        while true {
            let next = current.count == chunkSize ? try read(chunkSize) : Data()
            let isFinal = next.isEmpty
            let box = try AES.GCM.seal(current, using: key, nonce: nonce(index: index, isFinal: isFinal), authenticating: hdr)
            try write(box.ciphertext + box.tag)
            try progress?(current.count)
            if isFinal { return }
            current = next
            index += 1
        }
    }

    public static func decrypt(
        read: (Int) throws -> Data,
        write: (Data) throws -> Void,
        key: SymmetricKey,
        progress: ((Int) throws -> Void)? = nil
    ) throws {
        let hdr = Data(try read(headerSize))
        guard hdr.count == headerSize, hdr.prefix(4) == magic else {
            throw VaultError.corrupted("dosya başlığı geçersiz")
        }
        let chunkSize = hdr.suffix(4).reduce(0) { ($0 << 8) | Int($1) }
        guard (4096...(64 << 20)).contains(chunkSize) else {
            throw VaultError.corrupted("parça boyutu geçersiz")
        }
        let full = chunkSize + tagSize
        var index: UInt64 = 0
        var current = Data(try read(full))
        while true {
            guard current.count >= tagSize else { throw VaultError.corrupted("dosya kesik") }
            let next = current.count == full ? Data(try read(full)) : Data()
            let isFinal = next.isEmpty
            let box = try AES.GCM.SealedBox(
                nonce: nonce(index: index, isFinal: isFinal),
                ciphertext: current.prefix(current.count - tagSize),
                tag: current.suffix(tagSize)
            )
            let plain: Data
            do {
                plain = try AES.GCM.open(box, using: key, authenticating: hdr)
            } catch {
                throw VaultError.corrupted("içerik doğrulanamadı (bozulmuş, değiştirilmiş veya yanlış anahtar)")
            }
            try write(plain)
            try progress?(plain.count)
            if isFinal { return }
            current = next
            index += 1
        }
    }

    // MARK: - Dosya ve bellek yardımcıları

    /// Şifrelerken düz içeriğin SHA-256 özetini de hesaplar (mükerrer dosya tespiti için).
    @discardableResult
    public static func encryptFile(at source: URL, to destination: URL, key: SymmetricKey, progress: ((Int) throws -> Void)? = nil) throws -> SHA256.Digest {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        var hasher = SHA256()
        try writeAtomically(to: destination) { out in
            try encrypt(
                read: { n in
                    let chunk = try readFully(input, n)
                    hasher.update(data: chunk)
                    return chunk
                },
                write: { try out.write(contentsOf: $0) }, key: key, progress: progress
            )
        }
        return hasher.finalize()
    }

    public static func decryptFile(at source: URL, to destination: URL, key: SymmetricKey, progress: ((Int) throws -> Void)? = nil) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        try writeAtomically(to: destination) { out in
            try decrypt(read: { try readFully(input, $0) }, write: { try out.write(contentsOf: $0) }, key: key, progress: progress)
        }
    }

    public static func encrypt(data: Data, key: SymmetricKey, chunkSize: Int = defaultChunkSize) throws -> Data {
        var reader = DataReader(data: data)
        var out = Data()
        try encrypt(read: { reader.read($0) }, write: { out.append($0) }, key: key, chunkSize: chunkSize)
        return out
    }

    public static func decrypt(data: Data, key: SymmetricKey) throws -> Data {
        var reader = DataReader(data: data)
        var out = Data()
        try decrypt(read: { reader.read($0) }, write: { out.append($0) }, key: key)
        return out
    }

    public static func decryptFileToData(at source: URL, key: SymmetricKey) throws -> Data {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        var out = Data()
        try decrypt(read: { try readFully(input, $0) }, write: { out.append($0) }, key: key)
        return out
    }

    static func readFully(_ handle: FileHandle, _ count: Int) throws -> Data {
        var buffer = Data()
        while buffer.count < count {
            guard let chunk = try handle.read(upToCount: count - buffer.count), !chunk.isEmpty else { break }
            buffer.append(chunk)
        }
        return buffer
    }

    /// Önce gizli bir geçici dosyaya yazar, başarılıysa yerine taşır; yarım dosya bırakmaz.
    static func writeAtomically(to destination: URL, _ body: (FileHandle) throws -> Void) throws {
        let fm = FileManager.default
        let tmp = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        guard fm.createFile(atPath: tmp.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: tmp.path])
        }
        do {
            let out = try FileHandle(forWritingTo: tmp)
            do {
                try body(out)
                try out.synchronize()
                try out.close()
            } catch {
                try? out.close()
                throw error
            }
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: tmp, to: destination)
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
    }
}

struct DataReader {
    let data: Data
    var offset = 0

    mutating func read(_ count: Int) -> Data {
        let end = min(offset + count, data.count)
        defer { offset = end }
        return data.subdata(in: (data.startIndex + offset)..<(data.startIndex + end))
    }
}
