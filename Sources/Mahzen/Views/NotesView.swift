import MahzenCore
import SwiftUI

struct NotesView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedID: UUID?
    @State private var search = ""
    @State private var confirmDelete = false

    private var notes: [Note] {
        var list = state.index.notes.filter { $0.deletedAt == nil }
        if !search.isEmpty {
            list = list.filter { $0.title.localizedCaseInsensitiveContains(search) || $0.body.localizedCaseInsensitiveContains(search) }
        }
        return list.sorted { ($0.pinned ? 1 : 0, $0.updatedAt) > ($1.pinned ? 1 : 0, $1.updatedAt) }
    }

    private var selected: Note? { state.index.notes.first { $0.id == selectedID && $0.deletedAt == nil } }

    var body: some View {
        HSplitView {
            list
                .frame(minWidth: 230, idealWidth: 280, maxWidth: 380)
            Group {
                if let note = selected {
                    NoteEditor(noteID: note.id).id(note.id)
                } else {
                    EmptyState(
                        symbol: "note.text",
                        title: notes.isEmpty && search.isEmpty ? "Henüz not yok" : "Bir not seç",
                        message: "Notların başlıkları ve içerikleriyle birlikte şifrelenir.",
                        actionTitle: "Yeni Not",
                        action: newNote
                    )
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Notlar")
        .navigationSubtitle("\(state.index.notes.filter { $0.deletedAt == nil }.count) not")
        .searchable(text: $search, placement: .toolbar, prompt: "Notlarda ara")
        .toolbar {
            ToolbarItemGroup {
                if let note = selected {
                    Menu {
                        Button("Renk yok") { state.updateNote(note.id) { $0.color = nil } }
                        Divider()
                        ForEach(AccentChoice.allCases) { choice in
                            Button {
                                state.updateNote(note.id) { $0.color = choice.rawValue }
                            } label: {
                                Label(choice.title, systemImage: "circle.fill")
                            }
                        }
                    } label: {
                        Label("Renk", systemImage: "paintpalette")
                    }
                    .help("Not rengi")
                    Button {
                        state.updateNote(note.id) { $0.pinned.toggle() }
                    } label: {
                        Label(note.pinned ? "Sabitlemeyi kaldır" : "Sabitle", systemImage: note.pinned ? "pin.slash" : "pin")
                    }
                    .help(note.pinned ? "Sabitlemeyi kaldır" : "Üste sabitle")
                    Button { confirmDelete = true } label: { Label("Sil", systemImage: "trash") }
                        .help("Notu sil")
                }
                Button(action: newNote) { Label("Yeni Not", systemImage: "square.and.pencil") }
                    .help("Yeni not (⌘N)")
            }
        }
        .confirmationDialog("Bu not Çöp Kutusu'na taşınsın mı?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Çöp Kutusu'na Taşı", role: .destructive) {
                if let id = selectedID { state.deleteNote(id) }
                selectedID = notes.first?.id
            }
        }
        .onAppear { if selectedID == nil { selectedID = notes.first?.id } }
        .onChange(of: state.index.notes.first?.id) { _, newest in
            // ⌘N menüden geldiğinde yeni notu seç.
            if let newest, state.index.notes.first?.title.isEmpty == true, state.index.notes.first?.body.isEmpty == true {
                selectedID = newest
            }
        }
    }

    private var list: some View {
        List(selection: $selectedID) {
            ForEach(notes) { note in
                NoteRow(note: note).tag(note.id)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(.background.secondary)
    }

    private func newNote() {
        selectedID = state.addNote()
    }
}

private struct NoteRow: View {
    let note: Note

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(note.color.map { AccentChoice($0).color } ?? .clear)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(note.title.isEmpty ? "Başlıksız not" : note.title)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(note.title.isEmpty ? .secondary : .primary)
                    Spacer(minLength: 0)
                    if note.pinned { Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.tint) }
                }
                Text(preview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(Format.relative(note.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 5)
    }

    private var preview: String {
        let text = note.body.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        return text.isEmpty ? "Ek metin yok" : text
    }
}

private struct NoteEditor: View {
    let noteID: UUID
    @EnvironmentObject private var state: AppState

    private var note: Note? { state.index.notes.first { $0.id == noteID } }

    private var title: Binding<String> {
        Binding(get: { note?.title ?? "" }, set: { v in state.updateNote(noteID) { $0.title = v } })
    }

    private var bodyText: Binding<String> {
        Binding(get: { note?.body ?? "" }, set: { v in state.updateNote(noteID) { $0.body = v } })
    }

    var body: some View {
        let design = NoteFontDesign(rawValue: state.prefs.noteFontDesign)?.design ?? .default
        VStack(alignment: .leading, spacing: 0) {
            TextField("Başlık", text: title)
                .textFieldStyle(.plain)
                .font(.system(size: state.prefs.noteFontSize + 11, weight: .bold, design: design))
                .padding(.horizontal, 28)
                .padding(.top, 24)
            if let note {
                Text("Düzenlendi: \(Format.date(note.updatedAt))  ·  \(note.body.count) karakter")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 28)
                    .padding(.top, 4)
            }
            Divider().padding(.horizontal, 28).padding(.vertical, 14)
            TextEditor(text: bodyText)
                .font(.system(size: state.prefs.noteFontSize, design: design))
                .lineSpacing(state.prefs.noteFontSize * 0.25)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 23)
                .padding(.bottom, 16)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
    }
}
