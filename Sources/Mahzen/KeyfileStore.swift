import Foundation

/// Anahtar dosyalarını bu Mac'te (FileVault ile şifreli diskte) saklar; kasa SSD'sine asla yazılmaz.
/// Dosya adı yalnızca kasa kimliğidir; kasanın kendisinde bu dosyaya dair hiçbir iz yoktur.
enum KeyfileStore {
    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mahzen", isDirectory: true)
            .appendingPathComponent("Anahtarlar", isDirectory: true)
    }

    static func url(for vaultID: UUID) -> URL {
        directory.appendingPathComponent(vaultID.uuidString.lowercased())
    }

    static func load(for vaultID: UUID) -> Data? {
        try? Data(contentsOf: url(for: vaultID))
    }

    /// Yazar, geri okuyup doğrular; yalnızca kullanıcının okuyabileceği izinlerle.
    static func save(_ keyfile: Data, for vaultID: UUID) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let target = url(for: vaultID)
        try keyfile.write(to: target, options: [.atomic])
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        guard try Data(contentsOf: target) == keyfile else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: target.path])
        }
    }

    static func delete(for vaultID: UUID) {
        try? FileManager.default.removeItem(at: url(for: vaultID))
    }
}
