import CryptoKit
import Foundation
import MahzenCore
import Network
import UniformTypeIdentifiers

/// "Telefonda Göster" için yerel ağda çalışan küçük HTTP sunucusu.
///
/// - Yalnızca bu oturumun rastgele adresine (`/<jeton>/…`) cevap verir; başka her istek 404 alır.
/// - Yalnızca paylaşılmak üzere seçilen dosyaları sunar; dosyaları kasadan çözüp oturum anahtarıyla yeniden
///   şifreler (bkz. `PhoneShare`). Anahtar sunucuda değil, QR koddadır; ağda yalnızca şifreli bayt dolaşır.
/// - Durdurulunca dinlemeyi ve açık bağlantıları hemen keser.
final class PhoneShareServer: @unchecked Sendable {
    struct Entry: Sendable {
        let id: UUID
        let hasThumbnail: Bool
    }

    private let vault: Vault
    private let entries: [Entry]
    private let key: SymmetricKey
    private let token: String
    private let manifest: Data
    private let queue = DispatchQueue(label: "mahzen.phoneshare", qos: .userInitiated)
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var stopped = false

    /// Her başarılı istekte (uzak adres, sunulan dosya sırası ya da nil) ana iş parçacığında çağrılır.
    var onRequest: (@Sendable (String, Int?) -> Void)?

    init(vault: Vault, entries: [Entry], key: SymmetricKey, token: String, manifest: Data) {
        self.vault = vault
        self.entries = entries
        self.key = key
        self.token = token
        self.manifest = manifest
    }

    /// Verilen yerel adreste rastgele bir portta dinlemeye başlar; port numarasını döndürür.
    func start(host: String) async throws -> UInt16 {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: .any)
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            // Durum değişiklikleri sunucunun sıralı kuyruğunda gelir; devamı yalnızca bir kez çağırmak yeterli.
            final class Once: @unchecked Sendable { var done = false }
            let once = Once()
            listener.stateUpdateHandler = { state in
                guard !once.done else { return }
                switch state {
                case .ready:
                    once.done = true
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error):
                    once.done = true
                    continuation.resume(throwing: error)
                case .cancelled:
                    once.done = true
                    continuation.resume(throwing: CancellationError())
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        queue.async { [self] in
            stopped = true
            listener?.cancel()
            listener = nil
            connections.values.forEach { $0.cancel() }
            connections.removeAll()
        }
    }

    // MARK: - Bağlantılar

    private func accept(_ connection: NWConnection) {
        guard !stopped else { connection.cancel(); return }
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.queue.async { self?.connections[id] = nil }
            default: break
            }
        }
        connection.start(queue: queue)
        // İstek başlığını oku (en fazla 16 KB; gövde beklenmez, yalnızca GET).
        readHeader(connection, buffer: Data())
        // Yanıt vermeyen bağlantılar 30 sn sonra kapatılır.
        queue.asyncAfter(deadline: .now() + 30) { [weak connection] in
            if let connection, connection.state != .cancelled, self.connections[id] != nil, !self.busy.contains(id) {
                connection.cancel()
            }
        }
    }

    private var busy = Set<ObjectIdentifier>()

    private func readHeader(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                self.handle(connection, header: buffer[..<end.lowerBound])
            } else if error != nil || isComplete || buffer.count > 16 * 1024 {
                connection.cancel()
            } else {
                self.readHeader(connection, buffer: buffer)
            }
        }
    }

    private func remoteAddress(_ connection: NWConnection) -> String {
        if case .hostPort(let host, _) = connection.endpoint { return "\(host)" }
        return "?"
    }

    private func handle(_ connection: NWConnection, header: Data) {
        let requestLine = String(decoding: header.prefix(while: { $0 != 0x0D }), as: UTF8.self)
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return respond(connection, status: "405 Method Not Allowed") }
        let path = parts[1].split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
        let segments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        // Jeton sabit zamanlı karşılaştırılır.
        guard let first = segments.first, constantTimeEqual(first, token) else {
            return respond(connection, status: "404 Not Found")
        }
        let remote = remoteAddress(connection)
        let rest = Array(segments.dropFirst())
        let number = rest.count == 2 ? Int(rest[1]) : nil
        if rest.isEmpty {
            if !path.hasSuffix("/") { return respond(connection, status: "301 Moved Permanently", extra: ["Location": "/\(token)/"]) }
            onRequest?(remote, nil)
            respond(connection, status: "200 OK", contentType: "text/html; charset=utf-8", body: Data(PhoneShareViewer.html.utf8), extra: PhoneShareViewer.securityHeaders)
        } else if rest == ["m"] {
            onRequest?(remote, nil)
            sendSealed(connection, data: manifest, stream: PhoneShare.manifestStream)
        } else if rest.first == "t", let index = number, entries.indices.contains(index), entries[index].hasThumbnail,
                  let thumb = try? vault.readThumbnail(entries[index].id) {
            sendSealed(connection, data: thumb, stream: PhoneShare.thumbnailStream(index))
        } else if rest.first == "f", let index = number, entries.indices.contains(index) {
            onRequest?(remote, index)
            sendFile(connection, index: index)
        } else {
            respond(connection, status: "404 Not Found")
        }
    }

    private func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in x.indices { diff |= x[i] ^ y[i] }
        return diff == 0
    }

    // MARK: - Yanıtlar

    private static let baseHeaders = [
        "Cache-Control": "no-store",
        "X-Content-Type-Options": "nosniff",
        "Referrer-Policy": "no-referrer",
        "Connection": "close",
    ]

    private func headerData(status: String, contentType: String?, length: Int64, extra: [String: String]) -> Data {
        var lines = ["HTTP/1.1 \(status)", "Content-Length: \(length)"]
        if let contentType { lines.append("Content-Type: \(contentType)") }
        for (k, v) in Self.baseHeaders.merging(extra, uniquingKeysWith: { _, new in new }) { lines.append("\(k): \(v)") }
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    }

    private func respond(_ connection: NWConnection, status: String, contentType: String? = nil, body: Data = Data(), extra: [String: String] = [:]) {
        let data = headerData(status: status, contentType: contentType, length: Int64(body.count), extra: extra) + body
        connection.send(content: data, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func sendSealed(_ connection: NWConnection, data: Data, stream: UInt32) {
        guard let sealed = try? PhoneShare.seal(data, key: key, stream: stream) else {
            return respond(connection, status: "500 Internal Server Error")
        }
        respond(connection, status: "200 OK", contentType: "application/octet-stream", body: sealed)
    }

    /// Dosyayı kasadan parça parça çözüp yeniden şifreleyerek gönderir; bellekte en fazla bir parça tutulur.
    private func sendFile(_ connection: NWConnection, index: Int) {
        let reader: BlobReader
        do {
            reader = try vault.openReader(entries[index].id)
        } catch {
            return respond(connection, status: "500 Internal Server Error")
        }
        let id = ObjectIdentifier(connection)
        busy.insert(id)
        let size = reader.plainSize
        let header = headerData(status: "200 OK", contentType: "application/octet-stream",
                                length: PhoneShare.streamLength(plainSize: size), extra: [:])
        let stream = PhoneShare.fileStream(index)
        let chunkSize = Int64(PhoneShare.chunkSize)
        let chunkCount = max(1, (size + chunkSize - 1) / chunkSize)

        func sendChunk(_ chunk: Int64) {
            guard !stopped else { connection.cancel(); return }
            let final = chunk == chunkCount - 1
            let frame: Data
            do {
                let plain = try reader.read(offset: chunk * chunkSize, length: Int(chunkSize))
                frame = try PhoneShare.sealFrame(plain, key: key, stream: stream, chunk: UInt64(chunk), final: final)
            } catch {
                connection.cancel()
                return
            }
            connection.send(content: frame, isComplete: final, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if error != nil || final {
                    self.busy.remove(id)
                    connection.cancel()
                } else {
                    self.queue.async { sendChunk(chunk + 1) }
                }
            })
        }

        connection.send(content: header, completion: .contentProcessed { [weak self] error in
            guard let self, error == nil else { connection.cancel(); return }
            self.queue.async { sendChunk(0) }
        })
    }
}

// MARK: - Yerel ağ adresi

enum LocalNetwork {
    /// Mac'in yerel ağdaki IPv4 adresi (Wi-Fi ya da kablolu). Sanal makine köprüleri, VPN tünelleri ve
    /// AirDrop arayüzleri atlanır; telefonun ulaşabileceği adres bunlarda değildir.
    static func primaryIPv4() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var candidates: [(name: String, address: String)] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0,
                  let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard !["bridge", "utun", "awdl", "llw", "anpi", "ap", "gif", "stf", "vmnet"].contains(where: name.hasPrefix) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let address = String(cString: host)
            guard !address.hasPrefix("169.254.") else { continue }
            candidates.append((name, address))
        }
        // Önce en0 (çoğu Mac'te Wi-Fi), sonra diğer enX arayüzleri.
        return (candidates.first { $0.name == "en0" } ?? candidates.first { $0.name.hasPrefix("en") } ?? candidates.first)?.address
    }
}
