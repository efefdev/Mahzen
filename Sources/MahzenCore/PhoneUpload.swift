import CryptoKit
import Foundation

/// "Telefondan Ekle": telefondaki tarayıcı dosyaları kendisi şifreleyip yerel ağ üzerinden yükler; bilgisayar
/// gelen akışı bellekte çözer ve doğrudan kasanın şifreli biçimine yazar. Düz içerik hiçbir an diske yazılmaz.
///
/// Şifreleme "Telefonda Göster" ile aynıdır (`PhoneShare`): oturum anahtarı (256 bit) yalnızca QR koddaki adresin
/// `#` sonrasında bulunur, akış biçimi aynı çerçevelerdir (ChaCha20-Poly1305, nonce = akış + parça sırası,
/// ek doğrulanan veri = `"mahzen.phone.v1|"` + son parça bayrağı).
///
/// Akış kimlikleri: 0 = oturum bilgisi (bilgisayar → telefon); n. yükleme için 2n = dosya bilgisi, 2n+1 = içerik
/// (telefon → bilgisayar). Yükleme numaralarını bilgisayar dağıtır ve her birini bir kez kabul eder; böylece
/// aynı anahtarla aynı nonce iki kez kullanılmaz, bir yüklemenin parçaları başka bir yüklemeye taşınamaz.
///
/// Uç noktalar (hepsi `/<jeton>/` altında):
/// - `GET  /`          yükleme sayfası
/// - `GET  s`          oturum bilgisi (şifreli, akış 0)
/// - `POST n`          yeni yükleme numarası: `{"n": 1}`
/// - `POST u/<n>/0`    dosya bilgisi (şifreli, akış 2n, tek akış)
/// - `POST u/<n>/<p>`  içerik çerçeveleri (akış 2n+1), p = 1, 2, … sırayla; sonuncusu `?end=1` ile
/// - `POST x/<n>`      yüklemeyi iptal et
public enum PhoneUpload {
    public static let statusStream: UInt32 = 0
    public static func metaStream(_ number: Int) -> UInt32 { UInt32(2 * number) }
    public static func contentStream(_ number: Int) -> UInt32 { UInt32(2 * number + 1) }

    /// Tek dosya için üst sınır (8 GB).
    public static let maxFileSize: Int64 = 8_000_000_000
    /// Telefonun bir istekte gönderdiği en fazla çerçeve sayısı.
    public static let framesPerPart = 4
    /// Bir içerik isteğinin gövdesi en fazla bu kadar olabilir.
    public static let maxPartLength = framesPerPart * (4 + PhoneShare.StreamDecoder.maxFrameLength)
    /// Dosya bilgisi isteğinin gövdesi en fazla bu kadar olabilir.
    public static let maxMetaLength = 8 * 1024
    /// Aynı anda yarım kalabilecek en fazla yükleme sayısı.
    public static let maxOpenUploads = 4
    /// Bu kadar saniye hiç parça gelmeyen yükleme bırakılır ve geçici dosyası silinir.
    public static let idleTimeout: TimeInterval = 90
    /// Diskte dosyanın kendisinden sonra boş kalması gereken alan.
    public static let reserveSpace: Int64 = 64 << 20
}

/// Telefonun her dosya için gönderdiği bilgi. Şifreli gelir; dosya adı ağda görünmez.
public struct PhoneUploadMeta: Codable, Sendable, Equatable {
    public var name: String
    public var size: Int64
    /// Tarayıcının bildirdiği içerik türü (ör. "image/jpeg"); boş olabilir.
    public var type: String?
    /// Son değiştirilme zamanı (Unix zamanı, milisaniye); tarayıcı vermezse nil.
    public var modified: Double?

    public init(name: String, size: Int64, type: String? = nil, modified: Double? = nil) {
        self.name = name
        self.size = size
        self.type = type
        self.modified = modified
    }

    /// Kasada kullanılacak güvenli dosya adı: yol ayırıcıları ve denetim karakterleri atılır, en fazla 200 karakter.
    public var safeName: String { Self.sanitize(name) }

    public static func sanitize(_ raw: String) -> String {
        let last = raw.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        var name = String(String.UnicodeScalarView(last.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && $0 != "\u{FEFF}"
        })).trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        if name.count > 200 {
            let ext = (name as NSString).pathExtension
            let keep = ext.isEmpty || ext.count > 16 ? "" : "." + ext
            name = String(name.prefix(200 - keep.count)) + keep
        }
        return name.isEmpty ? L("dosya") : name
    }

    public var modifiedDate: Date? {
        guard let modified, modified.isFinite, modified > 0 else { return nil }
        return Date(timeIntervalSince1970: modified / 1000)
    }
}

/// Telefona gönderilen oturum bilgisi. Oturum boyunca değişmez (aynı nonce ile hep aynı içerik şifrelenir).
public struct PhoneUploadStatus: Codable, Sendable {
    /// Dosyaların ekleneceği klasörün adı.
    public var folder: String
    /// Oturumun sona ereceği an (Unix zamanı, saniye).
    public var expiresAt: Double
    public var maxFileSize: Int64
    public var framesPerPart: Int

    public init(folder: String, expiresAt: Double, maxFileSize: Int64 = PhoneUpload.maxFileSize,
                framesPerPart: Int = PhoneUpload.framesPerPart) {
        self.folder = folder
        self.expiresAt = expiresAt
        self.maxFileSize = maxFileSize
        self.framesPerPart = framesPerPart
    }
}

/// Bir yüklemenin bilgisayardaki alıcısı: ağdan bağımsız durum makinesi. Gelen her baytı önce oturum anahtarıyla
/// doğrular, sonra kasanın anahtarıyla şifreleyip yazar. Doğrulanmamış hiçbir bayt diske ulaşmaz.
public final class PhoneUploadReceiver {
    public enum Failure: Error, Equatable {
        /// Dosya bilgisi çözülemedi ya da geçersiz (yanlış anahtar, bozuk istek).
        case badMeta
        case tooLarge
        case noSpace
        /// Parça sırası bozuk ya da yükleme bu aşamada bu isteği beklemiyor.
        case outOfOrder
        /// İçerik doğrulanamadı, akış kesik ya da bildirilen boyuttan farklı.
        case corrupted
        case io(String)

        /// Telefona gönderilen kısa hata kodu.
        public var code: String {
            switch self {
            case .badMeta: return "meta"
            case .tooLarge: return "too-large"
            case .noSpace: return "no-space"
            case .outOfOrder: return "order"
            case .corrupted: return "crypto"
            case .io: return "io"
            }
        }
    }

    public let number: Int
    public let fileID = UUID()
    public private(set) var meta: PhoneUploadMeta?
    /// Şimdiye kadar doğrulanıp kasaya yazılan düz içerik.
    public private(set) var received: Int64 = 0
    public private(set) var finished = false

    private let key: SymmetricKey
    private let makeWriter: (UUID) throws -> BlobWriter
    private let freeSpace: () -> Int64?
    private let maxFileSize: Int64
    private var decoder: PhoneShare.StreamDecoder
    private var writer: BlobWriter?
    private var nextPart = 0

    public init(number: Int, key: SymmetricKey, maxFileSize: Int64 = PhoneUpload.maxFileSize,
                freeSpace: @escaping () -> Int64? = { nil },
                makeWriter: @escaping (UUID) throws -> BlobWriter) {
        self.number = number
        self.key = key
        self.maxFileSize = maxFileSize
        self.freeSpace = freeSpace
        self.makeWriter = makeWriter
        decoder = PhoneShare.StreamDecoder(key: key, streamID: PhoneUpload.contentStream(number))
    }

    public convenience init(number: Int, key: SymmetricKey, vault: Vault, maxFileSize: Int64 = PhoneUpload.maxFileSize) {
        self.init(number: number, key: key, maxFileSize: maxFileSize, freeSpace: { vault.availableCapacity() },
                  makeWriter: { try vault.beginImport(id: $0) })
    }

    deinit { writer?.cancel() }

    /// Bu parça sırada bekleneni mi? (İstek gövdesi okunmadan önce denetlenir.)
    public func expects(part: Int) -> Bool { !finished && part == nextPart }

    /// 0. parça: şifreli dosya bilgisi. Boyut sınırını ve boş alanı denetler, kasada geçici dosyayı açar.
    @discardableResult
    public func receiveMeta(_ sealed: Data) throws -> PhoneUploadMeta {
        guard expects(part: 0) else { throw Failure.outOfOrder }
        guard sealed.count <= PhoneUpload.maxMetaLength,
              let plain = try? PhoneShare.open(sealed, key: key, streamID: PhoneUpload.metaStream(number)),
              let meta = try? JSONDecoder().decode(PhoneUploadMeta.self, from: plain),
              meta.size >= 0 else { throw Failure.badMeta }
        guard meta.size <= maxFileSize else { throw Failure.tooLarge }
        if let free = freeSpace(), free < meta.size + PhoneUpload.reserveSpace { throw Failure.noSpace }
        do {
            writer = try makeWriter(fileID)
        } catch {
            throw Failure.io(error.localizedDescription)
        }
        self.meta = meta
        nextPart = 1
        return meta
    }

    /// İçerik parçasının bir bölümü (ağdan geldikçe). Doğrulanan parçalar hemen kasaya yazılır.
    public func consume(_ bytes: Data) throws {
        guard let writer, let meta, !finished, nextPart >= 1 else { throw Failure.outOfOrder }
        let plain: [Data]
        do { plain = try decoder.push(bytes) } catch { throw Failure.corrupted }
        try write(plain, to: writer, limit: meta.size)
    }

    /// İçerik parçası bitti. `final` ise akış kapatılır, boyut denetlenir ve dosya kasaya taşınır; düz içeriğin
    /// SHA-256 özeti döner. Değilse nil döner ve sıradaki parça beklenir.
    public func endPart(final: Bool) throws -> String? {
        guard let writer, let meta, !finished, nextPart >= 1 else { throw Failure.outOfOrder }
        nextPart += 1
        guard final else { return nil }
        let last: Data
        do { last = try decoder.finish() } catch { throw Failure.corrupted }
        try write([last], to: writer, limit: meta.size)
        guard received == meta.size else { throw Failure.corrupted }
        do {
            let hash = try writer.finish()
            finished = true
            self.writer = nil
            return hash
        } catch {
            throw Failure.io(error.localizedDescription)
        }
    }

    /// Yüklemeyi bırakır; yarım geçici dosya silinir. Tamamlanmış dosyaya dokunmaz.
    public func cancel() {
        writer?.cancel()
        writer = nil
        finished = true
    }

    private func write(_ parts: [Data], to writer: BlobWriter, limit: Int64) throws {
        for part in parts {
            guard received + Int64(part.count) <= limit else { throw Failure.corrupted }
            do { try writer.append(part) } catch { throw Failure.io(error.localizedDescription) }
            received += Int64(part.count)
        }
    }
}
