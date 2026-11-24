import CryptoKit
import XCTest
@testable import MahzenCore

/// "Telefondan Ekle": parça parça çözme, kasaya akışla yazma ve yükleme alıcısı.
final class PhoneUploadTests: XCTestCase {
    let key = PhoneShare.newKey()
    let small = KDFSettings.argon2id(time: 1, memoryKiB: 8192, parallelism: 1)
    var dir: URL!

    /// Sabit anahtarla (00 01 … 1f) telefon sayfasındaki JavaScript şifreleyicinin (`MahzenUpload.seal`) çıktıları.
    /// `linux/tests/test_phoneupload.py` aynı değerleri sayfanın kendisini Node.js'te çalıştırarak yeniden üretir.
    static let jsMessageStream7 = "00000026ce82694bab1a3dff756f99521c445a8179df065f1ea2ac457e2c24c6c0df6309a0c5e841acda"
    static let jsEmptyStream6 = "0000001086e0d882adcfcfd14518c46c2cbdd412"
    static let fixedKey = SymmetricKey(data: Data((0..<32).map { UInt8($0) }))

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("mahzen-upload-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Akışı düzensiz boyutlu parçalar hâlinde çözücüye verir.
    private func decodeInPieces(_ sealed: Data, streamID: UInt32) throws -> Data {
        let decoder = PhoneShare.StreamDecoder(key: key, streamID: streamID)
        var out = Data()
        var offset = 0
        var step = 1
        while offset < sealed.count {
            let end = min(sealed.count, offset + step)
            for part in try decoder.push(sealed.subdata(in: offset..<end)) { out.append(part) }
            offset = end
            step = (step * 7 + 13) % 300_000 + 1
        }
        out.append(try decoder.finish())
        return out
    }

    func testStreamDecoderMatchesSeal() throws {
        let n = PhoneShare.chunkSize
        for size in [0, 1, n - 1, n, n + 1, 3 * n + 17] {
            let data = Crypto.randomBytes(size)
            XCTAssertEqual(try decodeInPieces(PhoneShare.seal(data, key: key, stream: 9), streamID: 9), data, "boyut \(size)")
        }
    }

    func testStreamDecoderRejectsTamperingAndTruncation() throws {
        let data = Crypto.randomBytes(2 * PhoneShare.chunkSize + 10)
        let sealed = try PhoneShare.seal(data, key: key, stream: 3)
        var tampered = sealed
        tampered[200] ^= 1
        XCTAssertThrowsError(try decodeInPieces(tampered, streamID: 3))
        XCTAssertThrowsError(try decodeInPieces(sealed, streamID: 5), "başka bir akışın çerçeveleri kabul edilmemeli")
        let frame = 4 + PhoneShare.chunkSize + 16
        XCTAssertThrowsError(try decodeInPieces(sealed.prefix(2 * frame), streamID: 3), "sondan kesilmiş akış")
        XCTAssertThrowsError(try decodeInPieces(sealed.prefix(2 * frame + 7), streamID: 3), "yarım çerçeve")
        XCTAssertThrowsError(try PhoneShare.StreamDecoder(key: key, streamID: 3).finish(), "boş akış")
        // Sınırı aşan çerçeve uzunluğu, gövdesi gelmeden reddedilir.
        XCTAssertThrowsError(try PhoneShare.StreamDecoder(key: key, streamID: 3).push(Data([0x7f, 0, 0, 0])))
    }

    func testBlobWriterMatchesBlobCrypto() throws {
        let fileKey = SymmetricKey(size: .bits256)
        for size in [0, 1, 4095, 4096, 4097, 3 * 4096 + 5, 100_000] {
            let data = Crypto.randomBytes(size)
            let url = dir.appendingPathComponent("blobs/ab/\(size).mhz")
            let writer = try BlobWriter(destination: url, key: fileKey, chunkSize: 4096)
            var offset = 0
            var step = 1
            while offset < data.count {
                let end = min(data.count, offset + step)
                try writer.append(data.subdata(in: offset..<end))
                offset = end
                step = step * 3 + 1
            }
            let hash = try writer.finish()
            XCTAssertEqual(try Data(contentsOf: url), try BlobCrypto.encrypt(data: data, key: fileKey, chunkSize: 4096), "boyut \(size)")
            XCTAssertEqual(hash, SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
            XCTAssertEqual(try BlobCrypto.decrypt(data: Data(contentsOf: url), key: fileKey), data)
        }
        let cancelled = try BlobWriter(destination: dir.appendingPathComponent("blobs/cd/iptal.mhz"), key: fileKey)
        try cancelled.append(Crypto.randomBytes(3 << 20))
        cancelled.cancel()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("blobs/cd").path), [],
                       "iptal edilen yazımdan geçici dosya kalmamalı")
    }

    // MARK: - Alıcı

    /// Telefonun yapacağı gibi: dosya bilgisi akışı ve `framesPerPart` çerçevelik içerik parçaları.
    private func phoneParts(_ data: Data, meta: PhoneUploadMeta, number: Int) throws -> (meta: Data, parts: [Data]) {
        let sealedMeta = try PhoneShare.seal(JSONEncoder().encode(meta), key: key, stream: PhoneUpload.metaStream(number))
        let content = try PhoneShare.seal(data, key: key, stream: PhoneUpload.contentStream(number))
        let frame = 4 + PhoneShare.chunkSize + 16
        let partSize = PhoneUpload.framesPerPart * frame
        let parts = stride(from: 0, to: content.count, by: partSize).map { content.subdata(in: $0..<min(content.count, $0 + partSize)) }
        return (sealedMeta, parts)
    }

    private func blobFiles(_ vault: Vault) -> [String] {
        let root = vault.folder.appendingPathComponent("blobs")
        guard let e = FileManager.default.enumerator(atPath: root.path) else { return [] }
        return e.compactMap { $0 as? String }.filter { !$0.hasSuffix("/") && $0.contains(".") }
    }

    func testReceiverWritesEncryptedFileToVault() throws {
        let vault = try Vault.create(at: dir.appendingPathComponent("kasa"), password: "doğru-at-pil-zımba-42", kdf: small)
        let data = Crypto.randomBytes(9 * PhoneShare.chunkSize + 777)
        let meta = PhoneUploadMeta(name: "IMG_0001.HEIC", size: Int64(data.count), type: "image/heic", modified: 1_700_000_000_000)
        let (sealedMeta, parts) = try phoneParts(data, meta: meta, number: 3)
        XCTAssertNil(sealedMeta.range(of: Data("IMG_0001".utf8)), "dosya adı ağda görünmemeli")
        let receiver = PhoneUploadReceiver(number: 3, key: key, vault: vault)
        XCTAssertEqual(try receiver.receiveMeta(sealedMeta), meta)
        var hash: String?
        for (i, part) in parts.enumerated() {
            XCTAssertTrue(receiver.expects(part: i + 1))
            // Ağdan geldiği gibi düzensiz bölümler.
            for start in stride(from: 0, to: part.count, by: 300_001) {
                try receiver.consume(part.subdata(in: start..<min(part.count, start + 300_001)))
            }
            hash = try receiver.endPart(final: i == parts.count - 1)
        }
        XCTAssertEqual(hash, SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
        XCTAssertEqual(receiver.received, Int64(data.count))
        XCTAssertEqual(try vault.readFile(receiver.fileID), data)
        XCTAssertEqual(blobFiles(vault).count, 1, "yalnızca kasaya taşınmış şifreli dosya kalmalı")
        XCTAssertNil(try Data(contentsOf: vault.blobURL(receiver.fileID)).range(of: data.prefix(64)), "düz içerik diske yazılmamalı")
    }

    func testReceiverRejectsBadInputAndCleansUp() throws {
        let vault = try Vault.create(at: dir.appendingPathComponent("kasa"), password: "doğru-at-pil-zımba-42", kdf: small)
        let data = Crypto.randomBytes(2 * PhoneShare.chunkSize + 5)
        let meta = PhoneUploadMeta(name: "video.mov", size: Int64(data.count))
        let (sealedMeta, parts) = try phoneParts(data, meta: meta, number: 1)

        func expect(_ failure: PhoneUploadReceiver.Failure, _ body: () throws -> Void) {
            XCTAssertThrowsError(try body()) { XCTAssertEqual($0 as? PhoneUploadReceiver.Failure, failure) }
        }
        // Başka bir yüklemenin numarasıyla şifrelenmiş bilgi ya da yanlış anahtar.
        expect(.badMeta) { try PhoneUploadReceiver(number: 2, key: key, vault: vault).receiveMeta(sealedMeta) }
        expect(.badMeta) { try PhoneUploadReceiver(number: 1, key: PhoneShare.newKey(), vault: vault).receiveMeta(sealedMeta) }
        // Boyut sınırı ve boş alan.
        expect(.tooLarge) { try PhoneUploadReceiver(number: 1, key: key, vault: vault, maxFileSize: 1000).receiveMeta(sealedMeta) }
        expect(.noSpace) {
            try PhoneUploadReceiver(number: 1, key: key, freeSpace: { 1 << 20 }, makeWriter: { try vault.beginImport(id: $0) })
                .receiveMeta(sealedMeta)
        }
        // Sıra: bilgi gelmeden içerik, aynı parça iki kez.
        expect(.outOfOrder) { try PhoneUploadReceiver(number: 1, key: key, vault: vault).consume(parts[0]) }
        let twice = PhoneUploadReceiver(number: 1, key: key, vault: vault)
        try twice.receiveMeta(sealedMeta)
        expect(.outOfOrder) { try twice.receiveMeta(sealedMeta) }
        XCTAssertFalse(twice.expects(part: 2))
        twice.cancel()

        // Bozulmuş içerik: hata verir, iptalden sonra geçici dosya kalmaz.
        let tampered = PhoneUploadReceiver(number: 1, key: key, vault: vault)
        try tampered.receiveMeta(sealedMeta)
        var bad = parts[0]
        bad[50] ^= 1
        expect(.corrupted) { try tampered.consume(bad); _ = try tampered.endPart(final: true) }
        tampered.cancel()

        // Sondan kesilmiş akış ("son" çerçeve hiç gelmedi).
        let truncated = PhoneUploadReceiver(number: 1, key: key, vault: vault)
        try truncated.receiveMeta(sealedMeta)
        let frame = 4 + PhoneShare.chunkSize + 16
        try truncated.consume(parts[0].prefix(2 * frame))
        expect(.corrupted) { _ = try truncated.endPart(final: true) }
        truncated.cancel()

        // Bildirilen boyuttan farklı içerik.
        let lying = PhoneUploadReceiver(number: 1, key: key, vault: vault)
        let (shortMeta, _) = try phoneParts(data, meta: PhoneUploadMeta(name: "x", size: 10), number: 1)
        try lying.receiveMeta(shortMeta)
        expect(.corrupted) { try lying.consume(parts[0]); _ = try lying.endPart(final: true) }
        lying.cancel()

        // Yarıda bırakılan yükleme (telefon kapandı): iptal geçici dosyayı siler.
        let abandoned = PhoneUploadReceiver(number: 1, key: key, vault: vault)
        try abandoned.receiveMeta(sealedMeta)
        try abandoned.consume(parts[0].prefix(frame + 100))
        abandoned.cancel()

        XCTAssertEqual(blobFiles(vault), [], "reddedilen ve yarım kalan yüklemelerden kasada dosya kalmamalı")
    }

    // MARK: - Tarayıcıyla çapraz denetim

    func testJavaScriptEncoderOutputDecrypts() throws {
        func hex(_ s: String) -> Data {
            Data(stride(from: 0, to: s.count, by: 2).map { i in
                UInt8(s[s.index(s.startIndex, offsetBy: i)..<s.index(s.startIndex, offsetBy: i + 2)], radix: 16)!
            })
        }
        XCTAssertEqual(try PhoneShare.open(hex(Self.jsMessageStream7), key: Self.fixedKey, streamID: 7), Data("Mahzen telefondan ekle".utf8))
        XCTAssertEqual(try PhoneShare.open(hex(Self.jsEmptyStream6), key: Self.fixedKey, streamID: 6), Data())
        // Swift'in kendi mühürlemesi de bayt bayt aynı olmalı (aynı biçim, belirlenimci nonce).
        XCTAssertEqual(try PhoneShare.seal(Data("Mahzen telefondan ekle".utf8), key: Self.fixedKey, stream: 7), hex(Self.jsMessageStream7))
    }

    /// Tarayıcıdaki şifreleyicinin büyük bir dosya için ürettiği akış (MAHZEN_UPLOAD_FIXTURE=<önek>: `<önek>.stream`,
    /// `<önek>.plain`, sabit anahtar, akış 9). `linux/tests/test_phoneupload.py` bu dosyaları Node.js ile yazar.
    func testJavaScriptFixtureDecrypts() throws {
        guard let prefix = ProcessInfo.processInfo.environment["MAHZEN_UPLOAD_FIXTURE"] else { throw XCTSkip("çapraz denetim istenmedi") }
        let stream = try Data(contentsOf: URL(fileURLWithPath: prefix + ".stream"))
        let plain = try Data(contentsOf: URL(fileURLWithPath: prefix + ".plain"))
        XCTAssertEqual(try PhoneShare.open(stream, key: Self.fixedKey, streamID: 9), plain)
    }

    func testMetaNameIsSanitized() {
        XCTAssertEqual(PhoneUploadMeta.sanitize("IMG_0001.JPG"), "IMG_0001.JPG")
        XCTAssertEqual(PhoneUploadMeta.sanitize("../../etc/passwd"), "passwd")
        XCTAssertEqual(PhoneUploadMeta.sanitize("C:\\Users\\a\\rapor.pdf"), "rapor.pdf")
        XCTAssertEqual(PhoneUploadMeta.sanitize(".gizli"), "gizli")
        XCTAssertEqual(PhoneUploadMeta.sanitize("a\u{0}b\nc.txt"), "abc.txt")
        XCTAssertEqual(PhoneUploadMeta.sanitize(String(repeating: "u", count: 300) + ".mp4").count, 200)
        XCTAssertTrue(PhoneUploadMeta.sanitize(String(repeating: "u", count: 300) + ".mp4").hasSuffix(".mp4"))
        XCTAssertFalse(PhoneUploadMeta.sanitize("/").isEmpty)
        XCTAssertEqual(PhoneUploadMeta(name: "a", size: 1, modified: 1_700_000_000_000).modifiedDate, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertNil(PhoneUploadMeta(name: "a", size: 1, modified: 0).modifiedDate)
    }
}
