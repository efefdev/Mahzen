import CryptoKit
import XCTest
@testable import MahzenCore

/// Linux sürümünün (linux/) oluşturduğu kasayı açar: iki sürüm aynı kasa biçimini konuşmalı.
/// Test verisi `python3 linux/tests/make_python_fixture.py` ile üretilir.
final class LinuxCompatibilityTests: XCTestCase {
    let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("linux/tests/fixtures")

    struct Expected: Decodable {
        struct File: Decodable { let id: String; let name: String; let size: Int; let sha256: String }
        let password: String
        let files: [File]
        let folder: String
        let thumb: String
    }

    func testOpensVaultCreatedOnLinux() throws {
        let expected = try JSONDecoder().decode(
            Expected.self, from: Data(contentsOf: fixtures.appendingPathComponent("python-expected.json")))
        let vault = try Vault.unlock(at: fixtures.appendingPathComponent("python-vault"), password: expected.password)
        XCTAssertFalse(vault.needsKDFUpgrade)
        let (index, recovered) = try vault.loadIndex()
        XCTAssertFalse(recovered)

        for file in expected.files {
            let id = try XCTUnwrap(UUID(uuidString: file.id))
            let record = try XCTUnwrap(index.files.first { $0.id == id })
            XCTAssertEqual(record.name, file.name)
            XCTAssertEqual(record.sha256, file.sha256)
            let data = try vault.readFile(id)
            XCTAssertEqual(data.count, file.size)
            XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), file.sha256)
            XCTAssertEqual(try vault.openReader(id).plainSize, Int64(file.size))
            if record.hasThumbnail {
                let thumb = try vault.readThumbnail(id)
                XCTAssertEqual(SHA256.hash(data: thumb).map { String(format: "%02x", $0) }.joined(), expected.thumb)
            }
        }
        let folderID = try XCTUnwrap(UUID(uuidString: expected.folder))
        XCTAssertEqual(index.folder(folderID)?.name, "Linux Klasörü")
        XCTAssertEqual(index.notes.first?.title, "Linux notu")
        XCTAssertEqual(index.notes.first?.pinned, true)
        XCTAssertEqual(index.secrets.first?.category, .wifi)
        XCTAssertEqual(index.trashedSecrets.count, 1)
        XCTAssertEqual(index.preferences.accent, "green")
        let report = try vault.checkIntegrity(files: index.files)
        XCTAssertTrue(report.problems.isEmpty)
        XCTAssertTrue(report.orphanURLs.isEmpty)
    }
}
