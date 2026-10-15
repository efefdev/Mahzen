"""Uygulama ve ana pencere."""

from __future__ import annotations

import os
import sys

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, Gio, GLib, Gtk  # noqa: E402

from .. import APP_ID, __version__  # noqa: E402
from ..core.index import parse_date  # noqa: E402
from .common import alert, confirm  # noqa: E402
from .files import FilesPage  # noqa: E402
from .lock import CreatePage, LockPage, WelcomePage  # noqa: E402
from .notes import NotesPage  # noqa: E402
from .secrets import SecretsPage  # noqa: E402
from .settings import SettingsPage  # noqa: E402
from .state import AppState  # noqa: E402
from .trash import TrashPage  # noqa: E402

DATA_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "data")

ACCENT_HEX = {
    "indigo": "#5856d6", "blue": "#3584e4", "teal": "#2190a4", "green": "#2ec27e", "orange": "#e66100",
    "pink": "#d6409f", "red": "#e01b24", "purple": "#9141ac", "graphite": "#6f7787",
}

SECTIONS = [
    ("files", "Dosyalar", "folder-symbolic"),
    ("notes", "Notlar", "document-edit-symbolic"),
    ("secrets", "Parolalar", "dialog-password-symbolic"),
    ("trash", "Çöp Kutusu", "user-trash-symbolic"),
    ("settings", "Ayarlar", "emblem-system-symbolic"),
]

BASE_CSS = """
.lock-clock { font-size: 64pt; font-weight: 200; font-feature-settings: "tnum"; }
.tile-frame { border-radius: 10px; background-color: alpha(currentColor, 0.06); }
.thumb { border-radius: 10px; }
.folder-icon { color: @accent_color; }
.favorite-star { color: #e5a50a; }
.note-title { font-weight: 700; background: none; box-shadow: none; }
.note-body { background: none; }
.secret-notes { padding: 6px; }
.drop-target { box-shadow: inset 0 0 0 3px @accent_bg_color; border-radius: 12px; }
.color-dot { border-radius: 999px; min-width: 10px; min-height: 10px; }
.task-bar { padding: 6px 12px; }
.shake { animation: shake 0.4s; }
@keyframes shake { 0% { margin-left: 0; } 25% { margin-left: 8px; } 50% { margin-left: -8px; }
                   75% { margin-left: 4px; } 100% { margin-left: 0; } }
""" + "\n".join(f".accent-{k} {{ background-color: {v}; }}" for k, v in ACCENT_HEX.items())


def _load_css(provider: Gtk.CssProvider, css: str) -> None:
    if hasattr(provider, "load_from_string"):
        provider.load_from_string(css)
    else:
        provider.load_from_data(css, -1)


class MainWindow(Adw.ApplicationWindow):
    def __init__(self, app: "MahzenApp"):
        super().__init__(application=app, title="Mahzen", default_width=1180, default_height=760)
        self.state = app.state
        self.set_size_request(360, 480)

        self.toasts = Adw.ToastOverlay()
        self.outer = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE)
        self.toasts.set_child(self.outer)

        self.welcome = WelcomePage(self.state, lambda: self.outer.set_visible_child_name("create"))
        self.create_page = CreatePage(self.state, self._back_from_create)
        self.lock_page = LockPage(self.state, lambda: self.outer.set_visible_child_name("create"))
        self.outer.add_named(self.welcome, "welcome")
        self.outer.add_named(self.create_page, "create")
        self.outer.add_named(self.lock_page, "locked")
        self.outer.add_named(self._build_main(), "unlocked")

        # İlerleme çubuğu (uzun işlemler)
        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        root.append(self.toasts)
        self.toasts.set_vexpand(True)
        self.task_revealer = Gtk.Revealer(transition_type=Gtk.RevealerTransitionType.SLIDE_UP)
        task_box = Gtk.Box(spacing=12, css_classes=["toolbar", "task-bar"])
        self.task_spinner = Gtk.Spinner()
        task_box.append(self.task_spinner)
        labels = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, valign=Gtk.Align.CENTER)
        self.task_title = Gtk.Label(xalign=0, css_classes=["heading"])
        self.task_detail = Gtk.Label(xalign=0, css_classes=["caption", "dim-label"], ellipsize=3)
        labels.append(self.task_title)
        labels.append(self.task_detail)
        task_box.append(labels)
        self.task_progress = Gtk.ProgressBar(hexpand=True, valign=Gtk.Align.CENTER)
        task_box.append(self.task_progress)
        self.task_cancel = Gtk.Button(label="Durdur")
        self.task_cancel.connect("clicked", lambda *_: self.state.cancel_task())
        task_box.append(self.task_cancel)
        self.task_revealer.set_child(task_box)
        root.append(self.task_revealer)
        self.set_content(root)

        self.state.connect("phase-changed", lambda *_: self._on_phase())
        self.state.connect("task-changed", lambda *_: self._on_task())
        self.state.connect("toast", lambda _s, msg: self.toasts.add_toast(Adw.Toast(title=msg, timeout=3)))
        self.state.connect("alert", lambda _s, title, msg: alert(self, title, msg))
        self.state.connect("offer-trash-originals", lambda _s, sources: self._offer_trash(sources))
        self.state.connect("prefs-changed", lambda *_: self._on_prefs())
        self.state.connect("index-changed", lambda *_: self._update_badges())

        # Etkinlik takibi (otomatik kilit için)
        for controller in (Gtk.EventControllerKey(), Gtk.EventControllerMotion(), Gtk.GestureClick()):
            if isinstance(controller, Gtk.EventControllerKey):
                controller.connect("key-pressed", lambda *_: (self.state.note_activity(), False)[1])
            elif isinstance(controller, Gtk.EventControllerMotion):
                controller.connect("motion", lambda *_: self.state.note_activity())
            else:
                controller.connect("pressed", lambda *_: self.state.note_activity())
            controller.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
            self.add_controller(controller)

        self.connect("close-request", self._on_close)
        self._on_phase()

    # MARK: - Ana görünüm

    def _make_header(self, title: str, lock: bool = True) -> Adw.HeaderBar:
        header = Adw.HeaderBar()
        if title:
            header.set_title_widget(Adw.WindowTitle(title=title))
        else:
            header.set_title_widget(Gtk.Box())
        if lock:
            btn = Gtk.Button(icon_name="system-lock-screen-symbolic", tooltip_text="Kilitle (Ctrl+L)")
            btn.connect("clicked", lambda *_: self.state.lock())
            header.pack_end(btn)
        return header

    def _build_main(self) -> Gtk.Widget:
        self.split = Adw.NavigationSplitView(min_sidebar_width=200, max_sidebar_width=240)

        sidebar = Adw.ToolbarView()
        side_header = Adw.HeaderBar()
        self.side_title = Adw.WindowTitle(title="Mahzen")
        side_header.set_title_widget(self.side_title)
        menu = Gio.Menu()
        menu.append("Klavye Kısayolları", "win.show-help-overlay")
        menu.append("Mahzen Hakkında", "app.about")
        side_header.pack_end(Gtk.MenuButton(icon_name="open-menu-symbolic", menu_model=menu, tooltip_text="Menü"))
        sidebar.add_top_bar(side_header)

        self.nav = Gtk.ListBox(css_classes=["navigation-sidebar"])
        self.nav_rows = {}
        self.badges = {}
        for key, title, icon in SECTIONS:
            row = Gtk.ListBoxRow()
            box = Gtk.Box(spacing=12, margin_start=6, margin_end=6, margin_top=4, margin_bottom=4)
            box.append(Gtk.Image(icon_name=icon))
            box.append(Gtk.Label(label=title, xalign=0, hexpand=True))
            badge = Gtk.Label(css_classes=["dim-label", "caption"])
            box.append(badge)
            row.set_child(box)
            row.key = key
            self.nav.append(row)
            self.nav_rows[key] = row
            self.badges[key] = badge
        self.nav.connect("row-selected", self._on_nav)
        side_scroller = Gtk.ScrolledWindow(vexpand=True, hscrollbar_policy=Gtk.PolicyType.NEVER)
        side_scroller.set_child(self.nav)
        sidebar.set_content(side_scroller)
        self.recovered_banner = Gtk.Label(wrap=True, css_classes=["caption", "warning"], margin_start=12,
                                          margin_end=12, margin_bottom=12, visible=False,
                                          label="Dizin yedekten kurtarıldı.")
        sidebar.add_bottom_bar(self.recovered_banner)
        self.split.set_sidebar(Adw.NavigationPage(title="Mahzen", child=sidebar))

        self.content = Gtk.Stack(transition_type=Gtk.StackTransitionType.CROSSFADE, transition_duration=120)
        self.files = FilesPage(self.state, self._make_header)
        self.backup_banner = self.files.banner
        self.backup_banner.connect("button-clicked", lambda *_: self._backup_from_banner())
        self.notes = NotesPage(self.state, self._make_header)
        self.secrets = SecretsPage(self.state, self._make_header)
        self.trash = TrashPage(self.state, self._make_header)
        self.settings = SettingsPage(self.state, self._make_header)
        for key, page in [("files", self.files), ("notes", self.notes), ("secrets", self.secrets),
                          ("trash", self.trash), ("settings", self.settings)]:
            self.content.add_named(page, key)
        self.content_page = Adw.NavigationPage(title="Dosyalar", child=self.content)
        self.split.set_content(self.content_page)

        breakpoint_ = Adw.Breakpoint.new(Adw.BreakpointCondition.parse("max-width: 640sp"))
        breakpoint_.add_setter(self.split, "collapsed", True)
        self.add_breakpoint(breakpoint_)
        return self.split

    def _on_nav(self, _list, row) -> None:
        if row is None:
            return
        self.content.set_visible_child_name(row.key)
        self.content_page.set_title(dict((k, t) for k, t, _ in SECTIONS)[row.key])
        self.split.set_show_content(True)
        page = self.content.get_visible_child()
        if hasattr(page, "refresh"):
            page.refresh()
        elif hasattr(page, "refresh_list"):
            page.refresh_list()

    def show_section(self, key: str) -> None:
        self.nav.select_row(self.nav_rows[key])

    def _update_badges(self) -> None:
        if self.state.phase != "unlocked":
            return
        idx = self.state.index
        counts = {
            "files": len(idx.live_files),
            "notes": sum(1 for n in idx.notes if not n.get("deletedAt")),
            "secrets": sum(1 for s in idx.secrets if not s.get("deletedAt")),
            "trash": idx.trash_count,
        }
        for key, label in self.badges.items():
            label.set_text(str(counts[key]) if counts.get(key) else "")

    # MARK: - Durum değişiklikleri

    def _on_phase(self) -> None:
        phase = self.state.phase
        if phase != "unlocked":
            # Önizleme ve diğer pencereler çözülmüş içerik gösterebilir: kilitte hepsini kapat.
            dialog = self.get_visible_dialog()
            while dialog is not None:
                dialog.force_close()
                nxt = self.get_visible_dialog()
                dialog = nxt if nxt is not dialog else None
        self.outer.set_visible_child_name(phase)
        if phase == "locked":
            self.lock_page.on_shown()
        elif phase == "unlocked":
            self.recovered_banner.set_visible(self.state.recovered_from_backup)
            self.show_section("files")
            self.files.refresh()
            self.notes.refresh_list()
            self.secrets.refresh_list()
            self.trash.refresh()
            self.settings.refresh()
            self._update_badges()
        self.get_application().apply_appearance()

    def _back_from_create(self) -> None:
        self.outer.set_visible_child_name("locked" if self.state.phase == "locked" else "welcome")
        if self.state.phase == "locked":
            self.lock_page.on_shown()

    def _on_prefs(self) -> None:
        if self.state.phase != "unlocked":
            return
        self.side_title.set_title(self.state.prefs.get("displayName") or "Mahzen")
        self.get_application().apply_appearance()
        self._update_backup_banner()

    def _update_backup_banner(self) -> None:
        p = self.state.prefs
        days = int(p.get("backupReminderDays", 7))
        last = parse_date(p.get("lastBackupAt"))
        show = False
        if days > 0 and self.state.index.live_files:
            if last is None:
                show = True
                self.backup_banner.set_title("Kasanın henüz yedeği yok")
            else:
                from datetime import datetime, timezone
                age = (datetime.now(timezone.utc) - last).days
                if age >= days:
                    show = True
                    self.backup_banner.set_title(f"Son yedek {age} gün önce")
        self.backup_banner.set_revealed(show)

    def _backup_from_banner(self) -> None:
        if self.state.prefs.get("backupPath"):
            self.state.backup_now(self._update_backup_banner)
        else:
            self.show_section("settings")
            self.state.toast("Önce bir yedek konumu seçin")

    def _on_task(self) -> None:
        task = self.state.task
        if task is None:
            self.task_revealer.set_reveal_child(False)
            self.task_spinner.stop()
            return
        self.task_title.set_text(task.title)
        self.task_detail.set_text(task.detail)
        self.task_detail.set_visible(bool(task.detail))
        if task.fraction is None:
            self.task_progress.set_visible(False)
            self.task_spinner.start()
            self.task_spinner.set_visible(True)
        else:
            self.task_progress.set_visible(True)
            self.task_progress.set_fraction(min(max(task.fraction, 0), 1))
            self.task_spinner.stop()
            self.task_spinner.set_visible(False)
        self.task_cancel.set_visible(task.cancellable)
        # Kilit ekranında anahtar türetme kendi göstergesini kullanır.
        self.task_revealer.set_reveal_child(self.state.phase == "unlocked")

    def _offer_trash(self, sources: list[str]) -> None:
        names = ", ".join(os.path.basename(s) for s in sources[:4]) + (" …" if len(sources) > 4 else "")
        confirm(self, "Orijinaller çöp kutusuna taşınsın mı?",
                f"Şifreli kopyaları kasaya güvenle yazıldı: {names}\n\n"
                "Orijinaller sistemin çöp kutusuna taşınır (kalıcı silinmez).",
                "Çöpe Taşı", lambda: self.state.trash_originals(sources))

    def _on_close(self, *_args) -> bool:
        self.state.lock()
        self.state.wipe_temporary_files()
        return False


class MahzenApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.DEFAULT_FLAGS)
        GLib.set_application_name("Mahzen")
        self.state = AppState()
        self.window: MainWindow | None = None
        self._accent_css = Gtk.CssProvider()
        self._dbus_subscriptions = []

    def do_startup(self):
        Adw.Application.do_startup(self)
        display = Gdk.Display.get_default()
        icons = os.path.join(DATA_DIR, "icons")
        if os.path.isdir(icons):
            Gtk.IconTheme.get_for_display(display).add_search_path(icons)
        base = Gtk.CssProvider()
        _load_css(base, BASE_CSS)
        Gtk.StyleContext.add_provider_for_display(display, base, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        Gtk.StyleContext.add_provider_for_display(display, self._accent_css,
                                                  Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 2)
        Gtk.Window.set_default_icon_name(APP_ID)

        for name, callback, accels in [
            ("lock", lambda *_: self.state.lock(), ["<Control>l"]),
            ("quit", lambda *_: self.quit_app(), ["<Control>q"]),
            ("about", lambda *_: self.show_about(), []),
            ("import", lambda *_: self._in_files(lambda w: w.files.present_import()), ["<Control>o"]),
            ("new-folder", lambda *_: self._in_files(lambda w: w.files.new_folder()), ["<Control><Shift>n"]),
            ("new-item", lambda *_: self._new_item(), ["<Control>n"]),
            ("find", lambda *_: self._in_files(lambda w: w.files.focus_search()), ["<Control>f"]),
            ("section-1", lambda *_: self._section("files"), ["<Alt>1"]),
            ("section-2", lambda *_: self._section("notes"), ["<Alt>2"]),
            ("section-3", lambda *_: self._section("secrets"), ["<Alt>3"]),
            ("section-4", lambda *_: self._section("trash"), ["<Alt>4"]),
            ("section-5", lambda *_: self._section("settings"), ["<Control>comma"]),
        ]:
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", callback)
            self.add_action(action)
            if accels:
                self.set_accels_for_action(f"app.{name}", accels)
        self._watch_system_lock()
        Adw.StyleManager.get_default().connect("notify::dark", lambda *_: self.apply_appearance())

    def do_activate(self):
        if self.window is None:
            self.window = MainWindow(self)
            self._install_help_overlay()
        self.window.present()

    def do_shutdown(self):
        self.state.lock()
        self.state.wipe_temporary_files()
        Adw.Application.do_shutdown(self)

    def quit_app(self) -> None:
        self.state.lock()
        self.quit()

    def _section(self, key: str) -> None:
        if self.window and self.state.phase == "unlocked":
            self.window.show_section(key)

    def _in_files(self, fn) -> None:
        if self.window and self.state.phase == "unlocked":
            self.window.show_section("files")
            fn(self.window)

    def _new_item(self) -> None:
        if not self.window or self.state.phase != "unlocked":
            return
        visible = self.window.content.get_visible_child_name()
        if visible == "secrets":
            self.window.secrets.new_secret()
        else:
            self.window.show_section("notes")
            self.window.notes.new_note()

    # MARK: - Görünüm

    def apply_appearance(self) -> None:
        state = self.state
        if state.phase == "unlocked":
            appearance, accent = state.prefs.get("appearance"), state.prefs.get("accent")
        else:
            appearance, accent = state.settings.get("lockAppearance"), state.settings.get("lockAccent")
        manager = Adw.StyleManager.get_default()
        manager.set_color_scheme({
            "light": Adw.ColorScheme.FORCE_LIGHT, "dark": Adw.ColorScheme.FORCE_DARK,
        }.get(appearance or "dark", Adw.ColorScheme.DEFAULT))
        color = ACCENT_HEX.get(accent or "orange", ACCENT_HEX["orange"])
        css = (f"@define-color accent_bg_color {color};\n@define-color accent_color {color};\n"
               f"@define-color accent_fg_color #ffffff;\n")
        if (Gtk.get_major_version(), Gtk.get_minor_version()) >= (4, 16):
            css += f":root {{ --accent-bg-color: {color}; --accent-color: {color}; --accent-fg-color: #ffffff; }}\n"
        _load_css(self._accent_css, css)

    # MARK: - Uyku ve ekran kilidi

    def _watch_system_lock(self) -> None:
        """Uykuya geçerken (logind) ve ekran kilitlenince (ScreenSaver / logind oturumu) kasayı kilitler."""
        def subscribe(bus_type, sender, interface, member, path, handler):
            try:
                bus = Gio.bus_get_sync(bus_type, None)
            except GLib.Error:
                return
            sid = bus.signal_subscribe(sender, interface, member, path, None, Gio.DBusSignalFlags.NONE,
                                       handler)
            self._dbus_subscriptions.append((bus, sid))

        def on_sleep(_c, _s, _p, _i, _m, params):
            if params.unpack()[0]:
                self.state.lock_for_system_event()

        def on_active(_c, _s, _p, _i, _m, params):
            if params.unpack()[0]:
                self.state.lock_for_system_event()

        def on_session_lock(*_args):
            self.state.lock_for_system_event()

        subscribe(Gio.BusType.SYSTEM, "org.freedesktop.login1", "org.freedesktop.login1.Manager",
                  "PrepareForSleep", "/org/freedesktop/login1", on_sleep)
        subscribe(Gio.BusType.SYSTEM, "org.freedesktop.login1", "org.freedesktop.login1.Session",
                  "Lock", None, on_session_lock)
        for iface in ("org.gnome.ScreenSaver", "org.freedesktop.ScreenSaver", "org.cinnamon.ScreenSaver",
                      "org.mate.ScreenSaver"):
            subscribe(Gio.BusType.SESSION, None, iface, "ActiveChanged", None, on_active)

    # MARK: - Hakkında ve kısayollar

    def show_about(self) -> None:
        about = Adw.AboutDialog(
            application_name="Mahzen", application_icon=APP_ID, version=__version__, developer_name="efefdev",
            website="https://github.com/efefdev/Mahzen", issue_url="https://github.com/efefdev/Mahzen/issues",
            license_type=Gtk.License.CUSTOM, license="Lisans için depodaki LICENSE dosyasına bakın.",
            comments="Dosyalar, notlar ve parolalar için şifreli, taşınabilir kasa.\n"
                     "AES-256-GCM + Argon2id. macOS sürümüyle aynı kasayı açar.")
        about.present(self.window)

    def _install_help_overlay(self) -> None:
        ui = """<?xml version="1.0" encoding="UTF-8"?>
<interface>
  <object class="GtkShortcutsWindow" id="help_overlay">
    <property name="modal">True</property>
    <child><object class="GtkShortcutsSection"><property name="section-name">genel</property>
      <child><object class="GtkShortcutsGroup"><property name="title">Genel</property>
        <child><object class="GtkShortcutsShortcut"><property name="title">Kasayı kilitle</property><property name="accelerator">&lt;Control&gt;l</property></object></child>
        <child><object class="GtkShortcutsShortcut"><property name="title">Çıkış</property><property name="accelerator">&lt;Control&gt;q</property></object></child>
        <child><object class="GtkShortcutsShortcut"><property name="title">Dosyalar / Notlar / Parolalar / Çöp</property><property name="accelerator">&lt;Alt&gt;1 &lt;Alt&gt;2 &lt;Alt&gt;3 &lt;Alt&gt;4</property></object></child>
        <child><object class="GtkShortcutsShortcut"><property name="title">Ayarlar</property><property name="accelerator">&lt;Control&gt;comma</property></object></child>
      </object></child>
      <child><object class="GtkShortcutsGroup"><property name="title">Dosyalar</property>
        <child><object class="GtkShortcutsShortcut"><property name="title">Dosya ekle</property><property name="accelerator">&lt;Control&gt;o</property></object></child>
        <child><object class="GtkShortcutsShortcut"><property name="title">Yeni klasör</property><property name="accelerator">&lt;Control&gt;&lt;Shift&gt;n</property></object></child>
        <child><object class="GtkShortcutsShortcut"><property name="title">Ara</property><property name="accelerator">&lt;Control&gt;f</property></object></child>
        <child><object class="GtkShortcutsShortcut"><property name="title">Seçileni çöpe taşı</property><property name="accelerator">Delete</property></object></child>
        <child><object class="GtkShortcutsShortcut"><property name="title">Üst klasör</property><property name="accelerator">&lt;Alt&gt;BackSpace</property></object></child>
      </object></child>
      <child><object class="GtkShortcutsGroup"><property name="title">Notlar ve parolalar</property>
        <child><object class="GtkShortcutsShortcut"><property name="title">Yeni not / kayıt</property><property name="accelerator">&lt;Control&gt;n</property></object></child>
      </object></child>
    </object></child>
  </object>
</interface>"""
        builder = Gtk.Builder.new_from_string(ui, -1)
        self.window.set_help_overlay(builder.get_object("help_overlay"))
        self.set_accels_for_action("win.show-help-overlay", ["<Control>question"])


def main(argv=None) -> int:
    app = MahzenApp()
    return app.run(argv if argv is not None else sys.argv)
