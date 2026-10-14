import AppKit
import MahzenCore
import SwiftUI

struct SecretsView: View {
    @Environment(\.vaultAccent) private var accent
    @EnvironmentObject private var state: AppState
    @State private var selectedID: UUID?
    @State private var search = ""
    @State private var category: SecretCategory?
    @State private var favoritesOnly = false
    @State private var editing: Secret?
    @State private var confirmDelete = false

    private var secrets: [Secret] {
        state.index.secrets
            .filter { $0.deletedAt == nil }
            .filter { category == nil || $0.category == category }
            .filter { !favoritesOnly || $0.favorite }
            .filter {
                search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
                    || $0.username.localizedCaseInsensitiveContains(search) || $0.url.localizedCaseInsensitiveContains(search)
            }
            .sorted { ($0.favorite ? 0 : 1, $0.title.lowercased()) < ($1.favorite ? 0 : 1, $1.title.lowercased()) }
    }

    private var selected: Secret? { state.index.secrets.first { $0.id == selectedID && $0.deletedAt == nil } }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip("Tümü", symbol: "square.grid.2x2", active: category == nil && !favoritesOnly) {
                            category = nil
                            favoritesOnly = false
                        }
                        chip("Favoriler", symbol: "star.fill", active: favoritesOnly) {
                            favoritesOnly.toggle()
                            category = nil
                        }
                        ForEach(SecretCategory.allCases, id: \.self) { c in
                            chip(c.title, symbol: c.symbol, active: category == c) {
                                category = category == c ? nil : c
                                favoritesOnly = false
                            }
                        }
                    }
                    .padding(10)
                }
                Divider()
                List(selection: $selectedID) {
                    ForEach(secrets) { secret in
                        SecretRow(secret: secret).tag(secret.id)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
            .background(.background.secondary)
            .frame(minWidth: 250, idealWidth: 300, maxWidth: 400)

            Group {
                if let secret = selected {
                    SecretDetail(secret: secret, onEdit: { editing = secret }, onDelete: { confirmDelete = true })
                } else {
                    EmptyState(
                        symbol: "key.horizontal.fill",
                        title: state.index.secrets.allSatisfy { $0.deletedAt != nil } ? "Henüz parola kaydı yok" : "Bir kayıt seç",
                        message: "Hesaplar, kart bilgileri, Wi-Fi ve sunucu parolaları burada şifreli saklanır.",
                        actionTitle: "Yeni Kayıt",
                        action: { editing = Secret() }
                    )
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Parolalar")
        .navigationSubtitle("\(state.index.secrets.filter { $0.deletedAt == nil }.count) kayıt")
        .searchable(text: $search, placement: .toolbar, prompt: "Parolalarda ara")
        .toolbar {
            ToolbarItemGroup {
                Button { editing = Secret() } label: { Label("Yeni Kayıt", systemImage: "plus") }
                    .help("Yeni parola kaydı (⇧⌘N)")
            }
        }
        .sheet(item: $editing) { secret in
            SecretEditor(secret: secret) { saved in
                state.saveSecret(saved)
                selectedID = saved.id
            }
        }
        .confirmationDialog("Bu kayıt Çöp Kutusu'na taşınsın mı?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Çöp Kutusu'na Taşı", role: .destructive) {
                if let id = selectedID { state.deleteSecret(id) }
                selectedID = nil
            }
        }
        .onAppear {
            if selectedID == nil { selectedID = secrets.first?.id }
            consumeNewRequest()
        }
        .onChange(of: state.newSecretRequested) { _, _ in consumeNewRequest() }
    }

    private func consumeNewRequest() {
        guard state.newSecretRequested else { return }
        state.newSecretRequested = false
        editing = Secret()
    }

    private func chip(_ title: String, symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(active ? accent : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(active ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

private struct SecretIcon: View {
    @Environment(\.vaultAccent) private var accent
    let secret: Secret
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(accent.gradient)
            if let initial = secret.title.first, secret.category == .login {
                Text(String(initial).uppercased())
                    .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: secret.category.symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct SecretRow: View {
    let secret: Secret

    var body: some View {
        HStack(spacing: 10) {
            SecretIcon(secret: secret)
            VStack(alignment: .leading, spacing: 2) {
                Text(secret.title.isEmpty ? "Adsız" : secret.title).font(.headline).lineLimit(1)
                Text(secret.username.isEmpty ? secret.category.title : secret.username)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if secret.favorite { Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow) }
        }
        .padding(.vertical, 4)
    }
}

private struct SecretDetail: View {
    let secret: Secret
    let onEdit: () -> Void
    let onDelete: () -> Void
    @EnvironmentObject private var state: AppState
    @State private var reveal = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 16) {
                    SecretIcon(secret: secret, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(secret.title.isEmpty ? "Adsız" : secret.title).font(.title.weight(.bold))
                        Text(secret.category.title).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        var s = secret
                        s.favorite.toggle()
                        state.saveSecret(s)
                    } label: {
                        Image(systemName: secret.favorite ? "star.fill" : "star")
                            .foregroundStyle(secret.favorite ? .yellow : .secondary)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .help(secret.favorite ? "Favorilerden çıkar" : "Favorilere ekle")
                }

                // Satırlar arasındaki 1 pt boşluk ayırıcı çizgi işlevi görür; son satırdan sonra çizgi kalmaz.
                VStack(spacing: 1) {
                    if !secret.username.isEmpty {
                        FieldRow(label: "Kullanıcı adı", copyValue: secret.username) { Text(secret.username) }
                            .background(.quaternary.opacity(0.35))
                    }
                    if !secret.password.isEmpty {
                        FieldRow(label: "Parola", copyValue: secret.password, sensitive: true) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 10) {
                                    Text(reveal ? secret.password : String(repeating: "•", count: min(secret.password.count, 18)))
                                        .font(.system(.body, design: .monospaced))
                                    Button { reveal.toggle() } label: {
                                        Image(systemName: reveal ? "eye.slash" : "eye")
                                    }
                                    .buttonStyle(.borderless)
                                    .help(reveal ? "Gizle" : "Göster")
                                }
                                StrengthMeter(password: secret.password).frame(maxWidth: 320)
                            }
                        }
                        .background(.quaternary.opacity(0.35))
                    }
                    if !secret.url.isEmpty {
                        FieldRow(label: "Web sitesi", copyValue: secret.url) {
                            if let url = URL(string: secret.url.contains("://") ? secret.url : "https://\(secret.url)") {
                                Link(secret.url, destination: url)
                            } else {
                                Text(secret.url)
                            }
                        }
                        .background(.quaternary.opacity(0.35))
                    }
                    if !secret.notes.isEmpty {
                        FieldRow(label: "Notlar", copyValue: secret.notes, sensitive: true) { Text(secret.notes) }
                            .background(.quaternary.opacity(0.35))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("Oluşturuldu \(Format.date(secret.createdAt)) · Güncellendi \(Format.date(secret.updatedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button(action: onEdit) { Label("Düzenle", systemImage: "pencil") }
                        .keyboardShortcut("e", modifiers: .command)
                    Button(role: .destructive, action: onDelete) { Label("Sil", systemImage: "trash") }
                }
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: secret.id) { _, _ in reveal = false }
    }
}

struct SecretEditor: View {
    @State var secret: Secret
    let onSave: (Secret) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showGenerator = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(secret.title.isEmpty ? "Yeni kayıt" : secret.title)
                .font(.title2.weight(.bold))
                .padding([.horizontal, .top], 22)
            Form {
                Picker("Tür", selection: $secret.category) {
                    ForEach(SecretCategory.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                TextField("Başlık", text: $secret.title, prompt: Text("ör. Gmail"))
                TextField("Kullanıcı adı", text: $secret.username, prompt: Text("e-posta veya kullanıcı adı"))
                LabeledContent("Parola") {
                    HStack {
                        RevealableField(title: "Parola", text: $secret.password)
                        Button {
                            showGenerator = true
                        } label: {
                            Image(systemName: "wand.and.stars")
                        }
                        .help("Güçlü parola üret")
                        .popover(isPresented: $showGenerator, arrowEdge: .bottom) {
                            GeneratorView { secret.password = $0; showGenerator = false }
                        }
                    }
                }
                if !secret.password.isEmpty {
                    LabeledContent(" ") { StrengthMeter(password: secret.password) }
                }
                TextField("Web sitesi", text: $secret.url, prompt: Text("ornek.com"))
                LabeledContent("Notlar") {
                    TextEditor(text: $secret.notes)
                        .font(.body)
                        .frame(height: 80)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                }
                Toggle("Favori", isOn: $secret.favorite)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Vazgeç") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Kaydet") {
                    onSave(secret)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(secret.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding([.horizontal, .bottom], 22)
        }
        .frame(width: 540, height: 600)
    }
}

struct GeneratorView: View {
    var onUse: ((String) -> Void)?
    @EnvironmentObject private var state: AppState
    @State private var generated = ""

    private var options: GeneratorOptions { state.prefs.generator }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Parola üretici").font(.headline)
            HStack {
                Text(generated)
                    .font(.system(.title3, design: .monospaced).weight(.medium))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: regenerate) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Yeniden üret")
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            StrengthMeter(password: generated)

            HStack {
                Text("Uzunluk")
                Slider(value: Binding(get: { Double(options.length) }, set: { v in set { $0.length = Int(v) } }), in: 8...64, step: 1)
                Text("\(options.length)").monospacedDigit().frame(width: 28)
            }
            Toggle("Büyük harf (A–Z)", isOn: binding(\.uppercase))
            Toggle("Küçük harf (a–z)", isOn: binding(\.lowercase))
            Toggle("Rakam (0–9)", isOn: binding(\.digits))
            Toggle("Sembol (!@#…)", isOn: binding(\.symbols))
            Toggle("Karışan karakterleri çıkar (O/0, l/1)", isOn: binding(\.avoidAmbiguous))

            HStack {
                Button("Kopyala") { state.copy(generated, label: "Parola kopyalandı") }
                Spacer()
                if let onUse {
                    Button("Bu Parolayı Kullan") { onUse(generated) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .toggleStyle(.checkbox)
        .padding(18)
        .frame(width: 380)
        .onAppear(perform: regenerate)
    }

    private func binding(_ kp: WritableKeyPath<GeneratorOptions, Bool>) -> Binding<Bool> {
        Binding(get: { options[keyPath: kp] }, set: { v in set { $0[keyPath: kp] = v } })
    }

    private func set(_ change: (inout GeneratorOptions) -> Void) {
        state.updatePreferences { change(&$0.generator) }
        regenerate()
    }

    private func regenerate() {
        generated = PasswordGenerator.generate(state.prefs.generator)
    }
}
