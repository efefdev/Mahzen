import AVFoundation
import AVKit
import MahzenCore
import SwiftUI

/// AVPlayer'ın istediği bayt aralıklarını kasadan bellekte çözerek verir; düz içerik diske yazılmaz.
final class EncryptedMediaLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    static let scheme = "mahzen-media"

    private let reader: BlobReader
    private let contentType: String
    private let delegateQueue = DispatchQueue(label: "mahzen.media.loader")
    private let lock = NSLock()
    private var active = true

    init(reader: BlobReader, contentType: String) {
        self.reader = reader
        self.contentType = contentType
    }

    func makeAsset(fileExtension: String) -> AVURLAsset {
        let ext = fileExtension.isEmpty ? "bin" : fileExtension
        let asset = AVURLAsset(url: URL(string: "\(Self.scheme)://media/\(UUID().uuidString).\(ext)")!)
        asset.resourceLoader.setDelegate(self, queue: delegateQueue)
        return asset
    }

    /// Kasa kilitlenince veya oynatıcı kapanınca yeni okuma yapılmaz.
    func invalidate() {
        lock.lock()
        active = false
        lock.unlock()
    }

    private var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        guard isActive else { return false }
        DispatchQueue.global(qos: .userInitiated).async { self.serve(request) }
        return true
    }

    private func serve(_ request: AVAssetResourceLoadingRequest) {
        if let info = request.contentInformationRequest {
            info.contentType = contentType
            info.contentLength = reader.plainSize
            info.isByteRangeAccessSupported = true
        }
        guard let dataRequest = request.dataRequest else {
            request.finishLoading()
            return
        }
        var offset = dataRequest.currentOffset != 0 ? dataRequest.currentOffset : dataRequest.requestedOffset
        let end = dataRequest.requestsAllDataToEndOfResource
            ? reader.plainSize
            : min(dataRequest.requestedOffset + Int64(dataRequest.requestedLength), reader.plainSize)
        do {
            while offset < end {
                guard !request.isCancelled, isActive else { return }
                let data = try reader.read(offset: offset, length: Int(min(end - offset, 512 * 1024)))
                guard !data.isEmpty else { break }
                dataRequest.respond(with: data)
                offset += Int64(data.count)
            }
            request.finishLoading()
        } catch {
            request.finishLoading(with: error)
        }
    }
}

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.allowsPictureInPicturePlayback = false
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}

extension FileRecord {
    var isMedia: Bool { utType.conforms(to: .audiovisualContent) }
    var isAudioOnly: Bool { utType.conforms(to: .audio) }
}
