import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import CryptoKit
import Foundation
import MahzenCore
import UniformTypeIdentifiers

/// Bir "Telefonda Göster" oturumu: sunucuyu başlatır, QR adresini üretir, süre dolunca kendini kapatır.
@MainActor
final class PhoneShareSession: ObservableObject, Identifiable {
    enum Phase: Equatable {
        case starting
        case running(url: String)
        case failed(String)
        case stopped
    }

    static let lifetime: TimeInterval = 10 * 60

    let id = UUID()
    let title: String
    let photoCount: Int
    let videoCount: Int
    @Published private(set) var phase = Phase.starting
    @Published private(set) var devices = Set<String>()
    @Published private(set) var expiresAt: Date

    private var server: PhoneShareServer?
    private var expiryTimer: Timer?

    /// Paylaşılabilecek dosyalar: telefondaki tarayıcının gösterebildiği fotoğraf ve videolar.
    static func isShareable(_ file: FileRecord) -> Bool { kind(of: file) != nil }

    private static func kind(of file: FileRecord) -> String? {
        let type = file.utType
        if type.conforms(to: .image) { return "image" }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return "video" }
        return nil
    }

    /// `files`: (dosya, paylaşılan klasöre göre yol) çiftleri.
    init?(vault: Vault, title: String, files: [(FileRecord, [String])]) {
        let media = files.filter { Self.isShareable($0.0) }
            .sorted { a, b in
                let pa = a.1.joined(separator: "/"), pb = b.1.joined(separator: "/")
                if pa != pb { return pa.localizedStandardCompare(pb) == .orderedAscending }
                return a.0.name.localizedStandardCompare(b.0.name) == .orderedAscending
            }
        guard !media.isEmpty else { return nil }
        self.title = title
        expiresAt = Date().addingTimeInterval(Self.lifetime)
        var items: [PhoneShareManifest.Item] = []
        var entries: [PhoneShareServer.Entry] = []
        for (i, (file, path)) in media.enumerated() {
            items.append(.init(index: i, name: file.name, path: path, kind: Self.kind(of: file) ?? "image",
                               mime: file.utType.preferredMIMEType ?? "application/octet-stream",
                               size: file.size, hasThumbnail: file.hasThumbnail))
            entries.append(.init(id: file.id, hasThumbnail: file.hasThumbnail))
        }
        photoCount = items.filter { $0.kind == "image" }.count
        videoCount = items.count - photoCount

        let key = PhoneShare.newKey()
        let token = Self.base64url(Crypto.randomBytes(16))
        let manifest = PhoneShareManifest(title: title, expiresAt: expiresAt.timeIntervalSince1970, items: items)
        guard let manifestData = try? JSONEncoder().encode(manifest) else { return nil }
        let server = PhoneShareServer(vault: vault, entries: entries, key: key, token: token, manifest: manifestData)
        self.server = server
        let keyText = key.withUnsafeBytes { Self.base64url(Data($0)) }

        server.onRequest = { [weak self] remote, _ in
            Task { @MainActor in self?.devices.insert(remote) }
        }
        Task { [weak self] in
            guard let host = LocalNetwork.primaryIPv4() else {
                self?.fail(L("Bu Mac bir Wi-Fi ya da yerel ağa bağlı görünmüyor. Telefonla aynı ağa bağlanıp yeniden deneyin."))
                return
            }
            do {
                let port = try await server.start(host: host)
                guard let self, self.phase == .starting else { server.stop(); return }
                self.phase = .running(url: "http://\(host):\(port)/\(token)/#\(keyText)")
                self.scheduleExpiry()
            } catch {
                self?.fail(L("Paylaşım başlatılamadı: {0}", error.localizedDescription))
            }
        }
    }

    private func fail(_ message: String) {
        server?.stop()
        server = nil
        phase = .failed(message)
    }

    private func scheduleExpiry() {
        expiryTimer = Timer.scheduledTimer(withTimeInterval: expiresAt.timeIntervalSinceNow, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
    }

    func stop() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        server?.stop()
        server = nil
        if case .failed = phase { return }
        phase = .stopped
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func qrImage(for text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}

extension AppState {
    /// Seçili dosyalardaki fotoğraf ve videoları telefonda gösterir.
    func showOnPhone(files: [FileRecord]) {
        let title = files.count == 1 ? files[0].name : LN("{0} öğe", files.count)
        startPhoneShare(title: title, files: files.map { ($0, []) })
    }

    /// Klasörü alt klasörleriyle birlikte telefonda gösterir.
    func showOnPhone(folder: Folder) {
        let ids = index.descendantFolderIDs(of: folder.id).union([folder.id])
        let base = index.path(to: folder.id).count
        let files = index.liveFiles.filter { $0.folderID.map(ids.contains) ?? false }
            .map { file in (file, Array(index.path(to: file.folderID).dropFirst(base).map(\.name))) }
        startPhoneShare(title: folder.name, files: files)
    }

    private func startPhoneShare(title: String, files: [(FileRecord, [String])]) {
        guard let vault else { return }
        phoneShare?.stop()
        guard let session = PhoneShareSession(vault: vault, title: title, files: files) else {
            alert = AlertItem(title: L("Gösterilecek fotoğraf ya da video yok"),
                              message: L("Telefonda yalnızca fotoğraflar ve videolar gösterilebilir."))
            return
        }
        phoneShare = session
    }

    func stopPhoneShare() {
        phoneShare?.stop()
        phoneShare = nil
    }
}
