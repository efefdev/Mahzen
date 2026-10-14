import Foundation

/// Kasaya eklenecek dosyaların listesi ve atlanan öğelerin hesabı.
///
/// Klasör sürüklendiğinde gizli dosyalar, paketler (ör. Keynote/Pages belgeleri, uygulamalar),
/// sembolik bağlantılar ve okunamayan öğeler kasaya eklenmez. Bunların sayısı kaynağa göre tutulur;
/// atlanan öğesi olan bir kaynağın orijinali "kasada" sayılmaz ve çöpe taşınması önerilmez.
public struct ImportPlan: Sendable {
    public struct Item: Sendable {
        public let url: URL
        public let size: Int64
        public let modified: Date?
        /// Sürüklenen klasörün kasada yeniden oluşturulacak yolu (ör. ["Tatil", "2026"]).
        public let folderPath: [String]
        /// Kullanıcının seçtiği/sürüklediği üst öğe.
        public let source: URL
    }

    public var items: [Item] = []
    public var skipped: [URL: [String]] = [:]

    public var skippedCount: Int { skipped.values.reduce(0) { $0 + $1.count } }

    public init(urls: [URL]) {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey,
                                         .isHiddenKey, .fileSizeKey, .contentModificationDateKey]
        for source in urls {
            guard let values = try? source.resourceValues(forKeys: keys) else {
                skip(source, source)
                continue
            }
            if values.isDirectory == true, values.isPackage != true, values.isSymbolicLink != true {
                walk(directory: source, keys: keys)
            } else if values.isRegularFile == true, values.isSymbolicLink != true {
                items.append(Item(url: source, size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate,
                                  folderPath: [], source: source))
            } else {
                skip(source, source)
            }
        }
    }

    private mutating func walk(directory source: URL, keys: Set<URLResourceKey>) {
        let root = source.standardizedFileURL.pathComponents
        var unreadable: [URL] = []
        let enumerator = FileManager.default.enumerator(
            at: source, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants]
        ) { url, _ in
            unreadable.append(url)
            return true
        }
        while let child = enumerator?.nextObject() as? URL {
            guard let v = try? child.resourceValues(forKeys: keys) else {
                skip(source, child)
                continue
            }
            if v.isHidden == true || child.lastPathComponent.hasPrefix(".") {
                // .DS_Store gibi Finder dosyaları kullanıcı verisi değildir; sayılmaz.
                if child.lastPathComponent != ".DS_Store" { skip(source, child) }
                if v.isDirectory == true { enumerator?.skipDescendants() }
                continue
            }
            if v.isSymbolicLink == true || v.isPackage == true {
                skip(source, child)
                continue
            }
            if v.isDirectory == true { continue }
            guard v.isRegularFile == true else {
                skip(source, child)
                continue
            }
            let parent = child.deletingLastPathComponent().standardizedFileURL.pathComponents
            items.append(Item(url: child, size: Int64(v.fileSize ?? 0), modified: v.contentModificationDate,
                              folderPath: [source.lastPathComponent] + parent.dropFirst(root.count), source: source))
        }
        for url in unreadable { skip(source, url) }
    }

    private mutating func skip(_ source: URL, _ url: URL) {
        skipped[source, default: []].append(url.lastPathComponent)
    }

    /// Orijinali güvenle çöpe taşınabilecek kaynaklar: içindeki her dosya kasaya girmiş (veya zaten
    /// kasadaymış) ve hiçbir öğesi atlanmamış olanlar.
    public func removableSources(safelyStored: [URL: Int]) -> [URL] {
        let expected = Dictionary(grouping: items, by: \.source).mapValues(\.count)
        return expected.compactMap { source, count in
            safelyStored[source] == count && (skipped[source]?.isEmpty ?? true) ? source : nil
        }
    }
}
