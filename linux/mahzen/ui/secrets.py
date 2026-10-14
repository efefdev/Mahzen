"""Parolalar: hesap, kart, Wi-Fi ve sunucu kayıtları; parola üretici ve güç ölçer."""

from __future__ import annotations

import copy

from gi.repository import Adw, GLib, Gtk, Pango

from ..core.index import SECRET_CATEGORIES, new_secret, sort_key
from ..core.passwords import STRENGTH_LABELS, generate, strength
from .common import clear_box, format_date, icon_button

CATEGORY_TITLES = {"login": "Hesap", "card": "Kart", "wifi": "Wi-Fi", "server": "Sunucu", "note": "Gizli not",
                   "other": "Diğer"}
CATEGORY_ICONS = {"login": "avatar-default-symbolic", "card": "mahzen-card-symbolic",
                  "wifi": "network-wireless-symbolic", "server": "network-server-symbolic",
                  "note": "document-edit-symbolic", "other": "dialog-password-symbolic"}


class SecretsPage(Adw.Bin):
    def __init__(self, state, make_header):
        super().__init__()
        self.state = state
        self.selected_id: str | None = None
        self.category: str | None = None
        self.search = ""
        self._loading = False
        self.draft: dict | None = None

        split = Adw.NavigationSplitView(min_sidebar_width=260, max_sidebar_width=340)
        self.split = split

        list_toolbar = Adw.ToolbarView()
        header = make_header("Parolalar", lock=False)
        add = Gtk.Button(icon_name="list-add-symbolic", tooltip_text="Yeni kayıt (Ctrl+N)")
        add.connect("clicked", lambda *_: self.new_secret())
        header.pack_start(add)
        list_toolbar.add_top_bar(header)
        search = Gtk.SearchEntry(margin_start=8, margin_end=8, margin_bottom=6)
        search.set_property("placeholder-text", "Parolalarda ara")
        search.connect("search-changed", lambda e: self._set_search(e.get_text()))
        list_toolbar.add_top_bar(search)
        self.category_dropdown = Gtk.DropDown.new_from_strings(
            ["Tümü", "Favoriler"] + [CATEGORY_TITLES[c] for c in SECRET_CATEGORIES])
        self.category_dropdown.set_margin_start(8)
        self.category_dropdown.set_margin_end(8)
        self.category_dropdown.set_margin_bottom(6)
        self.category_dropdown.connect("notify::selected", lambda *_: self.refresh_list())
        list_toolbar.add_top_bar(self.category_dropdown)
        self.listbox = Gtk.ListBox(css_classes=["navigation-sidebar"])
        self.listbox.connect("row-selected", self._on_row_selected)
        scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, vexpand=True)
        scroller.set_child(self.listbox)
        list_toolbar.set_content(scroller)
        split.set_sidebar(Adw.NavigationPage(title="Parolalar", child=list_toolbar))

        detail_toolbar = Adw.ToolbarView()
        detail_header = make_header("")
        self.fav_btn = Gtk.ToggleButton(icon_name="starred-symbolic", tooltip_text="Favori")
        self.fav_btn.connect("toggled", lambda b: self._set("favorite", b.get_active()))
        detail_header.pack_start(self.fav_btn)
        delete = Gtk.Button(icon_name="user-trash-symbolic", tooltip_text="Çöp kutusuna taşı")
        delete.connect("clicked", lambda *_: self.delete_secret())
        detail_header.pack_start(delete)
        detail_toolbar.add_top_bar(detail_header)

        self.detail_stack = Gtk.Stack()
        self.empty = Adw.StatusPage(icon_name="dialog-password-symbolic", title="Bir kayıt seç",
                                    description="Hesap, kart, Wi-Fi ve sunucu bilgilerini şifreli saklayın.")
        self.detail_stack.add_named(self.empty, "empty")
        self.form = self._build_form()
        self.detail_stack.add_named(self.form, "form")
        detail_toolbar.set_content(self.detail_stack)
        split.set_content(Adw.NavigationPage(title="Kayıt", child=detail_toolbar))
        self.set_child(split)

        state.connect("index-changed", lambda *_: self.refresh_list())
        state.connect("phase-changed", lambda *_: self._on_phase())

    def _on_phase(self) -> None:
        if self.state.phase != "unlocked":
            self.selected_id = None
            self.draft = None
            self.detail_stack.set_visible_child_name("empty")
            self._loading = True
            for row in (self.title_row, self.username_row, self.password_row, self.url_row):
                row.set_text("")
            self.notes_view.get_buffer().set_text("")
            self._loading = False

    # MARK: - Form

    def _build_form(self) -> Gtk.Widget:
        page = Adw.PreferencesPage()
        group = Adw.PreferencesGroup()
        self.category_row = Adw.ComboRow(title="Tür", model=Gtk.StringList.new(
            [CATEGORY_TITLES[c] for c in SECRET_CATEGORIES]))
        self.category_row.connect("notify::selected", self._on_category)
        group.add(self.category_row)
        self.title_row = Adw.EntryRow(title="Başlık")
        self.title_row.connect("changed", lambda r: self._set("title", r.get_text()))
        group.add(self.title_row)
        page.add(group)

        creds = Adw.PreferencesGroup()
        self.username_row = Adw.EntryRow(title="Kullanıcı adı / e-posta")
        self.username_row.connect("changed", lambda r: self._set("username", r.get_text()))
        self.username_row.add_suffix(icon_button("edit-copy-symbolic", "Kopyala",
                                                 lambda: self._copy("username", False)))
        creds.add(self.username_row)

        self.password_row = Adw.PasswordEntryRow(title="Parola")
        self.password_row.connect("changed", self._on_password)
        self.password_row.add_suffix(icon_button("view-refresh-symbolic", "Güçlü parola üret", self._generate))
        self.password_row.add_suffix(icon_button("edit-copy-symbolic", "Kopyala", lambda: self._copy("password", True)))
        creds.add(self.password_row)

        meter_row = Adw.ActionRow(activatable=False)
        self.meter = Gtk.LevelBar(min_value=0, max_value=5, mode=Gtk.LevelBarMode.DISCRETE, hexpand=True,
                                  valign=Gtk.Align.CENTER)
        self.meter_label = Gtk.Label(css_classes=["caption", "dim-label"], width_chars=16, xalign=1)
        meter_row.add_prefix(self.meter)
        meter_row.add_suffix(self.meter_label)
        creds.add(meter_row)

        self.url_row = Adw.EntryRow(title="Adres (URL)")
        self.url_row.connect("changed", lambda r: self._set("url", r.get_text()))
        self.url_row.add_suffix(icon_button("web-browser-symbolic", "Tarayıcıda aç", self._open_url))
        creds.add(self.url_row)
        page.add(creds)

        gen_group = Adw.PreferencesGroup()
        expander = Adw.ExpanderRow(title="Parola üretici ayarları")
        self.length_row = Adw.SpinRow.new_with_range(8, 64, 1)
        self.length_row.set_title("Uzunluk")
        self.length_row.connect("notify::value", lambda *_: self._gen_pref("length", int(self.length_row.get_value())))
        expander.add_row(self.length_row)
        self.gen_switches = {}
        for key, title in [("uppercase", "Büyük harf"), ("lowercase", "Küçük harf"), ("digits", "Rakam"),
                           ("symbols", "Simge"), ("avoidAmbiguous", "Karışabilen karakterleri kullanma (O0Il1)")]:
            row = Adw.SwitchRow(title=title)
            row.connect("notify::active", lambda r, _p, k=key: self._gen_pref(k, r.get_active()))
            expander.add_row(row)
            self.gen_switches[key] = row
        gen_group.add(expander)
        page.add(gen_group)

        notes_group = Adw.PreferencesGroup(title="Notlar")
        self.notes_view = Gtk.TextView(wrap_mode=Gtk.WrapMode.WORD_CHAR, top_margin=10, bottom_margin=10,
                                       left_margin=10, right_margin=10, height_request=120,
                                       css_classes=["card", "secret-notes"])
        self.notes_view.get_buffer().connect(
            "changed", lambda b: self._set("notes", b.get_text(b.get_start_iter(), b.get_end_iter(), False)))
        notes_group.add(self.notes_view)
        page.add(notes_group)

        self.dates_label = Gtk.Label(css_classes=["caption", "dim-label"], margin_bottom=12)
        info = Adw.PreferencesGroup()
        info.add(self.dates_label)
        page.add(info)
        return page

    def _gen_pref(self, key, value) -> None:
        if self._loading:
            return
        gen = dict(self.state.prefs.get("generator", {}))
        gen[key] = value
        self.state.update_prefs(generator=gen)

    def _generate(self) -> None:
        if not self.draft:
            return
        self.password_row.set_text(generate(self.state.prefs.get("generator", {})))
        self.password_row.grab_focus()

    def _copy(self, field: str, sensitive: bool) -> None:
        if self.draft and self.draft.get(field):
            self.state.copy(self.draft[field], sensitive=sensitive,
                            label="Parola kopyalandı" if sensitive else "Kopyalandı")

    def _open_url(self) -> None:
        url = (self.draft or {}).get("url", "").strip()
        if not url:
            return
        if "://" not in url:
            url = "https://" + url
        Gtk.UriLauncher.new(url).launch(self.get_root(), None, None)

    def _on_password(self, row) -> None:
        pw = row.get_text()
        score, bits = strength(pw)
        self.meter.set_value(score + 1 if pw else 0)
        self.meter_label.set_text(f"{STRENGTH_LABELS[score]} · {bits:.0f} bit" if pw else "")
        self._set("password", pw)

    def _on_category(self, row, _pspec) -> None:
        self._set("category", SECRET_CATEGORIES[row.get_selected()])

    def _set(self, key, value) -> None:
        if self._loading or not self.draft:
            return
        if self.draft.get(key) == value:
            return
        self.draft[key] = value
        self.state.save_secret(copy.deepcopy(self.draft))

    def _load(self, secret: dict | None) -> None:
        self._loading = True
        self.draft = copy.deepcopy(secret) if secret else None
        if secret is None:
            self.detail_stack.set_visible_child_name("empty")
            has_any = any(not s.get("deletedAt") for s in self.state.index.secrets)
            self.empty.set_title("Bir kayıt seç" if has_any else "Henüz parola kaydı yok")
        else:
            self.detail_stack.set_visible_child_name("form")
            cat = secret.get("category", "login")
            self.category_row.set_selected(SECRET_CATEGORIES.index(cat) if cat in SECRET_CATEGORIES else 0)
            self.title_row.set_text(secret.get("title", ""))
            self.username_row.set_text(secret.get("username", ""))
            self.password_row.set_text(secret.get("password", ""))
            self.url_row.set_text(secret.get("url", ""))
            self.notes_view.get_buffer().set_text(secret.get("notes", ""))
            self.fav_btn.set_active(bool(secret.get("favorite")))
            self.dates_label.set_text(f"Oluşturuldu: {format_date(secret.get('createdAt'))} · "
                                      f"Düzenlendi: {format_date(secret.get('updatedAt'))}")
        gen = self.state.prefs.get("generator", {})
        self.length_row.set_value(int(gen.get("length", 20)))
        for key, row in self.gen_switches.items():
            row.set_active(bool(gen.get(key, True)))
        self._loading = False
        if secret is not None:
            self._on_password_meter_only()

    def _on_password_meter_only(self) -> None:
        pw = self.password_row.get_text()
        score, bits = strength(pw)
        self.meter.set_value(score + 1 if pw else 0)
        self.meter_label.set_text(f"{STRENGTH_LABELS[score]} · {bits:.0f} bit" if pw else "")

    # MARK: - Liste

    def _set_search(self, text: str) -> None:
        self.search = text.strip().casefold()
        self.refresh_list()

    def _secret(self, sid) -> dict | None:
        return next((s for s in self.state.index.secrets if s["id"] == sid), None)

    def refresh_list(self) -> None:
        if self.state.phase != "unlocked":
            return
        choice = self.category_dropdown.get_selected()
        secrets = [s for s in self.state.index.secrets if not s.get("deletedAt")]
        if choice == 1:
            secrets = [s for s in secrets if s.get("favorite")]
        elif choice >= 2:
            secrets = [s for s in secrets if s.get("category") == SECRET_CATEGORIES[choice - 2]]
        if self.search:
            secrets = [s for s in secrets if self.search in s.get("title", "").casefold()
                       or self.search in s.get("username", "").casefold()
                       or self.search in s.get("url", "").casefold()]
        secrets.sort(key=lambda s: (not s.get("favorite"), sort_key(s.get("title", ""))))
        self._loading = True
        clear_box(self.listbox)
        selected_row = None
        for s in secrets:
            row = Gtk.ListBoxRow()
            row.sid = s["id"]
            box = Gtk.Box(spacing=10, margin_top=6, margin_bottom=6, margin_start=4, margin_end=4)
            box.append(Gtk.Image(icon_name=CATEGORY_ICONS.get(s.get("category"), "dialog-password-symbolic"),
                                 pixel_size=24, css_classes=["accent"]))
            texts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, hexpand=True)
            texts.append(Gtk.Label(label=s.get("title") or "Adsız", xalign=0, ellipsize=Pango.EllipsizeMode.END,
                                   css_classes=["heading"]))
            texts.append(Gtk.Label(label=s.get("username") or CATEGORY_TITLES.get(s.get("category"), ""), xalign=0,
                                   ellipsize=Pango.EllipsizeMode.END, css_classes=["caption", "dim-label"]))
            box.append(texts)
            if s.get("favorite"):
                box.append(Gtk.Image(icon_name="starred-symbolic", css_classes=["favorite-star"]))
            row.set_child(box)
            self.listbox.append(row)
            if s["id"] == self.selected_id:
                selected_row = row
        if selected_row is not None:
            self.listbox.select_row(selected_row)
        self._loading = False
        current = self._secret(self.selected_id) if self.selected_id else None
        if self.selected_id and (current is None or current.get("deletedAt")):
            self.selected_id = None
            self._load(None)
        elif self.draft is None and self.selected_id is None:
            self._load(None)

    def _on_row_selected(self, _list, row) -> None:
        if self._loading or row is None:
            return
        if row.sid != self.selected_id:
            self.selected_id = row.sid
            self._load(self._secret(row.sid))
        self.split.set_show_content(True)

    def new_secret(self) -> None:
        if self.state.phase != "unlocked":
            return
        choice = self.category_dropdown.get_selected()
        secret = new_secret(SECRET_CATEGORIES[choice - 2] if choice >= 2 else "login")
        self.state.save_secret(secret)
        self.state.flush_save()
        self.selected_id = secret["id"]
        self.refresh_list()
        self._load(self._secret(secret["id"]))
        self.split.set_show_content(True)
        GLib.idle_add(lambda: self.title_row.grab_focus() and False)

    def delete_secret(self) -> None:
        if not self.selected_id:
            return
        sid = self.selected_id
        self.selected_id = None
        self.state.mutate(lambda idx: idx.trash_secret(sid))
        self._load(None)
        self.state.toast("Kayıt çöp kutusuna taşındı")
