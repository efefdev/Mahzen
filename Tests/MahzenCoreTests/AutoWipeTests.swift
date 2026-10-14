import XCTest
@testable import MahzenCore

final class AutoWipeTests: XCTestCase {
    var dir: URL!
    let password = "doğru-at-pil-zımba-42"
    let small = KDFSettings.argon2id(time: 1, memoryKiB: 8192, parallelism: 1)

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("mahzen-wipe-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testOffByDefaultDoesNotCount() throws {
        _ = try Vault.create(at: dir, password: password, kdf: small)
        for _ in 0..<10 { XCTAssertEqual(try Vault.recordFailedAttempt(at: dir), .counted(remaining: nil)) }
        XCTAssertNil(try Vault.readHeader(at: dir).failedAttempts)
        _ = try Vault.unlock(at: dir, password: password)
    }

    func testWipesAfterLimit() throws {
        let vault = try Vault.create(at: dir, password: password, kdf: small)
        try vault.setAutoWipe(attempts: 3)
        XCTAssertEqual(try Vault.recordFailedAttempt(at: dir), .counted(remaining: 2))
        XCTAssertEqual(try Vault.recordFailedAttempt(at: dir), .counted(remaining: 1))
        XCTAssertEqual(Vault.remainingAttempts(at: dir), 1)
        XCTAssertEqual(try Vault.recordFailedAttempt(at: dir), .wiped)
        XCTAssertFalse(Vault.exists(at: dir))
        XCTAssertThrowsError(try Vault.unlock(at: dir, password: password))
    }

    func testSuccessfulUnlockResetsCounterAndRewrapKeepsSetting() throws {
        let vault = try Vault.create(at: dir, password: password, kdf: small)
        try vault.setAutoWipe(attempts: 4)
        _ = try Vault.recordFailedAttempt(at: dir)
        _ = try Vault.recordFailedAttempt(at: dir)
        let opened = try Vault.unlock(at: dir, password: password)
        opened.clearFailedAttempts()
        XCTAssertNil(try Vault.readHeader(at: dir).failedAttempts)
        try opened.changePassword(current: password, new: "yeni-parola-12345", kdf: small)
        XCTAssertEqual(try Vault.readHeader(at: dir).wipeAfterFailedAttempts, 4)
        try opened.setAutoWipe(attempts: nil)
        XCTAssertNil(try Vault.readHeader(at: dir).wipeAfterFailedAttempts)
        XCTAssertThrowsError(try opened.setAutoWipe(attempts: 1))
    }
}
