import CryptoKit
import Foundation

/// "Telefonda Göster" aktarım biçimi: kasadaki dosyalar, yerel ağ üzerinden telefona uçtan uca şifreli gider.
///
/// Oturum anahtarı (256 bit) yalnızca QR kodda, adresin `#` sonrasındadır; tarayıcı bu kısmı sunucuya hiç
/// göndermez. Sunucu kasadaki dosyayı kendi içinde çözer ve bu anahtarla yeniden şifreler; ağda yalnızca
/// şifreli bayt dolaşır. Çözme işi telefondaki tarayıcıda yapılır (ChaCha20-Poly1305, RFC 8439).
///
/// Akış biçimi: art arda çerçeveler. Her çerçeve `uzunluk (UInt32, big-endian)` + `şifreli metin + 16 bayt etiket`.
/// - Nonce (12 bayt) = akış kimliği (UInt32) + parça sırası (UInt64), big-endian.
/// - Ek doğrulanan veri = `"mahzen.phone.v1|"` + son parça bayrağı (`1`/`0`).
/// Böylece akışlar birbirine karıştırılamaz, parçalar yer değiştiremez, akış sondan kesilemez.
public enum PhoneShare {
    public static let chunkSize = 1 << 20
    static let tagSize = 16
    static let aadPrefix = Data("mahzen.phone.v1|".utf8)

    /// Akış kimlikleri: 0 = içerik listesi, 2i+1 = i. dosya, 2i+2 = i. dosyanın küçük resmi.
    public static let manifestStream: UInt32 = 0
    public static func fileStream(_ index: Int) -> UInt32 { UInt32(2 * index + 1) }
    public static func thumbnailStream(_ index: Int) -> UInt32 { UInt32(2 * index + 2) }

    public static func newKey() -> SymmetricKey { SymmetricKey(size: .bits256) }

    static func nonce(stream: UInt32, chunk: UInt64) throws -> ChaChaPoly.Nonce {
        var d = Data()
        withUnsafeBytes(of: stream.bigEndian) { d.append(contentsOf: $0) }
        withUnsafeBytes(of: chunk.bigEndian) { d.append(contentsOf: $0) }
        return try ChaChaPoly.Nonce(data: d)
    }

    static func aad(final: Bool) -> Data { aadPrefix + Data([final ? 0x31 : 0x30]) }

    /// `plainSize` baytlık bir içeriğin şifreli akış uzunluğu (Content-Length için).
    public static func streamLength(plainSize: Int64) -> Int64 {
        let chunks = max(1, (plainSize + Int64(chunkSize) - 1) / Int64(chunkSize))
        return plainSize + chunks * Int64(4 + tagSize)
    }

    /// Bir parçayı çerçeve olarak şifreler.
    public static func sealFrame(_ plain: Data, key: SymmetricKey, stream: UInt32, chunk: UInt64, final: Bool) throws -> Data {
        let box = try ChaChaPoly.seal(plain, using: key, nonce: nonce(stream: stream, chunk: chunk), authenticating: aad(final: final))
        var frame = Data(capacity: 4 + plain.count + tagSize)
        withUnsafeBytes(of: UInt32(plain.count + tagSize).bigEndian) { frame.append(contentsOf: $0) }
        frame.append(box.ciphertext)
        frame.append(box.tag)
        return frame
    }

    /// Bellekteki küçük bir içeriği (liste, küçük resim) tek akış olarak şifreler.
    public static func seal(_ data: Data, key: SymmetricKey, stream: UInt32) throws -> Data {
        var out = Data()
        var offset = 0
        var chunk: UInt64 = 0
        repeat {
            let end = min(offset + chunkSize, data.count)
            let final = end == data.count
            out.append(try sealFrame(data.subdata(in: offset..<end), key: key, stream: stream, chunk: chunk, final: final))
            offset = end
            chunk += 1
        } while offset < data.count
        return out
    }

    /// Bir akışı çözer (testler ve doğrulama için; telefonda aynı işi tarayıcı yapar).
    public static func open(_ stream: Data, key: SymmetricKey, streamID: UInt32) throws -> Data {
        var out = Data()
        var offset = stream.startIndex
        var chunk: UInt64 = 0
        while offset < stream.endIndex {
            guard stream.endIndex - offset >= 4 else { throw VaultError.corrupted("akış kesik") }
            let length = stream[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
            offset += 4
            guard length >= tagSize, stream.endIndex - offset >= length else { throw VaultError.corrupted("akış kesik") }
            let body = stream[offset..<offset + length]
            offset += length
            let final = offset == stream.endIndex
            let box = try ChaChaPoly.SealedBox(
                nonce: nonce(stream: streamID, chunk: chunk),
                ciphertext: body.prefix(length - tagSize),
                tag: body.suffix(tagSize)
            )
            out.append(try ChaChaPoly.open(box, using: key, authenticating: aad(final: final)))
            chunk += 1
        }
        guard chunk > 0 else { throw VaultError.corrupted("akış boş") }
        return out
    }
}

/// Telefona gönderilen içerik listesi. Şifreli gider; dosya adları da ağda görünmez.
public struct PhoneShareManifest: Codable, Sendable {
    public struct Item: Codable, Sendable {
        public var index: Int
        public var name: String
        /// Kasadaki klasör yolu (paylaşılan klasöre göre), ör. ["Tatil", "2026"].
        public var path: [String]
        /// "image" ya da "video"
        public var kind: String
        public var mime: String
        public var size: Int64
        public var hasThumbnail: Bool

        public init(index: Int, name: String, path: [String], kind: String, mime: String, size: Int64, hasThumbnail: Bool) {
            self.index = index
            self.name = name
            self.path = path
            self.kind = kind
            self.mime = mime
            self.size = size
            self.hasThumbnail = hasThumbnail
        }
    }

    public var title: String
    /// Paylaşımın sona ereceği an (Unix zamanı, saniye).
    public var expiresAt: Double
    public var items: [Item]

    public init(title: String, expiresAt: Double, items: [Item]) {
        self.title = title
        self.expiresAt = expiresAt
        self.items = items
    }
}
