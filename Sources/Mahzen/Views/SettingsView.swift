import AppKit
import MahzenCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var changingPassword = false
    @State private var keyfileSheet: KeyfileSheet.Mode?
    @State private var showGenerator = false

    var body: some View {
        Form {
            SwiftUI.Section("Görünüm") {
                Picker("Tema", selection: state.preference(\.appearance)) {
                    ForEach(AppearanceChoice.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)

                LabeledContent("Vurgu rengi") {
                    HStack(spacing: 8) {
                        ForEach(AccentChoice.allCases) { choice in
                            Button {
                                state.updatePreferences { $0.accent = choice.rawValue }
                            } label: {
                                Circle()
                                    .fill(choice.color.gradient)
                                    .frame(width: 22, height: 22)
                                    .overlay(Circle().strokeBorder(.white, lineWidth: state.accent == choice ? 2.5 : 0))
                                    .overlay(Circle().strokeBorder(choice.color, lineWidth: state.accent == choice ? 1 : 0).padding(-3))
                            }
                            .buttonStyle(.plain)
                            .help(choice.title)
                        }
                    }
                }

                TextField("Kasa adı", text: state.preference(\.displayName))

                Picker("Not yazı tipi", selection: state.preference(\.noteFontDesign)) {
                    ForEach(NoteFontDesign.allCases) { Text($0.title).tag($0.rawValue) }
                }

                LabeledContent("Not yazı boyutu") {
                    HStack {
                        Slider(value: state.preference(\.noteFontSize), in: 11...26, step: 1)
                            .frame(width: 200)
                        Text("\(Int(state.prefs.noteFontSize)) pt").monospacedDigit().frame(width: 44)
                    }
                }

                Picker("Dosya görünümü", selection: state.preference(\.filesLayout)) {
                    Text("Izgara").tag("grid")
                    Text("Liste").tag("list")
                }
            }

            SwiftUI.Section {
                Picker("Otomatik kilit", selection: state.preference(\.autoLockMinutes)) {
                    ForEach([1, 2, 5, 10, 15, 30, 60], id: \.self) { Text("\($0) dk hareketsizlikte").tag($0) }
                    Divider()
                    Text("Kapalı").tag(0)
                }
                Picker("Kopyalanan parolayı panodan sil", selection: state.preference(\.clipboardClearSeconds)) {
                    ForEach([10, 20, 30, 60, 120], id: \.self) { Text("\($0) sn sonra").tag($0) }
                    Divider()
                    Text("Silme").tag(0)
                }
                Toggle("Uyku, ekran kilidi ve kullanıcı değişiminde kilitle", isOn: state.preference(\.lockOnSleep))
                Toggle("Ekran görüntüsü, kayıt ve paylaşımda pencereyi gizle", isOn: state.preference(\.hideFromScreenCapture))
                Toggle("Ekledikten sonra orijinalleri Çöp Kutusu'na taşımayı sor", isOn: state.preference(\.askToTrashOriginals))
                LabeledContent("Ana parola") {
                    Button("Parolayı Değiştir…") { changingPassword = true }
                }
                LabeledContent("Parola üretici") {
                    Button("Aç…") { showGenerator = true }
                        .popover(isPresented: $showGenerator) { GeneratorView() }
                }
            } header: {
                Text("Güvenlik")
            } footer: {
                Text("SSD çıkarıldığında kasa her zaman kilitlenir.")
                    .foregroundStyle(.secondary)
            }

            SwiftUI.Section {
                LabeledContent("Durum") {
                    Label(state.keyfileEnabled ? "Açık — kasa yalnızca bu Mac'te açılır" : "Kapalı — kasa parolayla her Mac'te açılır",
                          systemImage: state.keyfileEnabled ? "lock.laptopcomputer" : "lock.open")
                        .foregroundStyle(state.keyfileEnabled ? Color.green : Color.secondary)
                }
                HStack {
                    if state.keyfileEnabled {
                        Button("Anahtar Dosyasını Yedekle…") { state.exportKeyfile() }
                        Button("Bağlantıyı Kaldır…", role: .destructive) { keyfileSheet = .disable }
                    } else {
                        Button {
                            keyfileSheet = .enable
                        } label: { Label("Bu Mac'e Bağla…", systemImage: "lock.laptopcomputer") }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .disabled(state.task != nil)
            } header: {
                Text("Bu Mac'e bağlama (anahtar dosyası)")
            } footer: {
                Text("Açıkken kasa, parola + bu Mac'te saklanan rastgele bir anahtar dosyasıyla açılır. Başka bir Mac'te doğru parola bile yalnızca \"Parola yanlış\" der; kasada anahtar dosyası kullanıldığına dair iz yoktur.")
                    .foregroundStyle(.secondary)
            }

            SwiftUI.Section {
                LabeledContent("Yedek konumu") {
                    HStack {
                        if let url = state.backupURL {
                            Text(url.path).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            } label: { Image(systemName: "arrow.right.circle.fill") }
                                .buttonStyle(.borderless)
                                .help("Finder'da göster")
                                .disabled(!FileManager.default.fileExists(atPath: url.path))
                        } else {
                            Text("Seçilmedi").foregroundStyle(.secondary)
                        }
                        Button("Değiştir…") { state.chooseBackupLocation() }
                    }
                }
                LabeledContent("Son yedek", value: state.prefs.lastBackupAt.map { "\(Format.date($0)) (\(Format.relative($0)))" } ?? "Hiç alınmadı")
                Picker("Hatırlat", selection: state.preference(\.backupReminderDays)) {
                    ForEach([1, 3, 7, 14, 30], id: \.self) { Text("\($0) gün yedek alınmazsa").tag($0) }
                    Divider()
                    Text("Hatırlatma").tag(0)
                }
                HStack {
                    Button {
                        state.backupNow()
                    } label: { Label("Şimdi Yedekle", systemImage: "externaldrive.fill.badge.timemachine") }
                        .buttonStyle(.borderedProminent)
                    Button {
                        state.runIntegrityScan()
                    } label: { Label("Bütünlük Taraması", systemImage: "checkmark.shield") }
                }
                .disabled(state.task != nil)
            } header: {
                Text("Yedekleme ve bakım")
            } footer: {
                Text("Yedek yalnızca değişen dosyaları kopyalar ve şifreli kalır; aynı parolayla Mahzen'de \"Mevcut kasayı aç\" ile açılır. Bütünlük taraması her dosyayı çözerek doğrular, bozukları yedekten geri yükleyebilir.")
                    .foregroundStyle(.secondary)
            }

            SwiftUI.Section("Kasa") {
                if let url = state.vaultURL {
                    LabeledContent("Konum") {
                        HStack {
                            Text(url.path).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            } label: {
                                Image(systemName: "arrow.right.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .help("Finder'da göster")
                        }
                    }
                }
                LabeledContent("Şifreleme", value: "AES-256-GCM (dosya başına ayrı anahtar)")
                LabeledContent("Anahtar türetme", value: state.kdfSummary)
                LabeledContent("İçerik", value: "\(state.index.liveFiles.count) dosya · \(state.index.folders.filter { $0.deletedAt == nil }.count) klasör · \(state.index.notes.filter { $0.deletedAt == nil }.count) not · \(state.index.secrets.filter { $0.deletedAt == nil }.count) parola")
                Picker("Çöp Kutusu'nu otomatik boşalt", selection: state.preference(\.trashRetentionDays)) {
                    ForEach([7, 30, 90, 365], id: \.self) { Text("\($0) gün sonra").tag($0) }
                    Divider()
                    Text("Hiçbir zaman").tag(0)
                }
            }

        }
        .formStyle(.grouped)
        .navigationTitle("Ayarlar")
        .sheet(isPresented: $changingPassword) { ChangePasswordSheet() }
        .sheet(item: $keyfileSheet) { KeyfileSheet(mode: $0) }
    }
}

private struct ChangePasswordSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var error: String?
    @State private var working = false

    private var valid: Bool {
        !current.isEmpty && new.count >= Vault.minimumPasswordLength && new == confirm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ana parolayı değiştir").font(.title3.weight(.bold))
            Text("Dosyaların yeniden şifrelenmesi gerekmez; yalnızca ana anahtar yeni parolayla yeniden sarılır.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            RevealableField(title: "Mevcut parola", text: $current)
            RevealableField(title: "Yeni parola (en az \(Vault.minimumPasswordLength) karakter)", text: $new)
            StrengthMeter(password: new)
            RevealableField(title: "Yeni parolayı tekrarla", text: $confirm, onSubmit: save)
            if !confirm.isEmpty, confirm != new {
                Text("Parolalar eşleşmiyor").font(.caption).foregroundStyle(.orange)
            }
            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Vazgeç") { dismiss() }.keyboardShortcut(.cancelAction).disabled(working)
                Button(action: save) {
                    if working { ProgressView().controlSize(.small) } else { Text("Değiştir") }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!valid || working)
            }
        }
        .padding(22)
        .frame(width: 420)
    }

    private func save() {
        guard valid, !working else { return }
        working = true
        error = nil
        Task {
            if let message = await state.changePassword(current: current, new: new) {
                error = message
                working = false
            } else {
                dismiss()
            }
        }
    }
}

struct KeyfileSheet: View {
    enum Mode: String, Identifiable {
        case enable, disable
        var id: String { rawValue }
    }

    let mode: Mode
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var understood = false
    @State private var working = false
    @State private var error: String?
    @State private var done = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if done {
                Label("Kasa bu Mac'e bağlandı", systemImage: "checkmark.seal.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.green)
                Text("Şimdi anahtar dosyasının bir yedeğini al. Bu Mac bozulur, çalınır ya da sıfırlanırsa kasayı açmanın tek yolu o yedektir. Yedeği SSD'de değil, ayrı ve güvendiğin bir yerde tut (ör. başka bir USB bellek).")
                    .fixedSize(horizontal: false, vertical: true)
                Text("Kasanın mevcut yedeği, bir sonraki \"Şimdi Yedekle\" ile güncellenince o da anahtar dosyası ister.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Sonra") { dismiss() }
                    Button("Anahtar Dosyasını Yedekle…") {
                        state.exportKeyfile()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                Text(mode == .enable ? "Kasayı bu Mac'e bağla" : "Bu Mac'e bağlantıyı kaldır")
                    .font(.title3.weight(.bold))
                if mode == .enable {
                    VStack(alignment: .leading, spacing: 8) {
                        bullet("lock.laptopcomputer", "Kasa bundan sonra parola + bu Mac'teki anahtar dosyasıyla açılır.")
                        bullet("eye.slash", "SSD başka bir Mac'e takılırsa doğru parola da \"Parola yanlış\" der; anahtar dosyası istendiği belli olmaz.")
                        bullet("exclamationmark.triangle.fill", "Bu Mac bozulur, sıfırlanır ya da anahtar dosyası silinirse, yedeği yoksa kasa bir daha açılamaz.")
                    }
                    Toggle(isOn: $understood) {
                        Text("Anahtar dosyasının yedeğini almazsam verilerimi kaybedebileceğimi anlıyorum.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .toggleStyle(.checkbox)
                } else {
                    Text("Kasa yeniden yalnızca parolayla açılır hale gelir ve bu Mac'teki anahtar dosyası silinir. Dışa aktardığın yedek kopyaları kendin silmelisin.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                RevealableField(title: "Kasa parolası", text: $password, onSubmit: submit)
                if let error {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button("Vazgeç") { dismiss() }.keyboardShortcut(.cancelAction).disabled(working)
                    Button(action: submit) {
                        if working { ProgressView().controlSize(.small) } else { Text(mode == .enable ? "Bağla" : "Kaldır") }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty || working || (mode == .enable && !understood))
                }
            }
        }
        .padding(22)
        .frame(width: 460)
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 20)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }

    private func submit() {
        guard !password.isEmpty, !working, mode == .disable || understood else { return }
        working = true
        error = nil
        Task {
            let message = mode == .enable ? await state.enableKeyfile(password: password) : await state.disableKeyfile(password: password)
            working = false
            password = ""
            if let message {
                error = message
            } else if mode == .enable {
                done = true
            } else {
                dismiss()
            }
        }
    }
}
