import AppKit
import MahzenCore
import SwiftUI

private let turkish = Locale(identifier: "tr_TR")

/// Büyük saat ve tarih (macOS kilit ekranı gibi).
private struct LockClock: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 0) {
                Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(turkish)))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(context.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(turkish)))
                    .font(.system(size: 92, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.primary.opacity(0.9))
            }
        }
    }
}

/// macOS girişindeki gibi içinde ok düğmesi olan kapsül parola alanı.
private struct PillPasswordField: View {
    @Binding var password: String
    let working: Bool
    let failed: Bool
    let onSubmit: () -> Void
    @FocusState private var focused: Bool
    @Environment(\.vaultAccent) private var accent

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "key.fill")
                .foregroundStyle(.secondary)
                .padding(.leading, 16)
            SecureField("Parola", text: $password)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($focused)
                .onSubmit(onSubmit)
                .disabled(working)
            Button(action: onSubmit) {
                ZStack {
                    Circle().fill(password.isEmpty ? Color.secondary.opacity(0.2) : accent)
                    if working {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(password.isEmpty ? Color.secondary : .white)
                    }
                }
                .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .disabled(password.isEmpty || working)
            .keyboardShortcut(.defaultAction)
            .help("Kilidi aç (↩)")
            .padding(.trailing, 6)
        }
        .frame(width: 340, height: 46)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(
                failed ? Color.red.opacity(0.8) : (focused ? accent.opacity(0.8) : Color.white.opacity(0.15)),
                lineWidth: focused || failed ? 1.5 : 1
            )
        )
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .onAppear { focused = true }
        .onChange(of: working) { _, isWorking in if !isWorking { focused = true } }
    }
}

/// Caps Lock durumunu izler.
private final class CapsLockMonitor: ObservableObject {
    @Published var isOn = NSEvent.modifierFlags.contains(.capsLock)
    private var monitor: Any?

    init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.isOn = event.modifierFlags.contains(.capsLock)
            return event
        }
    }

    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}

struct UnlockView: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var capsLock = CapsLockMonitor()
    @State private var password = ""
    @State private var error: String?
    @State private var working = false
    @State private var opened = false
    @State private var shake: CGFloat = 0

    var body: some View {
        ZStack {
            AuraBackground()
            VStack(spacing: 0) {
                LockClock()
                    .padding(.top, 56)
                Spacer(minLength: 24)
                VStack(spacing: 18) {
                    VaultBadge(size: 84, open: opened)
                        .scaleEffect(opened ? 1.08 : 1)
                    VStack(spacing: 6) {
                        Text(opened ? "Kilit açıldı" : "Mahzen kilitli")
                            .font(.title2.weight(.semibold))
                            .contentTransition(.opacity)
                        if let url = state.vaultURL {
                            Label(location(url), systemImage: "externaldrive.fill")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    PillPasswordField(password: $password, working: working, failed: error != nil, onSubmit: unlock)
                        .modifier(ShakeEffect(amount: shake))
                        .padding(.top, 6)
                        .opacity(opened ? 0 : 1)
                    statusLine
                        .frame(height: 18)
                }
                Spacer(minLength: 24)
                footer
                    .padding(.bottom, 22)
            }
            .padding(.horizontal, 24)
        }
        .animation(.smooth(duration: 0.35), value: opened)
        .animation(.smooth(duration: 0.2), value: error)
        .animation(.smooth(duration: 0.2), value: capsLock.isOn)
    }

    @ViewBuilder
    private var statusLine: some View {
        if let error {
            Label(error, systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.callout)
                .transition(.opacity)
        } else if working {
            Text("Anahtar türetiliyor…")
                .foregroundStyle(.secondary)
                .font(.callout)
        } else if capsLock.isOn {
            Label("Caps Lock açık", systemImage: "capslock.fill")
                .foregroundStyle(.orange)
                .font(.callout)
                .transition(.opacity)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 16) {
                Label("AES-256-GCM", systemImage: "lock.fill")
                Label("Argon2id", systemImage: "cpu")
                Label("Çevrimdışı", systemImage: "wifi.slash")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            Button("Başka bir kasa aç veya yeni oluştur") { state.showWelcome() }
                .buttonStyle(.link)
                .font(.callout)
        }
    }

    private func location(_ url: URL) -> String {
        let volume = (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName
        return [volume, url.lastPathComponent].compactMap { $0 }.joined(separator: " › ")
    }

    private func unlock() {
        guard !password.isEmpty, !working else { return }
        working = true
        error = nil
        Task {
            let message = await state.unlock(password: password) {
                working = false
                opened = true
                try? await Task.sleep(for: .milliseconds(550))
            }
            working = false
            password = ""
            if let message {
                error = message
                withAnimation(.linear(duration: 0.4)) { shake += 1 }
            }
        }
    }
}

struct ShakeEffect: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(amount * .pi * 6), y: 0))
    }
}

struct WelcomeView: View {
    @EnvironmentObject private var state: AppState
    @State private var creating = false

    var body: some View {
        ZStack {
            AuraBackground()
            if creating {
                SetupView(onBack: { creating = false })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                VStack(spacing: 28) {
                    VStack(spacing: 14) {
                        VaultBadge(size: 104)
                        Text("Mahzen")
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                        Text("Dosyaların, notların ve parolaların için\nşifreli, taşınabilir bir kasa.")
                            .font(.title3)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    Card(width: 440) {
                        VStack(alignment: .leading, spacing: 16) {
                            feature("lock.shield.fill", "Her şey şifreli", "Dosya adları, notlar ve parolalar dahil; AES-256-GCM ve Argon2id.")
                            feature("externaldrive.fill", "Seninle taşınır", "Kasa, uygulamanın yanında SSD'de durur; her Mac'te açılır.")
                            feature("wifi.slash", "Tamamen çevrimdışı", "Hiçbir şey internete gönderilmez, hesap gerekmez.")
                            Divider().padding(.vertical, 2)
                            Button {
                                withAnimation(.smooth) { creating = true }
                            } label: {
                                Label("Yeni kasa oluştur", systemImage: "plus.circle.fill")
                                    .frame(maxWidth: .infinity).frame(height: 28)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            Button(action: openExisting) {
                                Label("Mevcut kasayı aç…", systemImage: "folder")
                                    .frame(maxWidth: .infinity).frame(height: 28)
                            }
                            .controlSize(.large)
                        }
                    }
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.primary.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func openExisting() {
        let panel = NSOpenPanel()
        panel.title = "Mahzen kasa klasörünü seç"
        panel.prompt = "Aç"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { state.selectVault(url) }
    }
}

struct SetupView: View {
    let onBack: () -> Void
    @EnvironmentObject private var state: AppState
    @State private var location = AppState.defaultVaultURL
    @State private var password = ""
    @State private var confirm = ""
    @State private var understood = false

    private var strength: PasswordStrength { PasswordStrength.evaluate(password) }
    private var problem: String? {
        if password.count < Vault.minimumPasswordLength { return "En az \(Vault.minimumPasswordLength) karakter" }
        if !confirm.isEmpty, confirm != password { return "Parolalar eşleşmiyor" }
        return nil
    }
    private var canCreate: Bool { problem == nil && understood && !confirm.isEmpty }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button(action: onBack) { Image(systemName: "chevron.left") }
                        .buttonStyle(.borderless)
                    Text("Yeni kasa").font(.title2.weight(.bold))
                    Spacer()
                    VaultBadge(size: 36)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Konum").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Image(systemName: "folder.fill").foregroundStyle(.tint)
                        Text(location.path)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer()
                        Button("Değiştir…", action: chooseLocation).controlSize(.small)
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Ana parola").font(.caption).foregroundStyle(.secondary)
                    RevealableField(title: "Parola", text: $password)
                    StrengthMeter(password: password)
                    RevealableField(title: "Parolayı tekrarla", text: $confirm, onSubmit: create)
                    Text(password.isEmpty ? "Uzun bir cümle iyi bir paroladır: \"mor-kedi 7 kez çay demledi!\"" : (problem ?? (strength.score < 3 ? "Daha uzun bir parola önerilir." : "Harika.")))
                        .font(.caption)
                        .foregroundStyle(problem != nil && !password.isEmpty ? .orange : .secondary)
                }

                Toggle(isOn: $understood) {
                    Text("Bu parolayı unutursam kasadaki verilerin **hiçbir şekilde** kurtarılamayacağını anlıyorum.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(.checkbox)

                Button(action: create) {
                    Text("Kasayı Oluştur").frame(maxWidth: .infinity).frame(height: 26)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canCreate)
            }
        }
    }

    private func chooseLocation() {
        let panel = NSOpenPanel()
        panel.title = "Kasanın oluşturulacağı yer (ör. SSD)"
        panel.prompt = "Burada Oluştur"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            location = url.appendingPathComponent("Mahzen Kasası", isDirectory: true)
        }
    }

    private func create() {
        guard canCreate else { return }
        state.createVault(at: location, password: password)
    }
}
