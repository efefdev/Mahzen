"""Notlar: renkli, sabitlenebilir notlar; liste + düzenleyici."""

from __future__ import annotations

from gi.repository import Adw, Gio, GLib, Gtk, Pango

from ..core.index import parse_date
from .common import clear_box, relative_date

# macOS sürümüyle aynı renk adları (vurgu renkleri).
NOTE_COLORS = [
    (None, "Renk yok"), ("indigo", "Çivit"), ("blue", "Mavi"), ("teal", "Turkuaz"), ("green", "Yeşil"),
    ("orange", "Turuncu"), ("pink", "Pembe"), ("red", "Kırmızı"), ("purple", "Mor"), ("graphite", "Grafit"),
]


def _sorted_notes(notes: list[dict]) -> list[dict]:
    live = [n for n in notes if not n.get("deletedAt")]
    live.sort(key=lambda n: parse_date(n.get("updatedAt")) or parse_date("1970-01-01T00:00:00Z"), reverse=True)
    live.sort(key=lambda n: not n.get("pinned"))
    return live


class NotesPage(Adw.Bin):
    def __init__(self, state, make_header):
        super().__init__()
        self.state = state
        self.selected_id: str | None = None
        self.search = ""
        self._loading = False

        split = Adw.NavigationSplitView(min_sidebar_width=260, max_sidebar_width=340)
        self.split = split

        # Liste
        list_toolbar = Adw.ToolbarView()
        list_header = make_header("Notlar", lock=False)
        add = Gtk.Button(icon_name="list-add-symbolic", tooltip_text="Yeni not (Ctrl+N)")
        add.connect("clicked", lambda *_: self.new_note())
        list_header.pack_start(add)
        list_toolbar.add_top_bar(list_header)
        search = Gtk.SearchEntry(margin_start=8, margin_end=8, margin_bottom=6)
        search.set_property("placeholder-text", "Notlarda ara")
        search.connect("search-changed", lambda e: self._set_search(e.get_text()))
        list_toolbar.add_top_bar(search)
        self.listbox = Gtk.ListBox(css_classes=["navigation-sidebar"])
        self.listbox.connect("row-selected", self._on_row_selected)
        scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, vexpand=True)
        scroller.set_child(self.listbox)
        list_toolbar.set_content(scroller)
        split.set_sidebar(Adw.NavigationPage(title="Notlar", child=list_toolbar))

        # Düzenleyici
        editor_toolbar = Adw.ToolbarView()
        editor_header = make_header("")
        self.pin_btn = Gtk.ToggleButton(icon_name="view-pin-symbolic", tooltip_text="Sabitle")
        self.pin_btn.connect("toggled", self._on_pin)
        editor_header.pack_start(self.pin_btn)
        self.color_btn = Gtk.MenuButton(icon_name="color-select-symbolic", tooltip_text="Renk")
        color_menu = Gio.Menu()
        for key, label in NOTE_COLORS:
            color_menu.append(label, f"note.color('{key or ''}')")
        self.color_btn.set_menu_model(color_menu)
        editor_header.pack_start(self.color_btn)
        delete = Gtk.Button(icon_name="user-trash-symbolic", tooltip_text="Çöp kutusuna taşı")
        delete.connect("clicked", lambda *_: self.delete_note())
        editor_header.pack_start(delete)
        editor_toolbar.add_top_bar(editor_header)

        group = Gio.SimpleActionGroup()
        color_action = Gio.SimpleAction.new("color", GLib.VariantType.new("s"))
        color_action.connect("activate", lambda _a, v: self._set_color(v.get_string() or None))
        group.add_action(color_action)
        self.insert_action_group("note", group)

        self.editor_stack = Gtk.Stack()
        self.editor_stack.add_named(Adw.StatusPage(icon_name="document-edit-symbolic", title="Not seçilmedi",
                                                   description="Soldan bir not seçin ya da yeni bir not ekleyin."),
                                    "empty")
        editor = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.title_entry = Gtk.Entry(css_classes=["note-title", "flat"], margin_start=18, margin_end=18,
                                     margin_top=12, has_frame=False)
        self.title_entry.set_property("placeholder-text", "Başlık")
        self.title_entry.connect("changed", self._on_title)
        editor.append(self.title_entry)
        self.date_label = Gtk.Label(xalign=0, css_classes=["caption", "dim-label"], margin_start=22)
        editor.append(self.date_label)
        self.body = Gtk.TextView(wrap_mode=Gtk.WrapMode.WORD_CHAR, top_margin=12, bottom_margin=24,
                                 left_margin=22, right_margin=22, vexpand=True, css_classes=["note-body"])
        self.body.get_buffer().connect("changed", self._on_body)
        body_scroller = Gtk.ScrolledWindow(vexpand=True)
        body_scroller.set_child(self.body)
        editor.append(body_scroller)
        self.editor_stack.add_named(editor, "editor")
        editor_toolbar.set_content(self.editor_stack)
        self.editor_page = Adw.NavigationPage(title="Not", child=editor_toolbar)
        split.set_content(self.editor_page)

        self.set_child(split)
        self._font_css = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_display(self.get_display(), self._font_css,
                                                  Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)
        state.connect("index-changed", lambda *_: self.refresh_list())
        state.connect("prefs-changed", lambda *_: self._apply_font())
        state.connect("phase-changed", lambda *_: self._on_phase())

    def _on_phase(self) -> None:
        if self.state.phase != "unlocked":
            self.selected_id = None
            self._load(None)

    def _apply_font(self) -> None:
        if self.state.phase != "unlocked":
            return
        size = float(self.state.prefs.get("noteFontSize", 15))
        design = self.state.prefs.get("noteFontDesign", "default")
        family = {"serif": "serif", "monospaced": "monospace", "rounded": "sans-serif"}.get(design)
        font = f"font-family: {family};" if family else ""
        # macOS sürümündeki gibi: gövde seçilen boyutta, başlık 11 punto büyük ve kalın.
        css = (f".note-body {{ font-size: {size:.0f}px; {font} }}\n"
               f".note-title {{ font-size: {size + 11:.0f}px; {font} }}")
        if hasattr(self._font_css, "load_from_string"):
            self._font_css.load_from_string(css)
        else:
            self._font_css.load_from_data(css, -1)

    def _set_search(self, text: str) -> None:
        self.search = text.strip().casefold()
        self.refresh_list()

    def _note(self, nid) -> dict | None:
        return next((n for n in self.state.index.notes if n["id"] == nid), None)

    def refresh_list(self) -> None:
        if self.state.phase != "unlocked":
            return
        notes = _sorted_notes(self.state.index.notes)
        if self.search:
            notes = [n for n in notes if self.search in n.get("title", "").casefold()
                     or self.search in n.get("body", "").casefold()]
        self._loading = True
        clear_box(self.listbox)
        selected_row = None
        for n in notes:
            row = Gtk.ListBoxRow()
            row.nid = n["id"]
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2, margin_top=6, margin_bottom=6,
                          margin_start=4, margin_end=4)
            top = Gtk.Box(spacing=6)
            if n.get("color"):
                dot = Gtk.Box(width_request=10, height_request=10, valign=Gtk.Align.CENTER,
                              css_classes=["color-dot", f"accent-{n['color']}"])
                top.append(dot)
            top.append(Gtk.Label(label=n.get("title") or "Başlıksız not", xalign=0, hexpand=True,
                                 ellipsize=Pango.EllipsizeMode.END, css_classes=["heading"]))
            if n.get("pinned"):
                top.append(Gtk.Image(icon_name="view-pin-symbolic", css_classes=["dim-label"]))
            box.append(top)
            first_line = next((line for line in n.get("body", "").splitlines() if line.strip()), "")
            box.append(Gtk.Label(label=f"{relative_date(n.get('updatedAt'))}  {first_line}", xalign=0,
                                 ellipsize=Pango.EllipsizeMode.END, css_classes=["caption", "dim-label"]))
            row.set_child(box)
            self.listbox.append(row)
            if n["id"] == self.selected_id:
                selected_row = row
        if selected_row is not None:
            self.listbox.select_row(selected_row)
        self._loading = False
        if self.selected_id and not self._note(self.selected_id):
            self.selected_id = None
            self._load(None)
        elif self.selected_id and self._note(self.selected_id).get("deletedAt"):
            self.selected_id = None
            self._load(None)

    def _on_row_selected(self, _list, row) -> None:
        if self._loading or row is None:
            return
        if row.nid != self.selected_id:
            self.selected_id = row.nid
            self._load(self._note(row.nid))
        self.split.set_show_content(True)

    def _load(self, note: dict | None) -> None:
        self._loading = True
        if note is None:
            self.editor_stack.set_visible_child_name("empty")
            self.title_entry.set_text("")
            self.body.get_buffer().set_text("")
        else:
            self.editor_stack.set_visible_child_name("editor")
            self.title_entry.set_text(note.get("title", ""))
            self.body.get_buffer().set_text(note.get("body", ""))
            self.pin_btn.set_active(bool(note.get("pinned")))
            self.date_label.set_text("Düzenlendi: " + relative_date(note.get("updatedAt")))
        self._loading = False

    def _update(self, **values) -> None:
        if self._loading or not self.selected_id:
            return
        self.state.update_note(self.selected_id, **values)

    def _on_title(self, entry) -> None:
        self._update(title=entry.get_text())

    def _on_body(self, buffer) -> None:
        self._update(body=buffer.get_text(buffer.get_start_iter(), buffer.get_end_iter(), False))

    def _on_pin(self, button) -> None:
        self._update(pinned=button.get_active())

    def _set_color(self, color) -> None:
        if not self.selected_id:
            return
        note = self._note(self.selected_id)
        if color is None:
            self.state.mutate(lambda idx: note.pop("color", None))
        else:
            self._update(color=color)

    def new_note(self) -> None:
        if self.state.phase != "unlocked":
            return
        self.selected_id = self.state.add_note()
        self.refresh_list()
        self._load(self._note(self.selected_id))
        self.split.set_show_content(True)
        self.title_entry.grab_focus()

    def delete_note(self) -> None:
        if not self.selected_id:
            return
        nid = self.selected_id
        self.selected_id = None
        self.state.mutate(lambda idx: idx.trash_note(nid))
        self._load(None)
        self.state.toast("Not çöp kutusuna taşındı")
