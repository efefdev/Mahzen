import AppKit
import MahzenCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var changingPassword = false
    @State private var keyfileSheet: KeyfileSheet.Mode?
    @State private var confirmAutoWipe = false
    @State private var showGenerator = false
    @State private var languageChoice = UserDefaults.standard.string(forKey: Localization.overrideKey) ?? "system"

    /// Seçim açılıştakinden farklıysa yeniden açmak gerekir.
    private var languageChangePending: Bool {
        languageChoice != (Localization.overrideAtLaunch ?? "system")
    }

    private func setLanguage(_ choice: String) {
        languageChoice = choice
        if let language = Language(rawValue: choice) {
            UserDefaults.standard.set(language.rawValue, forKey: Localization.overrideKey)
            // Menü çubuğu ve sistem pencereleri de aynı dili kullansın.
            UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: Localization.overrideKey)
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }

    private func relaunch() {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "app" else { return NSApp.terminate(nil) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    var body: some View {
        Form {
            SwiftUI.Section(L("Görünüm")) {
                Picker(L("Tema"), selection: state.preference(\.appearance)) {
                    ForEach(AppearanceChoice.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)

                LabeledContent(L("Vurgu rengi")) {
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

                TextField(L("Kasa adı"), text: state.preference(\.displayName))

                Picker(L("Not yazı tipi"), selection: state.preference(\.noteFontDesign)) {
                    ForEach(NoteFontDesign.allCases) { Text($0.title).tag($0.rawValue) }
                }

                LabeledContent(L("Not yazı boyutu")) {
                    HStack {
                        Slider(value: state.preference(\.noteFontSize), in: 11...26, step: 1)
                            .frame(width: 200)
                        Text("\(Int(state.prefs.noteFontSize)) pt").monospacedDigit().frame(width: 44)
                    }
                }

                Picker(L("Dosya görünümü"), selection: state.preference(\.filesLayout)) {
                    Text(L("Izgara")).tag("grid")
                    Text(L("Liste")).tag("list")
                }

                Picker(L("Dil"), selection: Binding(get: { languageChoice }, set: setLanguage)) {
                    Text(L("Sistem")).tag("system")
                    Text(verbatim: "Türkçe").tag("tr")
                    Text(verbatim: "English").tag("en")
                }
                if languageChangePending {
                    LabeledContent {
                        Button(L("Yeniden Aç"), action: relaunch)
                    } label: {
                        Text(L("Dil değişikliği Mahzen yeniden açılınca uygulanır."))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SwiftUI.Section {
                Picker(L("Otomatik kilit"), selection: state.preference(\.autoLockMinutes)) {
                    ForEach([1, 2, 5, 10, 15, 30, 60], id: \.self) { Text(L("{0} dk hareketsizlikte", $0)).tag($0) }
                    Divider()
                    Text(L("Kapalı")).tag(0)
                }
                Picker(L("Kopyalanan parolayı panodan sil"), selection: state.preference(\.clipboardClearSeconds)) {
                    ForEach([10, 20, 30, 60, 120], id: \.self) { Text(L("{0} sn sonra", $0)).tag($0) }
                    Divider()
                    Text(L("Silme")).tag(0)
                }
                Toggle(L("Uyku, ekran kilidi ve kullanıcı değişiminde kilitle"), isOn: state.preference(\.lockOnSleep))
                Toggle(L("Ekran görüntüsü, kayıt ve paylaşımda pencereyi gizle"), isOn: state.preference(\.hideFromScreenCapture))
                Toggle(L("Ekledikten sonra orijinalleri Çöp Kutusu'na taşımayı sor"), isOn: state.preference(\.askToTrashOriginals))
                LabeledContent(L("Ana parola")) {
                    Button(L("Parolayı Değiştir…")) { changingPassword = true }
                }
                LabeledContent(L("Parola üretici")) {
                    Button(L("Aç…")) { showGenerator = true }
                        .popover(isPresented: $showGenerator) { GeneratorView() }
                }
            } header: {
                Text(L("Güvenlik"))
            } footer: {
                Text(L("SSD çıkarıldığında kasa her zaman kilitlenir."))
                    .foregroundStyle(.secondary)
            }

            SwiftUI.Section {
                Toggle(L("Yanlış parolada kasayı kalıcı olarak sil"), isOn: Binding(
                    get: { state.autoWipeAttempts != nil },
                    set: { on in
                        if on { confirmAutoWipe = true } else { state.setAutoWipe(nil) }
                    }
                ))
                if let attempts = state.autoWipeAttempts {
                    Stepper(value: Binding(get: { attempts }, set: { state.setAutoWipe($0) }),
                            in: Vault.autoWipeRange) {
                        LabeledContent(L("Deneme sayısı"), value: LN("{0} yanlış parola", attempts))
                    }
                }
            } header: {
                Text(L("Yanlış parola sınırı"))
            } footer: {
                Text(L("Açıkken art arda bu kadar yanlış parola girilirse kasanın anahtarları yok edilir ve kasadaki her şey kalıcı olarak açılamaz hale gelir; geri alınamaz. Sayaç doğru parolayla açılınca sıfırlanır. Anahtar dosyalı bir kasayı başka bir Mac'te açmaya çalışmak da yanlış deneme sayılır. Yedekler bu ayardan etkilenmez."))
                    .foregroundStyle(.secondary)
            }
            .confirmationDialog(L("Yanlış parola sınırı açılsın mı?"), isPresented: $confirmAutoWipe, titleVisibility: .visible) {
                Button(L("{0} yanlış denemede sil", Vault.defaultAutoWipeAttempts), role: .destructive) {
                    state.setAutoWipe(Vault.defaultAutoWipeAttempts)
                }
                Button(L("Vazgeç"), role: .cancel) {}
            } message: {
                Text(L("Art arda {0} yanlış parola girilirse kasa kalıcı olarak silinir ve hiçbir şekilde geri getirilemez. Deneme sayısını sonra değiştirebilirsiniz. Güncel bir yedeğiniz olduğundan emin olun.", Vault.defaultAutoWipeAttempts))
            }

            SwiftUI.Section {
                LabeledContent(L("Durum")) {
                    Label(state.keyfileEnabled ? L("Açık — kasa yalnızca bu Mac'te açılır") : L("Kapalı — kasa parolayla her Mac'te açılır"),
                          systemImage: state.keyfileEnabled ? "lock.laptopcomputer" : "lock.open")
                        .foregroundStyle(state.keyfileEnabled ? Color.green : Color.secondary)
                }
                HStack {
                    if state.keyfileEnabled {
                        Button(L("Anahtar Dosyasını Yedekle…")) { state.exportKeyfile() }
                        Button(L("Bağlantıyı Kaldır…"), role: .destructive) { keyfileSheet = .disable }
                    } else {
                        Button {
                            keyfileSheet = .enable
                        } label: { Label(L("Bu Mac'e Bağla…"), systemImage: "lock.laptopcomputer") }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .disabled(state.task != nil)
            } header: {
                Text(L("Bu Mac'e bağlama (anahtar dosyası)"))
            } footer: {
                Text(L("Açıkken kasa, parola + bu Mac'te saklanan rastgele bir anahtar dosyasıyla açılır. Başka bir Mac'te doğru parola bile yalnızca \"Parola yanlış\" der; kasada anahtar dosyası kullanıldığına dair iz yoktur."))
                    .foregroundStyle(.secondary)
            }

            SwiftUI.Section {
                LabeledContent(L("Yedek konumu")) {
                    HStack {
                        if let url = state.backupURL {
                            Text(url.path).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            } label: { Image(systemName: "arrow.right.circle.fill") }
                                .buttonStyle(.borderless)
                                .help(L("Finder'da göster"))
                                .disabled(!FileManager.default.fileExists(atPath: url.path))
                        } else {
                            Text(L("Seçilmedi")).foregroundStyle(.secondary)
                        }
                        Button(L("Değiştir…")) { state.chooseBackupLocation() }
                    }
                }
                LabeledContent(L("Son yedek"), value: state.prefs.lastBackupAt.map { "\(Format.date($0)) (\(Format.relative($0)))" } ?? L("Hiç alınmadı"))
                Picker(L("Hatırlat"), selection: state.preference(\.backupReminderDays)) {
                    ForEach([1, 3, 7, 14, 30], id: \.self) { Text(LN("{0} gün yedek alınmazsa", $0)).tag($0) }
                    Divider()
                    Text(L("Hatırlatma")).tag(0)
                }
                HStack {
                    Button {
                        state.backupNow()
                    } label: { Label(L("Şimdi Yedekle"), systemImage: "externaldrive.fill.badge.timemachine") }
                        .buttonStyle(.borderedProminent)
                    Button {
                        state.runIntegrityScan()
                    } label: { Label(L("Bütünlük Taraması"), systemImage: "checkmark.shield") }
                }
                .disabled(state.task != nil)
            } header: {
                Text(L("Yedekleme ve bakım"))
            } footer: {
                Text(L("Yedek yalnızca değişen dosyaları kopyalar ve şifreli kalır; aynı parolayla Mahzen'de \"Mevcut kasayı aç\" ile açılır. Bütünlük taraması her dosyayı çözerek doğrular, bozukları yedekten geri yükleyebilir."))
                    .foregroundStyle(.secondary)
            }

            SwiftUI.Section(L("Kasa")) {
                if let url = state.vaultURL {
                    LabeledContent(L("Konum")) {
                        HStack {
                            Text(url.path).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            } label: {
                                Image(systemName: "arrow.right.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .help(L("Finder'da göster"))
                        }
                    }
                }
                LabeledContent(L("Şifreleme"), value: L("AES-256-GCM (dosya başına ayrı anahtar)"))
                LabeledContent(L("Anahtar türetme"), value: state.kdfSummary)
                LabeledContent(L("İçerik"), value: [LN("{0} dosya", state.index.liveFiles.count), LN("{0} klasör", state.index.folders.filter { $0.deletedAt == nil }.count), LN("{0} not", state.index.notes.filter { $0.deletedAt == nil }.count), LN("{0} parola", state.index.secrets.filter { $0.deletedAt == nil }.count)].joined(separator: " · "))
                Picker(L("Çöp Kutusu'nu otomatik boşalt"), selection: state.preference(\.trashRetentionDays)) {
                    ForEach([7, 30, 90, 365], id: \.self) { Text(LN("{0} gün sonra", $0)).tag($0) }
                    Divider()
                    Text(L("Hiçbir zaman")).tag(0)
                }
            }

        }
        .formStyle(.grouped)
        .navigationTitle(L("Ayarlar"))
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
            Text(L("Ana parolayı değiştir")).font(.title3.weight(.bold))
            Text(L("Dosyaların yeniden şifrelenmesi gerekmez; yalnızca ana anahtar yeni parolayla yeniden sarılır."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            RevealableField(title: L("Mevcut parola"), text: $current)
            RevealableField(title: L("Yeni parola (en az {0} karakter)", Vault.minimumPasswordLength), text: $new)
            StrengthMeter(password: new)
            RevealableField(title: L("Yeni parolayı tekrarla"), text: $confirm, onSubmit: save)
            if !confirm.isEmpty, confirm != new {
                Text(L("Parolalar eşleşmiyor")).font(.caption).foregroundStyle(.orange)
            }
            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(L("Vazgeç")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(working)
                Button(action: save) {
                    if working { ProgressView().controlSize(.small) } else { Text(L("Değiştir")) }
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
                Label(L("Kasa bu Mac'e bağlandı"), systemImage: "checkmark.seal.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.green)
                Text(L("Şimdi anahtar dosyasının bir yedeğini al. Bu Mac bozulur, çalınır ya da sıfırlanırsa kasayı açmanın tek yolu o yedektir. Yedeği SSD'de değil, ayrı ve güvendiğin bir yerde tut (ör. başka bir USB bellek)."))
                    .fixedSize(horizontal: false, vertical: true)
                Text(L("Kasanın mevcut yedeği, bir sonraki \"Şimdi Yedekle\" ile güncellenince o da anahtar dosyası ister."))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button(L("Sonra")) { dismiss() }
                    Button(L("Anahtar Dosyasını Yedekle…")) {
                        state.exportKeyfile()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                Text(mode == .enable ? L("Kasayı bu Mac'e bağla") : L("Bu Mac'e bağlantıyı kaldır"))
                    .font(.title3.weight(.bold))
                if mode == .enable {
                    VStack(alignment: .leading, spacing: 8) {
                        bullet("lock.laptopcomputer", L("Kasa bundan sonra parola + bu Mac'teki anahtar dosyasıyla açılır."))
                        bullet("eye.slash", L("SSD başka bir Mac'e takılırsa doğru parola da \"Parola yanlış\" der; anahtar dosyası istendiği belli olmaz."))
                        bullet("exclamationmark.triangle.fill", L("Bu Mac bozulur, sıfırlanır ya da anahtar dosyası silinirse, yedeği yoksa kasa bir daha açılamaz."))
                    }
                    Toggle(isOn: $understood) {
                        Text(L("Anahtar dosyasının yedeğini almazsam verilerimi kaybedebileceğimi anlıyorum."))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .toggleStyle(.checkbox)
                } else {
                    Text(L("Kasa yeniden yalnızca parolayla açılır hale gelir ve bu Mac'teki anahtar dosyası silinir. Dışa aktardığın yedek kopyaları kendin silmelisin."))
                        .fixedSize(horizontal: false, vertical: true)
                }
                RevealableField(title: L("Kasa parolası"), text: $password, onSubmit: submit)
                if let error {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button(L("Vazgeç")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(working)
                    Button(action: submit) {
                        if working { ProgressView().controlSize(.small) } else { Text(mode == .enable ? L("Bağla") : L("Kaldır")) }
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
