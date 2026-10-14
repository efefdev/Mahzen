#if DEBUG
import AVFoundation
import AppKit
import MahzenCore
import SwiftUI

/// Yalnızca debug derlemede: `MAHZEN_SNAPSHOTS=<klasör>` ile başlatılırsa geçici bir demo kasa kurar,
/// her ekranın görüntüsünü PNG olarak kaydeder ve çıkar. Gerçek kasalara dokunmaz.
@MainActor
enum DebugSnapshots {
    static func runIfRequested(_ state: AppState) async {
        guard let out = ProcessInfo.processInfo.environment["MAHZEN_SNAPSHOTS"] else { return }
        let outDir = URL(fileURLWithPath: out, isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("MahzenDemo-\(UUID().uuidString)")
        let vaultURL = work.appendingPathComponent("Mahzen Kasası")
        let password = "demo-parola-uzun-123"
        defer { try? FileManager.default.removeItem(at: work) }

        state.showWelcome()
        await snap("01-karsilama", outDir)

        // Eski sürüm gibi PBKDF2 ile oluştur; kilit açılınca Argon2id'ye yükseltilmeli.
        _ = try? Vault.create(at: vaultURL, password: password, kdf: .pbkdf2(iterations: 10_000))
        state.selectVault(vaultURL)
        await snap("02-kilitli", outDir)

        _ = await state.unlock(password: password)
        state.updatePreferences { $0.displayName = "Kişisel Kasa"; $0.askToTrashOriginals = false; $0.hideFromScreenCapture = false }

        var report: [String] = []
        let header = try? Vault.readHeader(at: vaultURL)
        report.append("KDF yükseltme: \(header?.kdf.algorithm ?? "?") v\(header?.version ?? 0)")

        let samples = makeSampleFiles(in: work.appendingPathComponent("ornek"))
        state.importFiles(samples, into: nil)
        while state.task != nil { try? await Task.sleep(for: .milliseconds(100)) }

        // Klasör yapısıyla içe aktarma: Tatil/2026/... ve aynı dosyaların tekrar eklenmesi.
        let trip = work.appendingPathComponent("Tatil")
        let year = trip.appendingPathComponent("2026")
        try? FileManager.default.createDirectory(at: year, withIntermediateDirectories: true)
        for (i, url) in samples.prefix(3).enumerated() {
            try? FileManager.default.copyItem(at: url, to: (i == 0 ? trip : year).appendingPathComponent("kopya-" + url.lastPathComponent))
        }
        try? Data("benzersiz".utf8).write(to: year.appendingPathComponent("plan.txt"))
        state.importFiles([trip], into: nil)
        while state.task != nil { try? await Task.sleep(for: .milliseconds(100)) }
        report.append("Mükerrer uyarısı: \(state.alert?.title ?? "yok")")
        state.alert = nil
        let tripID = state.index.childFolders(of: nil).first { $0.name == "Tatil" }?.id
        let yearID = tripID.flatMap { id in state.index.childFolders(of: id).first { $0.name == "2026" }?.id }
        report.append("Klasörler: \(state.index.folders.map(\.name).sorted()) · 2026 içinde \(state.index.liveFiles(in: yearID).map(\.name))")
        state.createFolder(named: "Belgeler", in: nil)
        if let doc = state.index.liveFiles.first(where: { $0.name.hasSuffix(".txt") }) {
            state.setTags(["iş", "gizli"], for: [doc.id])
        }
        if let zip = state.index.liveFiles.first(where: { $0.name.hasSuffix(".zip") }) {
            state.trashFiles([zip.id])
        }

        state.mutate { idx in
            var n1 = Note(); n1.title = "Pasaport bilgileri"; n1.body = "Seri no ve yenileme tarihi burada.\nKonsolosluk randevusu: Kasım."; n1.pinned = true; n1.color = "orange"
            var n2 = Note(); n2.title = "Kripto kurtarma ifadesi"; n2.body = "Kağıt kopyası kasada, ikinci kopya ailede."; n2.color = "teal"
            var n3 = Note(); n3.title = "Proje fikirleri"; n3.body = "Yeni uygulama için taslak notlar…"
            idx.notes = [n1, n2, n3]
            var s1 = Secret(); s1.title = "Gmail"; s1.username = "ornek@gmail.com"; s1.password = "ornek-gmail-parolasi"; s1.url = "mail.google.com"; s1.favorite = true
            var s2 = Secret(); s2.title = "Ev Wi-Fi"; s2.category = .wifi; s2.password = "kahve-masasi-2024"
            var s3 = Secret(); s3.title = "Örnek sunucu"; s3.category = .server; s3.username = "kullanici"; s3.password = "ornek-sunucu-parolasi"; s3.url = "ornek.com"
            var s4 = Secret(); s4.title = "Banka kartı"; s4.category = .card; s4.notes = "Son kullanma 08/29"
            idx.secrets = [s1, s2, s3, s4]
        }

        report += await mediaAndDragChecks(state, work: work)

        report += await backupAndIntegrityChecks(state, vaultURL: vaultURL, work: work, password: password)
        report += await keyfileChecks(state, vaultURL: vaultURL, password: password)
        report += await lockDuringTaskCheck(state, work: work, password: password)

        if let first = state.index.notes.last?.id { state.deleteNote(first) }
        report.append("Çöp kutusu: \(state.index.trashCount) öğe · etiketler \(state.index.allTags)")

        state.section = .files
        await snap("03-dosyalar", outDir)
        state.currentFolder = tripID
        await snap("03b-klasor-ici", outDir)
        state.currentFolder = nil
        state.updatePreferences { $0.filesLayout = "list" }
        await snap("04-dosyalar-liste", outDir)
        state.updatePreferences { $0.filesLayout = "grid" }
        state.section = .notes
        await snap("05-notlar", outDir)
        state.section = .secrets
        await snap("06-parolalar", outDir)
        state.section = .trash
        await snap("06b-cop-kutusu", outDir)
        state.section = .settings
        await snap("07-ayarlar", outDir)

        state.updatePreferences { $0.appearance = "dark"; $0.accent = "teal" }
        state.section = .secrets
        await snap("08-koyu-parolalar", outDir)
        state.section = .files
        await snap("09-koyu-dosyalar", outDir)
        state.lock()
        await snap("10-koyu-kilitli", outDir)
        UserDefaults.standard.set("light", forKey: "lockAppearance")
        UserDefaults.standard.set("indigo", forKey: "lockAccent")
        state.applyAppearance()
        state.objectWillChange.send()
        await snap("11-acik-kilitli", outDir)
        state.showWelcome()
        await snap("12-acik-karsilama", outDir)

        // Kilitledikten sonra kasa klasöründe düz metin kalmadığını doğrula.
        let leaks = scanForPlaintext(vaultURL, needles: ["Pasaport", "ornek-gmail-parolasi", "ornek@gmail.com", "manzara", "rapor", "Tatil", "gizli", "benzersiz"])
        report.append(leaks.isEmpty ? "Düz metin taraması: TEMIZ" : "SIZINTI: \(leaks)")
        try? report.joined(separator: "\n").write(to: outDir.appendingPathComponent("tarama.txt"), atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    /// Şifreli videoyu bellekte çözerek oynatma, Finder'a sürükleme ve klasöre taşıma denetimleri.
    private static func mediaAndDragChecks(_ state: AppState, work: URL) async -> [String] {
        var out: [String] = []
        let movie = work.appendingPathComponent("klip.mov")
        do {
            try await writeTestMovie(to: movie)
        } catch {
            return ["Test videosu üretilemedi: \(error)"]
        }
        state.importFiles([movie], into: nil)
        while state.task != nil { try? await Task.sleep(for: .milliseconds(100)) }
        guard let record = state.index.liveFiles.first(where: { $0.name == "klip.mov" }) else { return ["Video eklenemedi"] }

        do {
            let loader = EncryptedMediaLoader(reader: try await state.openReader(record), contentType: record.utType.identifier)
            let asset = loader.makeAsset(fileExtension: "mov")
            let playable = try await asset.load(.isPlayable)
            let duration = try await asset.load(.duration).seconds
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let (frame, _) = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600))
            let tempUsed = FileManager.default.fileExists(atPath: state.tempRoot.path)
            out.append("Video: oynatılabilir=\(playable) süre=\(String(format: "%.1f", duration))sn kare=\(frame.width)x\(frame.height) geçici-dosya=\(tempUsed ? "VAR" : "yok")")
            loader.invalidate()
        } catch {
            out.append("Video oynatma HATASI: \(error)")
        }

        // Finder'a sürükleme: sağlayıcıdan çözülmüş kopya alınır, içerik orijinalle aynı olmalı.
        let provider = state.dragProvider(for: record, alongWith: [])
        let (exported, dragError): (Data?, String?) = await withCheckedContinuation { cont in
            _ = provider.loadFileRepresentation(forTypeIdentifier: record.utType.identifier) { url, error in
                cont.resume(returning: (url.flatMap { try? Data(contentsOf: $0) }, error.map { "\($0)" }))
            }
        }
        let original = try? Data(contentsOf: movie)
        out.append("Sürükle→Finder: \(exported == original ? "içerik birebir aynı" : "HATALI (alınan \(exported?.count ?? -1) bayt, beklenen \(original?.count ?? -1); \(dragError ?? "-"); tür \(record.utType.identifier); kayıtlı \(provider.registeredTypeIdentifiers))")")

        // Kasa içi sürükle-bırak: dosyayı Belgeler klasörüne taşı.
        out.append("Sürükleme verisindeki türler: \(provider.registeredTypeIdentifiers) (yalnızca dosya türü olmalı)")
        let target = state.createFolder(named: "Videolar", in: nil)
        _ = state.handleDrop([state.dragProvider(for: record, alongWith: [])], into: target)
        try? await Task.sleep(for: .milliseconds(500))
        out.append("Klasöre sürükleme: \(state.index.files.first { $0.id == record.id }?.folderID == target ? "taşındı" : "TAŞINMADI")")
        return out
    }

    private static func waitForTask(_ state: AppState) async {
        try? await Task.sleep(for: .milliseconds(200))
        while state.task != nil { try? await Task.sleep(for: .milliseconds(100)) }
    }

    private static func backupAndIntegrityChecks(_ state: AppState, vaultURL: URL, work: URL, password: String) async -> [String] {
        var out: [String] = []
        let dest = work.appendingPathComponent("Yedek Diski/Mahzen Kasası Yedek")
        try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        out.append("Yedek hatırlatması (yedeksiz): \(state.backupDue ? "gösteriliyor" : "YOK")")
        state.updatePreferences { $0.backupPath = dest.path }
        state.backupNow()
        await waitForTask(state)
        let opened = try? Vault.unlock(at: dest, password: password)
        let backupFiles = (try? opened?.loadIndex().index.files.count) ?? -1
        out.append("Yedek: açılıyor=\(opened != nil) dosya=\(backupFiles)/\(state.index.files.count) hatırlatma=\(state.backupDue ? "HÂLÂ VAR" : "kalktı")")
        state.backupNow()
        await waitForTask(state)
        out.append("İkinci yedek: \(state.toast ?? "-")")

        // Kasadaki bir dosyayı boz, birini sil, bir artık dosya bırak; tarama hepsini bulmalı.
        guard let vault = state.vault, state.index.liveFiles.count >= 2 else { return out + ["Tarama için dosya yok"] }
        let damaged = state.index.liveFiles[0], missing = state.index.liveFiles[1]
        if var raw = try? Data(contentsOf: vault.blobURL(damaged.id)) {
            raw[raw.count / 2] ^= 0xFF
            try? raw.write(to: vault.blobURL(damaged.id))
        }
        try? FileManager.default.removeItem(at: vault.blobURL(missing.id))
        try? Data("artık".utf8).write(to: vault.folder.appendingPathComponent("blobs/zz-artik.mhz"))
        state.runIntegrityScan()
        await waitForTask(state)
        guard let scan = state.integrityReport else { return out + ["Tarama raporu YOK"] }
        out.append("Tarama: \(scan.checkedFiles) dosya, sorunlu=\(scan.problems.count) (bozuk: \(scan.problems[damaged.id].map { "\($0)".prefix(7) } ?? "-"), eksik: \(scan.problems[missing.id] == .missing)), artık=\(scan.orphanURLs.count)")
        let failed = await state.restoreFromBackup([damaged.id, missing.id])
        let ok1 = (try? vault.verifyFile(damaged.id)) == damaged.sha256
        let ok2 = (try? vault.verifyFile(missing.id)) == missing.sha256
        out.append("Yedekten geri yükleme: \(failed.isEmpty && ok1 && ok2 ? "iki dosya da sağlam döndü" : "HATA \(failed)")")
        state.removeOrphans(scan.orphanURLs)
        try? await Task.sleep(for: .milliseconds(300))
        state.integrityReport = nil
        state.runIntegrityScan()
        await waitForTask(state)
        let clean = state.integrityReport
        out.append("İkinci tarama: sorun=\(clean?.problems.count ?? -1) artık=\(clean?.orphanURLs.count ?? -1) parmak-izi-eksik=\(state.index.files.filter { $0.sha256 == nil }.count)")
        state.integrityReport = nil
        return out
    }

    private static func keyfileChecks(_ state: AppState, vaultURL: URL, password: String) async -> [String] {
        var out: [String] = []
        guard let id = state.vault?.header.vaultID else { return ["Anahtar dosyası testi: kasa yok"] }
        let store = KeyfileStore.standard
        // Yalnızca bu demo kasanın kimliğiyle başlayan dosyalar; başka (gerçek) anahtarlara dokunulmaz.
        func demoFiles() -> [URL] {
            let prefix = id.uuidString.lowercased()
            return ((try? FileManager.default.contentsOfDirectory(atPath: store.directory.path)) ?? [])
                .filter { $0.hasPrefix(prefix) }
                .map { store.directory.appendingPathComponent($0) }
        }
        defer { demoFiles().forEach { try? FileManager.default.removeItem(at: $0) } }

        let enableError = await state.enableKeyfile(password: password)
        let headerText = (try? String(contentsOf: vaultURL.appendingPathComponent("vault.json"), encoding: .utf8)) ?? ""
        let perms = (try? FileManager.default.attributesOfItem(atPath: store.url(for: id).path))?[.posixPermissions] as? Int ?? 0
        out.append("Bu Mac'e bağla: \(enableError ?? "tamam") · başlıkta iz: \((headerText.lowercased().contains("keyfile") || headerText.lowercased().contains("anahtar")) ? "VAR" : "yok") · dosya izinleri \(String(format: "%o", perms))")

        state.lock()
        out.append("Bu Mac'te açılış: \(await state.unlock(password: password) ?? "açıldı")")

        // Başka bir Mac'i taklit et: demo anahtarlarını geçici olarak kenara al.
        let aside = FileManager.default.temporaryDirectory.appendingPathComponent("mahzen-kenar-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: aside, withIntermediateDirectories: true)
        let moved = demoFiles()
        for url in moved { try? FileManager.default.moveItem(at: url, to: aside.appendingPathComponent(url.lastPathComponent)) }
        state.lock()
        out.append("Başka Mac'te doğru parola: \(await state.unlock(password: password) ?? "AÇILDI (HATA)")")
        for url in moved { try? FileManager.default.moveItem(at: aside.appendingPathComponent(url.lastPathComponent), to: url) }
        try? FileManager.default.removeItem(at: aside)
        out.append("Anahtar geri gelince: \(await state.unlock(password: password) ?? "açıldı")")

        let disableError = await state.disableKeyfile(password: password)
        state.lock()
        let plain = await state.unlock(password: password)
        out.append("Bağlantı kaldırılınca: \(disableError ?? "tamam") · dosyasız açılış \(plain ?? "açıldı") · etkin anahtar \(store.load(for: id) == nil ? "arşivlendi" : "DURUYOR") · arşivde \(store.candidates(for: id).count)")

        // Denetim bulgusu: anahtarsız açılmış eski bir kopya "bağlanmaya" çalışılınca asıl anahtar değişmemeli.
        let refusal = await state.enableKeyfile(password: password)
        out.append("Arşivde anahtar varken yeniden bağlama: \(refusal == nil ? "İZİN VERİLDİ (HATA)" : "engellendi")")
        return out
    }

    /// Denetim bulgusu: işlem sürerken kilit çalışmıyordu. Büyük dosya şifrelenirken kilitle.
    private static func lockDuringTaskCheck(_ state: AppState, work: URL, password: String) async -> [String] {
        let big = work.appendingPathComponent("buyuk-video.bin")
        FileManager.default.createFile(atPath: big.path, contents: nil)
        if let h = try? FileHandle(forWritingTo: big) {
            for _ in 0..<300 { h.write(Crypto.randomBytes(1 << 20)) }
            try? h.close()
        }
        let before = state.index.files.count
        guard let vault = state.vault else { return ["Kilit testi: kasa yok"] }
        let blobsBefore = ((FileManager.default.enumerator(atPath: vault.folder.appendingPathComponent("blobs").path)?.allObjects as? [String]) ?? []).filter { $0.hasSuffix(".mhz") }.count
        state.importFiles([big], into: nil)
        try? await Task.sleep(for: .milliseconds(400))
        let wasRunning = state.task != nil
        let start = Date()
        state.lock()
        let lockDelay = Date().timeIntervalSince(start)
        let lockedNow = state.phase == .locked && state.task == nil
        try? await Task.sleep(for: .seconds(2))
        _ = await state.unlock(password: password)
        let blobsAfter = ((FileManager.default.enumerator(atPath: vault.folder.appendingPathComponent("blobs").path)?.allObjects as? [String]) ?? []).filter { $0.hasSuffix(".mhz") }.count
        let tmpLeft = (FileManager.default.enumerator(atPath: vault.folder.path)?.allObjects as? [String] ?? []).filter { $0.hasSuffix(".tmp") }.count
        return ["İşlem sürerken kilit: işlem sürüyordu=\(wasRunning) · anında kilitlendi=\(lockedNow) (\(String(format: "%.2f", lockDelay)) sn) · yeni kayıt=\(state.index.files.count - before) · yeni şifreli dosya=\(blobsAfter - blobsBefore) · yarım dosya=\(tmpLeft)"]
    }

    private static func writeTestMovie(to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 240,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 240,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for i in 0..<60 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            guard let buffer else { continue }
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), Int32(i * 4), CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 30))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    private static func snap(_ name: String, _ dir: URL) async {
        try? await Task.sleep(for: .milliseconds(1200))
        // Ekran kaydı izni varsa gerçek pencere görüntüsü (buzlu cam, araç çubuğu dahil), yoksa iç çizim.
        if ProcessInfo.processInfo.environment["MAHZEN_REAL_CAPTURE"] != nil,
           let window = NSApp.windows.first(where: { $0.isVisible && $0.isKeyWindow || $0.isMainWindow }) ?? NSApp.windows.first(where: \.isVisible) {
            window.sharingType = .readOnly
            NSApp.activate(ignoringOtherApps: true)
            let target = window.attachedSheet ?? window
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-o", "-l\(target.windowNumber)", dir.appendingPathComponent("\(name).png").path]
            try? process.run()
            process.waitUntilExit()
            return
        }
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
    }

    private static func makeSampleFiles(in dir: URL) -> [URL] {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var urls: [URL] = []
        let palettes: [(String, [NSColor])] = [
            ("manzara-gun-batimi.png", [.systemOrange, .systemPink, .systemPurple]),
            ("deniz.png", [.systemTeal, .systemBlue, .systemIndigo]),
            ("orman.png", [.systemGreen, .systemMint, .systemTeal]),
            ("kimlik-tarama.png", [.systemGray, .white, .systemGray]),
        ]
        for (name, colors) in palettes {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 600, bitsPerSample: 8, samplesPerPixel: 4,
                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSGradient(colors: colors)!.draw(in: NSRect(x: 0, y: 0, width: 800, height: 600), angle: 60)
            NSGraphicsContext.restoreGraphicsState()
            let url = dir.appendingPathComponent(name)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            urls.append(url)
        }
        let text = dir.appendingPathComponent("rapor-2026.txt")
        try? String(repeating: "Gizli rapor satırı.\n", count: 200).write(to: text, atomically: true, encoding: .utf8)
        urls.append(text)
        let zip = dir.appendingPathComponent("yedek-arsiv.zip")
        try? Crypto.randomBytes(2_500_000).write(to: zip)
        urls.append(zip)
        return urls
    }

    private static func scanForPlaintext(_ dir: URL, needles: [String]) -> [String] {
        var found: [String] = []
        let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)
        while let url = e?.nextObject() as? URL {
            if url.lastPathComponent == "OKU-BENİ.txt" { continue }
            for needle in needles where url.lastPathComponent.contains(needle) { found.append("ad: \(url.lastPathComponent)") }
            guard let data = try? Data(contentsOf: url) else { continue }
            for needle in needles where data.range(of: Data(needle.utf8)) != nil { found.append("\(needle) → \(url.lastPathComponent)") }
        }
        return found
    }
}
#endif
