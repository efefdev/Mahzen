"""Dosyalar: klasörler, ızgara/liste görünümü, arama, etiketler, önizleme, ekleme ve dışa aktarma."""

from __future__ import annotations

from gi.repository import Adw, Gdk, Gio, GLib, GObject, Gtk, Pango

from ..core.index import sort_key
from .common import alert, ask_text, clear_box, format_date, format_size, icon_for, kind_of

TEXT_PREVIEW_LIMIT = 4 * 1024 * 1024
IMAGE_PREVIEW_LIMIT = 80 * 1024 * 1024


class FilesPage(Adw.Bin):
    def __init__(self, state, make_header):
        super().__init__()
        self.state = state
        self.search_text = ""
        self.tag_filter: str | None = None
        self.favorites_only = False
        self._items: list[tuple[str, dict]] = []

        toolbar = Adw.ToolbarView()
        header = make_header("Dosyalar")
        add_btn = Gtk.Button(icon_name="list-add-symbolic", tooltip_text="Dosya ekle (Ctrl+O)")
        add_btn.connect("clicked", lambda *_: self.present_import())
        header.pack_start(add_btn)
        add_folder_btn = Gtk.Button(icon_name="folder-new-symbolic", tooltip_text="Kasaya klasör ekle")
        add_folder_btn.connect("clicked", lambda *_: self.present_import(folders=True))
        header.pack_start(add_folder_btn)
        new_folder = Gtk.Button(icon_name="tab-new-symbolic", tooltip_text="Yeni klasör (Ctrl+Shift+N)")
        new_folder.connect("clicked", lambda *_: self.new_folder())
        header.pack_start(new_folder)

        self.search_toggle = Gtk.ToggleButton(icon_name="system-search-symbolic", tooltip_text="Ara (Ctrl+F)")
        header.pack_end(self.search_toggle)
        self.layout_btn = Gtk.Button(tooltip_text="Görünümü değiştir")
        self.layout_btn.connect("clicked", lambda *_: self._toggle_layout())
        header.pack_end(self.layout_btn)
        toolbar.add_top_bar(header)
        self.banner = Adw.Banner(button_label="Yedekle")
        toolbar.add_top_bar(self.banner)

        self.search_bar = Gtk.SearchBar()
        self.search_entry = Gtk.SearchEntry(hexpand=True)
        self.search_entry.set_property("placeholder-text", "Kasada ara")
        self.search_entry.connect("search-changed", self._on_search)
        clamp = Adw.Clamp(maximum_size=500, child=self.search_entry)
        self.search_bar.set_child(clamp)
        self.search_bar.connect_entry(self.search_entry)
        self.search_toggle.bind_property("active", self.search_bar, "search-mode-enabled",
                                         GObject.BindingFlags.BIDIRECTIONAL)
        toolbar.add_top_bar(self.search_bar)

        # Konum çubuğu + filtreler
        bar = Gtk.Box(spacing=6, margin_start=12, margin_end=12, margin_top=6, margin_bottom=6)
        self.crumbs = Gtk.Box(spacing=2, hexpand=True)
        bar.append(self.crumbs)
        self.fav_toggle = Gtk.ToggleButton(icon_name="starred-symbolic", tooltip_text="Yalnızca favoriler",
                                           css_classes=["flat"])
        self.fav_toggle.connect("toggled", self._on_fav_toggle)
        bar.append(self.fav_toggle)
        self.tag_menu_btn = Gtk.MenuButton(icon_name="mahzen-tag-symbolic", tooltip_text="Etikete göre süz",
                                           css_classes=["flat"])
        self.tag_popover = Gtk.Popover()
        self.tag_list = Gtk.ListBox(css_classes=["navigation-sidebar"], selection_mode=Gtk.SelectionMode.NONE)
        self.tag_list.connect("row-activated", lambda _l, row: self._set_tag(row.tag))
        self.tag_popover.set_child(self.tag_list)
        self.tag_menu_btn.set_popover(self.tag_popover)
        bar.append(self.tag_menu_btn)
        toolbar.add_top_bar(bar)

        # İçerik
        self.stack = Gtk.Stack(vexpand=True)
        self.empty = Adw.StatusPage(icon_name="folder-open-symbolic", title="Bu klasör boş",
                                    description="Dosyaları buraya sürükleyin ya da + düğmesiyle ekleyin.\n"
                                                "Her şey eklenirken bu bilgisayarda şifrelenir.")
        self.stack.add_named(self.empty, "empty")

        self.flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.MULTIPLE, activate_on_single_click=False,
                                homogeneous=True, min_children_per_line=2, max_children_per_line=30,
                                column_spacing=6, row_spacing=6, valign=Gtk.Align.START,
                                margin_start=12, margin_end=12, margin_top=6, margin_bottom=12)
        self.flow.connect("child-activated", lambda _f, child: self._activate(child.item))
        self.flow.connect("selected-children-changed", lambda *_: self._update_selection_bar())
        grid_scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        grid_scroller.set_child(self.flow)
        self.stack.add_named(grid_scroller, "grid")

        self.list = Gtk.ListBox(selection_mode=Gtk.SelectionMode.MULTIPLE, activate_on_single_click=False,
                                css_classes=["boxed-list"], valign=Gtk.Align.START)
        self.list.connect("row-activated", lambda _l, row: self._activate(row.item))
        self.list.connect("selected-rows-changed", lambda *_: self._update_selection_bar())
        list_clamp = Adw.Clamp(maximum_size=1100, child=self.list, margin_start=12, margin_end=12,
                               margin_top=6, margin_bottom=12)
        list_scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        list_scroller.set_child(list_clamp)
        self.stack.add_named(list_scroller, "list")

        drop = Gtk.DropTarget.new(Gdk.FileList, Gdk.DragAction.COPY)
        drop.connect("drop", self._on_drop)
        drop.connect("enter", lambda *_: (self.stack.add_css_class("drop-target"), Gdk.DragAction.COPY)[1])
        drop.connect("leave", lambda *_: self.stack.remove_css_class("drop-target"))
        self.stack.add_controller(drop)
        toolbar.set_content(self.stack)

        # Seçim çubuğu
        self.action_bar = Gtk.ActionBar(revealed=False)
        self.selection_label = Gtk.Label(css_classes=["dim-label"])
        self.action_bar.pack_start(self.selection_label)
        for icon, tip, cb in [
            ("user-trash-symbolic", "Çöp kutusuna taşı (Delete)", self.trash_selected),
            ("mahzen-tag-symbolic", "Etiketler", self.tag_selected),
            ("starred-symbolic", "Favori", self.favorite_selected),
            ("folder-symbolic", "Taşı", self.move_selected),
            ("document-save-symbolic", "Dışa aktar", self.export_selected),
        ]:
            b = Gtk.Button(icon_name=icon, tooltip_text=tip)
            b.connect("clicked", lambda *_, c=cb: c())
            self.action_bar.pack_end(b)
        toolbar.add_bottom_bar(self.action_bar)
        self.set_child(toolbar)

        keys = Gtk.EventControllerKey()
        keys.connect("key-pressed", self._on_key)
        self.add_controller(keys)

        # Görünmüyorken yeniden kurma (ör. not yazarken); bölüme geçilince zaten yenilenir.
        state.connect("index-changed", lambda *_: self.refresh() if self.get_mapped() else None)
        state.connect("prefs-changed", lambda *_: self.refresh() if self.get_mapped() else None)
        state.connect("phase-changed", lambda *_: self._clear_if_locked())

    def _clear_if_locked(self) -> None:
        """Kilitlenince dosya adları ve küçük resimler arayüzde kalmasın."""
        if self.state.phase == "unlocked":
            return
        for box in (self.flow, self.list, self.crumbs, self.tag_list):
            clear_box(box)
        self._items = []
        self.search_entry.set_text("")
        self.search_text = ""
        self.tag_filter = None
        self.favorites_only = False
        self.fav_toggle.set_active(False)
        self.search_toggle.set_active(False)
        self.stack.set_visible_child_name("empty")

    # MARK: - Görünüm

    @property
    def layout(self) -> str:
        return self.state.prefs.get("filesLayout", "grid")

    def _toggle_layout(self) -> None:
        self.state.update_prefs(filesLayout="list" if self.layout == "grid" else "grid")

    def refresh(self) -> None:
        if self.state.phase != "unlocked":
            return
        idx = self.state.index
        current = self.state.current_folder
        if current and (idx.folder(current) is None or idx.folder(current).get("deletedAt")):
            self.state.current_folder = current = None
        self.layout_btn.set_icon_name("view-list-symbolic" if self.layout == "grid" else "view-grid-symbolic")

        filtering = bool(self.search_text or self.tag_filter or self.favorites_only)
        if filtering:
            q = self.search_text.casefold()
            folders = [f for f in idx.folders if not f.get("deletedAt") and q and q in f["name"].casefold()]
            files = [f for f in idx.live_files
                     if (not q or q in f["name"].casefold() or any(q in t.casefold() for t in f.get("tags", [])))
                     and (not self.tag_filter or self.tag_filter in f.get("tags", []))
                     and (not self.favorites_only or f.get("favorite"))]
        else:
            folders = idx.child_folders(current)
            files = idx.live_files_in(current)
        files.sort(key=lambda f: sort_key(f["name"]))
        self._items = [("folder", f) for f in sorted(folders, key=lambda f: sort_key(f["name"]))] + \
                      [("file", f) for f in files]
        self._rebuild_crumbs(filtering)
        self._rebuild_tags()

        clear_box(self.flow)
        clear_box(self.list)
        if not self._items:
            if filtering:
                self.empty.set_icon_name("system-search-symbolic")
                self.empty.set_title("Sonuç yok")
                self.empty.set_description("Aramayı veya filtreleri değiştirin.")
            else:
                self.empty.set_icon_name("folder-open-symbolic")
                self.empty.set_title("Bu klasör boş" if current else "Kasa boş")
                self.empty.set_description("Dosyaları buraya sürükleyin ya da + düğmesiyle ekleyin.\n"
                                           "Her şey eklenirken bu bilgisayarda şifrelenir.")
            self.stack.set_visible_child_name("empty")
        elif self.layout == "grid":
            for item in self._items:
                self.flow.append(self._make_tile(item))
            self.stack.set_visible_child_name("grid")
        else:
            for item in self._items:
                self.list.append(self._make_row(item))
            self.stack.set_visible_child_name("list")
        self._update_selection_bar()

    def _rebuild_crumbs(self, filtering: bool) -> None:
        clear_box(self.crumbs)
        if filtering:
            parts = []
            if self.search_text:
                parts.append(f"“{self.search_text}”")
            if self.tag_filter:
                parts.append(f"#{self.tag_filter}")
            if self.favorites_only:
                parts.append("Favoriler")
            self.crumbs.append(Gtk.Label(label="Arama: " + " · ".join(parts), css_classes=["heading"]))
            return
        path = self.state.index.path_to(self.state.current_folder)
        root = Gtk.Button(label=self.state.prefs.get("displayName") or "Mahzen", css_classes=["flat"])
        root.connect("clicked", lambda *_: self.open_folder(None))
        self._add_folder_drop(root, None)
        self.crumbs.append(root)
        for f in path:
            self.crumbs.append(Gtk.Image(icon_name="go-next-symbolic", css_classes=["dim-label"]))
            b = Gtk.Button(label=f["name"], css_classes=["flat"])
            b.connect("clicked", lambda *_, fid=f["id"]: self.open_folder(fid))
            self._add_folder_drop(b, f["id"])
            self.crumbs.append(b)

    def _rebuild_tags(self) -> None:
        clear_box(self.tag_list)
        tags = self.state.index.all_tags
        self.tag_menu_btn.set_visible(bool(tags) or self.tag_filter is not None)
        if self.tag_filter:
            self.tag_menu_btn.add_css_class("accent")
        else:
            self.tag_menu_btn.remove_css_class("accent")
        for tag in [None, *tags]:
            row = Gtk.ListBoxRow()
            label = Gtk.Label(label="Tüm dosyalar" if tag is None else f"#{tag}", xalign=0,
                              margin_start=6, margin_end=6)
            if tag == self.tag_filter:
                label.add_css_class("heading")
            row.set_child(label)
            row.tag = tag
            self.tag_list.append(row)

    def _set_tag(self, tag) -> None:
        self.tag_filter = tag
        self.tag_popover.popdown()
        self.refresh()

    def _on_fav_toggle(self, button) -> None:
        self.favorites_only = button.get_active()
        self.refresh()

    def _on_search(self, entry) -> None:
        self.search_text = entry.get_text().strip()
        self.refresh()

    def focus_search(self) -> None:
        self.search_toggle.set_active(True)
        self.search_entry.grab_focus()

    # MARK: - Öğeler

    def _thumb_widget(self, kind: str, record: dict, width: int, height: int) -> Gtk.Widget:
        """Sabit boyutlu küçük resim alanı. Resim üst katmanda durur; böylece boyutu ölçüme katılmaz."""
        icon_size = min(width, height) // 2
        if kind == "folder":
            icon = Gtk.Image(icon_name="folder-symbolic", pixel_size=icon_size, css_classes=["folder-icon"])
        else:
            icon = Gtk.Image(icon_name=icon_for(record), pixel_size=icon_size, css_classes=["dim-label"])
        holder = Gtk.Overlay(width_request=width, height_request=height, overflow=Gtk.Overflow.HIDDEN,
                             css_classes=["tile-frame"])
        holder.set_child(icon)
        if kind == "file" and record.get("hasThumbnail"):
            picture = Gtk.Picture(content_fit=Gtk.ContentFit.COVER, can_shrink=True, css_classes=["thumb"])
            holder.add_overlay(picture)
            holder.set_clip_overlay(picture, True)

            def got(texture):
                if texture is not None:
                    picture.set_paintable(texture)
                    icon.set_visible(False)

            self.state.thumbnail(record, got)
        return holder

    def _make_tile(self, item) -> Gtk.FlowBoxChild:
        kind, record = item
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, margin_top=6, margin_bottom=6,
                      margin_start=6, margin_end=6)
        frame = self._thumb_widget(kind, record, 132, 100)
        if kind == "file" and record.get("favorite"):
            star = Gtk.Image(icon_name="starred-symbolic", halign=Gtk.Align.END, valign=Gtk.Align.START,
                             margin_top=4, margin_end=4, css_classes=["favorite-star"])
            frame.add_overlay(star)
        box.append(frame)
        name = Gtk.Label(label=record["name"], ellipsize=Pango.EllipsizeMode.MIDDLE, max_width_chars=16,
                         lines=2, wrap=True, wrap_mode=Pango.WrapMode.WORD_CHAR, justify=Gtk.Justification.CENTER)
        box.append(name)
        detail = (f"{self.state.index.live_file_count_in_tree(record['id'])} dosya" if kind == "folder"
                  else format_size(int(record.get("size", 0))))
        box.append(Gtk.Label(label=detail, css_classes=["caption", "dim-label"]))
        child = Gtk.FlowBoxChild(child=box, tooltip_text=record["name"])
        child.item = item
        self._attach_menu(child, item)
        if kind == "folder":
            self._add_folder_drop(child, record["id"])
        self._add_drag_source(child, item)
        return child

    def _make_row(self, item) -> Gtk.ListBoxRow:
        kind, record = item
        row = Adw.ActionRow(title=GLib.markup_escape_text(record["name"]), activatable=True)
        thumb = self._thumb_widget(kind, record, 40, 40)
        thumb.set_valign(Gtk.Align.CENTER)
        row.add_prefix(thumb)
        if kind == "folder":
            row.set_subtitle(f"{self.state.index.live_file_count_in_tree(record['id'])} dosya")
            row.add_suffix(Gtk.Image(icon_name="go-next-symbolic"))
            self._add_folder_drop(row, record["id"])
        else:
            tags = " ".join(f"#{t}" for t in record.get("tags", []))
            row.set_subtitle(GLib.markup_escape_text(" · ".join(
                x for x in [format_size(int(record.get("size", 0))), format_date(record.get("addedAt")), tags] if x)))
            if record.get("favorite"):
                row.add_suffix(Gtk.Image(icon_name="starred-symbolic", css_classes=["favorite-star"]))
        row.item = item
        self._attach_menu(row, item)
        self._add_drag_source(row, item)
        return row

    def _activate(self, item) -> None:
        kind, record = item
        if kind == "folder":
            self.open_folder(record["id"])
        else:
            self.preview(record)

    def open_folder(self, fid) -> None:
        self.state.current_folder = fid
        if self.search_text or self.tag_filter or self.favorites_only:
            self.search_entry.set_text("")
            self.search_text = ""
            self.tag_filter = None
            self.fav_toggle.set_active(False)
            self.favorites_only = False
            self.search_toggle.set_active(False)
        self.refresh()

    # MARK: - Seçim

    def selected(self) -> list[tuple[str, dict]]:
        if self.layout == "grid":
            return [c.item for c in self.flow.get_selected_children()]
        return [r.item for r in self.list.get_selected_rows()]

    def _selected_file_ids(self) -> set[str]:
        return {r["id"] for k, r in self.selected() if k == "file"}

    def _update_selection_bar(self) -> None:
        items = self.selected()
        self.action_bar.set_revealed(bool(items))
        files = sum(1 for k, _ in items if k == "file")
        folders = len(items) - files
        parts = []
        if files:
            parts.append(f"{files} dosya")
        if folders:
            parts.append(f"{folders} klasör")
        self.selection_label.set_text(", ".join(parts) + " seçili" if parts else "")

    def _select_only(self, widget) -> None:
        if isinstance(widget, Gtk.FlowBoxChild):
            if not widget.is_selected():
                self.flow.unselect_all()
                self.flow.select_child(widget)
        elif isinstance(widget, Gtk.ListBoxRow):
            if not widget.is_selected():
                self.list.unselect_all()
                self.list.select_row(widget)

    # MARK: - Bağlam menüsü

    def _attach_menu(self, widget, item) -> None:
        kind, record = item
        menu = Gio.Menu()
        if kind == "folder":
            menu.append("Aç", "item.open")
            menu.append("Yeniden Adlandır…", "item.rename")
            menu.append("Taşı…", "item.move")
            section = Gio.Menu()
            section.append("Çöp Kutusuna Taşı", "item.trash")
            menu.append_section(None, section)
        else:
            menu.append("Önizle", "item.open")
            menu.append("Geçici Olarak Aç", "item.open-temp")
            menu.append("Dışa Aktar…", "item.export")
            section = Gio.Menu()
            section.append("Yeniden Adlandır…", "item.rename")
            section.append("Favori", "item.favorite")
            section.append("Etiketler…", "item.tags")
            section.append("Taşı…", "item.move")
            menu.append_section(None, section)
            trash = Gio.Menu()
            trash.append("Çöp Kutusuna Taşı", "item.trash")
            menu.append_section(None, trash)

        group = Gio.SimpleActionGroup()
        actions = {
            "open": lambda: self._activate(item),
            "open-temp": lambda: self.open_temporarily(record),
            "export": self.export_selected,
            "rename": lambda: self.rename(item),
            "favorite": self.favorite_selected,
            "tags": self.tag_selected,
            "move": self.move_selected,
            "trash": self.trash_selected,
        }
        for name, cb in actions.items():
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", lambda *_, c=cb: c())
            group.add_action(action)
        widget.insert_action_group("item", group)

        popover = Gtk.PopoverMenu(menu_model=menu, has_arrow=False, halign=Gtk.Align.START)
        popover.set_parent(widget)
        widget.connect("destroy", lambda *_: popover.unparent())

        def pressed(gesture, _n, x, y):
            gesture.set_state(Gtk.EventSequenceState.CLAIMED)
            self._select_only(widget)
            rect = Gdk.Rectangle()
            rect.x, rect.y, rect.width, rect.height = int(x), int(y), 1, 1
            popover.set_pointing_to(rect)
            popover.popup()

        click = Gtk.GestureClick(button=3)
        click.connect("pressed", pressed)
        widget.add_controller(click)
        long_press = Gtk.GestureLongPress(touch_only=True)
        long_press.connect("pressed", lambda g, x, y: pressed(g, 1, x, y))
        widget.add_controller(long_press)

    # MARK: - Sürükle-bırak (kasa içinde taşıma)

    def _add_drag_source(self, widget, item) -> None:
        source = Gtk.DragSource(actions=Gdk.DragAction.MOVE)

        def prepare(_src, _x, _y):
            self._select_only(widget)
            ids = [f"{k}:{r['id']}" for k, r in self.selected()] or [f"{item[0]}:{item[1]['id']}"]
            return Gdk.ContentProvider.new_for_value("mahzen-items\n" + "\n".join(ids))

        source.connect("prepare", prepare)
        widget.add_controller(source)

    def _add_folder_drop(self, widget, folder_id) -> None:
        target = Gtk.DropTarget.new(str, Gdk.DragAction.MOVE)

        def on_drop(_t, value, _x, _y):
            if not isinstance(value, str) or not value.startswith("mahzen-items\n"):
                return False
            self._move_items(value.split("\n")[1:], folder_id)
            return True

        target.connect("drop", on_drop)
        widget.add_controller(target)

    def _move_items(self, keys: list[str], folder_id) -> None:
        file_ids = {k.split(":", 1)[1] for k in keys if k.startswith("file:")}
        folder_ids = [k.split(":", 1)[1] for k in keys if k.startswith("folder:")]
        failed = []

        def body(idx):
            if file_ids:
                idx.move_files(file_ids, folder_id)
            for fid in folder_ids:
                if fid != folder_id and not idx.move_folder(fid, folder_id):
                    failed.append(fid)

        self.state.mutate(body)
        if failed:
            alert(self, "Taşınamadı", "Bir klasör kendi içine taşınamaz.")
        else:
            target = self.state.index.folder(folder_id)
            self.state.toast(f"Taşındı: {target['name'] if target else self.state.prefs.get('displayName', 'Mahzen')}")

    # MARK: - İşlemler

    def _on_key(self, _ctrl, keyval, _code, mods) -> bool:
        if keyval == Gdk.KEY_Delete and self.selected():
            self.trash_selected()
            return True
        if keyval == Gdk.KEY_BackSpace and mods & Gdk.ModifierType.ALT_MASK:
            self.go_up()
            return True
        return False

    def go_up(self) -> None:
        current = self.state.index.folder(self.state.current_folder)
        if current:
            self.open_folder(current.get("parentID"))

    def _on_drop(self, _target, value, _x, _y) -> bool:
        self.stack.remove_css_class("drop-target")
        files = value.get_files() if hasattr(value, "get_files") else []
        local = [f.get_path() for f in files if f.get_path()]
        if not local:
            return False
        self.state.import_files(local, self.state.current_folder)
        return True

    def present_import(self, folders: bool = False) -> None:
        if self.state.task:
            return
        dialog = Gtk.FileDialog(title="Kasaya eklenecek klasörleri seç" if folders else
                                "Kasaya eklenecek dosyaları seç", accept_label="Şifrele ve Ekle", modal=True)
        target = self.state.current_folder

        def done(d, result):
            try:
                chosen = d.select_multiple_folders_finish(result) if folders else d.open_multiple_finish(result)
            except GLib.Error:
                return
            local = [chosen.get_item(i).get_path() for i in range(chosen.get_n_items())]
            local = [p for p in local if p]
            if local:
                self.state.import_files(local, target)

        if folders:
            dialog.select_multiple_folders(self.get_root(), None, done)
        else:
            dialog.open_multiple(self.get_root(), None, done)

    def new_folder(self) -> None:
        def create(name):
            result = {}
            self.state.mutate(lambda idx: result.update(id=idx.create_folder(name, self.state.current_folder)))
        ask_text(self, "Yeni klasör", "Yeni Klasör", "Oluştur", create)

    def rename(self, item) -> None:
        kind, record = item
        if kind == "folder":
            ask_text(self, "Klasörü yeniden adlandır", record["name"], "Yeniden Adlandır",
                     lambda name: self.state.mutate(lambda idx: idx.rename_folder(record["id"], name)))
        else:
            ask_text(self, "Dosyayı yeniden adlandır", record["name"], "Yeniden Adlandır",
                     lambda name: self.state.rename_file(record["id"], name))

    def trash_selected(self) -> None:
        items = self.selected()
        files = {r["id"] for k, r in items if k == "file"}
        for k, r in items:
            if k == "folder":
                self.state.trash_folder(r["id"])
        if files:
            self.state.trash_files(files)

    def favorite_selected(self) -> None:
        ids = self._selected_file_ids()
        if ids:
            self.state.toggle_favorite(ids)

    def tag_selected(self) -> None:
        ids = self._selected_file_ids()
        if not ids:
            return
        current = sorted({t for f in self.state.index.files if f["id"] in ids for t in f.get("tags", [])})
        ask_text(self, "Etiketler", ", ".join(current), "Kaydet",
                 lambda text: self.state.mutate(lambda idx: idx.set_tags(text.split(","), ids)),
                 body="Etiketleri virgülle ayırın. Hepsini silmek için alanı boşaltıp kaydedin.")

    def move_selected(self) -> None:
        items = self.selected()
        if not items:
            return
        moving_folders = {r["id"] for k, r in items if k == "folder"}
        blocked = set(moving_folders)
        for fid in moving_folders:
            blocked |= {x for x in self.state.index.descendant_folder_ids(fid)}
        blocked = {b.upper() for b in blocked}

        dialog = Adw.AlertDialog(heading="Taşı", body="Hedef klasörü seçin.")
        listbox = Gtk.ListBox(css_classes=["boxed-list"], selection_mode=Gtk.SelectionMode.SINGLE)
        rows = []

        def add(folder, depth):
            label = folder["name"] if folder else (self.state.prefs.get("displayName") or "Mahzen")
            row = Gtk.ListBoxRow()
            box = Gtk.Box(spacing=8, margin_start=12 + depth * 18, margin_end=12, margin_top=8, margin_bottom=8)
            box.append(Gtk.Image(icon_name="folder-symbolic" if folder else "drive-harddisk-symbolic"))
            box.append(Gtk.Label(label=label, xalign=0))
            row.set_child(box)
            row.target = folder["id"] if folder else None
            listbox.append(row)
            rows.append(row)
            for child in self.state.index.child_folders(folder["id"] if folder else None):
                if child["id"].upper() not in blocked:
                    add(child, depth + 1)

        add(None, 0)
        scroller = Gtk.ScrolledWindow(min_content_height=240, max_content_height=360, propagate_natural_height=True)
        scroller.set_child(listbox)
        dialog.set_extra_child(scroller)
        dialog.add_response("cancel", "Vazgeç")
        dialog.add_response("ok", "Taşı")
        dialog.set_response_appearance("ok", Adw.ResponseAppearance.SUGGESTED)
        dialog.set_close_response("cancel")

        def on_response(_d, response):
            row = listbox.get_selected_row()
            if response == "ok" and row is not None:
                self._move_items([f"{k}:{r['id']}" for k, r in items], row.target)

        dialog.connect("response", on_response)
        dialog.present(self)

    def export_selected(self) -> None:
        records = [r for k, r in self.selected() if k == "file"]
        if not records:
            return
        dialog = Gtk.FileDialog(title="Şifresi çözülmüş kopyaların kaydedileceği klasör", accept_label="Dışa Aktar",
                                modal=True)

        def done(d, result):
            try:
                folder = d.select_folder_finish(result)
            except GLib.Error:
                return
            if folder and folder.get_path():
                self.state.export_files(records, folder.get_path())

        dialog.select_folder(self.get_root(), None, done)

    def open_temporarily(self, record: dict) -> None:
        if self.state.settings.get("tempOpenWarned"):
            self.state.open_temporarily(record)
            return
        dialog = Adw.AlertDialog(
            heading="Dosya geçici olarak açılsın mı?",
            body="Dosyanın şifresiz bir kopyası oturumun geçici klasörüne yazılır ve kasa kilitlenince ya da "
                 "uygulama kapanınca silinir. Açan uygulama kendi önbelleğinde iz bırakabilir.")
        check = Gtk.CheckButton(label="Bir daha sorma")
        dialog.set_extra_child(check)
        dialog.add_response("cancel", "Vazgeç")
        dialog.add_response("ok", "Aç")
        dialog.set_response_appearance("ok", Adw.ResponseAppearance.SUGGESTED)
        dialog.set_close_response("cancel")

        def on_response(_d, response):
            if response != "ok":
                return
            if check.get_active():
                self.state._remember(tempOpenWarned=True)
            self.state.open_temporarily(record)

        dialog.connect("response", on_response)
        dialog.present(self)

    # MARK: - Önizleme

    def preview(self, record: dict) -> None:
        PreviewDialog(self, record).present(self)


class PreviewDialog(Adw.Dialog):
    def __init__(self, page: FilesPage, record: dict):
        super().__init__(title=record["name"], content_width=820, content_height=620)
        self.page = page
        self.state = page.state
        self.record = record

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        open_btn = Gtk.Button(icon_name="document-open-symbolic", tooltip_text="Geçici olarak aç")
        open_btn.connect("clicked", lambda *_: (self.close(), page.open_temporarily(record)))
        header.pack_start(open_btn)
        export_btn = Gtk.Button(icon_name="document-save-symbolic", tooltip_text="Dışa aktar")
        export_btn.connect("clicked", lambda *_: self._export())
        header.pack_start(export_btn)
        toolbar.add_top_bar(header)

        self.stack = Gtk.Stack()
        spinner = Gtk.Spinner(spinning=True, width_request=32, height_request=32,
                              halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER)
        self.stack.add_named(spinner, "loading")
        toolbar.set_content(self.stack)

        info = " · ".join(x for x in [format_size(int(record.get("size", 0))),
                                      "Eklendi: " + format_date(record.get("addedAt")),
                                      " ".join(f"#{t}" for t in record.get("tags", []))] if x)
        footer = Gtk.Label(label=info, css_classes=["caption", "dim-label"], margin_top=6, margin_bottom=6,
                           ellipsize=Pango.EllipsizeMode.END)
        toolbar.add_bottom_bar(footer)
        self.set_child(toolbar)
        # Kilitte çözülmüş içerik ekranda kalmasın.
        handler = self.state.connect("phase-changed", lambda *_: self.force_close())
        self.connect("closed", lambda *_: self.state.disconnect(handler))

        kind = kind_of(record)
        size = int(record.get("size", 0))
        if kind == "image" and size <= IMAGE_PREVIEW_LIMIT:
            self.state.read_file(record, self._show_image)
        elif kind == "text" and size <= TEXT_PREVIEW_LIMIT:
            self.state.read_file(record, self._show_text)
        else:
            self._show_fallback()

    def _show_image(self, data, error) -> None:
        if error or data is None:
            self._show_error(error)
            return
        try:
            texture = Gdk.Texture.new_from_bytes(GLib.Bytes.new(data))
        except GLib.Error:
            self._show_fallback("Bu görsel biçimi önizlenemiyor.")
            return
        picture = Gtk.Picture(paintable=texture, content_fit=Gtk.ContentFit.CONTAIN, can_shrink=True)
        self.stack.add_named(picture, "content")
        self.stack.set_visible_child_name("content")

    def _show_text(self, data, error) -> None:
        if error or data is None:
            self._show_error(error)
            return
        text = data.decode("utf-8", errors="replace")
        view = Gtk.TextView(editable=False, monospace=True, wrap_mode=Gtk.WrapMode.WORD_CHAR,
                            top_margin=12, bottom_margin=12, left_margin=12, right_margin=12, cursor_visible=False)
        view.get_buffer().set_text(text)
        scroller = Gtk.ScrolledWindow(child=view)
        self.stack.add_named(scroller, "content")
        self.stack.set_visible_child_name("content")

    def _show_fallback(self, message: str | None = None) -> None:
        status = Adw.StatusPage(
            icon_name=icon_for(self.record), title=self.record["name"],
            description=message or "Bu dosya türü uygulama içinde önizlenemiyor.\n"
                                   "Geçici olarak açabilir ya da dışa aktarabilirsiniz.")
        button = Gtk.Button(label="Geçici Olarak Aç", css_classes=["pill", "suggested-action"],
                            halign=Gtk.Align.CENTER)
        button.connect("clicked", lambda *_: (self.close(), self.page.open_temporarily(self.record)))
        status.set_child(button)
        self.stack.add_named(status, "content")
        self.stack.set_visible_child_name("content")

    def _show_error(self, error) -> None:
        status = Adw.StatusPage(icon_name="dialog-error-symbolic", title="Dosya çözülemedi",
                                description=str(error) if error else "")
        self.stack.add_named(status, "content")
        self.stack.set_visible_child_name("content")

    def _export(self) -> None:
        self.close()
        dialog = Gtk.FileDialog(title="Şifresi çözülmüş kopyanın kaydedileceği klasör", accept_label="Dışa Aktar",
                                modal=True)

        def done(d, result):
            try:
                folder = d.select_folder_finish(result)
            except GLib.Error:
                return
            if folder and folder.get_path():
                self.state.export_files([self.record], folder.get_path())

        dialog.select_folder(self.page.get_root(), None, done)

