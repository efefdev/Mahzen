import CryptoKit
import Foundation
import MahzenCore
import Network

/// "Telefondan Ekle" için yerel ağda çalışan küçük HTTP sunucusu (uç noktalar için bkz. `PhoneUpload`).
///
/// - Yalnızca bu oturumun rastgele adresine (`/<jeton>/…`) cevap verir; başka her istek 404 alır.
/// - Gelen her bayt önce oturum anahtarıyla doğrulanır, sonra kasanın anahtarıyla şifrelenip yazılır
///   (`PhoneUploadReceiver`); düz içerik diske hiç yazılmaz. Anahtar sunucuda değil, QR koddadır.
/// - Yarım kalan, iptal edilen ya da uzun süre parça gelmeyen yüklemelerin geçici dosyaları silinir.
/// - Durdurulunca dinlemeyi, açık bağlantıları ve yarım yüklemeleri hemen keser.
final class PhoneUploadServer: @unchecked Sendable {
    enum Event: Sendable {
        /// Bir cihaz sayfayı ya da oturum bilgisini açtı (uzak adres).
        case connected(String)
        case started(Int, PhoneUploadMeta)
        case progress(Int, Int64)
        case failed(Int, String)
        case cancelled(Int)
    }

    struct Completed: Sendable {
        let number: Int
        let meta: PhoneUploadMeta
        let fileID: UUID
        let sha256: String
    }

    enum Outcome: String, Sendable {
        case saved, duplicate, rejected
    }

    private final class Upload {
        let receiver: PhoneUploadReceiver
        var lastActivity = Date()
        var connection: NWConnection?
        init(receiver: PhoneUploadReceiver) { self.receiver = receiver }
    }

    private struct Request {
        let method: String
        let path: String
        let query: String
        let contentLength: Int?
        let chunked: Bool
    }

    private let key: SymmetricKey
    private let token: String
    private let status: Data
    private let expiresAt: Date
    private let makeReceiver: @Sendable (Int) -> PhoneUploadReceiver
    private let discard: @Sendable (UUID) -> Void
    private let queue = DispatchQueue(label: "mahzen.phoneupload", qos: .userInitiated)
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var uploads: [Int: Upload] = [:]
    private var nextNumber = 1
    private var stopped = false
    private var sweeper: DispatchSourceTimer?

    /// Olaylar sunucu kuyruğunda çağrılır; arayüz ana iş parçacığına kendisi geçer.
    var onEvent: (@Sendable (Event) -> Void)?
    /// Biten her yükleme için çağrılır; sonuç bildirilene kadar telefonun isteği bekletilir.
    /// Atanmamışsa ya da sunucu durmuşsa dosya silinir.
    var onCompleted: (@Sendable (Completed, @escaping @Sendable (Outcome) -> Void) -> Void)?

    /// - `status`: telefona gönderilecek oturum bilgisi (düz JSON; burada şifrelenir).
    /// - `makeReceiver`: verilen numara için kasaya yazan alıcı. `discard`: kasaya taşınmış ama kabul edilmeyen dosyayı siler.
    init(key: SymmetricKey, token: String, status: Data, expiresAt: Date,
         makeReceiver: @escaping @Sendable (Int) -> PhoneUploadReceiver, discard: @escaping @Sendable (UUID) -> Void) {
        self.key = key
        self.token = token
        self.status = status
        self.expiresAt = expiresAt
        self.makeReceiver = makeReceiver
        self.discard = discard
    }

    /// Verilen yerel adreste rastgele bir portta dinlemeye başlar; port numarasını döndürür.
    func start(host: String) async throws -> UInt16 {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: .any)
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        let port = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
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
        queue.async { [self] in
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 10, repeating: 10)
            timer.setEventHandler { [weak self] in self?.sweep() }
            timer.resume()
            sweeper = timer
        }
        return port
    }

    func stop() {
        queue.async { [self] in
            stopped = true
            sweeper?.cancel()
            sweeper = nil
            listener?.cancel()
            listener = nil
            connections.values.forEach { $0.cancel() }
            connections.removeAll()
            for upload in uploads.values { upload.receiver.cancel() }
            uploads.removeAll()
        }
    }

    /// Uzun süre parça gelmeyen yüklemeleri bırakır (telefon kilitlendi, sayfa kapandı, ağ koptu).
    private func sweep() {
        let now = Date()
        for (number, upload) in uploads where now.timeIntervalSince(upload.lastActivity) > PhoneUpload.idleTimeout {
            upload.connection?.cancel()
            drop(number, event: .failed(number, "timeout"))
        }
    }

    private func drop(_ number: Int, event: Event?) {
        guard let upload = uploads.removeValue(forKey: number) else { return }
        upload.receiver.cancel()
        if let event { onEvent?(event) }
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
        readHeader(connection, buffer: Data())
        // Başlığını göndermeyen bağlantılar 30 sn sonra kapatılır.
        queue.asyncAfter(deadline: .now() + 30) { [weak self, weak connection] in
            guard let self, let connection, self.connections[id] != nil, !self.reading.contains(id) else { return }
            connection.cancel()
        }
    }

    /// Gövdesi okunmakta olan bağlantılar (zaman aşımını yükleme denetimi üstlenir).
    private var reading = Set<ObjectIdentifier>()

    private func readHeader(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let rest = Data(buffer[end.upperBound...])
                self.handle(connection, header: Data(buffer[..<end.lowerBound]), leftover: rest)
            } else if error != nil || isComplete || buffer.count > 16 * 1024 {
                connection.cancel()
            } else {
                self.readHeader(connection, buffer: buffer)
            }
        }
    }

    private func parse(_ header: Data) -> Request? {
        let lines = String(decoding: header, as: UTF8.self).components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2 else { return nil }
        let target = parts[1].split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        var length: Int?
        var chunked = false
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if name == "content-length" {
                guard let n = Int(value), n >= 0, length == nil || length == n else { return nil }
                length = n
            } else if name == "transfer-encoding" {
                chunked = true
            }
        }
        return Request(method: String(parts[0]), path: String(target[0]),
                       query: target.count > 1 ? String(target[1]) : "", contentLength: length, chunked: chunked)
    }

    private func remoteAddress(_ connection: NWConnection) -> String {
        if case .hostPort(let host, _) = connection.endpoint { return "\(host)" }
        return "?"
    }

    private func handle(_ connection: NWConnection, header: Data, leftover: Data) {
        guard let request = parse(header) else { return respond(connection, status: "400 Bad Request") }
        let segments = request.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        // Jeton sabit zamanlı karşılaştırılır. Süresi dolan oturum da bulunamaz.
        guard let first = segments.first, constantTimeEqual(first, token), Date() < expiresAt, !stopped else {
            return respond(connection, status: "404 Not Found")
        }
        let rest = Array(segments.dropFirst())
        let remote = remoteAddress(connection)
        switch (request.method, rest.first) {
        case ("GET", nil):
            if !request.path.hasSuffix("/") { return respond(connection, status: "301 Moved Permanently", extra: ["Location": "/\(token)/"]) }
            onEvent?(.connected(remote))
            respond(connection, status: "200 OK", contentType: "text/html; charset=utf-8",
                    body: Data(PhoneUploadPage.html.utf8), extra: PhoneUploadPage.securityHeaders)
        case ("GET", "s") where rest.count == 1:
            onEvent?(.connected(remote))
            guard let sealed = try? PhoneShare.seal(status, key: key, stream: PhoneUpload.statusStream) else {
                return respond(connection, status: "500 Internal Server Error")
            }
            respond(connection, status: "200 OK", contentType: "application/octet-stream", body: sealed)
        case ("POST", "n") where rest.count == 1:
            guard request.contentLength ?? 0 == 0, !request.chunked else { return fail(connection, "411 Length Required", "length") }
            guard uploads.count < PhoneUpload.maxOpenUploads else { return fail(connection, "429 Too Many Requests", "busy") }
            let number = nextNumber
            nextNumber += 1
            uploads[number] = Upload(receiver: makeReceiver(number))
            respondJSON(connection, ["n": number])
        case ("POST", "x") where rest.count == 2:
            if let number = Int(rest[1]), let upload = uploads[number] {
                upload.connection?.cancel()
                drop(number, event: .cancelled(number))
            }
            respondJSON(connection, [:])
        case ("POST", "u") where rest.count == 3:
            guard let number = Int(rest[1]), let part = Int(rest[2]), let upload = uploads[number] else {
                return drain(connection, leftover: leftover, length: request.contentLength) { $0.fail(connection, "409 Conflict", "order") }
            }
            guard let length = request.contentLength, !request.chunked else {
                drop(number, event: .failed(number, "length"))
                return fail(connection, "411 Length Required", "length")
            }
            guard upload.connection == nil, upload.receiver.expects(part: part) else {
                drop(number, event: .failed(number, "order"))
                return drain(connection, leftover: leftover, length: length) { $0.fail(connection, "409 Conflict", "order") }
            }
            guard length <= (part == 0 ? PhoneUpload.maxMetaLength : PhoneUpload.maxPartLength) else {
                drop(number, event: .failed(number, "length"))
                return fail(connection, "413 Content Too Large", "length")
            }
            let final = request.query.split(separator: "&").contains("end=1")
            upload.connection = connection
            upload.lastActivity = Date()
            reading.insert(ObjectIdentifier(connection))
            readBody(connection, upload: upload, number: number, part: part, final: final,
                     remaining: length, pending: leftover, collected: Data())
        default:
            respond(connection, status: request.method == "GET" || request.method == "POST" ? "404 Not Found" : "405 Method Not Allowed")
        }
    }

    // MARK: - Yükleme gövdesi

    /// Gövdeyi geldikçe alıcıya verir. 0. parça (dosya bilgisi) bütün olarak, içerik parçaları akarak işlenir.
    private func readBody(_ connection: NWConnection, upload: Upload, number: Int, part: Int, final: Bool,
                          remaining: Int, pending: Data, collected: Data) {
        // Bu arada iptal edildi, süresi doldu ya da sunucu durdu.
        guard !stopped, uploads[number] === upload else { connection.cancel(); return }
        var remaining = remaining
        var collected = collected
        let chunk = pending.prefix(remaining)
        remaining -= chunk.count
        do {
            if !chunk.isEmpty {
                upload.lastActivity = Date()
                if part == 0 { collected.append(chunk) } else { try upload.receiver.consume(Data(chunk)) }
            }
            if remaining == 0 {
                reading.remove(ObjectIdentifier(connection))
                upload.connection = nil
                return try finishPart(connection, upload: upload, number: number, part: part, final: final, collected: collected)
            }
        } catch {
            return reject(connection, number: number, error: error)
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: min(remaining, 256 * 1024)) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.readBody(connection, upload: upload, number: number, part: part, final: final,
                              remaining: remaining, pending: data, collected: collected)
            } else if error != nil || isComplete {
                // Telefon isteği yarıda kesti: yükleme bırakılır, geçici dosya silinir.
                self.reading.remove(ObjectIdentifier(connection))
                self.drop(number, event: .failed(number, "net"))
                connection.cancel()
            } else {
                self.readBody(connection, upload: upload, number: number, part: part, final: final,
                              remaining: remaining, pending: Data(), collected: collected)
            }
        }
    }

    /// Reddedilen isteğin (sınır içindeki) gövdesini okuyup atar, sonra yanıt verir. Okunmadan kapatılırsa tarayıcı
    /// yanıtı göremeden bağlantı sıfırlanır ve telefon hatayı "ulaşılamadı" sanır.
    private func drain(_ connection: NWConnection, leftover: Data, length: Int?, then respond: @escaping (PhoneUploadServer) -> Void) {
        guard let length, length <= PhoneUpload.maxPartLength else { return respond(self) }
        var remaining = length - leftover.count
        func next() {
            guard remaining > 0, !stopped else { return respond(self) }
            connection.receive(minimumIncompleteLength: 1, maximumLength: min(remaining, 256 * 1024)) { data, _, isComplete, error in
                remaining -= data?.count ?? 0
                if error != nil || (isComplete && remaining > 0) { connection.cancel(); return }
                next()
            }
        }
        next()
    }

    private func finishPart(_ connection: NWConnection, upload: Upload, number: Int, part: Int, final: Bool, collected: Data) throws {
        let receiver = upload.receiver
        if part == 0 {
            let meta = try receiver.receiveMeta(collected)
            onEvent?(.started(number, meta))
            return respondJSON(connection, [:])
        }
        guard let hash = try receiver.endPart(final: final) else {
            onEvent?(.progress(number, receiver.received))
            return respondJSON(connection, [:])
        }
        uploads[number] = nil
        guard let meta = receiver.meta else { return }
        let completed = Completed(number: number, meta: meta, fileID: receiver.fileID, sha256: hash)
        guard let onCompleted, !stopped else {
            discard(receiver.fileID)
            return fail(connection, "404 Not Found", "gone")
        }
        onCompleted(completed) { [weak self] outcome in
            guard let self else { return }
            self.queue.async {
                if outcome == .rejected { self.respond(connection, status: "404 Not Found") } else { self.respondJSON(connection, ["result": outcome.rawValue]) }
            }
        }
    }

    private func reject(_ connection: NWConnection, number: Int, error: Error) {
        reading.remove(ObjectIdentifier(connection))
        let failure = error as? PhoneUploadReceiver.Failure ?? .io(error.localizedDescription)
        drop(number, event: .failed(number, failure.code))
        let status: String
        switch failure {
        case .tooLarge: status = "413 Content Too Large"
        case .noSpace: status = "507 Insufficient Storage"
        case .io: status = "500 Internal Server Error"
        default: status = "400 Bad Request"
        }
        fail(connection, status, failure.code)
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

    private func respond(_ connection: NWConnection, status: String, contentType: String? = nil, body: Data = Data(), extra: [String: String] = [:]) {
        var lines = ["HTTP/1.1 \(status)", "Content-Length: \(body.count)"]
        if let contentType { lines.append("Content-Type: \(contentType)") }
        for (k, v) in Self.baseHeaders.merging(extra, uniquingKeysWith: { _, new in new }) { lines.append("\(k): \(v)") }
        let data = Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8) + body
        connection.send(content: data, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func respondJSON(_ connection: NWConnection, _ object: [String: Any], status: String = "200 OK") {
        let body = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        respond(connection, status: status, contentType: "application/json", body: body)
    }

    private func fail(_ connection: NWConnection, _ status: String, _ code: String) {
        respondJSON(connection, ["error": code], status: status)
    }
}
