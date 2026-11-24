#if DEBUG
import AVFoundation
import CryptoKit
import AppKit
import MahzenCore
import SwiftUI

/// Yalnızca debug derlemede: `MAHZEN_SNAPSHOTS=<klasör>` ile başlatılırsa geçici bir demo kasa kurar,
/// her ekranın görüntüsünü PNG olarak kaydeder ve çıkar. Gerçek kasalara dokunmaz.
@MainActor
enum DebugSnapshots {
    /// Örnek verinin dili arayüz diliyle aynı olsun (İngilizce ekran görüntüleri için).
    private static func D(_ turkish: String, _ english: String) -> String {
        Localization.language == .en ? english : turkish
    }

    /// Klasörü (alt klasörü ve boş bir alt klasörüyle) dışa aktarır ve diske çıkan yapıyı raporlar.
    private static func folderExportCheck(_ state: AppState, folder: UUID?, work: URL) async -> [String] {
        guard let folder else { return ["Klasör dışa aktarma: klasör yok"] }
        state.createFolder(named: D("Boş", "Empty"), in: folder)
        let out = work.appendingPathComponent("disari")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        // Aynı adlı bir şey varken ikinci kopya "Ad 2" olmalı.
        for _ in 0..<2 {
            state.performExport(state.index.exportPlan(files: [], folders: [folder]), to: out)
            while state.task != nil { try? await Task.sleep(for: .milliseconds(100)) }
        }
        let paths = (FileManager.default.enumerator(atPath: out.path)?.allObjects as? [String] ?? []).sorted()
        let expected = state.index.liveFileCount(inTree: folder)
        let firstRoot = paths.first.map { String($0.split(separator: "/")[0]) } ?? ""
        let exportedFiles = paths.filter { p in
            var dir: ObjCBool = false
            return p.hasPrefix(firstRoot + "/") && FileManager.default.fileExists(atPath: out.appendingPathComponent(p).path, isDirectory: &dir) && !dir.boolValue
        }
        return ["Klasör dışa aktarma: \(paths)", "  ilk kopyada \(exportedFiles.count)/\(expected) dosya · toast: \(state.toast ?? "-")"]
    }

    static func runIfRequested(_ state: AppState) async {
        guard let out = ProcessInfo.processInfo.environment["MAHZEN_SNAPSHOTS"] else { return }
        if ProcessInfo.processInfo.environment["MAHZEN_MARQUEE_TEST"] != nil {
            await marqueeTest(state, out: URL(fileURLWithPath: out, isDirectory: true))
            return
        }
        let outDir = URL(fileURLWithPath: out, isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("MahzenDemo-\(UUID().uuidString)")
        let vaultURL = work.appendingPathComponent(D("Mahzen Kasası", "Mahzen Vault"))
        let password = "demo-parola-uzun-123"
        defer { try? FileManager.default.removeItem(at: work) }

        state.showWelcome()
        await snap("01-karsilama", outDir)

        // Eski sürüm gibi PBKDF2 ile oluştur; kilit açılınca Argon2id'ye yükseltilmeli.
        _ = try? Vault.create(at: vaultURL, password: password, kdf: .pbkdf2(iterations: 10_000))
        state.selectVault(vaultURL)
        await snap("02-kilitli", outDir)

        _ = await state.unlock(password: password)
        state.updatePreferences { $0.displayName = D("Kişisel Kasa", "Personal Vault"); $0.askToTrashOriginals = false; $0.hideFromScreenCapture = false }

        var report: [String] = []
        let header = try? Vault.readHeader(at: vaultURL)
        report.append("KDF yükseltme: \(header?.kdf.algorithm ?? "?") v\(header?.version ?? 0)")

        let samples = makeSampleFiles(in: work.appendingPathComponent("ornek"))
        state.importFiles(samples, into: nil)
        while state.task != nil { try? await Task.sleep(for: .milliseconds(100)) }

        // Klasör yapısıyla içe aktarma: Tatil/2026/... ve aynı dosyaların tekrar eklenmesi.
        let trip = work.appendingPathComponent(D("Tatil", "Vacation"))
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
        let tripID = state.index.childFolders(of: nil).first { $0.name == D("Tatil", "Vacation") }?.id
        let yearID = tripID.flatMap { id in state.index.childFolders(of: id).first { $0.name == "2026" }?.id }
        report.append("Klasörler: \(state.index.folders.map(\.name).sorted()) · 2026 içinde \(state.index.liveFiles(in: yearID).map(\.name))")
        state.createFolder(named: D("Belgeler", "Documents"), in: nil)
        if let doc = state.index.liveFiles.first(where: { $0.name.hasSuffix(".txt") }) {
            state.setTags([D("iş", "work"), D("gizli", "private")], for: [doc.id])
        }
        if let zip = state.index.liveFiles.first(where: { $0.name.hasSuffix(".zip") }) {
            state.trashFiles([zip.id])
        }

        state.mutate { idx in
            var n1 = Note(); n1.title = D("Pasaport bilgileri", "Passport details"); n1.body = D("Seri no ve yenileme tarihi burada.\nKonsolosluk randevusu: Kasım.", "Serial number and renewal date are here.\nConsulate appointment: November."); n1.pinned = true; n1.color = "orange"
            var n2 = Note(); n2.title = D("Kripto kurtarma ifadesi", "Crypto recovery phrase"); n2.body = D("Kağıt kopyası kasada, ikinci kopya ailede.", "Paper copy in the safe, a second copy with family."); n2.color = "teal"
            var n3 = Note(); n3.title = D("Proje fikirleri", "Project ideas"); n3.body = D("Yeni uygulama için taslak notlar…", "Draft notes for a new app…")
            idx.notes = [n1, n2, n3]
            var s1 = Secret(); s1.title = "Gmail"; s1.username = D("ornek@gmail.com", "example@gmail.com"); s1.password = "ornek-gmail-parolasi"; s1.url = "mail.google.com"; s1.favorite = true
            var s2 = Secret(); s2.title = D("Ev Wi-Fi", "Home Wi-Fi"); s2.category = .wifi; s2.password = "kahve-masasi-2024"
            var s3 = Secret(); s3.title = D("Örnek sunucu", "Example server"); s3.category = .server; s3.username = D("kullanici", "admin"); s3.password = "ornek-sunucu-parolasi"; s3.url = "ornek.com"
            var s4 = Secret(); s4.title = D("Banka kartı", "Bank card"); s4.category = .card; s4.notes = D("Son kullanma 08/29", "Expires 08/29")
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
        report += await folderExportCheck(state, folder: tripID, work: work)
        state.currentFolder = nil
        try? await Task.sleep(for: .milliseconds(300))
        if let photo = state.index.liveFiles(in: nil).first(where: { $0.utType.conforms(to: .image) }) {
            state.debugPreview = photo
            try? await Task.sleep(for: .milliseconds(900))
            await snap("03d-onizleme", outDir)
            let before = state.index.files.first { $0.id == photo.id }?.favorite ?? false
            NSApp.keyWindow?.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                         windowNumber: NSApp.keyWindow?.windowNumber ?? 0, context: nil,
                                                         characters: "f", charactersIgnoringModifiers: "f", isARepeat: false, keyCode: 3)!)
            try? await Task.sleep(for: .milliseconds(500))
            let after = state.index.files.first { $0.id == photo.id }?.favorite ?? false
            report.append("Önizleme favori (F): \(before) → \(after)")
            await snap("03e-onizleme-favori", outDir)
            NSApp.keyWindow?.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
                                                         windowNumber: NSApp.keyWindow?.windowNumber ?? 0, context: nil,
                                                         characters: "\u{8}", charactersIgnoringModifiers: "\u{8}", isARepeat: false, keyCode: 51)!)
            try? await Task.sleep(for: .milliseconds(700))
            let trashed = state.index.files.first { $0.id == photo.id }?.deletedAt != nil
            report.append("Önizleme çöp (⌘⌫): çöpte=\(trashed)")
            let second = state.index.liveFiles(in: nil).first { $0.utType.conforms(to: .image) }
            NSApp.keyWindow?.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                         windowNumber: NSApp.keyWindow?.windowNumber ?? 0, context: nil,
                                                         characters: "f", charactersIgnoringModifiers: "f", isARepeat: false, keyCode: 3)!)
            try? await Task.sleep(for: .milliseconds(500))
            report.append("Önizleme favori ikinci deneme (F) \(second?.name ?? "-"): \(state.index.files.first { $0.id == second?.id }?.favorite ?? false) · anahtar pencere: \(NSApp.keyWindow?.className ?? "-")")
            await snap("03f-onizleme-sonraki", outDir)
            NSApp.keyWindow?.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                         windowNumber: NSApp.keyWindow?.windowNumber ?? 0, context: nil,
                                                         characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!)
            try? await Task.sleep(for: .milliseconds(500))
            if trashed { state.mutate { idx in idx.restoreFile(photo.id) } }
        }
        state.currentFolder = tripID
        if let trip = state.index.folder(tripID), let yearID {
            // Alt klasörü de kapsadığını görmek için bir fotoğrafı Tatil/2026 içine taşı.
            if let photo = state.index.liveFiles.first(where: { $0.utType.conforms(to: .image) && $0.folderID == nil }) {
                state.moveFiles([photo.id], to: yearID)
            }
            state.showOnPhone(folder: trip)
            report += await phoneShareChecks(state)
            await snap("03c-telefonda-goster", outDir)
            state.stopPhoneShare()
        }
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

        state.updatePreferences { $0.appearance = "dark"; $0.accent = "orange" }
        state.setAutoWipe(Vault.defaultAutoWipeAttempts)
        state.section = .settings
        await scrollSettings(toFraction: 0.40)
        await snap("13-sinir-ayar", outDir)
        state.section = .secrets
        await snap("08-koyu-parolalar", outDir)
        state.section = .files
        await snap("09-koyu-dosyalar", outDir)
        state.lock()
        await snap("10-koyu-kilitli", outDir)
        UserDefaults.standard.set("light", forKey: "lockAppearance")
        UserDefaults.standard.set("orange", forKey: "lockAccent")
        state.applyAppearance()
        state.objectWillChange.send()
        await snap("11-acik-kilitli", outDir)
        state.showWelcome()
        await snap("12-acik-karsilama", outDir)

        // Kilitledikten sonra kasa klasöründe düz metin kalmadığını doğrula.
        let leaks = scanForPlaintext(vaultURL, needles: [D("Pasaport", "Passport"), "ornek-gmail-parolasi", D("ornek@gmail.com", "example@gmail.com"), D("manzara", "sunset"), D("rapor", "report"), D("Tatil", "Vacation"), D("gizli", "private"), "benzersiz"])
        report.append(leaks.isEmpty ? "Düz metin taraması: TEMIZ" : "SIZINTI: \(leaks)")
        report += await wipeScenes(state, vaultURL: vaultURL, outDir: outDir)
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
        let target = state.createFolder(named: D("Videolar", "Videos"), in: nil)
        _ = state.handleDrop([state.dragProvider(for: record, alongWith: [])], into: target)
        try? await Task.sleep(for: .milliseconds(500))
        out.append("Klasöre sürükleme: \(state.index.files.first { $0.id == record.id }?.folderID == target ? "taşındı" : "TAŞINMADI")")
        return out
    }

    /// "Telefonda Göster": sunucu gerçekten açılıyor mu, içerik şifreli mi, telefonun anahtarıyla doğru çözülüyor mu?
    private static func phoneShareChecks(_ state: AppState) async -> [String] {
        guard let session = state.phoneShare else { return ["Telefon paylaşımı: oturum açılmadı"] }
        for _ in 0..<50 where session.phase == .starting { try? await Task.sleep(for: .milliseconds(100)) }
        guard case .running(let address) = session.phase, let hash = address.firstIndex(of: "#") else {
            return ["Telefon paylaşımı: \(session.phase)"]
        }
        var b64 = String(address[address.index(after: hash)...]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let keyData = Data(base64Encoded: b64) else { return ["Telefon paylaşımı: anahtar okunamadı"] }
        let key = SymmetricKey(data: keyData)
        let base = String(address[..<hash])
        func get(_ path: String) async -> (Int, Data, [AnyHashable: Any]) {
            guard let url = URL(string: base + path),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  let http = response as? HTTPURLResponse else { return (0, Data(), [:]) }
            return (http.statusCode, data, http.allHeaderFields)
        }
        var lines: [String] = []
        let (pageStatus, _, headers) = await get("")
        lines.append("Telefon sayfası: \(pageStatus) · CSP \(headers["Content-Security-Policy"] != nil ? "var" : "YOK")")
        let (_, manifestData, _) = await get("m")
        let manifest = (try? PhoneShare.open(manifestData, key: key, streamID: PhoneShare.manifestStream))
            .flatMap { try? JSONDecoder().decode(PhoneShareManifest.self, from: $0) }
        lines.append("Telefon listesi: \(manifest.map { "\($0.items.count) öğe, yollar \(Set($0.items.map { $0.path.joined(separator: "/") }).sorted())" } ?? "ÇÖZÜLEMEDİ")")
        if let first = manifest?.items.first,
           let record = state.index.liveFiles.first(where: { $0.name == first.name }),
           let original = try? await state.readFile(record) {
            let (_, sealed, _) = await get("f/0")
            let opened = try? PhoneShare.open(sealed, key: key, streamID: PhoneShare.fileStream(0))
            let leaks = sealed.range(of: original.prefix(64)) != nil
            lines.append("Telefon dosyası: \(opened == original ? "aynı" : "FARKLI") · ağda düz içerik \(leaks ? "VAR" : "yok")")
        }
        let (wrong, _, _) = await get("../yanlis-jeton/m")
        lines.append("Yanlış jeton: \(wrong)")
        return lines
    }

    /// Dikdörtgenle seçim: 60 fotoğraflık kasada pencereye gerçek fare olayları gönderip ekranın kenarına
    /// kadar sürükler; ızgaranın kendiliğinden kayıp kaydığı yerdeki öğeleri de seçtiğini görüntüyle doğrular.
    private static func marqueeTest(_ state: AppState, out: URL) async {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("MahzenMarquee-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        let vaultURL = work.appendingPathComponent("Kasa")
        let password = "demo-parola-uzun-123"
        _ = try? Vault.create(at: vaultURL, password: password, kdf: .pbkdf2(iterations: 10_000))
        state.selectVault(vaultURL)
        _ = await state.unlock(password: password)
        state.updatePreferences { $0.askToTrashOriginals = false; $0.hideFromScreenCapture = false; $0.filesLayout = "grid" }
        let samples = work.appendingPathComponent("ornek")
        try? FileManager.default.createDirectory(at: samples, withIntermediateDirectories: true)
        var urls: [URL] = []
        for i in 1...60 {
            let image = NSImage(size: NSSize(width: 160, height: 120), flipped: false) { rect in
                NSColor(hue: CGFloat(i) / 60, saturation: 0.6, brightness: 0.9, alpha: 1).setFill()
                rect.fill()
                ("\(i)" as NSString).draw(at: NSPoint(x: 60, y: 45), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 28)])
                return true
            }
            let url = samples.appendingPathComponent(String(format: "foto-%02d.png", i))
            if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
                urls.append(url)
            }
        }
        func log(_ text: String) {
            let url = out.appendingPathComponent("marquee.log")
            let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            try? (old + text + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
        log("örnek: \(urls.count) · faz \(state.phase)")
        state.importFiles(urls, into: nil)
        while state.task != nil { try? await Task.sleep(for: .milliseconds(100)) }
        log("içe aktarıldı: \(state.index.liveFiles.count) · uyarı \(state.alert?.title ?? "-")")
        state.alert = nil
        state.section = .files
        try? await Task.sleep(for: .seconds(2))

        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let scroll = allSubviews(window.contentView!).compactMap({ $0 as? NSScrollView })
                .max(by: { ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0) }) else {
            log("pencere ya da kaydırma görünümü bulunamadı: \(NSApp.windows.map { "\($0.title) \($0.isVisible)" })")
            return
        }
        log("kaydırma görünümü: \(scroll.frame) belge \(scroll.documentView?.bounds.height ?? 0)")
        let frame = scroll.convert(scroll.bounds, to: nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(500))
        let windowNumber = window.windowNumber
        // Fare basılıyken AppKit kendi izleme döngüsüne girer ve ana iş parçacığını tutar; olaylar arka planda kuyruğa eklenir.
        // Izgaranın sağ kenarındaki boş şeritten başla, sola ve aşağıya, pencerenin alt kenarına sürükle.
        let startPoint = NSPoint(x: frame.maxX - 19, y: frame.midY)
        let endPoint = NSPoint(x: frame.maxX - 420, y: frame.minY + 6)
        let before = scroll.documentVisibleRect.origin.y
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                func post(_ type: NSEvent.EventType, _ point: NSPoint) {
                    guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                         windowNumber: windowNumber, context: nil, eventNumber: Int.random(in: 1...1_000_000), clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1) else { return }
                    NSApp.postEvent(event, atStart: false)
                }
                post(.leftMouseDown, startPoint)
                usleep(50_000)
                for step in 1...20 {
                    let t = CGFloat(step) / 20
                    post(.leftMouseDragged, NSPoint(x: startPoint.x + (endPoint.x - startPoint.x) * t, y: startPoint.y + (endPoint.y - startPoint.y) * t))
                    usleep(16_000)
                }
                // Kenarda bekle: ızgara kendiliğinden kaymalı.
                usleep(1_500_000)
                post(.leftMouseDragged, endPoint)
                usleep(50_000)
                post(.leftMouseUp, endPoint)
                usleep(200_000)
                done.resume()
            }
        }
        let after = scroll.documentVisibleRect.origin.y
        log("kaydırma: \(before) → \(after) · seçim \(MarqueeSelection.debugLast.map { "\($0.selected) (bilinen konum \($0.known), dikdörtgen \($0.rect))" } ?? "hiç başlamadı")")
        await snap("marquee-birakildi", out)
        try? "kaydırma: \(before) → \(after) (belge \(scroll.documentView?.bounds.height ?? 0), görünür \(scroll.documentVisibleRect.height))\n"
            .write(to: out.appendingPathComponent("marquee.txt"), atomically: true, encoding: .utf8)
    }

    /// Ayarlar formunu belgenin verilen oranına kaydırır (yanlış parola sınırı bölümünü göstermek için).
    private static func scrollSettings(toFraction fraction: CGFloat) async {
        try? await Task.sleep(for: .milliseconds(800))
        guard let root = NSApp.windows.first(where: \.isVisible)?.contentView else { return }
        let scrolls = allSubviews(root).compactMap { $0 as? NSScrollView }
        guard let scroll = scrolls.max(by: { ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0) }),
              let doc = scroll.documentView else { return }
        let maxY = max(0, doc.bounds.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: maxY * fraction))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    /// Yanlış parola sınırı: kilit ekranında son deneme uyarısı, ardından kasanın silinmesi.
    private static func wipeScenes(_ state: AppState, vaultURL: URL, outDir: URL) async -> [String] {
        UserDefaults.standard.set("dark", forKey: "lockAppearance")
        state.applyAppearance()
        state.selectVault(vaultURL)
        var message: String?
        for _ in 1..<Vault.defaultAutoWipeAttempts {
            message = await state.unlock(password: "yanlis-parola")
        }
        state.debugUnlockError = message
        await snap("14-sinir-son-hak", outDir)
        state.debugUnlockError = nil
        _ = await state.unlock(password: "yanlis-parola")
        await snap("15-sinir-silindi", outDir)
        return ["Son hak mesajı: \(message ?? "-") · silindi: \(!Vault.exists(at: vaultURL)) · uyarı: \(state.alert?.title ?? "-")"]
    }

    private static func allSubviews(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(allSubviews)
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
            (D("manzara-gun-batimi.png", "sunset-landscape.png"), [.systemOrange, .systemPink, .systemPurple]),
            (D("deniz.png", "sea.png"), [.systemTeal, .systemBlue, .systemIndigo]),
            (D("orman.png", "forest.png"), [.systemGreen, .systemMint, .systemTeal]),
            (D("kimlik-tarama.png", "id-scan.png"), [.systemGray, .white, .systemGray]),
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
        let text = dir.appendingPathComponent(D("rapor-2026.txt", "report-2026.txt"))
        try? String(repeating: D("Gizli rapor satırı.\n", "Private report line.\n"), count: 200).write(to: text, atomically: true, encoding: .utf8)
        urls.append(text)
        let zip = dir.appendingPathComponent(D("yedek-arsiv.zip", "backup-archive.zip"))
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
