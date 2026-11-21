import MahzenCore
import SwiftUI

struct TrashView: View {
    @EnvironmentObject private var state: AppState
    @State private var confirmEmpty = false
    @State private var pendingPurge: TrashEntry?

    private var entries: [TrashEntry] {
        let idx = state.index
        var list: [TrashEntry] = []
        list += idx.trashedFolders.map { folder in
            let tree = idx.descendantFolderIDs(of: folder.id).union([folder.id])
            let count = idx.files.filter { $0.deletedAt == folder.deletedAt && $0.folderID.map(tree.contains) == true }.count
            return TrashEntry(id: folder.id, kind: .folder, title: folder.name, subtitle: L("Klasör") + " · " + LN("{0} dosya", count), deletedAt: folder.deletedAt!)
        }
        list += idx.trashedFiles.map { TrashEntry(id: $0.id, kind: .file($0), title: $0.name, subtitle: Format.size($0.size), deletedAt: $0.deletedAt!) }
        list += idx.trashedNotes.map { TrashEntry(id: $0.id, kind: .note, title: $0.title.isEmpty ? L("Başlıksız not") : $0.title, subtitle: L("Not"), deletedAt: $0.deletedAt!) }
        list += idx.trashedSecrets.map { TrashEntry(id: $0.id, kind: .secret($0.category), title: $0.title.isEmpty ? L("Adsız") : $0.title, subtitle: L("Parola kaydı"), deletedAt: $0.deletedAt!) }
        return list.sorted { $0.deletedAt > $1.deletedAt }
    }

    var body: some View {
        let entries = self.entries
        Group {
            if entries.isEmpty {
                EmptyState(symbol: "trash", title: L("Çöp Kutusu boş"), message: retentionText)
            } else {
                List {
                    SwiftUI.Section {
                        ForEach(entries) { entry in
                            row(entry)
                        }
                    } footer: {
                        Text(retentionText).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(L("Çöp Kutusu"))
        .navigationSubtitle(LN("{0} öğe", entries.count))
        .toolbar {
            ToolbarItem {
                Button(role: .destructive) { confirmEmpty = true } label: {
                    Label(L("Boşalt"), systemImage: "trash.slash")
                }
                .help(L("Çöp Kutusu'nu boşalt"))
                .disabled(entries.isEmpty)
            }
        }
        .confirmationDialog(L("Çöp Kutusu boşaltılsın mı?"), isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button(LN("{0} Öğeyi Kalıcı Olarak Sil", entries.count), role: .destructive) { state.emptyTrash() }
        } message: {
            Text(L("Bu işlem geri alınamaz."))
        }
        .confirmationDialog(
            L("\"{0}\" kalıcı olarak silinsin mi?", pendingPurge?.title ?? ""),
            isPresented: Binding(get: { pendingPurge != nil }, set: { if !$0 { pendingPurge = nil } }),
            titleVisibility: .visible
        ) {
            Button(L("Kalıcı Olarak Sil"), role: .destructive) {
                if let entry = pendingPurge { purge(entry) }
                pendingPurge = nil
            }
        } message: {
            Text(L("Bu işlem geri alınamaz."))
        }
    }

    private var retentionText: String {
        let days = state.prefs.trashRetentionDays
        return days > 0
            ? LN("Silinen dosya, not ve parolalar {0} gün burada kalır, sonra kalıcı olarak silinir.", days)
            : L("Otomatik silme kapalı; öğeler sen boşaltana kadar burada kalır.")
    }

    private func row(_ entry: TrashEntry) -> some View {
        HStack(spacing: 12) {
            entry.icon
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.headline).lineLimit(1)
                Text(L("{0} · {1} silindi", entry.subtitle, Format.relative(entry.deletedAt)) + remaining(entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(L("Geri Al")) { restore(entry) }
            Button(role: .destructive) { pendingPurge = entry } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help(L("Kalıcı olarak sil"))
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button(L("Geri Al")) { restore(entry) }
            Button(L("Kalıcı Olarak Sil…"), role: .destructive) { pendingPurge = entry }
        }
    }

    private func remaining(_ entry: TrashEntry) -> String {
        let days = state.prefs.trashRetentionDays
        guard days > 0 else { return "" }
        let left = Int(ceil(entry.deletedAt.addingTimeInterval(Double(days) * 86_400).timeIntervalSinceNow / 86_400))
        return " · " + LN("{0} gün sonra kalıcı silinecek", max(left, 0))
    }

    private func restore(_ entry: TrashEntry) {
        switch entry.kind {
        case .folder: state.restoreFolder(entry.id)
        case .file: state.restoreFile(entry.id)
        case .note: state.restoreNote(entry.id)
        case .secret: state.restoreSecret(entry.id)
        }
        state.showToast(L("\"{0}\" geri alındı", entry.title))
    }

    private func purge(_ entry: TrashEntry) {
        switch entry.kind {
        case .folder: state.purgeFolder(entry.id)
        case .file: state.purgeFile(entry.id)
        case .note: state.purgeNote(entry.id)
        case .secret: state.purgeSecret(entry.id)
        }
    }
}

struct TrashEntry: Identifiable {
    enum Kind {
        case folder, file(FileRecord), note, secret(SecretCategory)
    }

    let id: UUID
    let kind: Kind
    let title: String
    let subtitle: String
    let deletedAt: Date

    @ViewBuilder
    var icon: some View {
        switch kind {
        case .folder:
            Image(systemName: "folder.fill").font(.title2).foregroundStyle(.tint)
        case .file(let file):
            FileIcon(file: file, size: 30)
        case .note:
            Image(systemName: "note.text").font(.title2).foregroundStyle(.orange)
        case .secret(let category):
            Image(systemName: category.symbol).font(.title3).foregroundStyle(.tint)
        }
    }
}
