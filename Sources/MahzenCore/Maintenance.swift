import CryptoKit
import Foundation

public struct BackupReport: Sendable {
    public var copiedFiles = 0
    public var copiedBytes: Int64 = 0
    public var unchangedFiles = 0
    public var removedFiles = 0
    /// Dizinde kayıtlı ama kasada (kaynakta) bulunamayan dosyalar; yedekteki kopyaları korunur.
    public var missingInSource: [UUID] = []
}

public enum IntegrityProblem: Sendable, Equatable {
    case missing
    case damaged(String)
    case hashMismatch
}

public struct IntegrityReport: Sendable {
    public var checkedFiles = 0
    public var checkedBytes: Int64 = 0
    public var problems: [UUID: IntegrityProblem] = [:]
    /// Doğrulama sırasında hesaplanan içerik özetleri (eski kayıtlarda eksik olanları tamamlamak için).
    public var hashes: [UUID: String] = [:]
    public var brokenThumbnails: Set<UUID> = []
    /// Dizinde kaydı olmayan şifreli dosyalar ve yarım kalmış geçici dosyalar.
    public var orphanURLs: [URL] = []
    public var orphanBytes: Int64 = 0
    public var indexBackupReadable = true

    public init() {}
}

public struct MaintenanceCancelled: Error {
    public init() {}
}

extension Vault {
    // MARK: - Yedekleme

    /// Kasayı `destination` klasörüne artımlı olarak yedekler. Şifreli dosyalar olduğu gibi kopyalanır;
    /// yedek aynı parolayla açılır. Dizin ve başlık en son yazılır, böylece yarıda kalan yedek de tutarlıdır.
    /// `progress(kopyalanan, toplam)` `false` döndürürse işlem durur.
    public func backup(
        to destination: URL,
        fileIDs: Set<UUID>,
        thumbnailIDs: Set<UUID>,
        progress: (Int64, Int64) -> Bool = { _, _ in true }
    ) throws -> BackupReport {
        let fm = FileManager.default
        let source = folder.standardizedFileURL.resolvingSymlinksInPath().path
        let target = destination.standardizedFileURL.resolvingSymlinksInPath().path
        guard !target.hasPrefix(source + "/"), target != source, !source.hasPrefix(target + "/") else {
            throw VaultError.corrupted("yedek konumu kasanın kendisi veya içi olamaz")
        }
        if Vault.exists(at: destination) {
            let other = try Vault.readHeader(at: destination)
            guard other.vaultID == header.vaultID else {
                throw VaultError.corrupted("seçilen klasörde başka bir kasa var")
            }
        }

        // Tutarlı bir anlık görüntü: dizin ve başlık baştan belleğe alınır.
        let headerData = try Data(contentsOf: folder.appendingPathComponent(Self.headerName))
        let indexData = try Data(contentsOf: folder.appendingPathComponent(Self.indexName))
        let indexBackupData = try? Data(contentsOf: folder.appendingPathComponent(Self.indexBackupName))

        var report = BackupReport()
        var jobs: [(from: URL, to: URL, size: Int64)] = []
        func plan(_ src: URL, _ dst: URL, id: UUID?) {
            guard let size = fileSize(src) else {
                if let id { report.missingInSource.append(id) }
                return
            }
            if fileSize(dst) == size {
                report.unchangedFiles += 1
            } else {
                jobs.append((src, dst, size))
            }
        }
        for id in fileIDs {
            plan(blobURL(id), destination.appendingPathComponent(relativePath(blobURL(id))), id: id)
        }
        for id in thumbnailIDs {
            plan(thumbnailURL(id), destination.appendingPathComponent(relativePath(thumbnailURL(id))), id: nil)
        }

        let total = jobs.reduce(0) { $0 + $1.size }
        var done: Int64 = 0
        guard progress(0, total) else { throw MaintenanceCancelled() }
        for job in jobs {
            try fm.createDirectory(at: job.to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.copyFile(from: job.from, to: job.to) { n in
                done += Int64(n)
                return progress(done, total)
            }
            report.copiedFiles += 1
            report.copiedBytes += job.size
        }

        // Kaynakta kalıcı silinmiş öğelerin yedekteki kopyalarını temizle.
        let keepBlobs = Set(fileIDs.map { relativePath(blobURL($0)) })
        let keepThumbs = Set(thumbnailIDs.map { relativePath(thumbnailURL($0)) })
        for (sub, keep) in [("blobs", keepBlobs), ("thumbs", keepThumbs)] {
            let root = destination.appendingPathComponent(sub)
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { continue }
            while let url = e.nextObject() as? URL {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                if !keep.contains(relativePath(url)) {
                    try? fm.removeItem(at: url)
                    report.removedFiles += 1
                }
            }
        }

        if let indexBackupData { try indexBackupData.write(to: destination.appendingPathComponent(Self.indexBackupName), options: .atomic) }
        try indexData.write(to: destination.appendingPathComponent(Self.indexName), options: .atomic)
        try headerData.write(to: destination.appendingPathComponent(Self.headerName), options: .atomic)
        try? Self.readme.write(to: destination.appendingPathComponent("OKU-BENİ.txt"), atomically: true, encoding: .utf8)
        return report
    }

    // MARK: - Bütünlük taraması

    /// Her dosyayı baştan sona çözerek doğrular (AES-GCM etiketleri), özetini hesaplar,
    /// küçük resimleri ve sahipsiz dosyaları denetler. Diske hiçbir şey yazmaz.
    public func checkIntegrity(
        files: [FileRecord],
        progress: (Int64, Int64) -> Bool = { _, _ in true }
    ) throws -> IntegrityReport {
        var report = IntegrityReport()
        let total = files.reduce(0) { $0 + $1.size }
        var done: Int64 = 0
        guard progress(0, total) else { throw MaintenanceCancelled() }

        for file in files {
            report.checkedFiles += 1
            do {
                let hash = try verifyFile(file.id) { n in
                    done += Int64(n)
                    return progress(done, total)
                }
                report.hashes[file.id] = hash
                if let expected = file.sha256, expected != hash { report.problems[file.id] = .hashMismatch }
            } catch is MaintenanceCancelled {
                throw MaintenanceCancelled()
            } catch {
                report.problems[file.id] = fileSize(blobURL(file.id)) == nil ? .missing : .damaged(error.localizedDescription)
            }
            report.checkedBytes += file.size
            if file.hasThumbnail, (try? readThumbnail(file.id)) == nil { report.brokenThumbnails.insert(file.id) }
        }

        let referenced = Set(files.map { relativePath(blobURL($0.id)) })
            .union(files.filter(\.hasThumbnail).map { relativePath(thumbnailURL($0.id)) })
        let fm = FileManager.default
        for sub in ["blobs", "thumbs"] {
            let root = folder.appendingPathComponent(sub)
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { continue }
            while let url = e.nextObject() as? URL {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                // exFAT'ta macOS'un öznitelik dosyaları ve Finder dosyaları kasaya ait değildir.
                if url.lastPathComponent.hasPrefix("._") || url.lastPathComponent == ".DS_Store" { continue }
                if !referenced.contains(relativePath(url)) {
                    report.orphanURLs.append(url)
                    report.orphanBytes += fileSize(url) ?? 0
                }
            }
        }
        if let data = try? Data(contentsOf: folder.appendingPathComponent(Self.indexBackupName)) {
            report.indexBackupReadable = (try? Crypto.open(data, key: indexKey, aad: indexAAD)) != nil
        }
        return report
    }

    /// Dosyayı çözerek doğrular ve düz içeriğin SHA-256 özetini döndürür.
    public func verifyFile(_ id: UUID, progress: (Int) -> Bool = { _ in true }) throws -> String {
        let input = try FileHandle(forReadingFrom: blobURL(id))
        defer { try? input.close() }
        var hasher = SHA256()
        try BlobCrypto.decrypt(
            read: { try BlobCrypto.readFully(input, $0) },
            write: { chunk in
                hasher.update(data: chunk)
                if !progress(chunk.count) { throw MaintenanceCancelled() }
            },
            key: fileKey(id)
        )
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Yedekteki kopyayı önce doğrular, sağlamsa kasadaki bozuk/eksik dosyanın yerine koyar.
    public func restoreFile(_ id: UUID, fromBackup backupFolder: URL) throws {
        let backupBlob = backupFolder.appendingPathComponent(relativePath(blobURL(id)))
        guard Vault.exists(at: backupFolder), try Vault.readHeader(at: backupFolder).vaultID == header.vaultID else {
            throw VaultError.corrupted("yedek bu kasaya ait değil")
        }
        let input = try FileHandle(forReadingFrom: backupBlob)
        try BlobCrypto.decrypt(read: { try BlobCrypto.readFully(input, $0) }, write: { _ in }, key: fileKey(id))
        try? input.close()
        let dest = blobURL(id)
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.copyFile(from: backupBlob, to: dest) { _ in true }
    }

    public func removeOrphans(_ urls: [URL]) {
        let root = folder.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        for url in urls where url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Yardımcılar

    /// Kasa içindeki göreli yol ("blobs/ab/<id>.mhz" veya "thumbs/<id>.mhz").
    /// Yol ön eki karşılaştırması yapmaz: /var ile /private/var gibi sembolik bağlantılar yanıltmasın.
    func relativePath(_ url: URL) -> String {
        let components = url.standardizedFileURL.pathComponents
        guard let i = components.lastIndex(where: { $0 == "blobs" || $0 == "thumbs" }) else { return url.lastPathComponent }
        return components[i...].joined(separator: "/")
    }

    func fileSize(_ url: URL) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return (attrs[.size] as? NSNumber)?.int64Value
    }

    /// 4 MB'lık parçalarla kopyalar; önce geçici dosyaya yazar, bitince yerine taşır.
    static func copyFile(from source: URL, to destination: URL, progress: (Int) -> Bool) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        try BlobCrypto.writeAtomically(to: destination) { out in
            while let chunk = try input.read(upToCount: 4 << 20), !chunk.isEmpty {
                try out.write(contentsOf: chunk)
                if !progress(chunk.count) { throw MaintenanceCancelled() }
            }
        }
    }
}
