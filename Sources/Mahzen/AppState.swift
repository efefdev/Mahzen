import AppKit
import MahzenCore
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

enum Section: String, CaseIterable, Identifiable {
    case files, notes, secrets, trash, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .files: return "Dosyalar"
        case .notes: return "Notlar"
        case .secrets: return "Parolalar"
        case .trash: return "Çöp Kutusu"
        case .settings: return "Ayarlar"
        }
    }

    var symbol: String {
        switch self {
        case .files: return "doc.on.doc.fill"
        case .notes: return "note.text"
        case .secrets: return "key.fill"
        case .trash: return "trash.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct TaskProgress: Equatable {
    var title: String
    var detail = ""
    var fraction: Double?
    var cancellable = false
}

struct AlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Arka plandaki işi durdurma isteği (iş parçacıkları arasında paylaşılır).
final class CancelFlag: @unchecked Sendable {
    var value = false
}

/// İlerleme sayacını arka plan iş parçacığından güvenle güncellemek için.
private final class ProgressCounter: @unchecked Sendable {
    var done: Int64 = 0
    var lastReport = Date.distantPast
}

@MainActor
final class AppState: ObservableObject {
    enum Phase { case welcome, locked, unlocked }

    @Published var phase: Phase = .welcome
    @Published private(set) var vaultURL: URL?
    @Published var index = VaultIndex()
    @Published var section: Section = .files
    @Published var task: TaskProgress?
    @Published var alert: AlertItem?
    @Published var toast: String?
    @Published var recoveredFromBackup = false
    @Published var newSecretRequested = false
    @Published private(set) var kdfSummary = ""
    @Published var integrityReport: IntegrityReport?
    /// Açık kasa bu Mac'teki anahtar dosyasıyla mı korunuyor?
    @Published private(set) var keyfileEnabled = false
    /// Yanlış parola sınırı (kasa başlığında); `nil` = kapalı.
    @Published private(set) var autoWipeAttempts: Int?
    private var cancelFlag = CancelFlag()
    /// Her kilit açılışında değişir. Kilitten sonra biten bir işlem, sonucunu yeni oturuma yazamaz.
    private var session = UUID()
    /// Hassas olarak kopyalanan son içeriğin pano sayacı (kilitte/çıkışta temizlemek için).
    private var sensitiveClipboardCount: Int?
    private let keyfiles = KeyfileStore.standard

    private(set) var vault: Vault?
    private var thumbnails: [UUID: NSImage] = [:]
    private var lastActivity = Date()
    private var failedAttempts = 0
    private var cancelRequested = false
    private var saveWork: DispatchWorkItem?
    private var toastWork: DispatchWorkItem?
    private let io = DispatchQueue(label: "mahzen.io", qos: .userInitiated)
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("Mahzen-\(UUID().uuidString)", isDirectory: true)

    /// Uygulamanın yanındaki kasa: SSD'de `Mahzen.app` ile `Mahzen Kasası` yan yana durur.
    static var defaultVaultURL: URL {
        Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Mahzen Kasası", isDirectory: true)
    }

    var prefs: Preferences { index.preferences }
    var accent: AccentChoice { AccentChoice(phase == .unlocked ? prefs.accent : UserDefaults.standard.string(forKey: "lockAccent")) }

    init() {
        let remembered = UserDefaults.standard.string(forKey: "lastVaultPath").map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let found = [Self.defaultVaultURL, remembered].compactMap({ $0 }).first(where: Vault.exists) {
            vaultURL = found
            phase = .locked
        }
        installObservers()
        applyAppearance()
        Self.removeStaleTemporaryFolders()
    }

    /// Önceki bir çalışmadan (ör. çökme) kalan, 1 saatten eski şifresiz geçici klasörleri siler.
    private static func removeStaleTemporaryFolders() {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        let cutoff = Date().addingTimeInterval(-3600)
        for name in (try? fm.contentsOfDirectory(atPath: tmp.path)) ?? [] where name.hasPrefix("Mahzen-") {
            let url = tmp.appendingPathComponent(name)
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if modified < cutoff { try? fm.removeItem(at: url) }
        }
    }

    private func isCurrent(_ token: UUID) -> Bool { token == session && phase == .unlocked && vault != nil }

    // MARK: - Kasa açma / kapama

    func selectVault(_ url: URL) {
        guard Vault.exists(at: url) else {
            alert = AlertItem(title: "Kasa bulunamadı", message: VaultError.notAVault.localizedDescription)
            return
        }
        vaultURL = url
        phase = .locked
    }

    func showWelcome() { phase = .welcome }

    func createVault(at folder: URL, password: String) {
        task = TaskProgress(title: "Kasa oluşturuluyor", detail: "Bu Mac için anahtar türetme gücü ayarlanıyor…")
        Task {
            do {
                let vault = try await Task.detached(priority: .userInitiated) {
                    try Vault.create(at: folder, password: password)
                }.value
                task = nil
                open(vault, index: VaultIndex(), recovered: false)
            } catch {
                task = nil
                alert = AlertItem(title: "Kasa oluşturulamadı", message: error.localizedDescription)
            }
        }
    }

    /// Hata varsa mesajını döndürür. `beforeOpen`, parola doğrulandıktan sonra kasa gösterilmeden
    /// önce çalışır (kilit açılma animasyonu için).
    func unlock(password: String, beforeOpen: (@MainActor () async -> Void)? = nil) async -> String? {
        guard let url = vaultURL else { return "Kasa seçilmedi." }
        do {
            let (vault, loaded, recovered) = try await Task.detached(priority: .userInitiated) {
                let vault = try Self.unlockVault(at: url, password: password)
                vault.clearFailedAttempts()
                let (index, recovered) = try vault.loadIndex()
                // Eski (PBKDF2) kasaları doğru parola elimizdeyken Argon2id'ye yükselt.
                if vault.needsKDFUpgrade { try vault.upgradeKDF(password: password) }
                return (vault, index, recovered)
            }.value
            failedAttempts = 0
            await beforeOpen?()
            open(vault, index: loaded, recovered: recovered)
            return nil
        } catch VaultError.wrongPassword {
            // Yanlış parola sınırı açıksa say; aşıldıysa anahtarlar yok edilir.
            let outcome = try? await Task.detached { try Vault.recordFailedAttempt(at: url) }.value
            if outcome == .wiped {
                vaultWiped(url)
                return "Kasa silindi."
            }
            failedAttempts += 1
            try? await Task.sleep(for: .seconds(min(Double(failedAttempts), 5)))
            if case .counted(let remaining?) = outcome {
                return remaining == 1 ? "Parola yanlış. Son deneme hakkı: bir yanlış daha kasayı siler."
                    : "Parola yanlış. Kalan deneme: \(remaining)"
            }
            return VaultError.wrongPassword.localizedDescription
        } catch {
            // Arayüzde deneme hızını yavaşlatır; asıl koruma anahtar türetmenin maliyetidir.
            failedAttempts += 1
            try? await Task.sleep(for: .seconds(min(Double(failedAttempts), 5)))
            return error.localizedDescription
        }
    }

    /// Yanlış parola sınırı aşıldı: anahtarlar yok edildi, kasa artık açılamaz.
    private func vaultWiped(_ url: URL) {
        failedAttempts = 0
        vaultURL = nil
        if UserDefaults.standard.string(forKey: "lastVaultPath") == url.path {
            UserDefaults.standard.removeObject(forKey: "lastVaultPath")
        }
        phase = .welcome
        alert = AlertItem(
            title: "Kasa kalıcı olarak silindi",
            message: "Yanlış parola sınırı aşıldığı için kasanın anahtarları yok edildi. Kasadaki veriler artık hiçbir parolayla açılamaz. Klasörde kalan şifreli dosyalar işe yaramaz; silebilirsiniz."
        )
    }

    /// Yanlış parola sınırını açar (`attempts` dolu) veya kapatır (`nil`).
    func setAutoWipe(_ attempts: Int?) {
        guard let vault else { return }
        do {
            try vault.setAutoWipe(attempts: attempts)
            autoWipeAttempts = attempts
        } catch {
            alert = AlertItem(title: "Ayar kaydedilemedi", message: error.localizedDescription)
        }
    }

    /// Bu Mac'te kasa için bir anahtar dosyası varsa onunla açar. Olmazsa yalnızca parolayla dener:
    /// anahtar dosyası eklenmeden önce alınmış eski bir yedek de açılabilsin. Başka Mac'te anahtar
    /// dosyası yoktur ve sonuç sadece "Parola yanlış" olur; kasanın anahtar dosyası istediği anlaşılmaz.
    nonisolated static func unlockVault(at url: URL, password: String) throws -> Vault {
        let header = try Vault.readHeader(at: url)
        // Etkin anahtar, sonra arşivdekiler (kasa ile yedekleri aynı kimliği paylaşır), en son yalnızca parola.
        for keyfile in KeyfileStore.standard.candidates(for: header.vaultID) {
            do {
                return try Vault.unlock(at: url, password: password, keyfile: keyfile)
            } catch VaultError.wrongPassword {
                continue
            }
        }
        return try Vault.unlock(at: url, password: password)
    }

    private func open(_ vault: Vault, index: VaultIndex, recovered: Bool) {
        session = UUID()
        self.vault = vault
        self.index = index
        kdfSummary = vault.header.kdf.summary
        keyfileEnabled = vault.requiresKeyfile
        autoWipeAttempts = vault.header.wipeAfterFailedAttempts
        recoveredFromBackup = recovered
        vaultURL = vault.folder
        UserDefaults.standard.set(vault.folder.path, forKey: "lastVaultPath")
        lastActivity = Date()
        phase = .unlocked
        section = .files
        rememberLockScreenLook()
        applyAppearance()
        applyWindowPrivacy()
        let expired = self.index.purgeExpired(retentionDays: prefs.trashRetentionDays)
        if !expired.isEmpty { io.async { expired.forEach(vault.deleteFile) } }
        if recovered || !expired.isEmpty { scheduleSave() }
    }

    /// Her zaman anında kilitler. Çalışan bir işlem varsa durdurulur; oturum değiştiği için
    /// sonucu kasaya yazılamaz, çöpe taşıma önerisi de gösterilemez.
    func lock() {
        guard phase == .unlocked else { return }
        cancelTask()
        task = nil
        flushSave()
        session = UUID()
        clearSensitiveClipboard()
        vault = nil
        index = VaultIndex()
        thumbnails.removeAll()
        currentFolder = nil
        recoveredFromBackup = false
        wipeTemporaryFiles()
        phase = .locked
        applyAppearance()
        applyWindowPrivacy()
    }

    // MARK: - Anahtar dosyası (kasayı bu Mac'e bağlama)

    /// Yeni bir anahtar dosyası üretip önce Mac'e kaydeder, sonra kasayı parola + dosya ister hale getirir.
    func enableKeyfile(password: String) async -> String? {
        guard let vault else { return "Kasa kilitli." }
        let id = vault.header.vaultID
        // Bu kimlik için zaten bir anahtar varken anahtarsız açılmış kasa, büyük olasılıkla anahtar
        // dosyası eklenmeden önce alınmış bir yedektir. Bağlamak asıl kasanın anahtarını değiştirirdi.
        if !vault.requiresKeyfile, !keyfiles.candidates(for: id).isEmpty {
            return "Bu Mac'te bu kasa için zaten bir anahtar dosyası var. Açtığın kasa, anahtar dosyası eklenmeden önce alınmış bir yedek olabilir. Asıl kasayı korumak için işlem yapılmadı; asıl kasayı açıp oradan devam et."
        }
        let keyfile = Vault.generateKeyfile()
        do {
            try keyfiles.save(keyfile, for: id)
        } catch {
            return "Anahtar dosyası bu Mac'e kaydedilemedi: \(error.localizedDescription)"
        }
        do {
            try await Task.detached(priority: .userInitiated) { try vault.setKeyfile(keyfile, password: password) }.value
        } catch {
            try? keyfiles.archive(for: id)
            return error.localizedDescription
        }
        keyfileEnabled = true
        return nil
    }

    /// Bu kasayı yeniden yalnızca parolayla açılır yapar. Anahtar dosyası silinmez, arşivlenir:
    /// aynı kimliği taşıyan yedekler (veya asıl kasa) onu hâlâ gerektirebilir ve kilit açılırken denenir.
    func disableKeyfile(password: String) async -> String? {
        guard let vault else { return "Kasa kilitli." }
        let id = vault.header.vaultID
        let used = vault.keyfileData
        do {
            try await Task.detached(priority: .userInitiated) { try vault.setKeyfile(nil, password: password) }.value
        } catch {
            return error.localizedDescription
        }
        if let used, keyfiles.load(for: id) == used { try? keyfiles.archive(for: id) }
        keyfileEnabled = false
        showToast("Kasa artık yalnızca parolayla açılıyor")
        return nil
    }

    /// Mac bozulursa kurtarabilmek için kasayı açan anahtar dosyasının bir kopyasını seçilen yere yazar.
    func exportKeyfile() {
        guard let keyfile = vault?.keyfileData else { return }
        let panel = NSSavePanel()
        panel.title = "Anahtar dosyasının yedeği"
        panel.message = "SSD'den ayrı, güvendiğin bir yere kaydet. Dosya adı içeriği belli etmesin."
        panel.nameFieldStringValue = "yedek.bin"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let vaultID = volumeID(vaultURL), vaultID == volumeID(url.deletingLastPathComponent()) {
            alert = AlertItem(title: "Bu konum seçilemez", message: "Anahtar dosyasının yedeği kasayla aynı diskte olursa koruma anlamını yitirir.")
            return
        }
        // Dosya baştan yalnızca kullanıcının okuyabileceği izinle oluşturulur.
        guard FileManager.default.createFile(atPath: url.path, contents: keyfile, attributes: [.posixPermissions: 0o600]) else {
            alert = AlertItem(title: "Kaydedilemedi", message: url.path)
            return
        }
        showToast("Anahtar dosyasının yedeği kaydedildi")
    }

    /// Yedek anahtar dosyasını seçili kasa için içe alır. Mevcut anahtar varsa silinmez, arşivlenir.
    /// Dosyanın doğruluğu bilerek denetlenmez; doğruysa kasa parolayla açılır.
    func importKeyfile() {
        guard let vaultURL, let header = try? Vault.readHeader(at: vaultURL) else {
            alert = AlertItem(title: "Önce kasayı seç", message: "Anahtar dosyası, seçili kasa için içe aktarılır.")
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Anahtar dosyasını seç"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        guard data.count == Vault.keyfileLength else {
            alert = AlertItem(title: "Geçersiz dosya", message: "Seçilen dosya bir Mahzen anahtar dosyası değil.")
            return
        }
        do {
            let hadOne = keyfiles.load(for: header.vaultID) != nil
            try keyfiles.save(data, for: header.vaultID)
            showToast(hadOne ? "Anahtar dosyası içe aktarıldı (öncekisi arşivlendi)" : "Anahtar dosyası içe aktarıldı")
        } catch {
            alert = AlertItem(title: "İçe aktarılamadı", message: error.localizedDescription)
        }
    }

    func changePassword(current: String, new: String) async -> String? {
        guard let vault else { return "Kasa kilitli." }
        do {
            try await Task.detached(priority: .userInitiated) {
                try vault.changePassword(current: current, new: new)
            }.value
            kdfSummary = vault.header.kdf.summary
            showToast("Parola değiştirildi")
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - Kaydetme

    func mutate(debounce: Bool = false, _ body: (inout VaultIndex) -> Void) {
        body(&index)
        scheduleSave(delay: debounce ? 0.8 : 0.05)
    }

    func updatePreferences(_ body: (inout Preferences) -> Void) {
        mutate { body(&$0.preferences) }
        rememberLockScreenLook()
        applyAppearance()
        applyWindowPrivacy()
    }

    func preference<T>(_ keyPath: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { self.index.preferences[keyPath: keyPath] },
                set: { value in self.updatePreferences { $0[keyPath: keyPath] = value } })
    }

    private func scheduleSave(delay: Double = 0.05) {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.performSave() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Bekleyen kaydı hemen ve eşzamanlı yapar; sıradaki eski kayıtların bitmesini de bekler.
    /// Dizin diske yazıldıysa `true`.
    @discardableResult
    func flushSave() -> Bool {
        saveWork?.cancel()
        saveWork = nil
        guard let vault else { return false }
        let snapshot = index
        var failure: Error?
        io.sync {
            do { try vault.saveIndex(snapshot) } catch { failure = error }
        }
        if let failure {
            alert = AlertItem(title: "Kaydedilemedi", message: "\(failure.localizedDescription)\nSSD çıkarılmış olabilir.")
            return false
        }
        return true
    }

    private func performSave() {
        saveWork = nil
        guard let vault else { return }
        let snapshot = index
        io.async {
            do {
                try vault.saveIndex(snapshot)
            } catch {
                DispatchQueue.main.async {
                    self.alert = AlertItem(title: "Kaydedilemedi", message: "\(error.localizedDescription)\nSSD çıkarılmış olabilir.")
                }
            }
        }
    }

    // MARK: - Dosyalar

    /// Dosyalar bölümünde açık olan klasör; yeni eklenenler buraya gider.
    @Published var currentFolder: UUID?

    func presentImportPanel() {
        guard phase == .unlocked else { return }
        let panel = NSOpenPanel()
        panel.title = "Kasaya eklenecek dosyaları seç"
        panel.prompt = "Şifrele ve Ekle"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        if panel.runModal() == .OK { importFiles(panel.urls, into: currentFolder) }
    }

    func importFiles(_ urls: [URL], into folder: UUID?) {
        guard let vault, task == nil else { return }
        let plan = ImportPlan(urls: urls)
        guard !plan.items.isEmpty else {
            if plan.skippedCount > 0 {
                alert = AlertItem(title: "Eklenecek dosya yok", message: "Gizli dosyalar, paketler (ör. Keynote belgeleri), kısayollar ve okunamayan öğeler kasaya eklenmez.")
            }
            return
        }
        let items = plan.items
        let total = max(items.reduce(0) { $0 + $1.size }, 1)
        let token = session
        let flag = CancelFlag()
        cancelFlag = flag
        cancelRequested = false
        task = TaskProgress(title: "Şifreleniyor", fraction: 0, cancellable: true)

        Task {
            let counter = ProgressCounter()
            var failures: [String] = []
            var added = 0
            var duplicates: [String] = []
            // Bir kaynağın orijinali ancak içindeki her dosya kasaya güvenle girdiyse çöpe taşınabilir.
            var safelyStored: [URL: Int] = [:]
            for (i, item) in items.enumerated() {
                guard !flag.value, isCurrent(token) else { break }
                task?.title = "Şifreleniyor (\(i + 1)/\(items.count))"
                task?.detail = item.url.lastPathComponent
                let id = UUID()
                do {
                    let hash = try await Task.detached(priority: .userInitiated) {
                        try vault.importFile(at: item.url, id: id) { n in
                            if flag.value { throw MaintenanceCancelled() }
                            counter.done += Int64(n)
                            let now = Date()
                            guard now.timeIntervalSince(counter.lastReport) > 0.1 else { return }
                            counter.lastReport = now
                            let fraction = Double(counter.done) / Double(total)
                            DispatchQueue.main.async { if self.isCurrent(token) { self.task?.fraction = fraction } }
                        }
                    }.value
                    // Kilitlendiyse kayıt yeni oturuma yazılmaz; şifreli içerik artık dosya olarak kalır.
                    guard isCurrent(token) else { vault.deleteFile(id); break }
                    // Aynı içerik zaten kasadaysa yeni şifreli kopyayı at.
                    if index.existingFile(withHash: hash) != nil {
                        vault.deleteFile(id)
                        duplicates.append(item.url.lastPathComponent)
                        safelyStored[item.source, default: 0] += 1
                        continue
                    }
                    var hasThumb = false
                    if let thumb = await Self.makeThumbnail(for: item.url) {
                        hasThumb = (try? await Task.detached { try vault.writeThumbnail(thumb, id: id) }.value) != nil
                    }
                    guard isCurrent(token) else { vault.deleteFile(id); break }
                    mutate { idx in
                        let target = idx.ensureFolderPath(item.folderPath, under: folder)
                        idx.files.append(FileRecord(
                            id: id,
                            name: item.url.lastPathComponent,
                            size: item.size,
                            contentType: UTType(filenameExtension: item.url.pathExtension)?.identifier,
                            originalModifiedAt: item.modified,
                            hasThumbnail: hasThumb,
                            folderID: target,
                            sha256: hash
                        ))
                    }
                    added += 1
                    safelyStored[item.source, default: 0] += 1
                } catch is MaintenanceCancelled {
                    vault.deleteFile(id)
                    break
                } catch {
                    vault.deleteFile(id)
                    failures.append("\(item.url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            // Kasa bu arada kilitlendiyse hiçbir şey yazılmaz ve hiçbir şey önerilmez.
            guard isCurrent(token) else { return }
            task = nil
            // Orijinaller ancak dizin diske gerçekten yazıldıktan sonra çöpe önerilir.
            let saved = flushSave()
            let removable = plan.removableSources(safelyStored: safelyStored)
            if saved, !removable.isEmpty { offerToTrashOriginals(removable) }
            var notes: [String] = []
            if !failures.isEmpty { notes.append("Eklenemeyenler:\n" + failures.prefix(8).joined(separator: "\n")) }
            if plan.skippedCount > 0 {
                notes.append("\(plan.skippedCount) öğe eklenmedi (gizli dosya, paket, kısayol veya okunamayan öğe); bunları içeren klasörlerin orijinalleri çöpe önerilmedi.")
            }
            if !duplicates.isEmpty {
                notes.append("\(duplicates.count) dosya kasada zaten vardı: " + duplicates.prefix(6).joined(separator: ", ")
                    + (duplicates.count > 6 ? " …" : ""))
            }
            if notes.isEmpty {
                showToast(flag.value ? "Durduruldu · \(added) dosya eklendi" : "\(added) dosya şifrelendi")
            } else {
                alert = AlertItem(title: "\(added) dosya şifrelendi", message: notes.joined(separator: "\n\n"))
            }
        }
    }

    func cancelTask() {
        cancelRequested = true
        cancelFlag.value = true
    }

    // MARK: - Yedekleme ve bakım

    var backupURL: URL? { prefs.backupPath.map { URL(fileURLWithPath: $0, isDirectory: true) } }

    /// Kasada içerik var ve son yedek hatırlatma süresinden eski (ya da hiç yok).
    var backupDue: Bool {
        let days = prefs.backupReminderDays
        guard days > 0, !index.files.isEmpty || !index.notes.isEmpty || !index.secrets.isEmpty else { return false }
        guard let last = prefs.lastBackupAt else { return true }
        return Date().timeIntervalSince(last) > Double(days) * 86_400
    }

    @discardableResult
    func chooseBackupLocation() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Yedeğin tutulacağı yeri seç (tercihen başka bir disk)"
        panel.prompt = "Burada Yedekle"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let chosen = panel.url else { return false }
        let dest = Vault.exists(at: chosen) ? chosen : chosen.appendingPathComponent("Mahzen Kasası Yedek", isDirectory: true)
        if let vaultURL, dest.standardizedFileURL.path.hasPrefix(vaultURL.standardizedFileURL.path) {
            alert = AlertItem(title: "Bu konum seçilemez", message: "Yedek, kasanın kendi klasörünün içinde olamaz.")
            return false
        }
        if let vaultVolume = volumeID(vaultURL), vaultVolume == volumeID(chosen) {
            let warn = NSAlert()
            warn.messageText = "Yedek, kasayla aynı diskte olacak"
            warn.informativeText = "Disk bozulur ya da kaybolursa kasa ve yedeği birlikte gider. Mümkünse başka bir disk seç."
            warn.addButton(withTitle: "Yine de Kullan")
            warn.addButton(withTitle: "Vazgeç")
            guard warn.runModal() == .alertFirstButtonReturn else { return false }
        }
        updatePreferences { $0.backupPath = dest.path }
        return true
    }

    private func volumeID(_ url: URL?) -> String? {
        guard let url, let id = try? url.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier else { return nil }
        return "\(id)"
    }

    func backupNow() {
        guard let vault, task == nil else { return }
        if backupURL == nil, !chooseBackupLocation() { return }
        guard let dest = backupURL else { return }
        guard FileManager.default.fileExists(atPath: dest.deletingLastPathComponent().path) else {
            alert = AlertItem(title: "Yedek diski bağlı değil", message: "\(dest.deletingLastPathComponent().path) bulunamadı. Diski bağlayıp tekrar dene ya da Ayarlar'dan konumu değiştir.")
            return
        }
        flushSave()
        let fileIDs = Set(index.files.map(\.id))
        let thumbIDs = Set(index.files.filter(\.hasThumbnail).map(\.id))
        let token = session
        let flag = CancelFlag()
        cancelFlag = flag
        cancelRequested = false
        task = TaskProgress(title: "Yedekleniyor", detail: dest.path, fraction: 0, cancellable: true)
        Task {
            do {
                let counter = ProgressCounter()
                let report = try await Task.detached(priority: .userInitiated) {
                    try vault.backup(to: dest, fileIDs: fileIDs, thumbnailIDs: thumbIDs) { done, total in
                        let now = Date()
                        if now.timeIntervalSince(counter.lastReport) > 0.1 {
                            counter.lastReport = now
                            let fraction = total > 0 ? Double(done) / Double(total) : 1
                            DispatchQueue.main.async { self.task?.fraction = fraction }
                        }
                        return !flag.value
                    }
                }.value
                guard isCurrent(token) else { return }
                task = nil
                updatePreferences { $0.lastBackupAt = Date() }
                flushSave()
                if !report.missingInSource.isEmpty {
                    alert = AlertItem(
                        title: "Yedek alındı, ama \(report.missingInSource.count) dosya kasada bulunamadı",
                        message: "Bu dosyaların yedekteki eski kopyaları korundu. Ayarlar → Bütünlük Taraması ile ayrıntıları gör ve yedekten geri yükle."
                    )
                } else {
                    showToast(report.copiedFiles == 0
                        ? "Yedek güncel"
                        : "Yedeklendi: \(report.copiedFiles) dosya · \(Format.size(report.copiedBytes))")
                }
            } catch is MaintenanceCancelled {
                task = nil
                showToast("Yedekleme durduruldu (önceki yedek bozulmadı)")
            } catch {
                task = nil
                alert = AlertItem(title: "Yedeklenemedi", message: error.localizedDescription)
            }
        }
    }

    func runIntegrityScan() {
        guard let vault, task == nil else { return }
        flushSave()
        let files = index.files
        let token = session
        let flag = CancelFlag()
        cancelFlag = flag
        task = TaskProgress(title: "Bütünlük taraması", detail: "\(files.count) dosya çözülerek doğrulanıyor", fraction: 0, cancellable: true)
        Task {
            do {
                let counter = ProgressCounter()
                let report = try await Task.detached(priority: .userInitiated) {
                    try vault.checkIntegrity(files: files) { done, total in
                        let now = Date()
                        if now.timeIntervalSince(counter.lastReport) > 0.1 {
                            counter.lastReport = now
                            let fraction = total > 0 ? Double(done) / Double(total) : 1
                            DispatchQueue.main.async { self.task?.fraction = fraction }
                        }
                        return !flag.value
                    }
                }.value
                guard isCurrent(token) else { return }
                task = nil
                // Eski kayıtların eksik parmak izlerini tamamla, bozuk küçük resimleri bırak.
                mutate { idx in
                    for i in idx.files.indices {
                        let id = idx.files[i].id
                        if idx.files[i].sha256 == nil, let hash = report.hashes[id] { idx.files[i].sha256 = hash }
                        if report.brokenThumbnails.contains(id) { idx.files[i].hasThumbnail = false }
                    }
                }
                for id in report.brokenThumbnails { thumbnails[id] = nil }
                flushSave()
                integrityReport = report
            } catch is MaintenanceCancelled {
                task = nil
                showToast("Tarama durduruldu")
            } catch {
                task = nil
                alert = AlertItem(title: "Tarama tamamlanamadı", message: error.localizedDescription)
            }
        }
    }

    /// Bozuk/eksik dosyaları yedekten geri yükler; geri yüklenemeyenlerin adlarını döndürür.
    func restoreFromBackup(_ ids: [UUID]) async -> [String] {
        guard let vault, let dest = backupURL else { return ids.map { _ in "Yedek konumu yok" } }
        var failed: [String] = []
        for id in ids {
            do {
                try await Task.detached(priority: .userInitiated) { try vault.restoreFile(id, fromBackup: dest) }.value
                integrityReport?.problems[id] = nil
            } catch {
                let name = index.files.first { $0.id == id }?.name ?? id.uuidString
                failed.append("\(name): \(error.localizedDescription)")
            }
        }
        return failed
    }

    func removeOrphans(_ urls: [URL]) {
        guard let vault else { return }
        let total = urls.count
        io.async { vault.removeOrphans(urls) }
        integrityReport?.orphanURLs = []
        integrityReport?.orphanBytes = 0
        showToast("\(total) artık dosya temizlendi")
    }

    /// Kasaya güvenle giren dosyaların orijinallerini Mac'in Çöp Kutusu'na taşımayı önerir (kalıcı silmez).
    private func offerToTrashOriginals(_ urls: [URL]) {
        guard prefs.askToTrashOriginals else { return }
        let alert = NSAlert()
        alert.messageText = urls.count == 1
            ? "\"\(urls[0].lastPathComponent)\" orijinali Çöp Kutusu'na taşınsın mı?"
            : "\(urls.count) öğenin orijinali Çöp Kutusu'na taşınsın mı?"
        alert.informativeText = "Şifreli kopyaları artık kasada. Orijinaller Mac'in Çöp Kutusu'na gider; tamamen silinmeleri için Çöp Kutusu'nu boşaltman gerekir."
        alert.addButton(withTitle: "Çöp Kutusu'na Taşı")
        alert.addButton(withTitle: "Orijinalleri Sakla")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Bir daha sorma (Ayarlar'dan açılabilir)"
        let answer = alert.runModal()
        if alert.suppressionButton?.state == .on { updatePreferences { $0.askToTrashOriginals = false } }
        guard answer == .alertFirstButtonReturn else { return }
        NSWorkspace.shared.recycle(urls) { trashed, error in
            Task { @MainActor in
                if let error {
                    self.alert = AlertItem(title: "Orijinaller taşınamadı", message: error.localizedDescription)
                } else {
                    self.showToast("\(trashed.count) orijinal Çöp Kutusu'na taşındı")
                }
            }
        }
    }

    // MARK: - Sürükle-bırak

    /// Uygulama içinde başlayan sürüklemenin öğeleri. Sürükleme verisine kasa kimliği koymayız:
    /// Finder o veriyi dosya içeriği sanıp yazabiliyor. Bunun yerine kaynağı burada tutarız.
    private var activeDrag: Set<UUID>?

    /// Dosya sürükleme: Finder'a bırakılırsa şifresi çözülmüş kopya oluşur,
    /// kasadaki bir klasöre bırakılırsa (seçimle birlikte) oraya taşınır.
    func dragProvider(for file: FileRecord, alongWith selection: Set<UUID>) -> NSItemProvider {
        activeDrag = selection.contains(file.id) ? selection : [file.id]
        let provider = NSItemProvider()
        provider.suggestedName = file.name
        let id = file.id
        let name = file.name
        // Tek temsil: gerçek dosya içeriği. Başka hiçbir veri eklenmez.
        provider.registerFileRepresentation(forTypeIdentifier: file.utType.identifier, fileOptions: [], visibility: .all) { completion in
            Task { @MainActor in
                guard let vault = self.vault else { return completion(nil, false, VaultError.notAVault) }
                let token = self.session
                let dir = self.tempRoot.appendingPathComponent("surukle-\(UUID().uuidString)", isDirectory: true)
                let dest = dir.appendingPathComponent(name)
                Task.detached(priority: .userInitiated) {
                    do {
                        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                        try vault.exportFile(id, to: dest)
                        let stillOpen = await MainActor.run { self.isCurrent(token) }
                        guard stillOpen else {
                            try? FileManager.default.removeItem(at: dir)
                            return completion(nil, false, VaultError.notAVault)
                        }
                        completion(dest, false, nil)
                    } catch {
                        completion(nil, false, error)
                    }
                }
            }
            return nil
        }
        return provider
    }

    /// Klasör sürükleme yalnızca kasa içinde taşımak içindir; dışarıya yalnızca klasörün adı (metin) gider.
    func folderDragProvider(_ folder: Folder, alongWith selection: Set<UUID>) -> NSItemProvider {
        activeDrag = selection.contains(folder.id) ? selection : [folder.id]
        return NSItemProvider(object: folder.name as NSString)
    }

    /// Bırakma: Finder'dan dosya geliyorsa şifreleyip ekler, kasa içinden geliyorsa taşır.
    func handleDrop(_ providers: [NSItemProvider], into folder: UUID?) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        if fileProviders.isEmpty {
            guard let ids = activeDrag else { return false }
            activeDrag = nil
            moveItems(ids, to: folder)
            return true
        }
        activeDrag = nil
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in fileProviders {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            MainActor.assumeIsolated { self.importFiles(urls, into: folder) }
        }
        return true
    }

    private func moveItems(_ ids: Set<UUID>, to folder: UUID?) {
        let fileIDs = ids.filter { id in index.files.contains { $0.id == id } }
        let folderIDs = ids.filter { id in index.folders.contains { $0.id == id } }.subtracting(folder.map { [$0] } ?? [])
        guard !fileIDs.isEmpty || !folderIDs.isEmpty else { return }
        if !fileIDs.isEmpty { moveFiles(fileIDs, to: folder) }
        for id in folderIDs { moveFolder(id, to: folder) }
        if fileIDs.isEmpty { showToast("Taşındı: \(index.folder(folder)?.name ?? "Dosyalar")") }
    }

    nonisolated private static func makeThumbnail(for url: URL) async -> Data? {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 220, height: 220), scale: 2, representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        return NSBitmapImageRep(cgImage: rep.cgImage).representation(using: .jpeg, properties: [.compressionFactor: 0.78])
    }

    func thumbnail(for file: FileRecord) async -> NSImage? {
        if let cached = thumbnails[file.id] { return cached }
        guard file.hasThumbnail, let vault else { return nil }
        let id = file.id
        guard let data = try? await Task.detached(priority: .utility, operation: { try vault.readThumbnail(id) }).value,
              let image = NSImage(data: data) else { return nil }
        if phase == .unlocked { thumbnails[id] = image }
        return image
    }

    func readFile(_ file: FileRecord) async throws -> Data {
        guard let vault else { throw VaultError.notAVault }
        let id = file.id
        return try await Task.detached(priority: .userInitiated) { try vault.readFile(id) }.value
    }

    func openReader(_ file: FileRecord) async throws -> BlobReader {
        guard let vault else { throw VaultError.notAVault }
        let id = file.id
        return try await Task.detached(priority: .userInitiated) { try vault.openReader(id) }.value
    }

    func exportFiles(_ files: [FileRecord]) {
        guard let vault, !files.isEmpty, task == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "Şifresi çözülmüş kopyaların kaydedileceği klasör"
        panel.prompt = "Dışa Aktar"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        let token = session
        guard panel.runModal() == .OK, let dir = panel.url, isCurrent(token) else { return }
        let total = max(files.reduce(0) { $0 + $1.size }, 1)
        let flag = CancelFlag()
        cancelFlag = flag
        task = TaskProgress(title: "Dışa aktarılıyor", fraction: 0, cancellable: true)
        Task {
            let counter = ProgressCounter()
            var failures: [String] = []
            for file in files {
                guard !flag.value, isCurrent(token) else { break }
                task?.detail = file.name
                let dest = Self.uniqueURL(in: dir, name: file.name)
                let id = file.id
                do {
                    try await Task.detached(priority: .userInitiated) {
                        try vault.exportFile(id, to: dest) { n in
                            if flag.value { throw MaintenanceCancelled() }
                            counter.done += Int64(n)
                            let fraction = Double(counter.done) / Double(total)
                            DispatchQueue.main.async { self.task?.fraction = fraction }
                        }
                    }.value
                } catch is MaintenanceCancelled {
                    break
                } catch {
                    failures.append("\(file.name): \(error.localizedDescription)")
                }
            }
            guard isCurrent(token) else { return }
            task = nil
            if flag.value {
                showToast("Dışa aktarma durduruldu")
            } else if failures.isEmpty {
                showToast("\(files.count) dosya dışa aktarıldı")
                NSWorkspace.shared.activateFileViewerSelecting([dir])
            } else {
                alert = AlertItem(title: "Bazı dosyalar aktarılamadı", message: failures.prefix(8).joined(separator: "\n"))
            }
        }
    }

    /// Dosyayı Mac'in geçici klasörüne çözüp varsayılan uygulamasıyla açar. Kilitlenince silinir.
    func openTemporarily(_ file: FileRecord) {
        guard let vault, task == nil else { return }
        if !UserDefaults.standard.bool(forKey: "tempOpenWarned") {
            let alert = NSAlert()
            alert.messageText = "Dosya geçici olarak açılsın mı?"
            alert.informativeText = "Dosyanın şifresiz bir kopyası bu Mac'in geçici klasörüne yazılır ve kasa kilitlenince ya da uygulama kapanınca silinir. Açan uygulama (ör. Önizleme) kendi önbelleğinde iz bırakabilir."
            alert.addButton(withTitle: "Aç")
            alert.addButton(withTitle: "Vazgeç")
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Bir daha sorma"
            let token = session
            guard alert.runModal() == .alertFirstButtonReturn, isCurrent(token) else { return }
            if alert.suppressionButton?.state == .on { UserDefaults.standard.set(true, forKey: "tempOpenWarned") }
        }
        let token = session
        let dir = tempRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dest = dir.appendingPathComponent(file.name)
        let id = file.id
        task = TaskProgress(title: "Açılıyor", detail: file.name)
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    let fm = FileManager.default
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.deletingLastPathComponent().path)
                    try vault.exportFile(id, to: dest)
                }.value
                // Bu arada kilitlendiyse geçici klasör çoktan silindi; yeni çözülen kopyayı da sil.
                guard isCurrent(token) else { try? FileManager.default.removeItem(at: dir); return }
                task = nil
                NSWorkspace.shared.open(dest)
            } catch {
                try? FileManager.default.removeItem(at: dir)
                guard isCurrent(token) else { return }
                task = nil
                alert = AlertItem(title: "Açılamadı", message: error.localizedDescription)
            }
        }
    }

    func trashFiles(_ ids: Set<UUID>) {
        mutate { $0.trashFiles(ids) }
        showToast(ids.count == 1 ? "Çöp Kutusu'na taşındı" : "\(ids.count) dosya Çöp Kutusu'na taşındı")
    }

    /// Dizinden kalıcı olarak çıkarılan dosyaların şifreli içeriklerini siler.
    private func discardBlobs(_ ids: [UUID]) {
        guard let vault, !ids.isEmpty else { return }
        flushSave()
        for id in ids { thumbnails[id] = nil }
        io.async { ids.forEach(vault.deleteFile) }
    }

    // MARK: - Klasörler ve etiketler

    @discardableResult
    func createFolder(named name: String = "Yeni Klasör", in parent: UUID?) -> UUID {
        var id = UUID()
        mutate { id = $0.createFolder(named: name, in: parent) }
        return id
    }

    func renameFolder(_ id: UUID, to name: String) { mutate { $0.renameFolder(id, to: name) } }

    func trashFolder(_ id: UUID) {
        mutate { $0.trashFolder(id) }
        if currentFolder.map({ index.folder($0)?.deletedAt != nil }) == true { currentFolder = nil }
        showToast("Klasör Çöp Kutusu'na taşındı")
    }

    func moveFiles(_ ids: Set<UUID>, to folder: UUID?) {
        mutate { $0.moveFiles(ids, to: folder) }
        showToast("Taşındı: \(index.folder(folder)?.name ?? "Dosyalar")")
    }

    func moveFolder(_ id: UUID, to parent: UUID?) {
        var moved = false
        mutate { moved = $0.moveFolder(id, to: parent) }
        if !moved { alert = AlertItem(title: "Taşınamadı", message: "Bir klasör kendi içine taşınamaz.") }
    }

    func setTags(_ tags: [String], for ids: Set<UUID>) { mutate { $0.setTags(tags, for: ids) } }

    // MARK: - Çöp kutusu

    func restoreFile(_ id: UUID) { mutate { $0.restoreFile(id) } }
    func restoreFolder(_ id: UUID) { mutate { $0.restoreFolder(id) } }
    func restoreNote(_ id: UUID) { mutate { $0.restoreNote(id) } }
    func restoreSecret(_ id: UUID) { mutate { $0.restoreSecret(id) } }

    func purgeFile(_ id: UUID) {
        var removed: [UUID] = []
        mutate { removed = $0.purgeFiles([id]) }
        discardBlobs(removed)
    }

    func purgeFolder(_ id: UUID) {
        var removed: [UUID] = []
        mutate { removed = $0.purgeFolder(id) }
        discardBlobs(removed)
    }

    func purgeNote(_ id: UUID) { mutate { $0.purgeNote(id) } }
    func purgeSecret(_ id: UUID) { mutate { $0.purgeSecret(id) } }

    func emptyTrash() {
        var removed: [UUID] = []
        mutate { removed = $0.emptyTrash() }
        discardBlobs(removed)
        flushSave()
        showToast("Çöp Kutusu boşaltıldı")
    }

    func renameFile(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate { idx in
            if let i = idx.files.firstIndex(where: { $0.id == id }) { idx.files[i].name = trimmed }
        }
    }

    func toggleFavorite(_ ids: Set<UUID>) {
        mutate { idx in
            let makeFavorite = idx.files.contains { ids.contains($0.id) && !$0.favorite }
            for i in idx.files.indices where ids.contains(idx.files[i].id) { idx.files[i].favorite = makeFavorite }
        }
    }

    private static func uniqueURL(in dir: URL, name: String) -> URL {
        var url = dir.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }

    private func wipeTemporaryFiles() {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    // MARK: - Notlar ve parolalar

    @discardableResult
    func addNote() -> UUID {
        let note = Note()
        mutate { $0.notes.insert(note, at: 0) }
        return note.id
    }

    func updateNote(_ id: UUID, _ body: (inout Note) -> Void) {
        mutate(debounce: true) { idx in
            guard let i = idx.notes.firstIndex(where: { $0.id == id }) else { return }
            body(&idx.notes[i])
            idx.notes[i].updatedAt = Date()
        }
    }

    func deleteNote(_ id: UUID) {
        mutate { $0.trashNote(id) }
        showToast("Not Çöp Kutusu'na taşındı")
    }

    func saveSecret(_ secret: Secret) {
        var s = secret
        s.updatedAt = Date()
        mutate { idx in
            if let i = idx.secrets.firstIndex(where: { $0.id == s.id }) {
                idx.secrets[i] = s
            } else {
                idx.secrets.append(s)
            }
        }
    }

    func deleteSecret(_ id: UUID) {
        mutate { $0.trashSecret(id) }
        showToast("Kayıt Çöp Kutusu'na taşındı")
    }

    // MARK: - Pano

    func copy(_ text: String, sensitive: Bool = true, label: String = "Kopyalandı") {
        let pb = NSPasteboard.general
        // Hassas içerik Evrensel Pano ile iPhone'a / diğer Mac'lere gitmesin.
        pb.prepareForNewContents(with: sensitive ? .currentHostOnly : [])
        pb.setString(text, forType: .string)
        guard sensitive else {
            sensitiveClipboardCount = nil
            return showToast(label)
        }
        // Pano yöneticilerine "bunu geçmişe kaydetme" işareti.
        pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        sensitiveClipboardCount = pb.changeCount
        let seconds = prefs.clipboardClearSeconds
        if seconds > 0 {
            let count = pb.changeCount
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) {
                if pb.changeCount == count { pb.clearContents() }
            }
            showToast("\(label) · \(seconds) sn sonra panodan silinecek")
        } else {
            showToast(label)
        }
    }

    /// Panoda hâlâ bizim kopyaladığımız hassas içerik duruyorsa siler (kilitte ve çıkışta).
    private func clearSensitiveClipboard() {
        let pb = NSPasteboard.general
        if let count = sensitiveClipboardCount, pb.changeCount == count { pb.clearContents() }
        sensitiveClipboardCount = nil
    }

    func showToast(_ message: String) {
        toastWork?.cancel()
        withAnimation(.snappy) { toast = message }
        let work = DispatchWorkItem { [weak self] in withAnimation(.snappy) { self?.toast = nil } }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: work)
    }

    // MARK: - Görünüm ve gizlilik

    private func rememberLockScreenLook() {
        UserDefaults.standard.set(prefs.accent, forKey: "lockAccent")
        UserDefaults.standard.set(prefs.appearance, forKey: "lockAppearance")
    }

    func applyAppearance() {
        let raw = phase == .unlocked ? prefs.appearance : UserDefaults.standard.string(forKey: "lockAppearance")
        NSApp?.appearance = AppearanceChoice(rawValue: raw ?? "")?.nsAppearance
    }

    /// Açıkken pencere ekran görüntüsü, kayıt ve ekran paylaşımında boş görünür.
    func applyWindowPrivacy() {
        let hide = phase == .unlocked && prefs.hideFromScreenCapture
        let locked = phase != .unlocked
        for window in NSApp?.windows ?? [] where window.isVisible || window.isMiniaturized {
            window.sharingType = hide ? .none : .readOnly
            // Kilitliyken başlık çubuğu gizlenir, arka plan pencerenin tamamını kaplar.
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = locked
            window.titleVisibility = locked ? .hidden : .visible
        }
    }

    // MARK: - Otomatik kilit

    private func installObservers() {
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel, .mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated { self?.lastActivity = Date() }
            return event
        }
        // .common: kaydet/aç pencereleri gibi kalıcı pencereler açıkken de otomatik kilit çalışsın.
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkAutoLock() }
        }
        RunLoop.main.add(timer, forMode: .common)
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.lockIfConfigured() }
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockIfConfigured() }
        }
        // SSD çıkarılırken kasayı kapat.
        workspace.addObserver(forName: NSWorkspace.willUnmountNotification, object: nil, queue: .main) { [weak self] note in
            let path = note.userInfo?["NSDevicePath"] as? String
            MainActor.assumeIsolated {
                guard let self, let path, let vaultPath = self.vaultURL?.standardizedFileURL.path else { return }
                // "/Volumes/SSD" çıkarılınca "/Volumes/SSD 2" üzerindeki kasa etkilenmesin.
                let mount = path.hasSuffix("/") ? path : path + "/"
                guard vaultPath.hasPrefix(mount) || vaultPath == path else { return }
                self.lock()
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.flushSave()
                self?.clearSensitiveClipboard()
                self?.wipeTemporaryFiles()
            }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyWindowPrivacy() }
        }
    }

    private func lockIfConfigured() {
        if phase == .unlocked, prefs.lockOnSleep { lock() }
    }

    private func checkAutoLock() {
        let minutes = prefs.autoLockMinutes
        guard phase == .unlocked, task == nil, minutes > 0 else { return }
        if Date().timeIntervalSince(lastActivity) > Double(minutes) * 60 { lock() }
    }
}
