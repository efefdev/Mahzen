import CryptoKit
import XCTest
@testable import MahzenCore

final class BlobCryptoTests: XCTestCase {
    let key = SymmetricKey(size: .bits256)

    func testRoundTripAcrossChunkBoundaries() throws {
        for size in [0, 1, 4095, 4096, 4097, 4096 * 3, 4096 * 3 + 17] {
            let data = Crypto.randomBytes(size)
            let sealed = try BlobCrypto.encrypt(data: data, key: key, chunkSize: 4096)
            XCTAssertEqual(try BlobCrypto.decrypt(data: sealed, key: key), data, "boyut \(size)")
        }
    }

    func testCiphertextDoesNotContainPlaintext() throws {
        let plain = Data(String(repeating: "gizli-bilgi ", count: 1000).utf8)
        let sealed = try BlobCrypto.encrypt(data: plain, key: key)
        XCTAssertNil(sealed.range(of: Data("gizli-bilgi".utf8)))
    }

    func testWrongKeyFails() throws {
        let sealed = try BlobCrypto.encrypt(data: Data("merhaba".utf8), key: key)
        XCTAssertThrowsError(try BlobCrypto.decrypt(data: sealed, key: SymmetricKey(size: .bits256)))
    }

    func testTamperingIsDetected() throws {
        var sealed = try BlobCrypto.encrypt(data: Crypto.randomBytes(10_000), key: key, chunkSize: 4096)
        sealed[5000] ^= 0x01
        XCTAssertThrowsError(try BlobCrypto.decrypt(data: sealed, key: key))
    }

    func testTruncationAtChunkBoundaryIsDetected() throws {
        let sealed = try BlobCrypto.encrypt(data: Crypto.randomBytes(4096 * 3), key: key, chunkSize: 4096)
        // Son parçayı tamamen at: kalan son parça "son değil" olarak mühürlendiği için reddedilmeli.
        let truncated = sealed.prefix(BlobCrypto.headerSize + 2 * (4096 + 16))
        XCTAssertThrowsError(try BlobCrypto.decrypt(data: Data(truncated), key: key))
    }

    func testChunkReorderingIsDetected() throws {
        let sealed = try BlobCrypto.encrypt(data: Crypto.randomBytes(4096 * 2 + 10), key: key, chunkSize: 4096)
        let h = BlobCrypto.headerSize, c = 4096 + 16
        var swapped = sealed.prefix(h)
        swapped.append(sealed[(h + c)..<(h + 2 * c)])
        swapped.append(sealed[h..<(h + c)])
        swapped.append(sealed[(h + 2 * c)...])
        XCTAssertThrowsError(try BlobCrypto.decrypt(data: Data(swapped), key: key))
    }
}

final class VaultTests: XCTestCase {
    var dir: URL!
    let password = "doğru-at-pil-zımba-42"

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("mahzen-test-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func makeVault() throws -> Vault {
        try Vault.create(at: dir, password: password, kdf: .argon2id(time: 1, memoryKiB: 64, parallelism: 1))
    }

    func testWrongPasswordIsRejected() throws {
        _ = try makeVault()
        XCTAssertThrowsError(try Vault.unlock(at: dir, password: "yanlis-parola-123")) {
            XCTAssertEqual($0 as? VaultError, .wrongPassword)
        }
    }

    func testShortPasswordIsRejected() {
        XCTAssertThrowsError(try Vault.create(at: dir, password: "kisa", kdf: .argon2id(time: 1, memoryKiB: 64, parallelism: 1)))
    }

    func testIndexPersistsAndIsEncrypted() throws {
        let vault = try makeVault()
        var index = VaultIndex()
        var note = Note()
        note.title = "Banka"
        note.body = "kasa-kodu-9182"
        index.notes.append(note)
        try vault.saveIndex(index)

        let raw = try Data(contentsOf: dir.appendingPathComponent("index.enc"))
        XCTAssertNil(raw.range(of: Data("kasa-kodu-9182".utf8)))

        let reopened = try Vault.unlock(at: dir, password: password)
        let (loaded, recovered) = try reopened.loadIndex()
        XCTAssertFalse(recovered)
        XCTAssertEqual(loaded.notes.first?.body, "kasa-kodu-9182")
    }

    func testCorruptIndexFallsBackToBackup() throws {
        let vault = try makeVault()
        var index = VaultIndex()
        index.preferences.displayName = "Yedek"
        try vault.saveIndex(index)
        try vault.saveIndex(index) // yedek artık "Yedek" adlı sürümü içeriyor
        try Data("bozuk".utf8).write(to: dir.appendingPathComponent("index.enc"))

        let (loaded, recovered) = try Vault.unlock(at: dir, password: password).loadIndex()
        XCTAssertTrue(recovered)
        XCTAssertEqual(loaded.preferences.displayName, "Yedek")
    }

    func testChangePasswordKeepsData() throws {
        let vault = try makeVault()
        let source = dir.deletingLastPathComponent().appendingPathComponent("kaynak-\(UUID().uuidString).bin")
        let content = Crypto.randomBytes(3 * 1024 * 1024 + 5)
        try content.write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let id = UUID()
        try vault.importFile(at: source, id: id)

        XCTAssertThrowsError(try vault.changePassword(current: "yanlis-parola-123", new: "yeni-parola-uzun-1", kdf: .argon2id(time: 1, memoryKiB: 64, parallelism: 1)))
        try vault.changePassword(current: password, new: "yeni-parola-uzun-1", kdf: .argon2id(time: 1, memoryKiB: 64, parallelism: 1))

        XCTAssertThrowsError(try Vault.unlock(at: dir, password: password))
        let reopened = try Vault.unlock(at: dir, password: "yeni-parola-uzun-1")
        XCTAssertEqual(try reopened.readFile(id), content)
    }

    func testFileExportAndThumbnail() throws {
        let vault = try makeVault()
        let source = dir.appendingPathComponent("not.txt")
        try Data("dosya içeriği".utf8).write(to: source)
        let id = UUID()
        try vault.importFile(at: source, id: id)
        try vault.writeThumbnail(Data([1, 2, 3]), id: id)

        let out = dir.appendingPathComponent("disari.txt")
        try vault.exportFile(id, to: out)
        XCTAssertEqual(try String(contentsOf: out, encoding: .utf8), "dosya içeriği")
        XCTAssertEqual(try vault.readThumbnail(id), Data([1, 2, 3]))

        vault.deleteFile(id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.blobURL(id).path))
    }

    func testUnicodeNormalizationOfPassword() throws {
        let composed = "çğışöü-parola-1"
        let decomposed = composed.decomposedStringWithCanonicalMapping
        XCTAssertNotEqual(Array(composed.utf8), Array(decomposed.utf8))
        _ = try Vault.create(at: dir, password: composed, kdf: .argon2id(time: 1, memoryKiB: 64, parallelism: 1))
        XCTAssertNoThrow(try Vault.unlock(at: dir, password: decomposed))
    }

    func testOldPreferencesDecodeWithDefaults() throws {
        let json = Data(#"{"accent":"teal"}"#.utf8)
        let prefs = try JSONDecoder().decode(Preferences.self, from: json)
        XCTAssertEqual(prefs.accent, "teal")
        XCTAssertEqual(prefs.autoLockMinutes, Preferences().autoLockMinutes)
    }
}

final class PasswordTests: XCTestCase {
    func testGeneratorRespectsOptions() {
        var options = GeneratorOptions()
        options.length = 32
        options.symbols = false
        for _ in 0..<50 {
            let pw = PasswordGenerator.generate(options)
            XCTAssertEqual(pw.count, 32)
            XCTAssertTrue(pw.allSatisfy { $0.isLetter || $0.isNumber })
            XCTAssertTrue(pw.contains(where: \.isUppercase))
            XCTAssertTrue(pw.contains(where: \.isNumber))
        }
    }

    func testStrengthOrdering() {
        XCTAssertEqual(PasswordStrength.evaluate("password123").score, 0)
        XCTAssertLessThan(PasswordStrength.evaluate("aaaaaaaaaaaa").score, 2)
        XCTAssertGreaterThanOrEqual(PasswordStrength.evaluate("Ornek#Test!2026xQz").score, 3)
    }
}

final class Argon2Tests: XCTestCase {
    /// Argon2 referans paketindeki test vektörleri (src/test.c).
    func testReferenceVectors() throws {
        let salt = Data("somesalt".utf8)
        let a = try Crypto.argon2id(password: "password", salt: salt, time: 2, memoryKiB: 1 << 16, parallelism: 1)
        XCTAssertEqual(a.rawData.hex, "09316115d5cf24ed5a15a31a3ba326e5cf32edc24702987c02b6566f61913cf7")
        let b = try Crypto.argon2id(password: "password", salt: salt, time: 2, memoryKiB: 1 << 8, parallelism: 1)
        XCTAssertEqual(b.rawData.hex, "9dfeb910e80bad0311fee20f9c0e2b12c17987b4cac90c2ef54d5b3021c68bfe")
    }

    func testRecommendedSettingsCostAtLeastQuarterSecond() throws {
        guard case let .argon2id(t, m, p) = KDFSettings.recommended else { return XCTFail() }
        let start = Date()
        _ = try Crypto.argon2id(password: "deneme-parola", salt: Crypto.randomBytes(32), time: t, memoryKiB: m, parallelism: p)
        let elapsed = Date().timeIntervalSince(start)
        print("Argon2id önerilen ayar süresi: \(elapsed) sn")
        XCTAssertGreaterThan(elapsed, 0.25)
    }
}

final class UpgradeTests: XCTestCase {
    func testPBKDF2VaultUpgradesToArgon2idAndKeepsData() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mahzen-up-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let pw = "eski-kasa-parolasi-1"
        let old = try Vault.create(at: dir, password: pw, kdf: .pbkdf2(iterations: 1_000))
        var index = VaultIndex()
        var note = Note(); note.body = "korunmalı"
        index.notes = [note]
        try old.saveIndex(index)

        let opened = try Vault.unlock(at: dir, password: pw)
        XCTAssertTrue(opened.needsKDFUpgrade)
        try opened.upgradeKDF(password: pw, kdf: .argon2id(time: 1, memoryKiB: 64, parallelism: 1))
        XCTAssertFalse(opened.needsKDFUpgrade)

        let header = try Vault.readHeader(at: dir)
        XCTAssertEqual(header.kdf.algorithm, KDFParams.argon2id)
        XCTAssertEqual(header.version, Vault.currentVersion)
        let reopened = try Vault.unlock(at: dir, password: pw)
        XCTAssertEqual(try reopened.loadIndex().index.notes.first?.body, "korunmalı")
        XCTAssertThrowsError(try Vault.unlock(at: dir, password: "yanlis-parola-xx"))
    }

    func testOldIndexWithoutNewFieldsDecodes() throws {
        let json = #"{"version":1,"files":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"a.txt","size":3,"addedAt":"2026-01-01T00:00:00Z","hasThumbnail":false,"favorite":false}]}"#
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        let index = try d.decode(VaultIndex.self, from: Data(json.utf8))
        XCTAssertEqual(index.files.first?.tags, [])
        XCTAssertNil(index.files.first?.folderID)
        XCTAssertEqual(index.folders, [])
    }

    func testImportReturnsContentHash() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mahzen-h-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let vault = try Vault.create(at: dir, password: "hash-testi-parolasi", kdf: .argon2id(time: 1, memoryKiB: 64, parallelism: 1))
        let src = dir.appendingPathComponent("x.txt")
        try Data("abc".utf8).write(to: src)
        XCTAssertEqual(try vault.importFile(at: src, id: UUID()), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

final class IndexOperationTests: XCTestCase {
    func file(_ name: String, in folder: UUID? = nil, hash: String? = nil) -> FileRecord {
        FileRecord(id: UUID(), name: name, size: 1, contentType: nil, folderID: folder, sha256: hash)
    }

    func testFolderPathsAreReusedAndNested() {
        var idx = VaultIndex()
        let a = idx.ensureFolderPath(["Tatil", "2026"], under: nil)
        let b = idx.ensureFolderPath(["Tatil", "2026"], under: nil)
        XCTAssertEqual(a, b)
        XCTAssertEqual(idx.folders.count, 2)
        XCTAssertEqual(idx.path(to: a).map(\.name), ["Tatil", "2026"])
        let dup = idx.createFolder(named: "Tatil", in: nil)
        XCTAssertEqual(idx.folder(dup)?.name, "Tatil 2")
    }

    func testFolderCannotMoveIntoItself() {
        var idx = VaultIndex()
        let parent = idx.createFolder(named: "A", in: nil)
        let child = idx.createFolder(named: "B", in: parent)
        XCTAssertFalse(idx.moveFolder(parent, to: child))
        XCTAssertFalse(idx.moveFolder(parent, to: parent))
        XCTAssertTrue(idx.moveFolder(child, to: nil))
    }

    func testTrashAndRestoreFolderTree() {
        var idx = VaultIndex()
        let top = idx.createFolder(named: "Belgeler", in: nil)
        let sub = idx.createFolder(named: "Vergi", in: top)
        let f1 = file("a.pdf", in: top), f2 = file("b.pdf", in: sub), loose = file("c.txt")
        idx.files = [f1, f2, loose]
        idx.trashFiles([f2.id], at: Date(timeIntervalSince1970: 100)) // önceden ayrıca silinmiş

        idx.trashFolder(top, at: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(idx.liveFiles.map(\.name), ["c.txt"])
        XCTAssertEqual(idx.trashedFolders.map(\.id), [top])
        XCTAssertEqual(idx.trashedFiles.map(\.id), [f2.id], "ayrı silinen dosya kendi başına görünmeli")

        idx.restoreFolder(top)
        XCTAssertEqual(Set(idx.liveFiles.map(\.name)), ["a.pdf", "c.txt"], "önceden silinen dosya geri gelmemeli")
        XCTAssertNotNil(idx.folder(sub).map { $0.deletedAt == nil ? $0 : nil } ?? nil)
    }

    func testRestoreFileWhoseFolderIsGoneMovesToRoot() {
        var idx = VaultIndex()
        let folder = idx.createFolder(named: "Geçici", in: nil)
        let f = file("x", in: folder)
        idx.files = [f]
        idx.trashFiles([f.id])
        _ = idx.purgeFolder(folder)
        XCTAssertTrue(idx.files.isEmpty, "klasör kalıcı silinince içindeki dosya da gider")

        let g = file("y", in: idx.createFolder(named: "Diğer", in: nil))
        idx.files = [g]
        idx.trashFiles([g.id])
        idx.trashFolder(g.folderID!)
        idx.folders.removeAll()
        idx.restoreFile(g.id)
        XCTAssertNil(idx.files.first?.folderID)
    }

    func testPurgeExpiredRespectsRetention() {
        var idx = VaultIndex()
        let now = Date()
        let old = file("eski"), recent = file("yeni")
        idx.files = [old, recent]
        idx.trashFiles([old.id], at: now.addingTimeInterval(-40 * 86_400))
        idx.trashFiles([recent.id], at: now.addingTimeInterval(-5 * 86_400))
        var note = Note(); note.deletedAt = now.addingTimeInterval(-31 * 86_400)
        idx.notes = [note]

        XCTAssertEqual(idx.purgeExpired(now: now, retentionDays: 0), [])
        XCTAssertEqual(idx.purgeExpired(now: now, retentionDays: 30), [old.id])
        XCTAssertEqual(idx.files.map(\.id), [recent.id])
        XCTAssertTrue(idx.notes.isEmpty)
    }

    func testDuplicateDetectionIgnoresTrash() {
        var idx = VaultIndex()
        let f = file("a", hash: "h1")
        idx.files = [f]
        XCTAssertNotNil(idx.existingFile(withHash: "h1"))
        idx.trashFiles([f.id])
        XCTAssertNil(idx.existingFile(withHash: "h1"))
    }

    func testEmptyTrashReturnsAllBlobIDs() {
        var idx = VaultIndex()
        let folder = idx.createFolder(named: "K", in: nil)
        let a = file("a", in: folder), b = file("b"), c = file("c")
        idx.files = [a, b, c]
        idx.trashFolder(folder)
        idx.trashFiles([b.id])
        XCTAssertEqual(Set(idx.emptyTrash()), [a.id, b.id])
        XCTAssertEqual(idx.files.map(\.id), [c.id])
        XCTAssertTrue(idx.folders.isEmpty)
    }
}

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

final class BlobReaderTests: XCTestCase {
    func write(_ data: Data, chunk: Int, key: SymmetricKey) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("reader-\(UUID().uuidString).mhz")
        try BlobCrypto.encrypt(data: data, key: key, chunkSize: chunk).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testRandomAccessMatchesPlaintext() throws {
        let key = SymmetricKey(size: .bits256)
        for size in [0, 1, 4096, 4096 * 5 + 123] {
            let plain = Crypto.randomBytes(size)
            let reader = try BlobReader(url: write(plain, chunk: 4096, key: key), key: key)
            XCTAssertEqual(reader.plainSize, Int64(size))
            XCTAssertEqual(try reader.read(offset: 0, length: size + 100), plain)
            for _ in 0..<200 where size > 0 {
                let offset = Int.random(in: 0..<size)
                let length = Int.random(in: 1...9000)
                let expected = plain[offset..<min(offset + length, size)]
                XCTAssertEqual(try reader.read(offset: Int64(offset), length: length), Data(expected))
            }
            XCTAssertEqual(try reader.read(offset: Int64(size), length: 10), Data())
        }
    }

    func testTamperedMiddleChunkFailsWhenRead() throws {
        let key = SymmetricKey(size: .bits256)
        let plain = Crypto.randomBytes(4096 * 3)
        let url = try write(plain, chunk: 4096, key: key)
        var raw = try Data(contentsOf: url)
        raw[BlobCrypto.headerSize + (4096 + 16) * 1 + 10] ^= 0xFF // orta parça
        try raw.write(to: url)
        let reader = try BlobReader(url: url, key: key)
        XCTAssertEqual(try reader.read(offset: 0, length: 4096), plain.prefix(4096))
        XCTAssertThrowsError(try reader.read(offset: 4096, length: 10))
    }

    func testTamperedFinalChunkRejectedOnOpen() throws {
        let key = SymmetricKey(size: .bits256)
        let url = try write(Crypto.randomBytes(4096 * 3), chunk: 4096, key: key)
        var raw = try Data(contentsOf: url)
        raw[BlobCrypto.headerSize + (4096 + 16) * 2 + 10] ^= 0xFF // son parça
        try raw.write(to: url)
        XCTAssertThrowsError(try BlobReader(url: url, key: key))
    }

    func testTruncatedFileIsRejected() throws {
        let key = SymmetricKey(size: .bits256)
        let plain = Crypto.randomBytes(4096 * 3)
        let url = try write(plain, chunk: 4096, key: key)
        let raw = try Data(contentsOf: url)
        try raw.prefix(BlobCrypto.headerSize + 2 * (4096 + 16)).write(to: url)
        XCTAssertThrowsError(try BlobReader(url: url, key: key), "kesilmiş dosya açılırken reddedilmeli")
    }
}

final class MaintenanceTests: XCTestCase {
    var root: URL!
    var vault: Vault!
    let pw = "bakim-testi-parolasi"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mahzen-bakim-\(UUID().uuidString)")
        vault = try Vault.create(at: root.appendingPathComponent("Kasa"), password: pw, kdf: .argon2id(time: 1, memoryKiB: 64, parallelism: 1))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func addFile(_ bytes: Int) throws -> FileRecord {
        let src = root.appendingPathComponent(UUID().uuidString)
        let data = Crypto.randomBytes(bytes)
        try data.write(to: src)
        let id = UUID()
        let hash = try vault.importFile(at: src, id: id)
        try vault.writeThumbnail(Data([9, 9]), id: id)
        return FileRecord(id: id, name: "f", size: Int64(bytes), contentType: nil, hasThumbnail: true, sha256: hash)
    }

    func testBackupIsOpenableIncrementalAndPrunes() throws {
        let a = try addFile(3_000_000), b = try addFile(10)
        var index = VaultIndex()
        index.files = [a, b]
        try vault.saveIndex(index)
        let dest = root.appendingPathComponent("Yedek")

        let first = try vault.backup(to: dest, fileIDs: [a.id, b.id], thumbnailIDs: [a.id, b.id])
        XCTAssertEqual(first.copiedFiles, 4)
        let restored = try Vault.unlock(at: dest, password: pw)
        XCTAssertEqual(try restored.loadIndex().index.files.count, 2)
        XCTAssertEqual(try restored.verifyFile(a.id), a.sha256)

        let second = try vault.backup(to: dest, fileIDs: [a.id, b.id], thumbnailIDs: [a.id, b.id])
        XCTAssertEqual(second.copiedFiles, 0)
        XCTAssertEqual(second.unchangedFiles, 4)

        let third = try vault.backup(to: dest, fileIDs: [a.id], thumbnailIDs: [a.id])
        XCTAssertEqual(third.removedFiles, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.appendingPathComponent(vault.relativePath(vault.blobURL(b.id))).path))
    }

    func testBackupRefusesVaultFolderAndForeignVault() throws {
        XCTAssertThrowsError(try vault.backup(to: vault.folder.appendingPathComponent("ic"), fileIDs: [], thumbnailIDs: []))
        let other = root.appendingPathComponent("Baska")
        _ = try Vault.create(at: other, password: "baska-kasa-parolasi", kdf: .argon2id(time: 1, memoryKiB: 64, parallelism: 1))
        XCTAssertThrowsError(try vault.backup(to: other, fileIDs: [], thumbnailIDs: []))
    }

    func testIntegrityFindsDamageMissingOrphansAndRestoresFromBackup() throws {
        let good = try addFile(5_000), bad = try addFile(20_000), gone = try addFile(100)
        var legacy = good
        legacy.sha256 = nil
        let dest = root.appendingPathComponent("Yedek")
        _ = try vault.backup(to: dest, fileIDs: [good.id, bad.id, gone.id], thumbnailIDs: [])

        var raw = try Data(contentsOf: vault.blobURL(bad.id))
        raw[100] ^= 0x55
        try raw.write(to: vault.blobURL(bad.id))
        try FileManager.default.removeItem(at: vault.blobURL(gone.id))
        let orphan = try addFile(50)

        let report = try vault.checkIntegrity(files: [legacy, bad, gone])
        XCTAssertNil(report.problems[good.id])
        XCTAssertEqual(report.hashes[good.id], good.sha256, "eski kayıtların özeti tamamlanabilmeli")
        if case .damaged = report.problems[bad.id] {} else { XCTFail("bozuk dosya yakalanmalı") }
        XCTAssertEqual(report.problems[gone.id], .missing)
        XCTAssertEqual(Set(report.orphanURLs.map(\.lastPathComponent)),
                       [vault.blobURL(orphan.id).lastPathComponent, vault.thumbnailURL(orphan.id).lastPathComponent])

        try vault.restoreFile(bad.id, fromBackup: dest)
        try vault.restoreFile(gone.id, fromBackup: dest)
        XCTAssertEqual(try vault.verifyFile(bad.id), bad.sha256)
        XCTAssertEqual(try vault.verifyFile(gone.id), gone.sha256)

        vault.removeOrphans(report.orphanURLs)
        XCTAssertTrue(try vault.checkIntegrity(files: [good, bad, gone]).orphanURLs.isEmpty)
    }

    func testCancellationStopsBackup() throws {
        let a = try addFile(1_000_000)
        XCTAssertThrowsError(try vault.backup(to: root.appendingPathComponent("Y"), fileIDs: [a.id], thumbnailIDs: []) { _, _ in false })
    }
}

final class KeyfileTests: XCTestCase {
    var dir: URL!
    let pw = "anahtar-dosyasi-parolasi"
    let fast = KDFSettings.argon2id(time: 1, memoryKiB: 64, parallelism: 1)

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("mahzen-kf-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testMissingOrWrongKeyfileLooksLikeWrongPassword() throws {
        let keyfile = Vault.generateKeyfile()
        _ = try Vault.create(at: dir, password: pw, kdf: fast, keyfile: keyfile)
        for attempt in [nil, Vault.generateKeyfile()] {
            XCTAssertThrowsError(try Vault.unlock(at: dir, password: pw, keyfile: attempt)) {
                XCTAssertEqual($0 as? VaultError, .wrongPassword, "anahtar dosyasının varlığı hata mesajından anlaşılmamalı")
            }
        }
        XCTAssertThrowsError(try Vault.unlock(at: dir, password: "yanlis-parola-123", keyfile: keyfile)) {
            XCTAssertEqual($0 as? VaultError, .wrongPassword)
        }
        XCTAssertNoThrow(try Vault.unlock(at: dir, password: pw, keyfile: keyfile))
    }

    /// Anahtar dosyalı ve dosyasız kasanın başlığı aynı alanları ve sürümü taşımalı.
    func testHeaderDoesNotRevealKeyfile() throws {
        let plainDir = dir.appendingPathComponent("duz"), keyDir = dir.appendingPathComponent("anahtarli")
        _ = try Vault.create(at: plainDir, password: pw, kdf: fast)
        _ = try Vault.create(at: keyDir, password: pw, kdf: fast, keyfile: Vault.generateKeyfile())
        func shape(_ url: URL) throws -> [String: String] {
            let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url.appendingPathComponent("vault.json"))) as! [String: Any]
            var out: [String: String] = [:]
            for (k, v) in obj {
                if let nested = v as? [String: Any] { out[k] = nested.keys.sorted().joined(separator: ",") }
                else if k == "version" || k == "format" || k == "cipher" { out[k] = "\(v)" }
                else { out[k] = "değer" }
            }
            return out
        }
        XCTAssertEqual(try shape(plainDir), try shape(keyDir))
        let raw = try String(contentsOf: keyDir.appendingPathComponent("vault.json"), encoding: .utf8).lowercased()
        XCTAssertFalse(raw.contains("key") && raw.contains("file"), "başlıkta anahtar dosyasına dair iz olmamalı")
    }

    func testEnableDisableKeyfileKeepsData() throws {
        let vault = try Vault.create(at: dir, password: pw, kdf: fast)
        var index = VaultIndex()
        var note = Note(); note.body = "gizli"
        index.notes = [note]
        try vault.saveIndex(index)

        let keyfile = Vault.generateKeyfile()
        XCTAssertThrowsError(try vault.setKeyfile(keyfile, password: "yanlis-parola-123", kdf: fast))
        try vault.setKeyfile(keyfile, password: pw, kdf: fast)
        XCTAssertTrue(vault.requiresKeyfile)
        XCTAssertThrowsError(try Vault.unlock(at: dir, password: pw))
        let reopened = try Vault.unlock(at: dir, password: pw, keyfile: keyfile)
        XCTAssertEqual(try reopened.loadIndex().index.notes.first?.body, "gizli")

        // Parola değiştirme ve KDF yükseltme anahtar dosyası zorunluluğunu korumalı.
        try reopened.changePassword(current: pw, new: "yeni-parola-uzun-99", kdf: fast)
        XCTAssertThrowsError(try Vault.unlock(at: dir, password: "yeni-parola-uzun-99"))
        let again = try Vault.unlock(at: dir, password: "yeni-parola-uzun-99", keyfile: keyfile)
        try again.upgradeKDF(password: "yeni-parola-uzun-99", kdf: fast)
        XCTAssertThrowsError(try Vault.unlock(at: dir, password: "yeni-parola-uzun-99"))

        try again.setKeyfile(nil, password: "yeni-parola-uzun-99", kdf: fast)
        XCTAssertFalse(again.requiresKeyfile)
        XCTAssertNoThrow(try Vault.unlock(at: dir, password: "yeni-parola-uzun-99"))
    }
}

final class AuditFixTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("mahzen-fix-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Okunamaz yapılan klasörün iznini geri ver ki silinebilsin.
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.appendingPathComponent("Proje/kilitli").path)
        try? FileManager.default.removeItem(at: dir)
    }

    // Denetim: oynatıcı sondan kesilmiş dosyayı fark etmiyordu.
    func testBlobReaderRejectsTruncatedOrPaddedFile() throws {
        let key = SymmetricKey(size: .bits256)
        let plain = Crypto.randomBytes(4096 * 3 + 500)
        let sealed = try BlobCrypto.encrypt(data: plain, key: key, chunkSize: 4096)
        let cases: [Data] = [
            sealed.prefix(sealed.count - 516) + Crypto.randomBytes(16), // son parça yerine çöp
            sealed.prefix(sealed.count - 516),                          // son parça tamamen silinmiş
            sealed + Crypto.randomBytes(40),                            // sonuna çöp eklenmiş
        ]
        for (i, data) in cases.enumerated() {
            let url = dir.appendingPathComponent("k\(i).mhz")
            try data.write(to: url)
            XCTAssertThrowsError(try BlobReader(url: url, key: key), "durum \(i) reddedilmeli")
        }
        let ok = dir.appendingPathComponent("ok.mhz")
        try sealed.write(to: ok)
        XCTAssertEqual(try BlobReader(url: ok, key: key).read(offset: 0, length: plain.count), plain)
    }

    func testProgressCanCancelMidFile() throws {
        let key = SymmetricKey(size: .bits256)
        let src = dir.appendingPathComponent("buyuk.bin")
        try Crypto.randomBytes(5 << 20).write(to: src)
        let dest = dir.appendingPathComponent("buyuk.mhz")
        var calls = 0
        XCTAssertThrowsError(try BlobCrypto.encryptFile(at: src, to: dest, key: key) { _ in
            calls += 1
            if calls == 2 { throw MaintenanceCancelled() }
        })
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path), "yarım dosya kalmamalı")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".tmp") }
        XCTAssertEqual(leftovers, [])
    }

    // Denetim: anahtar dosyası sorgusuz siliniyor / üzerine yazılıyordu.
    func testKeyfileStoreNeverLosesAKey() throws {
        let store = KeyfileStore(directory: dir.appendingPathComponent("Anahtarlar"))
        let id = UUID()
        let first = Vault.generateKeyfile(), second = Vault.generateKeyfile()
        try store.save(first, for: id)
        try store.save(first, for: id) // aynısı: arşiv oluşmamalı
        try store.save(second, for: id)
        XCTAssertEqual(store.load(for: id), second)
        XCTAssertEqual(store.candidates(for: id), [second, first])

        try store.archive(for: id)
        XCTAssertNil(store.load(for: id))
        XCTAssertEqual(Set(store.candidates(for: id)), [first, second], "kaldırılan anahtar arşivden hâlâ denenebilmeli")
        let perms = try FileManager.default.attributesOfItem(atPath: store.directory.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o700)
    }

    // Denetim: klasördeki gizli dosya/paket/kısayol atlanınca orijinal yine de çöpe önerilebiliyordu.
    func testImportPlanCountsSkippedItems() throws {
        let fm = FileManager.default
        let project = dir.appendingPathComponent("Proje")
        try fm.createDirectory(at: project.appendingPathComponent("alt"), withIntermediateDirectories: true)
        try Data("a".utf8).write(to: project.appendingPathComponent("not.txt"))
        try Data("b".utf8).write(to: project.appendingPathComponent("alt/rapor.txt"))
        try Data("SECRET=1".utf8).write(to: project.appendingPathComponent(".env"))
        try Data().write(to: project.appendingPathComponent(".DS_Store"))
        try fm.createDirectory(at: project.appendingPathComponent("Eklenti.bundle/Contents"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: project.appendingPathComponent("kisayol"), withDestinationURL: project.appendingPathComponent("not.txt"))
        let locked = project.appendingPathComponent("kilitli")
        try fm.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data("c".utf8).write(to: locked.appendingPathComponent("gizli.txt"))
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)

        let clean = dir.appendingPathComponent("Temiz")
        try fm.createDirectory(at: clean, withIntermediateDirectories: true)
        try Data("d".utf8).write(to: clean.appendingPathComponent("foto.jpg"))
        let single = dir.appendingPathComponent("tek.txt")
        try Data("e".utf8).write(to: single)

        let plan = ImportPlan(urls: [project, clean, single])
        XCTAssertEqual(Set(plan.items.map(\.url.lastPathComponent)), ["not.txt", "rapor.txt", "foto.jpg", "tek.txt"])
        XCTAssertEqual(plan.items.first { $0.url.lastPathComponent == "rapor.txt" }?.folderPath, ["Proje", "alt"])
        let skippedNames = Set(plan.skipped[project] ?? [])
        XCTAssertTrue(skippedNames.isSuperset(of: [".env", "Eklenti.bundle", "kisayol", "kilitli"]), "atlananlar: \(skippedNames)")
        XCTAssertFalse(skippedNames.contains(".DS_Store"))

        // Hepsi güvenle kaydedilmiş olsa bile atlanan öğesi olan klasör çöpe önerilmez.
        let stored: [URL: Int] = [project: 2, clean: 1, single: 1]
        XCTAssertEqual(Set(plan.removableSources(safelyStored: stored)), [clean, single])
        // Bir dosyası eksik kaydedilen kaynak da önerilmez.
        XCTAssertEqual(plan.removableSources(safelyStored: [clean: 0, single: 1]), [single])
    }
}
