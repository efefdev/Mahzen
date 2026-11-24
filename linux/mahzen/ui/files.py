"""Dosyalar: klasörler, ızgara/liste görünümü, arama, etiketler, önizleme, ekleme ve dışa aktarma."""

from __future__ import annotations

from gi.repository import Adw, Gdk, Gio, GLib, GObject, Gtk, Pango

from ..core import selection as sel
from ..core.index import sort_key
from ..core.phoneshare import is_shareable
from ..i18n import tr
from .common import (alert, ask_text, clear_box, fill_rect, format_date, format_size, icon_for, kind_of, rgba,
                     widget_bounds, widget_point)
from .phoneshare import PhoneShareDialog

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
        header = make_header(tr("Dosyalar"))
        add_btn = Gtk.Button(icon_name="list-add-symbolic", tooltip_text=tr("Dosya ekle (Ctrl+O)"))
        add_btn.connect("clicked", lambda *_: self.present_import())
        header.pack_start(add_btn)
        add_folder_btn = Gtk.Button(icon_name="folder-new-symbolic", tooltip_text=tr("Kasaya klasör ekle"))
        add_folder_btn.connect("clicked", lambda *_: self.present_import(folders=True))
        header.pack_start(add_folder_btn)
        new_folder = Gtk.Button(icon_name="tab-new-symbolic", tooltip_text=tr("Yeni klasör (Ctrl+Shift+N)"))
        new_folder.connect("clicked", lambda *_: self.new_folder())
        header.pack_start(new_folder)

        self.search_toggle = Gtk.ToggleButton(icon_name="system-search-symbolic", tooltip_text=tr("Ara (Ctrl+F)"))
        header.pack_end(self.search_toggle)
        self.layout_btn = Gtk.Button(tooltip_text=tr("Görünümü değiştir"))
        self.layout_btn.connect("clicked", lambda *_: self._toggle_layout())
        header.pack_end(self.layout_btn)
        toolbar.add_top_bar(header)
        self.banner = Adw.Banner(button_label=tr("Yedekle"))
        toolbar.add_top_bar(self.banner)

        self.search_bar = Gtk.SearchBar()
        self.search_entry = Gtk.SearchEntry(hexpand=True)
        self.search_entry.set_property("placeholder-text", tr("Kasada ara"))
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
        self.fav_toggle = Gtk.ToggleButton(icon_name="starred-symbolic", tooltip_text=tr("Yalnızca favoriler"),
                                           css_classes=["flat"])
        self.fav_toggle.connect("toggled", self._on_fav_toggle)
        bar.append(self.fav_toggle)
        self.tag_menu_btn = Gtk.MenuButton(icon_name="mahzen-tag-symbolic", tooltip_text=tr("Etikete göre süz"),
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
        self.empty = Adw.StatusPage(icon_name="folder-open-symbolic", title=tr("Bu klasör boş"),
                                    description=tr("Dosyaları buraya sürükleyin ya da + düğmesiyle ekleyin.\n"
                                                   "Her şey eklenirken bu bilgisayarda şifrelenir."))
        self.stack.add_named(self.empty, "empty")

        self.flow = Gtk.FlowBox(selection_mode=Gtk.SelectionMode.MULTIPLE, activate_on_single_click=False,
                                homogeneous=True, min_children_per_line=2, max_children_per_line=30,
                                column_spacing=6, row_spacing=6, valign=Gtk.Align.START,
                                margin_start=12, margin_end=12, margin_top=6, margin_bottom=12)
        self.flow.connect("child-activated", lambda _f, child: self._activate(child.item))
        self.flow.connect("selected-children-changed", lambda *_: self._update_selection_bar())
        self.grid_scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER)
        # Boş alandan sürükleyerek dikdörtgenle seçim: ızgaranın üstünde, tıklamaları geçiren bir çizim katmanı.
        self.grid_overlay = Gtk.Overlay(vexpand=True)
        self.grid_overlay.set_child(self.flow)
        self.band = MarqueeBand(self)
        self.grid_overlay.add_overlay(self.band)
        self.grid_scroller.set_child(self.grid_overlay)
        self.stack.add_named(self.grid_scroller, "grid")
        self._marquee = None
        drag = Gtk.GestureDrag(propagation_phase=Gtk.PropagationPhase.CAPTURE)
        drag.connect("drag-begin", self._marquee_begin)
        drag.connect("drag-update", self._marquee_update)
        drag.connect("drag-end", self._marquee_end)
        self.grid_overlay.add_controller(drag)

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
            ("user-trash-symbolic", tr("Çöp kutusuna taşı (Delete)"), self.trash_selected),
            ("mahzen-tag-symbolic", tr("Etiketler"), self.tag_selected),
            ("starred-symbolic", tr("Favori"), self.favorite_selected),
            ("folder-symbolic", tr("Taşı"), self.move_selected),
            ("document-save-symbolic", tr("Dışa aktar"), self.export_selected),
        ]:
            b = Gtk.Button(icon_name=icon, tooltip_text=tip)
            b.connect("clicked", lambda *_, c=cb: c())
            self.action_bar.pack_end(b)
        self.phone_btn = Gtk.Button(icon_name="phone-symbolic", tooltip_text=tr("Telefonda göster"))
        self.phone_btn.connect("clicked", lambda *_: self.show_on_phone())
        self.action_bar.pack_end(self.phone_btn)
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
                self.empty.set_title(tr("Sonuç yok"))
                self.empty.set_description(tr("Aramayı veya filtreleri değiştirin."))
            else:
                self.empty.set_icon_name("folder-open-symbolic")
                self.empty.set_title(tr("Bu klasör boş") if current else tr("Kasa boş"))
                self.empty.set_description(tr("Dosyaları buraya sürükleyin ya da + düğmesiyle ekleyin.\n"
                                              "Her şey eklenirken bu bilgisayarda şifrelenir."))
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
                parts.append(tr("Favoriler"))
            self.crumbs.append(Gtk.Label(label=tr("Arama: {query}", query=" · ".join(parts)), css_classes=["heading"]))
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
            label = Gtk.Label(label=tr("Tüm dosyalar") if tag is None else f"#{tag}", xalign=0,
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
        detail = (tr("{n} dosya", n=self.state.index.live_file_count_in_tree(record["id"])) if kind == "folder"
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
            row.set_subtitle(tr("{n} dosya", n=self.state.index.live_file_count_in_tree(record["id"])))
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
            parts.append(tr("{n} dosya", n=files))
        if folders:
            parts.append(tr("{n} klasör", n=folders))
        self.selection_label.set_text(tr("{items} seçili", items=", ".join(parts)) if parts else "")
        self.phone_btn.set_visible(any(k == "file" and is_shareable(r) for k, r in items)
                                   or (not files and folders == 1))

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
            menu.append(tr("Aç"), "item.open")
            menu.append(tr("Yeniden Adlandır…"), "item.rename")
            menu.append(tr("Taşı…"), "item.move")
            menu.append(tr("Dışa Aktar…"), "item.export")
            menu.append(tr("Telefonda Göster…"), "item.phone")
            section = Gio.Menu()
            section.append(tr("Çöp Kutusuna Taşı"), "item.trash")
            menu.append_section(None, section)
        else:
            menu.append(tr("Önizle"), "item.open")
            menu.append(tr("Geçici Olarak Aç"), "item.open-temp")
            menu.append(tr("Dışa Aktar…"), "item.export")
            if is_shareable(record):
                menu.append(tr("Telefonda Göster…"), "item.phone")
            section = Gio.Menu()
            section.append(tr("Yeniden Adlandır…"), "item.rename")
            section.append(tr("Favori"), "item.favorite")
            section.append(tr("Etiketler…"), "item.tags")
            section.append(tr("Taşı…"), "item.move")
            menu.append_section(None, section)
            trash = Gio.Menu()
            trash.append(tr("Çöp Kutusuna Taşı"), "item.trash")
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
            "phone": lambda: self.show_on_phone(item),
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
            alert(self, tr("Taşınamadı"), tr("Bir klasör kendi içine taşınamaz."))
        else:
            target = self.state.index.folder(folder_id)
            self.state.toast(tr("Taşındı: {name}",
                                name=target["name"] if target else self.state.prefs.get("displayName", "Mahzen")))

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
        dialog = Gtk.FileDialog(title=tr("Kasaya eklenecek klasörleri seç") if folders else
                                tr("Kasaya eklenecek dosyaları seç"), accept_label=tr("Şifrele ve Ekle"), modal=True)
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
        ask_text(self, tr("Yeni klasör"), tr("Yeni Klasör"), tr("Oluştur"), create)

    def rename(self, item) -> None:
        kind, record = item
        if kind == "folder":
            ask_text(self, tr("Klasörü yeniden adlandır"), record["name"], tr("Yeniden Adlandır"),
                     lambda name: self.state.mutate(lambda idx: idx.rename_folder(record["id"], name)))
        else:
            ask_text(self, tr("Dosyayı yeniden adlandır"), record["name"], tr("Yeniden Adlandır"),
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
        ask_text(self, tr("Etiketler"), ", ".join(current), tr("Kaydet"),
                 lambda text: self.state.mutate(lambda idx: idx.set_tags(text.split(","), ids)),
                 body=tr("Etiketleri virgülle ayırın. Hepsini silmek için alanı boşaltıp kaydedin."))

    def move_selected(self) -> None:
        items = self.selected()
        if not items:
            return
        moving_folders = {r["id"] for k, r in items if k == "folder"}
        blocked = set(moving_folders)
        for fid in moving_folders:
            blocked |= {x for x in self.state.index.descendant_folder_ids(fid)}
        blocked = {b.upper() for b in blocked}

        dialog = Adw.AlertDialog(heading=tr("Taşı"), body=tr("Hedef klasörü seçin."))
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
        dialog.add_response("cancel", tr("Vazgeç"))
        dialog.add_response("ok", tr("Taşı"))
        dialog.set_response_appearance("ok", Adw.ResponseAppearance.SUGGESTED)
        dialog.set_close_response("cancel")

        def on_response(_d, response):
            row = listbox.get_selected_row()
            if response == "ok" and row is not None:
                self._move_items([f"{k}:{r['id']}" for k, r in items], row.target)

        dialog.connect("response", on_response)
        dialog.present(self)

    def export_selected(self) -> None:
        items = self.selected()
        file_ids = {r["id"] for k, r in items if k == "file"}
        folder_ids = {r["id"] for k, r in items if k == "folder"}
        if not file_ids and not folder_ids:
            return
        dialog = Gtk.FileDialog(title=tr("Şifresi çözülmüş kopyaların kaydedileceği klasör"),
                                accept_label=tr("Dışa Aktar"), modal=True)

        def done(d, result):
            try:
                folder = d.select_folder_finish(result)
            except GLib.Error:
                return
            if folder and folder.get_path():
                self.state.export_items(file_ids, folder_ids, folder.get_path())

        dialog.select_folder(self.get_root(), None, done)

    def show_on_phone(self, item=None) -> None:
        """Seçili fotoğraf/videoları ya da tek bir klasörü (alt klasörleriyle) telefonda gösterir."""
        items = self.selected() or ([item] if item else [])
        if item and (item not in items or item[0] == "folder"):
            items = [item]  # bir klasörün menüsünden: o klasör
        files = [r for k, r in items if k == "file"]
        folders = [r for k, r in items if k == "folder"]
        if files:
            session = self.state.show_files_on_phone(files)
        elif len(folders) == 1:
            session = self.state.show_folder_on_phone(folders[0])
        else:
            return
        if session is not None:
            PhoneShareDialog(self.state, session).present(self)

    def open_temporarily(self, record: dict) -> None:
        if self.state.settings.get("tempOpenWarned"):
            self.state.open_temporarily(record)
            return
        dialog = Adw.AlertDialog(
            heading=tr("Dosya geçici olarak açılsın mı?"),
            body=tr("Dosyanın şifresiz bir kopyası oturumun geçici klasörüne yazılır ve kasa kilitlenince ya da "
                    "uygulama kapanınca silinir. Açan uygulama kendi önbelleğinde iz bırakabilir."))
        check = Gtk.CheckButton(label=tr("Bir daha sorma"))
        dialog.set_extra_child(check)
        dialog.add_response("cancel", tr("Vazgeç"))
        dialog.add_response("ok", tr("Aç"))
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
        siblings = [r for k, r in self._items if k == "file"]
        PreviewDialog(self, record, siblings).present(self)

    # MARK: - Dikdörtgenle seçim

    def _flow_point(self, x: float, y: float) -> tuple[int, int]:
        point = widget_point(self.grid_overlay, self.flow, x, y) or (x, y)
        return int(point[0]), int(point[1])

    def _tile_frames(self) -> dict:
        frames = {}
        child = self.flow.get_first_child()
        while child is not None:
            if isinstance(child, Gtk.FlowBoxChild) and child.get_visible():
                bounds = widget_bounds(child, self.grid_overlay)
                if bounds is not None:
                    frames[child] = bounds
            child = child.get_next_sibling()
        return frames

    def _marquee_begin(self, gesture, x: float, y: float) -> None:
        """Boş alandan başlayan sürükleme. Bir öğenin üstünden başlarsa öğeye bırakılır (taşıma, seçim)."""
        event = gesture.get_current_event()
        device = event.get_device() if event else None
        touch = device is not None and device.get_source() == Gdk.InputSource.TOUCHSCREEN
        if touch or self.flow.get_child_at_pos(*self._flow_point(x, y)) is not None:
            gesture.set_state(Gtk.EventSequenceState.DENIED)
            self._marquee = None
            return
        mods = gesture.get_current_event_state()
        additive = bool(mods & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK))
        self._marquee = {
            "start": (x, y), "current": (x, y), "active": False, "additive": additive,
            "base": set(self.flow.get_selected_children()) if additive else set(),
            "pointer_y": y - self.grid_scroller.get_vadjustment().get_value(), "timer": 0, "speed": 0.0,
            "rect": None,
        }

    def _marquee_update(self, gesture, dx: float, dy: float) -> None:
        m = self._marquee
        if m is None:
            return
        if not m["active"]:
            if (dx * dx + dy * dy) ** 0.5 < sel.MARQUEE_THRESHOLD:
                return
            m["active"] = True
            gesture.set_state(Gtk.EventSequenceState.CLAIMED)
            self.flow.grab_focus()
        vadj = self.grid_scroller.get_vadjustment()
        m["current"] = (m["start"][0] + dx, m["start"][1] + dy)
        m["pointer_y"] = m["current"][1] - vadj.get_value()
        self._marquee_refresh()
        # İmleç görünür alanın kenarına yaklaştıkça hızlanarak kaydır.
        m["speed"] = sel.autoscroll_speed(m["pointer_y"], vadj.get_page_size())
        if m["speed"] and not m["timer"]:
            m["timer"] = GLib.timeout_add(16, self._marquee_tick)

    def _marquee_tick(self) -> bool:
        m = self._marquee
        if m is None or not m["speed"]:
            if m is not None:
                m["timer"] = 0
            return False
        vadj = self.grid_scroller.get_vadjustment()
        old = vadj.get_value()
        new = min(vadj.get_upper() - vadj.get_page_size(), max(vadj.get_lower(), old + m["speed"]))
        if new != old:
            vadj.set_value(new)
            m["current"] = (m["current"][0], m["pointer_y"] + new)
            self._marquee_refresh()
        return True

    def _marquee_refresh(self) -> None:
        m = self._marquee
        rect = sel.rect_from_points(m["start"], m["current"])
        m["rect"] = rect
        target = sel.marquee_selection(m["base"], self._tile_frames(), rect)
        child = self.flow.get_first_child()
        while child is not None:
            if isinstance(child, Gtk.FlowBoxChild):
                wanted = child in target
                if wanted != child.is_selected():
                    (self.flow.select_child if wanted else self.flow.unselect_child)(child)
            child = child.get_next_sibling()
        self.band.queue_draw()

    def _marquee_end(self, _gesture, _dx: float, _dy: float) -> None:
        m, self._marquee = self._marquee, None
        if m is None:
            return
        if m["timer"]:
            GLib.source_remove(m["timer"])
        if not m["active"] and not m["additive"]:
            # Boş alana tıklamak seçimi temizler.
            self.flow.unselect_all()
        self.band.queue_draw()

    def _accent_rgba(self) -> Gdk.RGBA:
        try:
            ok, color = self.band.get_style_context().lookup_color("accent_bg_color")
            if ok:
                return color
        except (AttributeError, TypeError):
            pass
        try:
            return Adw.StyleManager.get_default().get_accent_color_rgba()
        except AttributeError:
            color = Gdk.RGBA()
            color.parse("#3584e4")
            return color

    def snapshot_band(self, snapshot) -> None:
        m = self._marquee
        if m is None or not m["active"] or not m["rect"]:
            return
        x, y, w, h = m["rect"]
        c = self._accent_rgba()
        fill_rect(snapshot, x, y, w, h, rgba(c.red, c.green, c.blue, 0.12))
        edge = rgba(c.red, c.green, c.blue, 0.75)
        for rect in ((x, y, w, 1), (x, y + h - 1, w, 1), (x, y, 1, h), (x + w - 1, y, 1, h)):
            fill_rect(snapshot, *rect, edge)


class MarqueeBand(Gtk.Widget):
    """Izgaranın üstündeki seçim dikdörtgeni katmanı. Tıklamaları geçirir; cairo köprüsü gerektirmez."""

    __gtype_name__ = "MahzenMarqueeBand"

    def __init__(self, page: "FilesPage"):
        super().__init__(can_target=False, hexpand=True, vexpand=True)
        self.page = page

    def do_measure(self, _orientation, _for_size):
        return 0, 0, -1, -1

    def do_snapshot(self, snapshot) -> None:
        self.page.snapshot_band(snapshot)


class PreviewDialog(Adw.Dialog):
    """Dosya önizlemesi. Aynı ekrandaki dosyalar arasında ← / → tuşları, yatay kaydırma (dokunmatik yüzey,
    yatay tekerlek) ve dokunmatik ekranda kaydırma hareketiyle gezilir."""

    SWIPE_SURFACE = 50  # dokunmatik yüzeyde bir geçiş için gereken yatay kaydırma (piksel)

    def __init__(self, page: FilesPage, record: dict, siblings: list[dict] | None = None):
        super().__init__(title=record["name"], content_width=820, content_height=620)
        self.page = page
        self.state = page.state
        self.record = record
        self.siblings = siblings if siblings and any(s["id"] == record["id"] for s in siblings) else [record]
        self._generation = 0
        self._kind = ""
        self._content: Gtk.Widget | None = None
        self._swipe_x = 0.0
        self._swipe_used = False
        self._swipe_time = 0

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        open_btn = Gtk.Button(icon_name="document-open-symbolic", tooltip_text=tr("Geçici olarak aç"))
        open_btn.connect("clicked", lambda *_: (self.close(), page.open_temporarily(self.record)))
        header.pack_start(open_btn)
        export_btn = Gtk.Button(icon_name="document-save-symbolic", tooltip_text=tr("Dışa aktar"))
        export_btn.connect("clicked", lambda *_: self._export())
        header.pack_start(export_btn)

        nav = Gtk.Box(spacing=2, visible=len(self.siblings) > 1)
        self.prev_btn = Gtk.Button(icon_name="go-previous-symbolic", tooltip_text=tr("Önceki (←)"),
                                   css_classes=["flat"])
        self.prev_btn.connect("clicked", lambda *_: self.step(-1))
        self.counter = Gtk.Label(css_classes=["dim-label", "numeric"], width_chars=7)
        self.next_btn = Gtk.Button(icon_name="go-next-symbolic", tooltip_text=tr("Sonraki (→)"),
                                   css_classes=["flat"])
        self.next_btn.connect("clicked", lambda *_: self.step(1))
        for w in (self.prev_btn, self.counter, self.next_btn):
            nav.append(w)
        header.pack_end(nav)
        toolbar.add_top_bar(header)

        self.stack = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE, transition_duration=150)
        spinner = Gtk.Spinner(spinning=True, width_request=32, height_request=32,
                              halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER)
        self.stack.add_named(spinner, "loading")
        toolbar.set_content(self.stack)

        # Alt çubuk: favori, dosya bilgisi, çöp kutusu.
        bottom = Gtk.Box(spacing=6, margin_start=6, margin_end=6, margin_top=4, margin_bottom=4)
        self.favorite_btn = Gtk.Button(css_classes=["flat"])
        self.favorite_btn.connect("clicked", lambda *_: self._toggle_favorite())
        self.footer = Gtk.Label(css_classes=["caption", "dim-label"], hexpand=True,
                                ellipsize=Pango.EllipsizeMode.END)
        trash_btn = Gtk.Button(css_classes=["flat", "destructive-action"], tooltip_text=tr("Çöp kutusuna taşı (Delete)"),
                               child=Adw.ButtonContent(icon_name="user-trash-symbolic", label=tr("Çöp Kutusuna Taşı")))
        trash_btn.connect("clicked", lambda *_: self._trash_current())
        for w in (self.favorite_btn, self.footer, trash_btn):
            bottom.append(w)
        toolbar.add_bottom_bar(bottom)
        self.set_child(toolbar)

        keys = Gtk.EventControllerKey(propagation_phase=Gtk.PropagationPhase.CAPTURE)
        keys.connect("key-pressed", self._on_key)
        self.add_controller(keys)
        scroll = Gtk.EventControllerScroll(flags=Gtk.EventControllerScrollFlags.BOTH_AXES,
                                        propagation_phase=Gtk.PropagationPhase.CAPTURE)
        scroll.connect("scroll-begin", lambda *_: self._reset_swipe())
        scroll.connect("scroll-end", lambda *_: self._reset_swipe())
        scroll.connect("scroll", self._on_scroll)
        self.stack.add_controller(scroll)
        swipe = Gtk.GestureSwipe(touch_only=True)
        swipe.connect("swipe", self._on_swipe)
        self.stack.add_controller(swipe)

        # Kilitte çözülmüş içerik ekranda kalmasın.
        handler = self.state.connect("phase-changed", lambda *_: self.force_close())
        self.connect("closed", lambda *_: self.state.disconnect(handler))
        self._load(record)

    # MARK: Gezinme

    @property
    def position(self) -> int:
        return next((i for i, s in enumerate(self.siblings) if s["id"] == self.record["id"]), 0)

    def step(self, delta: int) -> None:
        target = sel.step_position(self.position, delta, len(self.siblings))
        if target is not None:
            self._load(self.siblings[target])

    def _is_favorite(self) -> bool:
        current = self.state.index.file(self.record["id"])
        return bool((current or self.record).get("favorite"))

    def _update_favorite(self) -> None:
        on = self._is_favorite()
        self.favorite_btn.set_child(Adw.ButtonContent(
            icon_name="starred-symbolic" if on else "non-starred-symbolic",
            label=tr("Favorilerden Çıkar") if on else tr("Favorilere Ekle")))
        self.favorite_btn.set_tooltip_text(tr("Favorilerden çıkar (F)") if on else tr("Favorilere ekle (F)"))

    def _toggle_favorite(self) -> None:
        self.state.toggle_favorite({self.record["id"]})
        self._update_favorite()

    def _trash_current(self) -> None:
        """Dosyayı çöpe atar ve sıradaki dosyaya geçer; başka dosya yoksa önizlemeyi kapatır."""
        position, trashed = self.position, self.record
        self.state.trash_files({trashed["id"]})
        remaining = [s for s in self.siblings if s["id"] != trashed["id"]]
        if not remaining:
            self.close()
            return
        self.siblings = remaining
        self._load(remaining[min(position, len(remaining) - 1)])

    def _on_key(self, _ctrl, keyval, _code, mods) -> bool:
        plain = not mods & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SUPER_MASK)
        if plain and keyval in (Gdk.KEY_Delete, Gdk.KEY_KP_Delete):
            self._trash_current()
            return True
        if plain and keyval in (Gdk.KEY_f, Gdk.KEY_F) and not mods & Gdk.ModifierType.SHIFT_MASK:
            self._toggle_favorite()
            return True
        # Metinde ok tuşları imlece kalır.
        if self._kind == "text" or mods & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK |
                                           Gdk.ModifierType.SHIFT_MASK | Gdk.ModifierType.SUPER_MASK):
            return False
        if keyval in (Gdk.KEY_Left, Gdk.KEY_KP_Left):
            self.step(-1)
            return True
        if keyval in (Gdk.KEY_Right, Gdk.KEY_KP_Right):
            self.step(1)
            return True
        return False

    def _reset_swipe(self) -> None:
        self._swipe_x = 0.0
        self._swipe_used = False

    def _on_scroll(self, controller, dx: float, dy: float) -> bool:
        """Her yatay kaydırma hareketinde bir dosya. Metinde yatay kaydırma içeriğe kalır."""
        if self._kind == "text":
            return False
        now = GLib.get_monotonic_time()
        if now - self._swipe_time > 300_000:  # olay vermeyen sürücüler için: kısa bir duraklama yeni hareket sayılır
            self._reset_swipe()
        self._swipe_time = now
        if abs(dx) <= abs(dy) and self._swipe_x == 0:
            return False
        wheel = hasattr(controller, "get_unit") and controller.get_unit() == Gdk.ScrollUnit.WHEEL
        self._swipe_x += dx
        if not self._swipe_used and abs(self._swipe_x) >= (1 if wheel else self.SWIPE_SURFACE):
            self.step(1 if self._swipe_x > 0 else -1)
            if wheel:
                self._reset_swipe()
            else:
                self._swipe_used = True
        return True

    def _on_swipe(self, _gesture, vx: float, vy: float) -> None:
        if abs(vx) > abs(vy) and abs(vx) > 300:
            self.step(-1 if vx > 0 else 1)

    # MARK: İçerik

    def _load(self, record: dict) -> None:
        self.record = record
        self._generation += 1
        generation = self._generation
        self.set_title(record["name"])
        position, count = self.position, len(self.siblings)
        self.counter.set_label(f"{position + 1} / {count}")
        self.prev_btn.set_sensitive(position > 0)
        self.next_btn.set_sensitive(position < count - 1)
        self._update_favorite()
        self.footer.set_label(" · ".join(x for x in [
            format_size(int(record.get("size", 0))), tr("Eklendi: {date}", date=format_date(record.get("addedAt"))),
            " ".join(f"#{t}" for t in record.get("tags", []))] if x))
        self.stack.set_visible_child_name("loading")
        if self._content is not None:
            self.stack.remove(self._content)
            self._content = None

        def current(fn):
            return lambda data, error: fn(data, error) if generation == self._generation else None

        kind = kind_of(record)
        size = int(record.get("size", 0))
        self._kind = kind
        if kind == "image" and size <= IMAGE_PREVIEW_LIMIT:
            self.state.read_file(record, current(self._show_image))
        elif kind == "text" and size <= TEXT_PREVIEW_LIMIT:
            self.state.read_file(record, current(self._show_text))
        else:
            self._show_fallback()

    def _set_content(self, widget: Gtk.Widget) -> None:
        if self._content is not None:
            self.stack.remove(self._content)
        self._content = widget
        self.stack.add_named(widget, "content")
        self.stack.set_visible_child_name("content")

    def _show_image(self, data, error) -> None:
        if error or data is None:
            self._show_error(error)
            return
        try:
            texture = Gdk.Texture.new_from_bytes(GLib.Bytes.new(data))
        except GLib.Error:
            self._show_fallback(tr("Bu görsel biçimi önizlenemiyor."))
            return
        self._set_content(Gtk.Picture(paintable=texture, content_fit=Gtk.ContentFit.CONTAIN, can_shrink=True))

    def _show_text(self, data, error) -> None:
        if error or data is None:
            self._show_error(error)
            return
        text = data.decode("utf-8", errors="replace")
        view = Gtk.TextView(editable=False, monospace=True, wrap_mode=Gtk.WrapMode.WORD_CHAR,
                            top_margin=12, bottom_margin=12, left_margin=12, right_margin=12, cursor_visible=False)
        view.get_buffer().set_text(text)
        self._set_content(Gtk.ScrolledWindow(child=view))

    def _show_fallback(self, message: str | None = None) -> None:
        record = self.record
        status = Adw.StatusPage(
            icon_name=icon_for(record), title=record["name"],
            description=message or tr("Bu dosya türü uygulama içinde önizlenemiyor.\n"
                                      "Geçici olarak açabilir ya da dışa aktarabilirsiniz."))
        button = Gtk.Button(label=tr("Geçici Olarak Aç"), css_classes=["pill", "suggested-action"],
                            halign=Gtk.Align.CENTER)
        button.connect("clicked", lambda *_: (self.close(), self.page.open_temporarily(record)))
        status.set_child(button)
        self._set_content(status)

    def _show_error(self, error) -> None:
        self._set_content(Adw.StatusPage(icon_name="dialog-error-symbolic", title=tr("Dosya çözülemedi"),
                                         description=str(error) if error else ""))

    def _export(self) -> None:
        record = self.record
        self.close()
        dialog = Gtk.FileDialog(title=tr("Şifresi çözülmüş kopyanın kaydedileceği klasör"),
                                accept_label=tr("Dışa Aktar"), modal=True)

        def done(d, result):
            try:
                folder = d.select_folder_finish(result)
            except GLib.Error:
                return
            if folder and folder.get_path():
                self.state.export_files([record], folder.get_path())

        dialog.select_folder(self.page.get_root(), None, done)
