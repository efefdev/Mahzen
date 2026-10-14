import Foundation

/// Kasanın şifreli dizini: dosya kayıtları, notlar, parolalar ve tercihler. Tamamı tek parça olarak şifrelenir.
public struct VaultIndex: Codable, Hashable, Sendable {
    public var version = 1
    public var files: [FileRecord] = []
    public var folders: [Folder] = []
    public var notes: [Note] = []
    public var secrets: [Secret] = []
    public var preferences = Preferences()

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        files = try c.decodeIfPresent([FileRecord].self, forKey: .files) ?? []
        folders = try c.decodeIfPresent([Folder].self, forKey: .folders) ?? []
        notes = try c.decodeIfPresent([Note].self, forKey: .notes) ?? []
        secrets = try c.decodeIfPresent([Secret].self, forKey: .secrets) ?? []
        preferences = try c.decodeIfPresent(Preferences.self, forKey: .preferences) ?? Preferences()
    }
}

public struct FileRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var size: Int64
    public var contentType: String?
    public var addedAt: Date
    public var originalModifiedAt: Date?
    public var hasThumbnail: Bool
    public var favorite: Bool
    /// `nil` = kök klasör.
    public var folderID: UUID?
    public var tags: [String]
    /// Düz içeriğin SHA-256 özeti; aynı dosyanın iki kez eklenmesini önlemek için.
    public var sha256: String?
    /// Doluysa öğe çöp kutusundadır.
    public var deletedAt: Date?

    public init(id: UUID, name: String, size: Int64, contentType: String?, addedAt: Date = Date(),
                originalModifiedAt: Date? = nil, hasThumbnail: Bool = false, favorite: Bool = false,
                folderID: UUID? = nil, tags: [String] = [], sha256: String? = nil) {
        self.id = id
        self.name = name
        self.size = size
        self.contentType = contentType
        self.addedAt = addedAt
        self.originalModifiedAt = originalModifiedAt
        self.hasThumbnail = hasThumbnail
        self.favorite = favorite
        self.folderID = folderID
        self.tags = tags
        self.sha256 = sha256
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        size = try c.decode(Int64.self, forKey: .size)
        contentType = try c.decodeIfPresent(String.self, forKey: .contentType)
        addedAt = try c.decode(Date.self, forKey: .addedAt)
        originalModifiedAt = try c.decodeIfPresent(Date.self, forKey: .originalModifiedAt)
        hasThumbnail = try c.decodeIfPresent(Bool.self, forKey: .hasThumbnail) ?? false
        favorite = try c.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        folderID = try c.decodeIfPresent(UUID.self, forKey: .folderID)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        sha256 = try c.decodeIfPresent(String.self, forKey: .sha256)
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }
}

public struct Folder: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var name: String
    /// `nil` = kök klasör.
    public var parentID: UUID?
    public var createdAt = Date()
    public var color: String?
    public var deletedAt: Date?

    public init(name: String, parentID: UUID? = nil) {
        self.name = name
        self.parentID = parentID
    }
}

public struct Note: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var title = ""
    public var body = ""
    public var createdAt = Date()
    public var updatedAt = Date()
    public var pinned = false
    public var color: String?
    public var deletedAt: Date?

    public init() {}
}

public enum SecretCategory: String, Codable, CaseIterable, Sendable {
    case login, card, wifi, server, note, other
}

public struct Secret: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var title = ""
    public var username = ""
    public var password = ""
    public var url = ""
    public var notes = ""
    public var category = SecretCategory.login
    public var favorite = false
    public var createdAt = Date()
    public var updatedAt = Date()
    public var deletedAt: Date?

    public init() {}
}

public struct GeneratorOptions: Codable, Hashable, Sendable {
    public var length = 20
    public var uppercase = true
    public var lowercase = true
    public var digits = true
    public var symbols = true
    public var avoidAmbiguous = true

    public init() {}
}

public struct Preferences: Codable, Hashable, Sendable {
    public var displayName = "Mahzen"
    public var accent = "indigo"
    public var appearance = "system"
    public var autoLockMinutes = 5
    public var clipboardClearSeconds = 30
    public var lockOnSleep = true
    public var hideFromScreenCapture = true
    public var noteFontSize: Double = 15
    public var noteFontDesign = "default"
    public var filesLayout = "grid"
    public var generator = GeneratorOptions()
    /// Çöp kutusundaki öğeler bu kadar gün sonra kalıcı silinir; 0 = otomatik silme yok.
    public var trashRetentionDays = 30
    /// Kasaya ekledikten sonra orijinalleri Mac'in Çöp Kutusu'na taşımayı sor.
    public var askToTrashOriginals = true
    /// Yedek klasörünün tam yolu (ör. /Volumes/Yedek/Mahzen Kasası Yedek). Şifreli dizinde saklanır.
    public var backupPath: String?
    public var lastBackupAt: Date?
    /// Son yedekten bu kadar gün geçince hatırlat; 0 = hatırlatma yok.
    public var backupReminderDays = 7

    public init() {}

    // Yeni sürümlerde eklenen alanlar eski kasalarda eksik olabilir; eksikse varsayılan kullanılır.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        displayName = value(.displayName, d.displayName)
        accent = value(.accent, d.accent)
        appearance = value(.appearance, d.appearance)
        autoLockMinutes = value(.autoLockMinutes, d.autoLockMinutes)
        clipboardClearSeconds = value(.clipboardClearSeconds, d.clipboardClearSeconds)
        lockOnSleep = value(.lockOnSleep, d.lockOnSleep)
        hideFromScreenCapture = value(.hideFromScreenCapture, d.hideFromScreenCapture)
        noteFontSize = value(.noteFontSize, d.noteFontSize)
        noteFontDesign = value(.noteFontDesign, d.noteFontDesign)
        filesLayout = value(.filesLayout, d.filesLayout)
        generator = value(.generator, d.generator)
        trashRetentionDays = value(.trashRetentionDays, d.trashRetentionDays)
        askToTrashOriginals = value(.askToTrashOriginals, d.askToTrashOriginals)
        backupPath = try? c.decodeIfPresent(String.self, forKey: .backupPath)
        lastBackupAt = try? c.decodeIfPresent(Date.self, forKey: .lastBackupAt)
        backupReminderDays = value(.backupReminderDays, d.backupReminderDays)
    }
}
