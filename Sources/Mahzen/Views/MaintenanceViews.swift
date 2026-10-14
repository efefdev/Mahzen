import MahzenCore
import SwiftUI

struct IntegrityReportSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.vaultAccent) private var accent
    @State private var restoring = false
    @State private var restoreErrors: [String] = []

    private var report: IntegrityReport { state.integrityReport ?? IntegrityReport() }

    private var problems: [(file: FileRecord, problem: IntegrityProblem)] {
        report.problems.compactMap { id, problem in
            state.index.files.first { $0.id == id }.map { ($0, problem) }
        }
        .sorted { $0.file.name.localizedStandardCompare($1.file.name) == .orderedAscending }
    }

    var body: some View {
        let problems = self.problems
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: problems.isEmpty ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(problems.isEmpty ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(problems.isEmpty ? "Kasa sağlam" : "\(problems.count) dosyada sorun var")
                        .font(.title2.weight(.bold))
                    Text("\(report.checkedFiles) dosya · \(Format.size(report.checkedBytes)) baştan sona çözülerek doğrulandı")
                        .foregroundStyle(.secondary)
                }
            }

            if !problems.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(problems, id: \.file.id) { item in
                        HStack(spacing: 10) {
                            FileIcon(file: item.file, size: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.file.name).lineLimit(1)
                                Text(describe(item.problem)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        Divider()
                    }
                }
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                .frame(maxHeight: 220)

                HStack {
                    if state.backupURL != nil {
                        Button {
                            restore(problems.map(\.file.id))
                        } label: {
                            if restoring { ProgressView().controlSize(.small) } else { Label("Yedekten Geri Yükle", systemImage: "arrow.counterclockwise") }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(restoring)
                    } else {
                        Text("Yedek konumu ayarlanmamış; bozuk dosyalar geri yüklenemez.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Button("Çöp Kutusu'na Taşı") {
                        state.trashFiles(Set(problems.map(\.file.id)))
                        state.integrityReport?.problems = [:]
                    }
                }
                if !restoreErrors.isEmpty {
                    Text("Geri yüklenemeyenler:\n" + restoreErrors.prefix(5).joined(separator: "\n"))
                        .font(.caption).foregroundStyle(.red)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                if !report.orphanURLs.isEmpty {
                    HStack {
                        Label("\(report.orphanURLs.count) artık dosya (\(Format.size(report.orphanBytes)))", systemImage: "doc.badge.ellipsis")
                        Spacer()
                        Button("Temizle") { state.removeOrphans(report.orphanURLs) }
                    }
                    Text("Kasada hiçbir kayda ait olmayan şifreli dosyalar veya yarıda kalmış yazmalar. Silinmeleri güvenlidir.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !report.brokenThumbnails.isEmpty {
                    Label("\(report.brokenThumbnails.count) bozuk küçük resim kaldırıldı (dosyaların kendisi sağlam)", systemImage: "photo.badge.exclamationmark")
                }
                if !report.indexBackupReadable {
                    Label("Dizin yedeği (index.enc.bak) okunamıyor; bir sonraki kayıtta yenilenecek.", systemImage: "exclamationmark.circle")
                }
            }
            .font(.callout)

            HStack {
                Spacer()
                Button("Kapat") {
                    state.integrityReport = nil
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func describe(_ problem: IntegrityProblem) -> String {
        switch problem {
        case .missing: return "Şifreli dosya kasada bulunamadı"
        case .damaged(let detail): return "Bozuk veya değiştirilmiş — \(detail)"
        case .hashMismatch: return "İçerik, eklendiği andakinden farklı"
        }
    }

    private func restore(_ ids: [UUID]) {
        restoring = true
        Task {
            restoreErrors = await state.restoreFromBackup(ids)
            restoring = false
            if restoreErrors.isEmpty { state.showToast("\(ids.count) dosya yedekten geri yüklendi") }
        }
    }
}

/// Yedek gecikince ana pencerenin üstünde görünen şerit.
struct BackupReminderBanner: View {
    @EnvironmentObject private var state: AppState
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive.badge.exclamationmark").foregroundStyle(.orange)
            Text(message).font(.callout)
            Spacer()
            Button("Şimdi Yedekle") { state.backupNow() }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            Button("Sonra", action: onDismiss).controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.10))
    }

    private var message: String {
        if let last = state.prefs.lastBackupAt {
            return "Son yedek \(Format.relative(last)) alındı."
        }
        return "Kasan henüz hiç yedeklenmedi. SSD bozulur ya da kaybolursa her şey gider."
    }
}
