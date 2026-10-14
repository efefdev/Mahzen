"""Çöp kutusu: geri yükleme ve kalıcı silme."""

from __future__ import annotations

from gi.repository import Adw, GLib, Gtk

from .common import confirm, format_date, format_size, icon_for
from .secrets import CATEGORY_ICONS


class TrashPage(Adw.Bin):
    def __init__(self, state, make_header):
        super().__init__()
        self.state = state
        toolbar = Adw.ToolbarView()
        header = make_header("Çöp Kutusu")
        self.empty_btn = Gtk.Button(label="Boşalt", css_classes=["destructive-action"])
        self.empty_btn.connect("clicked", lambda *_: self._confirm_empty())
        header.pack_start(self.empty_btn)
        toolbar.add_top_bar(header)
        self.stack = Gtk.Stack()
        self.stack.add_named(Adw.StatusPage(icon_name="user-trash-symbolic", title="Çöp kutusu boş"), "empty")
        self.page = Adw.PreferencesPage()
        self.stack.add_named(self.page, "list")
        toolbar.set_content(self.stack)
        self.set_child(toolbar)
        self._groups: list[Adw.PreferencesGroup] = []
        state.connect("index-changed", lambda *_: self.refresh() if self.get_mapped() else None)
        state.connect("prefs-changed", lambda *_: self.refresh() if self.get_mapped() else None)
        state.connect("phase-changed", lambda *_: self._clear_if_locked())

    def _clear_if_locked(self) -> None:
        if self.state.phase != "unlocked":
            for g in self._groups:
                self.page.remove(g)
            self._groups = []

    def _confirm_empty(self) -> None:
        confirm(self, "Çöp kutusu boşaltılsın mı?", "İçindeki her şey kalıcı olarak silinir; bu geri alınamaz.",
                "Kalıcı Olarak Sil", self.state.empty_trash)

    def refresh(self) -> None:
        if self.state.phase != "unlocked":
            return
        for g in self._groups:
            self.page.remove(g)
        self._groups = []
        idx = self.state.index
        retention = int(self.state.prefs.get("trashRetentionDays", 30))
        self.page.set_description(
            f"Çöp kutusundaki öğeler {retention} gün sonra kalıcı olarak silinir." if retention > 0
            else "Çöp kutusundaki öğeler siz boşaltana kadar saklanır.")
        sections = [
            ("Klasörler", idx.trashed_folders, lambda f: "folder-symbolic",
             lambda f: f"{idx.live_file_count_in_tree(f['id']) or _count_in_trash(idx, f)} dosya",
             "restore_folder", self.state.purge_folder),
            ("Dosyalar", idx.trashed_files, icon_for, lambda f: format_size(int(f.get("size", 0))),
             "restore_file", self.state.purge_file),
            ("Notlar", idx.trashed_notes, lambda n: "document-edit-symbolic", lambda n: "",
             "restore_note", lambda i: self.state.mutate(lambda x: x.purge_note(i))),
            ("Parolalar", idx.trashed_secrets, lambda s: CATEGORY_ICONS.get(s.get("category"), "dialog-password-symbolic"),
             lambda s: s.get("username", ""), "restore_secret", lambda i: self.state.mutate(lambda x: x.purge_secret(i))),
        ]
        total = 0
        for title, items, icon, detail, restore, purge in sections:
            if not items:
                continue
            group = Adw.PreferencesGroup(title=f"{title} ({len(items)})")
            for item in items:
                total += 1
                name = item.get("name") or item.get("title") or "Adsız"
                subtitle = " · ".join(x for x in [detail(item), "Silindi: " + format_date(item.get("deletedAt"))] if x)
                row = Adw.ActionRow(title=GLib.markup_escape_text(name), subtitle=GLib.markup_escape_text(subtitle))
                row.add_prefix(Gtk.Image(icon_name=icon(item)))
                restore_btn = Gtk.Button(icon_name="edit-undo-symbolic", tooltip_text="Geri yükle",
                                         valign=Gtk.Align.CENTER, css_classes=["flat"])
                restore_btn.connect("clicked", lambda *_, i=item["id"], r=restore: self._restore(r, i))
                purge_btn = Gtk.Button(icon_name="edit-delete-symbolic", tooltip_text="Kalıcı olarak sil",
                                       valign=Gtk.Align.CENTER, css_classes=["flat"])
                purge_btn.connect("clicked", lambda *_, i=item["id"], p=purge, n=name: confirm(
                    self, f"“{n}” kalıcı olarak silinsin mi?", "Bu işlem geri alınamaz.", "Kalıcı Olarak Sil",
                    lambda: p(i)))
                row.add_suffix(restore_btn)
                row.add_suffix(purge_btn)
                group.add(row)
            self.page.add(group)
            self._groups.append(group)
        self.empty_btn.set_sensitive(total > 0)
        self.stack.set_visible_child_name("list" if total else "empty")

    def _restore(self, restore, item_id) -> None:
        self.state.mutate(lambda idx: getattr(idx, restore)(item_id))
        self.state.toast("Geri yüklendi")


def _count_in_trash(idx, folder) -> int:
    tree = idx.descendant_folder_ids(folder["id"]) | {folder["id"].upper()}
    return sum(1 for f in idx.files if (f.get("folderID") or "").upper() in tree)
