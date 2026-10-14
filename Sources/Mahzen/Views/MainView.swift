import MahzenCore
import SwiftUI

struct MainView: View {
    @EnvironmentObject private var state: AppState
    @State private var backupBannerDismissed = false

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            VStack(spacing: 0) {
                if state.backupDue, !backupBannerDismissed, state.task == nil {
                    BackupReminderBanner { backupBannerDismissed = true }
                }
                if state.recoveredFromBackup {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("Dizin dosyası okunamadı; son yedekten geri yüklendi. En son birkaç değişiklik eksik olabilir.")
                            .font(.callout)
                        Spacer()
                        Button("Tamam") { state.recoveredFromBackup = false }.controlSize(.small)
                    }
                    .padding(10)
                    .background(.orange.opacity(0.12))
                }
                switch state.section {
                case .files: FilesView()
                case .notes: NotesView()
                case .secrets: SecretsView()
                case .trash: TrashView()
                case .settings: SettingsView()
                }
            }
        }
        .sheet(isPresented: Binding(get: { state.integrityReport != nil }, set: { if !$0 { state.integrityReport = nil } })) {
            IntegrityReportSheet()
        }
    }
}

private struct Sidebar: View {
    @EnvironmentObject private var state: AppState

    private var selection: Binding<Section?> {
        Binding(get: { state.section }, set: { if let s = $0 { state.section = s } })
    }

    var body: some View {
        List(selection: selection) {
            SwiftUI.Section("Kasa") {
                row(.files, count: state.index.liveFiles.count)
                row(.notes, count: state.index.notes.filter { $0.deletedAt == nil }.count)
                row(.secrets, count: state.index.secrets.filter { $0.deletedAt == nil }.count)
            }
            SwiftUI.Section {
                row(.trash, count: state.index.trashCount)
                row(.settings, count: nil)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) {
            HStack(spacing: 10) {
                VaultBadge(size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.prefs.displayName).font(.headline).lineLimit(1)
                    Text(Format.size(state.index.liveFiles.reduce(0) { $0 + $1.size }) + " şifreli")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: state.lock) {
                Label("Kilitle", systemImage: "lock.fill")
                    .frame(maxWidth: .infinity)
                    .frame(height: 22)
            }
            .controlSize(.large)
            .help("Kasayı kilitle (⌘L)")
            .padding(12)
            .disabled(state.task != nil)
        }
    }

    private func row(_ section: Section, count: Int?) -> some View {
        Label(section.title, systemImage: section.symbol)
            .badge(count ?? 0)
            .tag(section)
    }
}
