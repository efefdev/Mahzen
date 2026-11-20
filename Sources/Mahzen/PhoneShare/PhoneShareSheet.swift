import SwiftUI

/// QR kodu ve paylaşımın durumunu gösteren pencere. Kapatılınca paylaşım da durur.
struct PhoneShareSheet: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var session: PhoneShareSession

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text("Telefonda Göster").font(.title2.weight(.semibold))
                Text(summary).foregroundStyle(.secondary)
            }
            content
            Divider()
            HStack {
                Label("Uçtan uca şifreli · internete çıkmaz", systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(isRunning ? "Durdur" : "Kapat") { state.stopPhoneShare() }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private var isRunning: Bool {
        if case .running = session.phase { return true }
        return false
    }

    private var summary: String {
        let parts = [session.photoCount > 0 ? "\(session.photoCount) fotoğraf" : nil,
                     session.videoCount > 0 ? "\(session.videoCount) video" : nil].compactMap { $0 }
        return "\(session.title) · " + parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .starting:
            ProgressView("Başlatılıyor…").frame(height: 300)
        case .running(let url):
            VStack(spacing: 14) {
                if let image = PhoneShareSession.qrImage(for: url) {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 240, height: 240)
                        .padding(12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel("Paylaşım QR kodu")
                }
                VStack(spacing: 6) {
                    Text("iPhone'un kamerasıyla okutun")
                        .font(.headline)
                    Text("Telefon bu Mac ile aynı Wi-Fi ağında olmalı. Dosyalar şifreli gelir, anahtar yalnızca bu QR kodda bulunur.")
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 16) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let left = max(0, Int(session.expiresAt.timeIntervalSince(context.date)))
                        Label(String(format: "%d:%02d kaldı", left / 60, left % 60), systemImage: "timer")
                            .monospacedDigit()
                    }
                    Label(session.devices.isEmpty ? "Henüz bağlanan yok" : "\(session.devices.count) cihaz bağlandı",
                          systemImage: session.devices.isEmpty ? "iphone.slash" : "iphone")
                        .foregroundStyle(session.devices.isEmpty ? Color.secondary : Color.green)
                }
                .font(.callout)
            }
        case .failed(let message):
            ContentUnavailableView("Paylaşım başlatılamadı", systemImage: "wifi.exclamationmark", description: Text(message))
                .frame(height: 300)
        case .stopped:
            ContentUnavailableView("Paylaşım sona erdi", systemImage: "checkmark.circle",
                                   description: Text("Telefondaki sayfa artık açılmaz. Yeniden göstermek için yeni bir QR kod oluşturun."))
                .frame(height: 300)
        }
    }
}
