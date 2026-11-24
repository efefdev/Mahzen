import MahzenCore
import SwiftUI

/// "Telefondan Ekle" penceresi: QR kodu, gelen dosyaların canlı listesi ve Durdur. Kapatılınca oturum da durur.
struct PhoneUploadSheet: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var session: PhoneUploadSession

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text(L("Telefondan Ekle")).font(.title2.weight(.semibold))
                Label(session.folderName, systemImage: "folder").foregroundStyle(.secondary)
            }
            content
            if !session.items.isEmpty { receivedList }
            Divider()
            HStack {
                Label(L("Uçtan uca şifreli · internete çıkmaz"), systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(isRunning ? L("Durdur") : L("Kapat")) { state.stopPhoneUpload() }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private var isRunning: Bool {
        if case .running = session.phase { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch session.phase {
        case .starting:
            ProgressView(L("Başlatılıyor…")).frame(height: 300)
        case .running(let url):
            VStack(spacing: 14) {
                if let image = PhoneShareSession.qrImage(for: url) {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 220, height: 220)
                        .padding(12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel(L("Yükleme QR kodu"))
                }
                VStack(spacing: 6) {
                    Text(L("Telefonun kamerasıyla okutun")).font(.headline)
                    Text(L("Açılan sayfada fotoğraf, video ya da dosya seçin. Dosyalar telefonda şifrelenir ve kasaya şifreli olarak yazılır; telefon bu Mac ile aynı Wi-Fi ağında olmalı."))
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 16) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let left = max(0, Int(session.expiresAt.timeIntervalSince(context.date)))
                        Label(L("{0} kaldı", String(format: "%d:%02d", left / 60, left % 60)), systemImage: "timer")
                            .monospacedDigit()
                    }
                    Label(session.devices.isEmpty ? L("Henüz bağlanan yok") : LN("{0} cihaz bağlandı", session.devices.count),
                          systemImage: session.devices.isEmpty ? "iphone.slash" : "iphone")
                        .foregroundStyle(session.devices.isEmpty ? Color.secondary : Color.green)
                }
                .font(.callout)
            }
        case .failed(let message):
            ContentUnavailableView(L("Oturum başlatılamadı"), systemImage: "wifi.exclamationmark", description: Text(message))
                .frame(height: 220)
        case .stopped:
            ContentUnavailableView(L("Oturum sona erdi"), systemImage: "checkmark.circle",
                                   description: Text(L("Telefondaki sayfa artık dosya gönderemez. Yeniden eklemek için yeni bir QR kod oluşturun.")))
                .frame(height: 220)
        }
    }

    private var receivedList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LN("{0} dosya eklendi", session.savedCount))
                .font(.subheadline.weight(.semibold))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(session.items) { item in
                            row(item).id(item.id)
                            if item.id != session.items.last?.id { Divider() }
                        }
                    }
                }
                .frame(maxHeight: 168)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                .onChange(of: session.items.count) { _, _ in
                    if let last = session.items.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
        }
    }

    private func row(_ item: PhoneUploadSession.Item) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol(item.state))
                .foregroundStyle(color(item.state))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                if item.state == .receiving {
                    ProgressView(value: Double(item.received), total: Double(max(item.size, 1)))
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                } else {
                    Text(detail(item)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func symbol(_ state: PhoneUploadSession.Item.State) -> String {
        switch state {
        case .receiving: return "arrow.down.circle"
        case .saved: return "checkmark.circle.fill"
        case .duplicate: return "equal.circle"
        case .failed: return "exclamationmark.circle.fill"
        case .cancelled: return "xmark.circle"
        }
    }

    private func color(_ state: PhoneUploadSession.Item.State) -> Color {
        switch state {
        case .receiving: return .accentColor
        case .saved: return .green
        case .failed: return .red
        case .duplicate, .cancelled: return .secondary
        }
    }

    private func detail(_ item: PhoneUploadSession.Item) -> String {
        switch item.state {
        case .receiving: return ""
        case .saved: return L("Kasaya eklendi")
        case .duplicate: return L("Kasada zaten vardı")
        case .failed(let reason): return reason
        case .cancelled: return L("Telefonda durduruldu")
        }
    }
}
