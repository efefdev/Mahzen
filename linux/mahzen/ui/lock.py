"""Karşılama, kasa oluşturma ve kilit ekranları."""

from __future__ import annotations

import os
from datetime import datetime

from gi.repository import Adw, Gdk, Gio, GLib, Gtk

from ..core import paths
from ..core import vault as vaultmod
from ..core.passwords import STRENGTH_LABELS, strength
from .common import alert

_DAYS = ["Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar"]
_MONTHS = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim",
           "Kasım", "Aralık"]


def _choose_folder(parent: Gtk.Widget, title: str, callback) -> None:
    dialog = Gtk.FileDialog(title=title, modal=True)

    def done(d, result):
        try:
            folder = d.select_folder_finish(result)
        except GLib.Error:
            return
        if folder and folder.get_path():
            callback(folder.get_path())

    dialog.select_folder(parent.get_root(), None, done)


class WelcomePage(Gtk.Box):
    def __init__(self, state, show_create):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.append(Adw.HeaderBar(show_title=False, css_classes=["flat"]))
        status = Adw.StatusPage(
            icon_name="dev.efef.Mahzen",
            title="Mahzen",
            description="Dosyaların, notların ve parolaların için\nşifreli, taşınabilir bir kasa.",
            vexpand=True,
        )
        create = Gtk.Button(label="Yeni Kasa Oluştur", css_classes=["pill", "suggested-action"])
        create.connect("clicked", lambda *_: show_create())
        open_btn = Gtk.Button(label="Var Olan Kasayı Aç…", css_classes=["pill"])
        open_btn.connect("clicked", lambda *_: _choose_folder(self, "Kasa klasörünü seç", state.select_vault))
        buttons = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, halign=Gtk.Align.CENTER)
        buttons.append(create)
        buttons.append(open_btn)
        buttons.append(Gtk.Label(
            label="macOS'ta oluşturulan kasalar da açılır: kasa klasörünü seçmeniz yeterli.",
            css_classes=["dim-label", "caption"], margin_top=24, wrap=True, justify=Gtk.Justification.CENTER,
        ))
        status.set_child(buttons)
        self.append(status)


class CreatePage(Gtk.Box):
    def __init__(self, state, back):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.state = state
        self.location = paths.default_new_vault_path()

        header = Adw.HeaderBar(show_title=False)
        back_btn = Gtk.Button(icon_name="go-previous-symbolic", tooltip_text="Geri")
        back_btn.connect("clicked", lambda *_: back())
        header.pack_start(back_btn)
        self.append(header)

        clamp = Adw.Clamp(maximum_size=460, vexpand=True, valign=Gtk.Align.CENTER, margin_start=16, margin_end=16)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18, margin_bottom=24)
        box.append(Gtk.Label(label="Yeni kasa", css_classes=["title-1"]))

        group = Adw.PreferencesGroup()
        self.location_row = Adw.ActionRow(title="Konum", subtitle=self.location, subtitle_selectable=True)
        change = Gtk.Button(label="Değiştir…", valign=Gtk.Align.CENTER)
        change.connect("clicked", lambda *_: _choose_folder(self, "Kasanın oluşturulacağı klasörü seç", self._set_parent))
        self.location_row.add_suffix(change)
        group.add(self.location_row)
        box.append(group)

        pw_group = Adw.PreferencesGroup(title="Ana parola",
                                        description=f"En az {vaultmod.MINIMUM_PASSWORD_LENGTH} karakter. "
                                                    "Rastgele seçilmiş 5+ kelime veya 12+ rastgele karakter önerilir.")
        self.password = Adw.PasswordEntryRow(title="Parola")
        self.repeat = Adw.PasswordEntryRow(title="Parola (tekrar)")
        self.password.connect("changed", self._validate)
        self.repeat.connect("changed", self._validate)
        self.repeat.connect("entry-activated", lambda *_: self._create())
        pw_group.add(self.password)
        pw_group.add(self.repeat)
        box.append(pw_group)

        self.meter = Gtk.LevelBar(min_value=0, max_value=4, mode=Gtk.LevelBarMode.DISCRETE)
        self.meter_label = Gtk.Label(xalign=0, css_classes=["caption", "dim-label"])
        meter_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        meter_box.append(self.meter)
        meter_box.append(self.meter_label)
        box.append(meter_box)

        self.understand = Gtk.CheckButton(
            label="Bu parolayı unutursam kasadaki verilerin hiçbir şekilde kurtarılamayacağını anlıyorum.")
        self.understand.get_last_child().set_wrap(True)
        self.understand.connect("toggled", self._validate)
        box.append(self.understand)

        self.create_btn = Gtk.Button(label="Kasayı Oluştur", css_classes=["pill", "suggested-action"],
                                     sensitive=False, halign=Gtk.Align.CENTER)
        self.create_btn.connect("clicked", lambda *_: self._create())
        box.append(self.create_btn)
        self.spinner = Gtk.Spinner(visible=False)
        box.append(self.spinner)

        clamp.set_child(box)
        scroller = Gtk.ScrolledWindow(vexpand=True, hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroller.set_child(clamp)
        self.append(scroller)

    def reset(self) -> None:
        self.password.set_text("")
        self.repeat.set_text("")
        self.understand.set_active(False)
        self.location = paths.default_new_vault_path()
        self.location_row.set_subtitle(self.location)

    def _set_parent(self, parent: str) -> None:
        self.location = os.path.join(parent, paths.DEFAULT_VAULT_NAME) if not vaultmod.exists(parent) else parent
        self.location_row.set_subtitle(self.location)

    def _validate(self, *_):
        pw = self.password.get_text()
        score, _bits = strength(pw)
        self.meter.set_value(score + 1 if pw else 0)
        self.meter_label.set_text(f"Parola gücü: {STRENGTH_LABELS[score]}" if pw else "")
        ok = (len(pw) >= vaultmod.MINIMUM_PASSWORD_LENGTH and pw == self.repeat.get_text()
              and self.understand.get_active())
        self.create_btn.set_sensitive(ok)
        return ok

    def _create(self) -> None:
        if not self._validate():
            if self.password.get_text() != self.repeat.get_text():
                alert(self, "Parolalar eşleşmiyor")
            return
        if vaultmod.exists(self.location):
            alert(self, "Bu konumda zaten bir kasa var", self.location)
            return
        if os.path.exists(self.location) and os.listdir(self.location):
            alert(self, "Klasör boş değil", "Kasa boş bir klasöre ya da yeni bir klasöre oluşturulmalı.")
            return
        self.create_btn.set_sensitive(False)
        self.spinner.set_visible(True)
        self.spinner.start()

        def done(error):
            self.spinner.stop()
            self.spinner.set_visible(False)
            self.create_btn.set_sensitive(True)
            if error:
                alert(self, "Kasa oluşturulamadı", error)
            else:
                self.reset()

        self.state.create_vault(self.location, self.password.get_text(), done)


class LockPage(Gtk.Box):
    def __init__(self, state, show_create):
        super().__init__(orientation=Gtk.Orientation.VERTICAL)
        self.state = state
        header = Adw.HeaderBar(show_title=False, css_classes=["flat"])
        menu = Gio.Menu()
        menu.append("Başka Kasa Aç…", "lock.open-other")
        menu.append("Yeni Kasa Oluştur…", "lock.create")
        menu.append("Anahtar Dosyası İçe Aktar…", "lock.import-keyfile")
        header.pack_end(Gtk.MenuButton(icon_name="open-menu-symbolic", menu_model=menu, tooltip_text="Menü"))
        self.append(header)

        group = Gio.SimpleActionGroup()
        for name, cb in [
            ("open-other", lambda *_: _choose_folder(self, "Kasa klasörünü seç", state.select_vault)),
            ("create", lambda *_: show_create()),
            ("import-keyfile", lambda *_: self._import_keyfile()),
        ]:
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate", cb)
            group.add_action(action)
        self.insert_action_group("lock", group)

        clamp = Adw.Clamp(maximum_size=360, vexpand=True, valign=Gtk.Align.CENTER, margin_start=16, margin_end=16)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10, margin_bottom=48)
        self.clock = Gtk.Label(css_classes=["lock-clock"])
        self.date = Gtk.Label(css_classes=["title-4", "dim-label"])
        box.append(self.clock)
        box.append(self.date)
        lock_icon = Gtk.Image(icon_name="system-lock-screen-symbolic", pixel_size=40, margin_top=36,
                              css_classes=["accent"])
        box.append(lock_icon)
        self.name = Gtk.Label(css_classes=["title-2"])
        box.append(self.name)
        self.path_label = Gtk.Label(css_classes=["caption", "dim-label"], ellipsize=3, margin_bottom=12)
        box.append(self.path_label)

        entry_box = Gtk.Box(spacing=6)
        self.entry = Gtk.PasswordEntry(show_peek_icon=True, hexpand=True)
        self.entry.set_property("placeholder-text", "Parola")
        self.entry.connect("activate", lambda *_: self._unlock())
        self.button = Gtk.Button(icon_name="go-next-symbolic", tooltip_text="Kilidi aç",
                                 css_classes=["suggested-action", "circular"])
        self.button.connect("clicked", lambda *_: self._unlock())
        entry_box.append(self.entry)
        entry_box.append(self.button)
        box.append(entry_box)

        self.status = Gtk.Label(css_classes=["caption"], wrap=True, justify=Gtk.Justification.CENTER)
        self.spinner = Gtk.Spinner()
        status_box = Gtk.Box(spacing=8, halign=Gtk.Align.CENTER, height_request=24)
        status_box.append(self.spinner)
        status_box.append(self.status)
        box.append(status_box)
        clamp.set_child(box)
        self.append(clamp)

        self._tick()
        GLib.timeout_add_seconds(1, self._tick)
        self.caps_handler = None

    def on_shown(self) -> None:
        settings = self.state.settings
        self.name.set_text(settings.get("lockName") or "Mahzen")
        self.path_label.set_text(self.state.vault_path or "")
        self.entry.set_text("")
        self._set_status("")
        self._watch_caps_lock()
        GLib.idle_add(lambda: self.entry.grab_focus() and False)

    def _watch_caps_lock(self) -> None:
        display = Gdk.Display.get_default()
        seat = display.get_default_seat() if display else None
        keyboard = seat.get_keyboard() if seat else None
        if keyboard is None:
            return
        if self.caps_handler is None:
            self.caps_handler = keyboard.connect("notify::caps-lock-state", lambda *_: self._update_caps(keyboard))
        self._update_caps(keyboard)

    def _update_caps(self, keyboard) -> None:
        if not self.spinner.get_spinning():
            self._set_status("Caps Lock açık" if keyboard.get_caps_lock_state() else "",
                             warning=True)

    def _tick(self) -> bool:
        n = datetime.now()
        self.clock.set_text(f"{n.hour:02d}:{n.minute:02d}")
        self.date.set_text(f"{n.day} {_MONTHS[n.month - 1]} {_DAYS[n.weekday()]}")
        return True

    def _set_status(self, text: str, warning: bool = False, error: bool = False) -> None:
        self.status.set_text(text)
        for c in ("warning", "error"):
            self.status.remove_css_class(c)
        if warning:
            self.status.add_css_class("warning")
        if error:
            self.status.add_css_class("error")

    def _unlock(self) -> None:
        password = self.entry.get_text()
        if not password or self.spinner.get_spinning():
            return
        self.entry.set_sensitive(False)
        self.button.set_sensitive(False)
        self.spinner.start()
        self._set_status("Anahtar türetiliyor…")

        def done(error):
            self.spinner.stop()
            self.entry.set_sensitive(True)
            self.button.set_sensitive(True)
            if error:
                self._set_status(error, error=True)
                self.entry.select_region(0, -1)
                self.entry.grab_focus()
                self.entry.add_css_class("shake")
                GLib.timeout_add(500, lambda: self.entry.remove_css_class("shake") and False)
            else:
                self.entry.set_text("")
                self._set_status("")

        self.state.unlock(password, done)

    def _import_keyfile(self) -> None:
        dialog = Gtk.FileDialog(title="Anahtar dosyasını seç", modal=True)

        def done(d, result):
            try:
                f = d.open_finish(result)
            except GLib.Error:
                return
            if f and f.get_path():
                self.state.import_keyfile(f.get_path())

        dialog.open(self.get_root(), None, done)
