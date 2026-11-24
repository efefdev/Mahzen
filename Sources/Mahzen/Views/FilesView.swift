import AVFoundation
import AppKit
import MahzenCore
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

enum FileSort: String, CaseIterable, Identifiable {
    case newest, oldest, name, largest
    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: return L("En yeni")
        case .oldest: return L("En eski")
        case .name: return L("Ada göre")
        case .largest: return L("En büyük")
        }
    }

    func sort(_ list: inout [FileRecord]) {
        switch self {
        case .newest: list.sort { $0.addedAt > $1.addedAt }
        case .oldest: list.sort { $0.addedAt < $1.addedAt }
        case .name: list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .largest: list.sort { $0.size > $1.size }
        }
    }
}

enum FileFilter: String, CaseIterable, Identifiable {
    case all, favorites, images, videos, documents
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return L("Tümü")
        case .favorites: return L("Favoriler")
        case .images: return L("Görseller")
        case .videos: return L("Videolar")
        case .documents: return L("Belgeler")
        }
    }

    func matches(_ file: FileRecord) -> Bool {
        let type = file.utType
        switch self {
        case .all: return true
        case .favorites: return file.favorite
        case .images: return type.conforms(to: .image)
        case .videos: return type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .audio)
        case .documents: return type.conforms(to: .pdf) || type.conforms(to: .text) || type.conforms(to: .presentation)
            || type.conforms(to: .spreadsheet) || type.identifier.contains("document")
        }
    }
}

extension FileRecord {
    var utType: UTType { contentType.flatMap(UTType.init) ?? .data }
    var kind: String { utType.localizedDescription ?? L("Dosya") }
}

/// Izgara ve listede klasör ile dosyayı tek satır tipi olarak göstermek için.
struct FileItem: Identifiable, Hashable {
    let folder: Folder?
    let file: FileRecord?
    var id: UUID { folder?.id ?? file!.id }
    var name: String { folder?.name ?? file!.name }
}

struct FilesView: View {
    @Environment(\.vaultAccent) private var accent
    @EnvironmentObject private var state: AppState
    @State private var search = ""
    @State private var sort = FileSort.newest
    @State private var filter = FileFilter.all
    @State private var tagFilter: String?
    @State private var selection = Set<UUID>()
    @State private var previewing: FileRecord?
    @State private var renamingFile: FileRecord?
    @State private var renamingFolder: Folder?
    @State private var tagging: Set<UUID>?
    @State private var dropTargeted = false
    @StateObject private var marquee = MarqueeSelection()

    private var index: VaultIndex { state.index }
    private var current: UUID? { state.currentFolder }
    /// Arama, filtre veya etiket etkinse bütün kasada aranır; değilse açık klasör gösterilir.
    private var isGlobal: Bool { !search.isEmpty || filter != .all || tagFilter != nil }

    private var items: [FileItem] {
        let folders = isGlobal ? [] : index.childFolders(of: current)
        var files = isGlobal ? index.liveFiles : index.liveFiles(in: current)
        files = files.filter { filter.matches($0) }
        if let tagFilter { files = files.filter { $0.tags.contains(tagFilter) } }
        if !search.isEmpty {
            files = files.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.tags.contains { $0.localizedCaseInsensitiveContains(search) } }
        }
        sort.sort(&files)
        return folders.map { FileItem(folder: $0, file: nil) } + files.map { FileItem(folder: nil, file: $0) }
    }

    private var layout: Binding<String> { state.preference(\.filesLayout) }

    var body: some View {
        let items = self.items
        VStack(spacing: 0) {
            header
            Divider()
            content(items)
        }
        .navigationTitle(L("Dosyalar"))
        .navigationSubtitle(LN("{0} dosya · {1}", index.liveFiles.count, Format.size(index.liveFiles.reduce(0) { $0 + $1.size })))
        .searchable(text: $search, placement: .toolbar, prompt: L("Tüm kasada ara"))
        .toolbar { toolbar }
        .onDrop(of: [.fileURL, .item], isTargeted: $dropTargeted) { state.handleDrop($0, into: current) }
        .overlay { if dropTargeted { dropOverlay } }
        .onDeleteCommand(perform: trashSelection)
        .onChange(of: state.currentFolder) { _, _ in selection.removeAll() }
        .sheet(item: $previewing) { FilePreviewSheet(file: $0, siblings: items.compactMap(\.file)) }
        .sheet(item: Binding(get: { state.phoneShare }, set: { if $0 == nil { state.stopPhoneShare() } })) {
            PhoneShareSheet(session: $0)
        }
        .sheet(item: Binding(get: { state.phoneUpload }, set: { if $0 == nil { state.stopPhoneUpload() } })) {
            PhoneUploadSheet(session: $0)
        }
        .sheet(item: $renamingFile) { file in
            RenameSheet(name: file.name) { state.renameFile(file.id, to: $0) }
        }
        .sheet(item: $renamingFolder) { folder in
            RenameSheet(name: folder.name) { state.renameFolder(folder.id, to: $0) }
        }
        .sheet(isPresented: Binding(get: { tagging != nil }, set: { if !$0 { tagging = nil } })) {
            if let ids = tagging {
                TagEditorSheet(
                    initial: Set(index.files.filter { ids.contains($0.id) }.flatMap(\.tags)),
                    known: index.allTags
                ) { state.setTags($0, for: ids) }
            }
        }
    }

    // MARK: - Üst çubuk

    private var header: some View {
        HStack(spacing: 4) {
            if isGlobal {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text(L("Tüm kasa")).font(.callout.weight(.medium))
                if let tagFilter {
                    tagChip(tagFilter) { self.tagFilter = nil }
                }
                if filter != .all {
                    tagChip(filter.title, symbol: "line.3.horizontal.decrease") { filter = .all }
                }
            } else {
                crumb(L("Dosyalar"), symbol: "house.fill", target: nil, isLast: current == nil)
                ForEach(index.path(to: current)) { folder in
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    crumb(folder.name, symbol: nil, target: folder.id, isLast: folder.id == current)
                }
            }
            Spacer()
            if !selection.isEmpty {
                Text(L("{0} seçili", selection.count)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
    }

    private func crumb(_ title: String, symbol: String?, target: UUID?, isLast: Bool) -> some View {
        Button {
            state.currentFolder = target
        } label: {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.caption) }
                Text(title).lineLimit(1)
            }
            .font(.callout.weight(isLast ? .semibold : .regular))
            .foregroundStyle(isLast ? .primary : .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrop(of: [.fileURL, .item], isTargeted: nil) { state.handleDrop($0, into: target) }
    }

    private func tagChip(_ title: String, symbol: String = "tag.fill", onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.caption2)
            Text(title).font(.caption.weight(.medium))
            Button(action: onRemove) { Image(systemName: "xmark.circle.fill").font(.caption) }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(accent.opacity(0.15), in: Capsule())
        .foregroundStyle(.tint)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Picker(L("Filtre"), selection: $filter) {
                ForEach(FileFilter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .help(L("Filtrele"))

            if !index.allTags.isEmpty {
                Menu {
                    Button(L("Tüm etiketler")) { tagFilter = nil }
                    Divider()
                    ForEach(index.allTags, id: \.self) { tag in
                        Button {
                            tagFilter = tag
                        } label: {
                            if tagFilter == tag { Label(tag, systemImage: "checkmark") } else { Text(tag) }
                        }
                    }
                } label: {
                    Label(L("Etiket"), systemImage: tagFilter == nil ? "tag" : "tag.fill")
                }
                .help(L("Etikete göre filtrele"))
            }

            Menu {
                Picker(L("Sırala"), selection: $sort) {
                    ForEach(FileSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label(L("Sırala"), systemImage: "arrow.up.arrow.down")
            }
            .help(L("Sırala"))

            Picker(L("Görünüm"), selection: layout) {
                Label(L("Izgara"), systemImage: "square.grid.2x2").tag("grid")
                Label(L("Liste"), systemImage: "list.bullet").tag("list")
            }
            .pickerStyle(.segmented)
            .help(L("Görünüm"))

            Button {
                let id = state.createFolder(in: current)
                if let folder = state.index.folder(id) { renamingFolder = folder }
            } label: {
                Label(L("Yeni Klasör"), systemImage: "folder.badge.plus")
            }
            .help(L("Yeni klasör"))
            .disabled(isGlobal)

            Menu {
                Button(L("Dosya Seç…"), action: state.presentImportPanel)
                Button(L("Telefondan Ekle…")) { state.addFromPhone(into: current) }
            } label: {
                Label(L("Ekle"), systemImage: "plus")
            } primaryAction: {
                state.presentImportPanel()
            }
            .help(L("Dosya ekle (⌘O)"))
        }
    }

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
            .foregroundStyle(.tint)
            .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                Label(L("Şifrelemek için bırak → {0}", index.folder(current)?.name ?? L("Dosyalar")), systemImage: "lock.doc.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.tint)
            )
            .padding(12)
            .allowsHitTesting(false)
    }

    // MARK: - İçerik

    @ViewBuilder
    private func content(_ items: [FileItem]) -> some View {
        if index.liveFiles.isEmpty && index.childFolders(of: nil).isEmpty {
            EmptyState(
                symbol: "tray.and.arrow.down.fill",
                title: L("Dosyaları buraya sürükle"),
                message: L("Eklediğin her dosya, adıyla birlikte şifrelenip kasaya yazılır. Klasör sürüklersen yapısı korunur."),
                actionTitle: L("Dosya Seç…"),
                action: state.presentImportPanel
            )
        } else if items.isEmpty {
            if isGlobal {
                EmptyState(symbol: "magnifyingglass", title: L("Sonuç yok"), message: L("Arama, filtre veya etiketle eşleşen dosya bulunamadı."))
            } else {
                EmptyState(symbol: "folder", title: L("Klasör boş"), message: L("Dosyaları buraya sürükleyebilir ya da başka klasörlerden taşıyabilirsin."))
            }
        } else if layout.wrappedValue == "list" {
            listView(items)
        } else {
            gridView(items)
        }
    }

    private func gridView(_ items: [FileItem]) -> some View {
        GeometryReader { geo in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 18)], spacing: 18) {
                    ForEach(items) { item in
                        tile(item)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { open(item) }
                            .simultaneousGesture(TapGesture().onEnded { select(item.id) })
                            .contextMenu { menu(for: selection.contains(item.id) ? selection : [item.id]) }
                            .onDrag { dragProvider(item) }
                            .background {
                                // Izgara tembel çizildiği için her öğe konumunu ekrana geldiğinde kaydeder.
                                GeometryReader { g in
                                    let frame = g.frame(in: .named(Self.gridSpace))
                                    Color.clear
                                        .onAppear { marquee.frames[item.id] = frame }
                                        .onChange(of: frame) { _, new in marquee.frames[item.id] = new }
                                }
                            }
                    }
                }
                .padding(22)
                .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)
                // Boş alana tıklamak seçimi temizler; sürüklemek Finder'daki gibi dikdörtgenle seçer.
                .background {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { selection.removeAll() }
                        .simultaneousGesture(marqueeGesture(items))
                        .background(EnclosingScrollViewReader { marquee.scrollView = $0 })
                }
                .overlay(alignment: .topLeading) {
                    if let rect = marquee.rect {
                        Rectangle()
                            .fill(accent.opacity(0.12))
                            .overlay(Rectangle().strokeBorder(accent.opacity(0.75), lineWidth: 1))
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                            .allowsHitTesting(false)
                    }
                }
                .coordinateSpace(name: Self.gridSpace)
            }
        }
    }

    // MARK: - Dikdörtgenle seçim

    private static let gridSpace = "files.grid"

    /// Boş alandan başlayan sürükleme: dikdörtgene değen öğeler seçilir. ⌘ ya da ⇧ basılıysa
    /// mevcut seçim korunur ve dikdörtgendekiler tersine çevrilir (Finder gibi). Kenara gelince ızgara kayar.
    private func marqueeGesture(_ items: [FileItem]) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.gridSpace))
            .onChanged { value in
                if marquee.rect == nil {
                    let flags = NSEvent.modifierFlags
                    let base = flags.contains(.command) || flags.contains(.shift) ? selection : []
                    let visible = Set(items.map(\.id))
                    marquee.begin(at: value.startLocation, base: base) { selection = $0.intersection(visible.union(base)) }
                }
                marquee.update(to: value.location)
            }
            .onEnded { _ in marquee.end() }
    }

    @ViewBuilder
    private func tile(_ item: FileItem) -> some View {
        if let folder = item.folder {
            FolderTile(folder: folder, count: index.liveFileCount(inTree: folder.id), selected: selection.contains(folder.id)) { providers in
                state.handleDrop(providers, into: folder.id)
            }
        } else if let file = item.file {
            FileTile(file: file, selected: selection.contains(file.id), showLocation: isGlobal ? locationName(file) : nil)
        }
    }

    private func locationName(_ file: FileRecord) -> String {
        index.path(to: file.folderID).map(\.name).joined(separator: " › ").nonEmpty ?? L("Dosyalar")
    }

    private func dragProvider(_ item: FileItem) -> NSItemProvider {
        if let file = item.file { return state.dragProvider(for: file, alongWith: selection) }
        return state.folderDragProvider(item.folder!, alongWith: selection)
    }

    private func select(_ id: UUID) {
        if NSEvent.modifierFlags.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else {
            selection = [id]
        }
    }

    private func open(_ item: FileItem) {
        if let folder = item.folder {
            search = ""
            state.currentFolder = folder.id
        } else if let file = item.file {
            previewing = file
        }
    }

    private func listView(_ items: [FileItem]) -> some View {
        Table(of: FileItem.self, selection: $selection) {
            TableColumn(L("Ad")) { item in
                HStack(spacing: 8) {
                    if let file = item.file {
                        FileIcon(file: file, size: 22)
                    } else {
                        Image(systemName: "folder.fill").foregroundStyle(folderColor(item.folder)).frame(width: 22)
                    }
                    Text(item.name).lineLimit(1)
                    if item.file?.favorite == true { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                }
            }
            .width(min: 220, ideal: 340)
            TableColumn(L("Etiketler")) { item in
                Text(item.file?.tags.joined(separator: ", ") ?? "").foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 60, ideal: 120)
            TableColumn(L("Tür")) { item in
                Text(item.file?.kind ?? L("Klasör")).foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 130)
            TableColumn(L("Boyut")) { item in
                Text(item.file.map { Format.size($0.size) } ?? LN("{0} öğe", index.liveFileCount(inTree: item.id)))
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            .width(min: 60, ideal: 90)
            TableColumn(L("Eklenme")) { item in
                Text(Format.date(item.file?.addedAt ?? item.folder!.createdAt)).foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 150)
        } rows: {
            ForEach(items) { item in
                TableRow(item).itemProvider { dragProvider(item) }
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            menu(for: ids)
        } primaryAction: { ids in
            if let id = ids.first, let item = items.first(where: { $0.id == id }) { open(item) }
        }
    }

    private func folderColor(_ folder: Folder?) -> Color {
        folder?.color.map { AccentChoice($0).color } ?? accent
    }

    // MARK: - Bağlam menüsü

    @ViewBuilder
    private func menu(for ids: Set<UUID>) -> some View {
        let files = index.files.filter { ids.contains($0.id) }
        let folders = index.folders.filter { ids.contains($0.id) }
        if folders.count == 1, files.isEmpty, let folder = folders.first {
            Button(L("Aç")) { open(FileItem(folder: folder, file: nil)) }
            Button(L("Yeniden Adlandır…")) { renamingFolder = folder }
            Menu(L("Renk")) {
                Button(L("Varsayılan")) { setFolderColor(folder.id, nil) }
                ForEach(AccentChoice.allCases) { c in Button(c.title) { setFolderColor(folder.id, c.rawValue) } }
            }
            moveMenu(files: [], folder: folder)
            Button(L("Telefonda Göster…")) { state.showOnPhone(folder: folder) }
            Button(L("Telefondan Ekle…")) { state.addFromPhone(into: folder.id) }
            Divider()
            Button(L("Çöp Kutusu'na Taşı"), role: .destructive) { state.trashFolder(folder.id) }
        } else if !files.isEmpty {
            if files.count == 1, let file = files.first {
                Button(L("Önizle")) { previewing = file }
                Button(L("Geçici Olarak Aç")) { state.openTemporarily(file) }
                Button(L("Yeniden Adlandır…")) { renamingFile = file }
                if isGlobal {
                    Button(L("Bulunduğu Klasöre Git")) {
                        search = ""; filter = .all; tagFilter = nil
                        state.currentFolder = file.folderID
                    }
                }
                Divider()
            }
            Button(L("Etiketler…")) { tagging = Set(files.map(\.id)) }
            Button(files.allSatisfy(\.favorite) ? L("Favorilerden Çıkar") : L("Favorilere Ekle")) { state.toggleFavorite(Set(files.map(\.id))) }
            moveMenu(files: Set(files.map(\.id)), folder: nil)
            Button(files.count == 1 ? L("Dışa Aktar…") : L("{0} Dosyayı Dışa Aktar…", files.count)) { state.exportFiles(files) }
            if files.contains(where: PhoneShareSession.isShareable) {
                Button(L("Telefonda Göster…")) { state.showOnPhone(files: files) }
            }
            Divider()
            Button(files.count == 1 ? L("Çöp Kutusu'na Taşı") : L("{0} Dosyayı Çöp Kutusu'na Taşı", files.count), role: .destructive) {
                state.trashFiles(Set(files.map(\.id)))
                selection.subtract(files.map(\.id))
            }
        }
    }

    /// Hedef klasör listesi; bir klasör kendi altına taşınamaz.
    private func moveMenu(files: Set<UUID>, folder: Folder?) -> some View {
        let excluded = folder.map { index.descendantFolderIDs(of: $0.id).union([$0.id]) } ?? []
        let targets = index.folders
            .filter { $0.deletedAt == nil && !excluded.contains($0.id) }
            .map { (id: $0.id, path: index.path(to: $0.id).map(\.name).joined(separator: " › ")) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return Menu(L("Taşı")) {
            Button(L("Dosyalar (en üst)")) { move(files: files, folder: folder, to: nil) }
            if !targets.isEmpty { Divider() }
            ForEach(targets, id: \.id) { target in
                Button(target.path) { move(files: files, folder: folder, to: target.id) }
            }
        }
    }

    private func move(files: Set<UUID>, folder: Folder?, to target: UUID?) {
        if let folder { state.moveFolder(folder.id, to: target) } else { state.moveFiles(files, to: target) }
        selection.removeAll()
    }

    private func setFolderColor(_ id: UUID, _ color: String?) {
        state.mutate { idx in
            if let i = idx.folders.firstIndex(where: { $0.id == id }) { idx.folders[i].color = color }
        }
    }

    private func trashSelection() {
        guard !selection.isEmpty else { return }
        let fileIDs = selection.filter { id in index.files.contains { $0.id == id } }
        for folder in index.folders where selection.contains(folder.id) { state.trashFolder(folder.id) }
        if !fileIDs.isEmpty { state.trashFiles(fileIDs) }
        selection.removeAll()
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

struct FolderTile: View {
    @Environment(\.vaultAccent) private var accent
    let folder: Folder
    let count: Int
    let selected: Bool
    let onDrop: ([NSItemProvider]) -> Bool
    @State private var hovering = false
    @State private var dropTargeted = false

    private var color: Color { folder.color.map { AccentChoice($0).color } ?? accent }

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(dropTargeted ? 0.3 : 0.12))
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .overlay {
                    Image(systemName: dropTargeted ? "folder.fill.badge.plus" : "folder.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(color.gradient)
                }
                .shadow(color: .black.opacity(hovering ? 0.18 : 0.06), radius: hovering ? 10 : 4, y: 2)
            VStack(spacing: 2) {
                Text(folder.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(LN("{0} dosya", count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(selected ? accent.opacity(0.18) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? accent.opacity(0.6) : .clear, lineWidth: 1.5))
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.snappy(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
        .onDrop(of: [.fileURL, .item], isTargeted: $dropTargeted, perform: onDrop)
        .help(folder.name)
    }
}

struct TagEditorSheet: View {
    @Environment(\.vaultAccent) private var accent
    @State var tags: Set<String>
    let known: [String]
    let onSave: ([String]) -> Void
    @State private var newTag = ""
    @Environment(\.dismiss) private var dismiss

    init(initial: Set<String>, known: [String], onSave: @escaping ([String]) -> Void) {
        _tags = State(initialValue: initial)
        self.known = known
        self.onSave = onSave
    }

    private var all: [String] {
        Array(Set(known).union(tags)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Etiketler")).font(.headline)
            if all.isEmpty {
                Text(L("Henüz etiket yok. Aşağıdan ilk etiketini ekle.")).font(.callout).foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(all, id: \.self) { tag in
                        let on = tags.contains(tag)
                        Button {
                            if on { tags.remove(tag) } else { tags.insert(tag) }
                        } label: {
                            Label(tag, systemImage: on ? "checkmark" : "tag")
                                .font(.callout)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(on ? accent : Color.secondary.opacity(0.12), in: Capsule())
                                .foregroundStyle(on ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack {
                TextField(L("Yeni etiket"), text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTag)
                Button(L("Ekle"), action: addTag).disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                Spacer()
                Button(L("Vazgeç")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Kaydet")) {
                    onSave(Array(tags))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func addTag() {
        let t = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        tags.insert(t)
        newTag = ""
    }
}

/// Etiket çiplerini satır satır dizer.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            if rows[rows.count - 1].width + size.width > width, !rows[rows.count - 1].indices.isEmpty {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            rows[rows.count - 1].indices.append(i)
            rows[rows.count - 1].width += size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}

struct FileIcon: View {
    let file: FileRecord
    var size: CGFloat

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(for: file.utType))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

struct FileTile: View {
    @Environment(\.vaultAccent) private var accent
    let file: FileRecord
    let selected: Bool
    var showLocation: String?
    @EnvironmentObject private var state: AppState
    @State private var thumbnail: NSImage?
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 8) {
            // Küçük resim taşmasın diye sabit boyutlu kutunun üstüne bindirilir ve kutuya kırpılır.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary.opacity(0.45))
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .overlay {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        FileIcon(file: file, size: 64)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if file.favorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(6)
                }
            }
            .shadow(color: .black.opacity(hovering ? 0.18 : 0.06), radius: hovering ? 10 : 4, y: 2)

            VStack(spacing: 2) {
                Text(file.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .truncationMode(.middle)
                Text(showLocation ?? (file.tags.isEmpty ? Format.size(file.size) : file.tags.map { "#\($0)" }.joined(separator: " ")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selected ? accent.opacity(0.18) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? accent.opacity(0.6) : .clear, lineWidth: 1.5)
        )
        .scaleEffect(hovering ? 1.02 : 1)
        .animation(.snappy(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
        .task(id: "\(file.id)\(file.hasThumbnail)") { thumbnail = await state.thumbnail(for: file) }
        .help(file.name)
    }
}

// MARK: - Önizleme

struct FilePreviewSheet: View {
    /// Önizlenen dosya; ok tuşları ya da izleme dörtgeninde kaydırma ile kardeşleri arasında gezilir.
    @State private var file: FileRecord
    /// Aynı ekranda görünen dosyalar, görünen sırayla.
    let siblings: [FileRecord]
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    init(file: FileRecord, siblings: [FileRecord] = []) {
        _file = State(initialValue: file)
        self.siblings = siblings.contains(where: { $0.id == file.id }) ? siblings : [file]
    }

    private var position: Int? { siblings.firstIndex { $0.id == file.id } }

    private enum Content {
        case loading
        case image(NSImage)
        case pdf(PDFDocument)
        case text(String)
        case media(AVPlayer)
        case unsupported(String)
    }

    @State private var content = Content.loading
    @State private var loader: EncryptedMediaLoader?
    static let maxInMemory: Int64 = 400 * 1024 * 1024

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                FileIcon(file: file, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name).font(.headline).lineLimit(1).truncationMode(.middle)
                    Text("\(file.kind) · \(Format.size(file.size)) · \(Format.date(file.addedAt))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if siblings.count > 1, let position {
                    HStack(spacing: 2) {
                        Button { step(-1) } label: { Image(systemName: "chevron.left") }
                            .disabled(position == 0)
                            .help(L("Önceki (←)"))
                        Text("\(position + 1) / \(siblings.count)")
                            .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                            .frame(minWidth: 56)
                        Button { step(1) } label: { Image(systemName: "chevron.right") }
                            .disabled(position == siblings.count - 1)
                            .help(L("Sonraki (→)"))
                    }
                    .buttonStyle(.borderless)
                }
                Button {
                    dismiss()
                    state.openTemporarily(file)
                } label: { Label(L("Geçici Aç"), systemImage: "arrow.up.forward.app") }
                Button {
                    dismiss()
                    state.exportFiles([file])
                } label: { Label(L("Dışa Aktar"), systemImage: "square.and.arrow.up") }
                Button(L("Kapat")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(14)
            Divider()
            Group {
                switch content {
                case .loading:
                    ProgressView(L("Şifre çözülüyor…")).frame(maxWidth: .infinity, maxHeight: .infinity)
                case .image(let image):
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                case .pdf(let doc):
                    PDFKitView(document: doc)
                case .text(let text):
                    ScrollView {
                        Text(text)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                case .media(let player):
                    PlayerView(player: player)
                        .overlay(alignment: .center) {
                            if file.isAudioOnly {
                                Image(systemName: "waveform")
                                    .font(.system(size: 90, weight: .light))
                                    .foregroundStyle(.tint)
                                    .allowsHitTesting(false)
                                    .offset(y: -40)
                            }
                        }
                case .unsupported(let reason):
                    EmptyState(symbol: "eye.slash", title: L("Uygulama içi önizleme yok"), message: reason)
                }
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.4))
            .id(file.id)
            .transition(.asymmetric(insertion: .move(edge: lastStep < 0 ? .leading : .trailing).combined(with: .opacity),
                                    removal: .opacity))
            .clipped()
        }
        .frame(minWidth: 720, idealWidth: 900, minHeight: 520, idealHeight: 680)
        .background(WindowReader { window = $0 })
        .task(id: file.id) { await load() }
        .onAppear(perform: installMonitor)
        .onDisappear {
            stopMedia()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
        .onChange(of: state.phase) { _, phase in if phase != .unlocked { stopMedia(); dismiss() } }
    }

    private func stopMedia() {
        if case .media(let player) = content { player.pause(); player.replaceCurrentItem(with: nil) }
        loader?.invalidate()
        loader = nil
    }

    // MARK: Gezinme

    @State private var window: NSWindow?
    @State private var monitor: Any?
    @State private var lastStep = 1
    @State private var swipeX: CGFloat = 0
    @State private var swipeUsed = false

    private func step(_ delta: Int) {
        guard let position, siblings.indices.contains(position + delta) else { return }
        stopMedia()
        lastStep = delta
        withAnimation(.easeOut(duration: 0.22)) {
            content = .loading
            file = siblings[position + delta]
        }
    }

    /// Belge ve metinde ok tuşları ile yatay kaydırma içeriğin kendisine kalır.
    private var contentScrolls: Bool {
        switch content {
        case .pdf, .text: return true
        default: return false
        }
    }

    /// ← / → tuşları ve izleme dörtgeninde iki parmakla yatay kaydırma (her harekette bir dosya).
    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel, .swipe]) { event in
            guard let window, event.window === window else { return event }
            switch event.type {
            case .keyDown:
                guard !contentScrolls, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
                      !(window.firstResponder is NSText) else { return event }
                if event.keyCode == 123 { step(-1); return nil }
                if event.keyCode == 124 { step(1); return nil }
            case .swipe:
                if event.deltaX != 0 { step(event.deltaX > 0 ? -1 : 1); return nil }
            case .scrollWheel:
                guard !contentScrolls, event.hasPreciseScrollingDeltas else { return event }
                if event.phase == .began { swipeX = 0; swipeUsed = false }
                // Kaydırma hareketi bitince gelen ivme olayları yeni bir geçiş başlatmasın.
                guard event.momentumPhase == [] else { return swipeUsed ? nil : event }
                guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) || swipeX != 0 else { return event }
                swipeX += event.scrollingDeltaX
                if !swipeUsed, abs(swipeX) > 50 {
                    swipeUsed = true
                    step(swipeX > 0 ? -1 : 1)
                }
                if event.phase == .ended || event.phase == .cancelled { swipeX = 0 }
                return nil
            default:
                break
            }
            return event
        }
    }

    private func loadMedia() async {
        do {
            let reader = try await state.openReader(file)
            let loader = EncryptedMediaLoader(reader: reader, contentType: file.utType.identifier)
            let asset = loader.makeAsset(fileExtension: (file.name as NSString).pathExtension)
            guard try await asset.load(.isPlayable) else {
                content = .unsupported(L("Bu biçim ({0}) macOS tarafından oynatılamıyor. \"Geçici Aç\" ile başka bir oynatıcıda açabilirsin.", file.kind))
                return
            }
            self.loader = loader
            let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            content = .media(player)
            player.play()
        } catch {
            content = .unsupported(error.localizedDescription)
        }
    }

    private func load() async {
        let type = file.utType
        if file.isMedia {
            await loadMedia()
            return
        }
        let previewable = type.conforms(to: .image) || type.conforms(to: .pdf) || type.conforms(to: .text) || type.conforms(to: .sourceCode)
        guard previewable else {
            content = .unsupported(L("Bu tür dosyalar ({0}) uygulama içinde gösterilemiyor. \"Geçici Aç\" ile varsayılan uygulamasında açabilirsin.", file.kind))
            return
        }
        guard file.size <= Self.maxInMemory else {
            content = .unsupported(L("Dosya önizleme için çok büyük. \"Geçici Aç\" veya \"Dışa Aktar\" kullan."))
            return
        }
        do {
            let data = try await state.readFile(file)
            if type.conforms(to: .pdf), let doc = PDFDocument(data: data) {
                content = .pdf(doc)
            } else if type.conforms(to: .image), let image = NSImage(data: data) {
                content = .image(image)
            } else if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                content = .text(text)
            } else {
                content = .unsupported(L("Dosya içeriği okunamadı."))
            }
        } catch {
            content = .unsupported(error.localizedDescription)
        }
    }
}

/// Dikdörtgenle seçim: öğe konumları, sürükleme dikdörtgeni ve kenarda otomatik kaydırma.
/// Konumlar ızgaranın içerik koordinatlarındadır (yukarıdan aşağı), kaydırmadan etkilenmez.
@MainActor
final class MarqueeSelection: ObservableObject {
    @Published private(set) var rect: CGRect?
    var frames: [UUID: CGRect] = [:]
    weak var scrollView: NSScrollView?
    private var start = CGPoint.zero
    private var current = CGPoint.zero
    private var base = Set<UUID>()
    private var apply: (Set<UUID>) -> Void = { _ in }
    private var timer: Timer?
    private var speed: CGFloat = 0

    func begin(at point: CGPoint, base: Set<UUID>, apply: @escaping (Set<UUID>) -> Void) {
        start = point
        self.base = base
        self.apply = apply
    }

    func update(to point: CGPoint) {
        current = point
        refresh()
        // İmleç görünür alanın kenarına yaklaştıkça hızlanarak kaydır.
        guard let visible = visibleRange() else { return }
        let edge: CGFloat = 48
        let y = point.y - visible.top
        if y < edge { speed = -min(28, (edge - y) * 0.6) }
        else if y > visible.height - edge { speed = min(28, (y - (visible.height - edge)) * 0.6) }
        else { speed = 0 }
        if speed != 0, timer == nil {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if speed == 0 {
            stopTimer()
        }
    }

    func end() {
        stopTimer()
        rect = nil
        base = []
        apply = { _ in }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        speed = 0
    }

    private func refresh() {
        let r = CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                       width: abs(current.x - start.x), height: abs(current.y - start.y))
        rect = r
        let hit = base.symmetricDifference(frames.filter { $0.value.intersects(r) }.keys)
        #if DEBUG
        Self.debugLast = (frames.count, hit.count, r)
        #endif
        apply(hit)
    }

    #if DEBUG
    /// Kendi kendini sınama için: (bilinen konum sayısı, seçilen sayısı, dikdörtgen).
    static var debugLast: (known: Int, selected: Int, rect: CGRect)?
    #endif

    /// Görünür alanın içerik koordinatlarındaki üst kenarı ve yüksekliği.
    private func visibleRange() -> (top: CGFloat, height: CGFloat, max: CGFloat)? {
        guard let scrollView, let document = scrollView.documentView else { return nil }
        let visible = scrollView.documentVisibleRect
        let total = document.bounds.height
        let top = document.isFlipped ? visible.minY : total - visible.maxY
        return (top, visible.height, max(0, total - visible.height))
    }

    private func tick() {
        guard speed != 0, let scrollView, let document = scrollView.documentView, let visible = visibleRange() else {
            return stopTimer()
        }
        let newTop = min(visible.max, max(0, visible.top + speed))
        let delta = newTop - visible.top
        guard delta != 0 else { return }
        let clip = scrollView.contentView
        let y = document.isFlipped ? newTop : document.bounds.height - newTop - visible.height
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
        scrollView.reflectScrolledClipView(clip)
        current.y += delta
        refresh()
    }
}

/// İçinde bulunduğu kaydırma görünümünü (NSScrollView) bildirir.
struct EnclosingScrollViewReader: NSViewRepresentable {
    let onFind: (NSScrollView?) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { onFind(view.enclosingScrollView) }
    }
}

/// Görünümün bulunduğu pencereyi bildirir.
struct WindowReader: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onChange(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { if view.window != nil { onChange(view.window) } }
    }
}

struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = document
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
    }
}

struct RenameSheet: View {
    @State var name: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Yeniden adlandır")).font(.headline)
            TextField(L("Ad"), text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 340)
                .onSubmit(save)
            HStack {
                Spacer()
                Button(L("Vazgeç")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Kaydet"), action: save).keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
    }

    private func save() {
        onSave(name)
        dismiss()
    }
}
