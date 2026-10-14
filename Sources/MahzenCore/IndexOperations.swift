import Foundation

/// Dizin üzerinde klasör, etiket ve çöp kutusu işlemleri. Disk işi yapmaz; kalıcı silinen dosyaların
/// kimliklerini döndürür, şifreli içerikleri silmek çağıranın işidir.
extension VaultIndex {
    // MARK: - Klasörler

    public func folder(_ id: UUID?) -> Folder? {
        guard let id else { return nil }
        return folders.first { $0.id == id }
    }

    public func childFolders(of parent: UUID?) -> [Folder] {
        folders
            .filter { $0.parentID == parent && $0.deletedAt == nil }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func liveFiles(in folder: UUID?) -> [FileRecord] {
        files.filter { $0.folderID == folder && $0.deletedAt == nil }
    }

    public var liveFiles: [FileRecord] { files.filter { $0.deletedAt == nil } }

    /// Kökten klasöre kadar olan yol (kök hariç).
    public func path(to id: UUID?) -> [Folder] {
        var result: [Folder] = []
        var current = folder(id)
        var seen = Set<UUID>()
        while let f = current, seen.insert(f.id).inserted {
            result.insert(f, at: 0)
            current = folder(f.parentID)
        }
        return result
    }

    /// Klasörün altındaki tüm klasörler (kendisi hariç, silinmiş olanlar dahil).
    public func descendantFolderIDs(of id: UUID) -> Set<UUID> {
        var result = Set<UUID>()
        var queue = [id]
        while let next = queue.popLast() {
            for child in folders where child.parentID == next && !result.contains(child.id) {
                result.insert(child.id)
                queue.append(child.id)
            }
        }
        return result
    }

    /// Klasördeki (alt klasörler dahil) canlı dosya sayısı.
    public func liveFileCount(inTree id: UUID) -> Int {
        let ids = descendantFolderIDs(of: id).union([id])
        return files.filter { $0.deletedAt == nil && $0.folderID.map(ids.contains) == true }.count
    }

    /// `names` yolundaki klasörleri (yoksa oluşturarak) bulur; aynı adlı canlı klasör varsa onu kullanır.
    public mutating func ensureFolderPath(_ names: [String], under parent: UUID?) -> UUID? {
        var current = parent
        for name in names where !name.isEmpty {
            if let existing = folders.first(where: { $0.parentID == current && $0.deletedAt == nil && $0.name == name }) {
                current = existing.id
            } else {
                let created = Folder(name: name, parentID: current)
                folders.append(created)
                current = created.id
            }
        }
        return current
    }

    @discardableResult
    public mutating func createFolder(named name: String, in parent: UUID?) -> UUID {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Yeni Klasör" : name
        var candidate = base
        var n = 2
        while folders.contains(where: { $0.parentID == parent && $0.deletedAt == nil && $0.name == candidate }) {
            candidate = "\(base) \(n)"
            n += 1
        }
        let folder = Folder(name: candidate, parentID: parent)
        folders.append(folder)
        return folder.id
    }

    public mutating func renameFolder(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].name = trimmed
    }

    public mutating func moveFiles(_ ids: Set<UUID>, to folder: UUID?) {
        for i in files.indices where ids.contains(files[i].id) { files[i].folderID = folder }
    }

    /// Klasörü kendi altına taşımaya izin vermez. Taşındıysa `true`.
    @discardableResult
    public mutating func moveFolder(_ id: UUID, to parent: UUID?) -> Bool {
        if let parent, parent == id || descendantFolderIDs(of: id).contains(parent) { return false }
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return false }
        folders[i].parentID = parent
        return true
    }

    // MARK: - Etiketler ve mükerrerler

    public var allTags: [String] {
        Array(Set(liveFiles.flatMap(\.tags))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public mutating func setTags(_ tags: [String], for ids: Set<UUID>) {
        let clean = Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        for i in files.indices where ids.contains(files[i].id) { files[i].tags = clean }
    }

    /// Aynı içerik kasada (çöp kutusu dışında) zaten varsa onu döndürür.
    public func existingFile(withHash hash: String) -> FileRecord? {
        files.first { $0.sha256 == hash && $0.deletedAt == nil }
    }

    // MARK: - Çöp kutusu

    public mutating func trashFiles(_ ids: Set<UUID>, at date: Date = Date()) {
        for i in files.indices where ids.contains(files[i].id) && files[i].deletedAt == nil { files[i].deletedAt = date }
    }

    /// Klasörü ve içindekileri aynı zaman damgasıyla çöpe taşır; geri alırken birlikte dönerler.
    public mutating func trashFolder(_ id: UUID, at date: Date = Date()) {
        let tree = descendantFolderIDs(of: id).union([id])
        for i in folders.indices where tree.contains(folders[i].id) && folders[i].deletedAt == nil { folders[i].deletedAt = date }
        for i in files.indices where files[i].folderID.map(tree.contains) == true && files[i].deletedAt == nil { files[i].deletedAt = date }
    }

    public mutating func restoreFile(_ id: UUID) {
        guard let i = files.firstIndex(where: { $0.id == id }) else { return }
        files[i].deletedAt = nil
        if let parent = files[i].folderID, folder(parent)?.deletedAt != nil || folder(parent) == nil {
            files[i].folderID = nil
        }
    }

    public mutating func restoreFolder(_ id: UUID) {
        guard let i = folders.firstIndex(where: { $0.id == id }), let stamp = folders[i].deletedAt else { return }
        let tree = descendantFolderIDs(of: id).union([id])
        for j in folders.indices where tree.contains(folders[j].id) && folders[j].deletedAt == stamp { folders[j].deletedAt = nil }
        for j in files.indices where files[j].folderID.map(tree.contains) == true && files[j].deletedAt == stamp { files[j].deletedAt = nil }
        if let parent = folders[i].parentID, folder(parent)?.deletedAt != nil || folder(parent) == nil {
            folders[i].parentID = nil
        }
    }

    public mutating func trashNote(_ id: UUID, at date: Date = Date()) {
        if let i = notes.firstIndex(where: { $0.id == id }) { notes[i].deletedAt = date }
    }

    public mutating func restoreNote(_ id: UUID) {
        if let i = notes.firstIndex(where: { $0.id == id }) { notes[i].deletedAt = nil }
    }

    public mutating func trashSecret(_ id: UUID, at date: Date = Date()) {
        if let i = secrets.firstIndex(where: { $0.id == id }) { secrets[i].deletedAt = date }
    }

    public mutating func restoreSecret(_ id: UUID) {
        if let i = secrets.firstIndex(where: { $0.id == id }) { secrets[i].deletedAt = nil }
    }

    /// Çöp kutusunda üst düzeyde gösterilecek öğeler (silinmiş bir klasörün içindekiler klasörle birlikte görünür).
    public var trashedFolders: [Folder] {
        folders.filter { f in f.deletedAt != nil && folder(f.parentID).map { $0.deletedAt != f.deletedAt } ?? true }
    }

    public var trashedFiles: [FileRecord] {
        files.filter { f in f.deletedAt != nil && folder(f.folderID).map { $0.deletedAt != f.deletedAt } ?? true }
    }

    public var trashedNotes: [Note] { notes.filter { $0.deletedAt != nil } }
    public var trashedSecrets: [Secret] { secrets.filter { $0.deletedAt != nil } }

    public var trashCount: Int {
        trashedFolders.count + trashedFiles.count + trashedNotes.count + trashedSecrets.count
    }

    // MARK: - Kalıcı silme (şifreli içerikleri silinecek dosya kimliklerini döndürür)

    public mutating func purgeFiles(_ ids: Set<UUID>) -> [UUID] {
        let removed = files.filter { ids.contains($0.id) }.map(\.id)
        files.removeAll { ids.contains($0.id) }
        return removed
    }

    public mutating func purgeFolder(_ id: UUID) -> [UUID] {
        let tree = descendantFolderIDs(of: id).union([id])
        folders.removeAll { tree.contains($0.id) }
        return purgeFiles(Set(files.filter { $0.folderID.map(tree.contains) == true }.map(\.id)))
    }

    public mutating func purgeNote(_ id: UUID) { notes.removeAll { $0.id == id } }
    public mutating func purgeSecret(_ id: UUID) { secrets.removeAll { $0.id == id } }

    public mutating func emptyTrash() -> [UUID] {
        var removed: [UUID] = []
        for f in folders where f.deletedAt != nil && folders.contains(where: { $0.id == f.id }) {
            removed += purgeFolder(f.id)
        }
        removed += purgeFiles(Set(files.filter { $0.deletedAt != nil }.map(\.id)))
        notes.removeAll { $0.deletedAt != nil }
        secrets.removeAll { $0.deletedAt != nil }
        return removed
    }

    /// Saklama süresi dolmuş öğeleri kalıcı siler.
    public mutating func purgeExpired(now: Date = Date(), retentionDays: Int) -> [UUID] {
        guard retentionDays > 0 else { return [] }
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        func expired(_ d: Date?) -> Bool { d.map { $0 < cutoff } ?? false }
        var removed: [UUID] = []
        for f in folders where expired(f.deletedAt) && folders.contains(where: { $0.id == f.id }) {
            removed += purgeFolder(f.id)
        }
        removed += purgeFiles(Set(files.filter { expired($0.deletedAt) }.map(\.id)))
        notes.removeAll { expired($0.deletedAt) }
        secrets.removeAll { expired($0.deletedAt) }
        return removed
    }
}
