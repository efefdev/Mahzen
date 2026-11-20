import CryptoKit
import XCTest
@testable import MahzenCore

final class PhoneShareTests: XCTestCase {
    let key = PhoneShare.newKey()

    func testRoundTripAndStreamLength() throws {
        for size in [0, 1, PhoneShare.chunkSize - 1, PhoneShare.chunkSize, PhoneShare.chunkSize + 1, 3 * PhoneShare.chunkSize + 17] {
            let data = Crypto.randomBytes(size)
            let sealed = try PhoneShare.seal(data, key: key, stream: 7)
            XCTAssertEqual(Int64(sealed.count), PhoneShare.streamLength(plainSize: Int64(size)), "boyut \(size)")
            XCTAssertEqual(try PhoneShare.open(sealed, key: key, streamID: 7), data, "boyut \(size)")
        }
    }

    func testWrongKeyOrStreamFails() throws {
        let sealed = try PhoneShare.seal(Data("merhaba".utf8), key: key, stream: 3)
        XCTAssertThrowsError(try PhoneShare.open(sealed, key: PhoneShare.newKey(), streamID: 3))
        // Bir dosyanın akışı başka bir dosyanınkiymiş gibi sunulamaz.
        XCTAssertThrowsError(try PhoneShare.open(sealed, key: key, streamID: 5))
    }

    func testTamperTruncationAndReorderAreDetected() throws {
        let data = Crypto.randomBytes(2 * PhoneShare.chunkSize + 10)
        let sealed = try PhoneShare.seal(data, key: key, stream: 1)
        var tampered = sealed
        tampered[100] ^= 1
        XCTAssertThrowsError(try PhoneShare.open(tampered, key: key, streamID: 1))
        // Son çerçeveyi at: kalan son çerçeve "son değil" diye mühürlendiği için reddedilmeli.
        let frame = 4 + PhoneShare.chunkSize + 16
        XCTAssertThrowsError(try PhoneShare.open(sealed.prefix(2 * frame), key: key, streamID: 1))
        // İlk iki çerçevenin yerini değiştir.
        let swapped = sealed[frame..<2 * frame] + sealed[0..<frame] + sealed[(2 * frame)...]
        XCTAssertThrowsError(try PhoneShare.open(Data(swapped), key: key, streamID: 1))
    }

    func testManifestIsEncrypted() throws {
        let manifest = PhoneShareManifest(title: "Tatil", expiresAt: 0, items: [
            .init(index: 0, name: "pasaport-taramasi.jpg", path: ["Belgeler"], kind: "image", mime: "image/jpeg", size: 10, hasThumbnail: true),
        ])
        let sealed = try PhoneShare.seal(JSONEncoder().encode(manifest), key: key, stream: PhoneShare.manifestStream)
        XCTAssertNil(sealed.range(of: Data("pasaport".utf8)))
    }

    /// Tarayıcıdaki çözücüyle çapraz denetim için sabit anahtarlı bir akış yazar (MAHZEN_PHONE_FIXTURE).
    func testWriteCrossCheckFixture() throws {
        guard let out = ProcessInfo.processInfo.environment["MAHZEN_PHONE_FIXTURE"] else { throw XCTSkip("çapraz denetim istenmedi") }
        let fixedKey = SymmetricKey(data: Data((0..<32).map { UInt8($0) }))
        var plain = Data(count: 2 * PhoneShare.chunkSize + 12345)
        for i in plain.indices { plain[i] = UInt8((i * 31 + i / 7) & 0xff) }
        try PhoneShare.seal(plain, key: fixedKey, stream: 5).write(to: URL(fileURLWithPath: out + ".stream"))
        try plain.write(to: URL(fileURLWithPath: out + ".plain"))
    }
}
