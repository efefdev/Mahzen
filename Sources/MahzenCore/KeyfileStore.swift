import Foundation

/// Anahtar dosyalarını bu Mac'te (FileVault ile şifreli diskte) saklar; kasa SSD'sine asla yazılmaz.
/// Dosya adı yalnızca kasa kimliğidir; kasanın kendisinde bu dosyaya dair hiçbir iz yoktur.
///
/// Hiçbir anahtar dosyası silinmez ya da üzerine yazılmaz: değişen veya kaldırılan anahtar
/// `<kimlik>.arsiv-<zaman>` adıyla arşivlenir. Kasa ile yedekleri aynı kimliği paylaştığından,
/// kilit açılırken arşivdekiler de denenir; böylece hiçbir kopya kilitli kalmaz.
public struct KeyfileStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static let standard = KeyfileStore(
        directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mahzen", isDirectory: true)
            .appendingPathComponent("Anahtarlar", isDirectory: true)
    )

    public func url(for vaultID: UUID) -> URL {
        directory.appendingPathComponent(vaultID.uuidString.lowercased())
    }

    /// Bu kasa için etkin anahtar dosyası.
    public func load(for vaultID: UUID) -> Data? {
        try? Data(contentsOf: url(for: vaultID))
    }

    /// Denenecek tüm anahtarlar: önce etkin olan, sonra arşivdekiler (yeniden eskiye), tekrarsız.
    public func candidates(for vaultID: UUID) -> [Data] {
        let prefix = vaultID.uuidString.lowercased() + ".arsiv-"
        let archived = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasPrefix(prefix) }
            .sorted(by: >)
            .compactMap { try? Data(contentsOf: directory.appendingPathComponent($0)) }
        var seen = Set<Data>()
        return ([load(for: vaultID)].compactMap { $0 } + archived).filter { seen.insert($0).inserted }
    }

    /// Yazar ve geri okuyup doğrular. Farklı bir anahtar zaten varsa önce arşivlenir.
    public func save(_ keyfile: Data, for vaultID: UUID) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let target = url(for: vaultID)
        if let existing = load(for: vaultID) {
            if existing == keyfile { return }
            try archive(for: vaultID)
        }
        try keyfile.write(to: target, options: [.atomic])
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        guard try Data(contentsOf: target) == keyfile else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: target.path])
        }
    }

    /// Etkin anahtarı arşive taşır (silmez). Etkin anahtar yoksa bir şey yapmaz.
    public func archive(for vaultID: UUID) throws {
        let source = url(for: vaultID)
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        var target = directory.appendingPathComponent("\(vaultID.uuidString.lowercased()).arsiv-\(stamp)")
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = directory.appendingPathComponent("\(vaultID.uuidString.lowercased()).arsiv-\(stamp)-\(n)")
            n += 1
        }
        try FileManager.default.moveItem(at: source, to: target)
    }
}
