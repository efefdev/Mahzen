import AppKit
import AVFoundation
import CryptoKit
import Foundation
import ImageIO
import MahzenCore
import UniformTypeIdentifiers

/// Bir "Telefondan Ekle" oturumu: sunucuyu başlatır, QR adresini üretir, gelen dosyaları listeler,
/// süre dolunca kendini kapatır.
@MainActor
final class PhoneUploadSession: ObservableObject, Identifiable {
    enum Phase: Equatable {
        case starting
        case running(url: String)
        case failed(String)
        case stopped
    }

    struct Item: Identifiable, Equatable {
        enum State: Equatable {
            case receiving
            case saved
            case duplicate
            case failed(String)
            case cancelled
        }

        let id: Int
        var name: String
        var size: Int64
        var received: Int64 = 0
        var state = State.receiving
    }

    static let lifetime: TimeInterval = 10 * 60

    let id = UUID()
    /// Dosyaların ekleneceği klasör (`nil` = kök).
    let folderID: UUID?
    let folderName: String
    @Published private(set) var phase = Phase.starting
    @Published private(set) var items: [Item] = []
    @Published private(set) var devices = Set<String>()
    let expiresAt: Date

    /// Biten bir yüklemeyi kasaya kaydeder (AppState atar). `.rejected` dönerse dosya silinir.
    var accept: ((PhoneUploadServer.Completed) -> PhoneUploadServer.Outcome)?

    private var server: PhoneUploadServer?
    private var expiryTimer: Timer?

    init?(vault: Vault, folderID: UUID?, folderName: String) {
        self.folderID = folderID
        self.folderName = folderName
        expiresAt = Date().addingTimeInterval(Self.lifetime)
        let key = PhoneShare.newKey()
        let token = Self.base64url(Crypto.randomBytes(16))
        let status = PhoneUploadStatus(folder: folderName, expiresAt: expiresAt.timeIntervalSince1970)
        guard let statusData = try? JSONEncoder().encode(status) else { return nil }
        let server = PhoneUploadServer(
            key: key, token: token, status: statusData, expiresAt: expiresAt,
            makeReceiver: { PhoneUploadReceiver(number: $0, key: key, vault: vault) },
            discard: { vault.deleteFile($0) })
        self.server = server
        let keyText = key.withUnsafeBytes { Self.base64url(Data($0)) }

        server.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        server.onCompleted = { [weak self] completed, reply in
            Task { @MainActor in
                let outcome = self?.complete(completed) ?? .rejected
                if outcome == .rejected { vault.deleteFile(completed.fileID) }
                reply(outcome)
            }
        }
        Task { [weak self] in
            var host = LocalNetwork.primaryIPv4()
            #if DEBUG
            // Yalnızca debug derlemede: tarayıcıyla bu Mac'te denemek için (ör. 127.0.0.1).
            if let override = ProcessInfo.processInfo.environment["MAHZEN_UPLOAD_HOST"] { host = override }
            #endif
            guard let host else {
                self?.fail(L("Bu Mac bir Wi-Fi ya da yerel ağa bağlı görünmüyor. Telefonla aynı ağa bağlanıp yeniden deneyin."))
                return
            }
            do {
                let port = try await server.start(host: host)
                guard let self, self.phase == .starting else { server.stop(); return }
                self.phase = .running(url: "http://\(host):\(port)/\(token)/#\(keyText)")
                self.scheduleExpiry()
            } catch {
                self?.fail(L("Oturum başlatılamadı: {0}", error.localizedDescription))
            }
        }
    }

    var savedCount: Int { items.filter { $0.state == .saved }.count }
    var isReceiving: Bool { items.contains { $0.state == .receiving } }

    private func handle(_ event: PhoneUploadServer.Event) {
        switch event {
        case .connected(let remote):
            devices.insert(remote)
        case .started(let number, let meta):
            items.append(Item(id: number, name: meta.safeName, size: meta.size))
        case .progress(let number, let received):
            update(number) { $0.received = received }
        case .failed(let number, let code):
            update(number) { $0.state = .failed(Self.failureText(code)) }
        case .cancelled(let number):
            update(number) { $0.state = .cancelled }
        }
    }

    private func complete(_ completed: PhoneUploadServer.Completed) -> PhoneUploadServer.Outcome {
        guard server != nil, let accept else { return .rejected }
        let outcome = accept(completed)
        update(completed.number) {
            $0.received = $0.size
            $0.state = outcome == .duplicate ? .duplicate : outcome == .saved ? .saved : .failed(L("Kaydedilemedi"))
        }
        return outcome
    }

    private func update(_ number: Int, _ body: (inout Item) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == number }) else { return }
        body(&items[i])
    }

    static func failureText(_ code: String) -> String {
        switch code {
        case "timeout": return L("Telefondan veri gelmedi")
        case "net": return L("Bağlantı koptu")
        case "crypto": return L("Doğrulanamadı")
        case "too-large": return L("Dosya çok büyük")
        case "no-space": return L("Diskte yer yok")
        case "io": return L("Kasaya yazılamadı")
        default: return L("Geçersiz istek")
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
        for i in items.indices where items[i].state == .receiving { items[i].state = .cancelled }
        if case .failed = phase { return }
        phase = .stopped
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Küçük resim (kasadan, bellekte)

    /// Kasaya yeni giren bir görsel ya da videonun küçük resmi. Düz içerik yalnızca bellekte çözülür.
    nonisolated static func thumbnail(vault: Vault, id: UUID, type: UTType) async -> Data? {
        let image: CGImage?
        if type.conforms(to: .image) {
            guard let reader = try? vault.openReader(id), reader.plainSize <= 200 << 20,
                  let data = try? vault.readFile(id),
                  let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 440,
            ] as CFDictionary)
        } else if type.conforms(to: .movie) || type.conforms(to: .video) {
            guard let reader = try? vault.openReader(id) else { return nil }
            let loader = EncryptedMediaLoader(reader: reader, contentType: type.identifier)
            defer { loader.invalidate() }
            let generator = AVAssetImageGenerator(asset: loader.makeAsset(fileExtension: type.preferredFilenameExtension ?? "mov"))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 440, height: 440)
            image = try? await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
        } else {
            return nil
        }
        guard let image else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.78])
    }
}

extension AppState {
    /// Telefondan dosya almak için oturum açar; dosyalar `folder` klasörüne (nil = kök) eklenir.
    func addFromPhone(into folder: UUID?) {
        guard let vault, phase == .unlocked else { return }
        stopPhoneShare()
        phoneUpload?.stop()
        let name = index.folder(folder).map(\.name) ?? L("Dosyalar")
        guard let session = PhoneUploadSession(vault: vault, folderID: folder, folderName: name) else { return }
        session.accept = { [weak self, weak session] completed in
            guard let self, let session else { return .rejected }
            return self.acceptPhoneUpload(completed, from: session)
        }
        phoneUpload = session
    }

    func stopPhoneUpload() {
        guard let session = phoneUpload else { return }
        session.stop()
        phoneUpload = nil
        let saved = session.savedCount
        if saved > 0 { showToast(LN("{0} dosya telefondan eklendi", saved)) }
    }
}
