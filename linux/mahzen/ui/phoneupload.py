"""“Telefondan Ekle” penceresi: QR kodu, gelen dosyaların canlı listesi ve Durdur. Kapatılınca oturum da durur."""

from __future__ import annotations

from gi.repository import Adw, GLib, Gtk, Pango

from ..core.phoneshare import primary_ipv4
from ..core.phoneupload import PhoneUploadSession
from ..core.virt import phone_network_warning
from ..i18n import tr
from .common import format_size
from .phoneshare import QRCodeView, _network_warning

def _state_text(state: str) -> str:
    if state == "saved":
        return tr("Kasaya eklendi")
    if state == "duplicate":
        return tr("Kasada zaten vardı")
    if state == "cancelled":
        return tr("Telefonda durduruldu")
    failures = {
        "failed:timeout": tr("Telefondan veri gelmedi"),
        "failed:net": tr("Bağlantı koptu"),
        "failed:crypto": tr("Doğrulanamadı"),
        "failed:too-large": tr("Dosya çok büyük"),
        "failed:no-space": tr("Diskte yer yok"),
        "failed:io": tr("Kasaya yazılamadı"),
    }
    if state.startswith("failed:"):
        return failures.get(state, tr("Geçersiz istek"))
    return ""


def _state_icon(state: str) -> tuple[str, str | None]:
    if state == "saved":
        return "emblem-ok-symbolic", "success"
    if state == "duplicate":
        return "edit-copy-symbolic", "dim-label"
    if state == "cancelled":
        return "process-stop-symbolic", "dim-label"
    if state.startswith("failed:"):
        return "dialog-error-symbolic", "error"
    return "folder-download-symbolic", "accent"


class PhoneUploadDialog(Adw.Dialog):
    def __init__(self, state, session: PhoneUploadSession):
        super().__init__(title=tr("Telefondan Ekle"), content_width=440)
        self.state = state
        self.session = session
        self.phase = "starting"  # starting | running | failed | stopped
        self._timer = 0
        self._shown: list = []

        toolbar = Adw.ToolbarView()
        toolbar.add_top_bar(Adw.HeaderBar())
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16, margin_start=24, margin_end=24,
                      margin_bottom=24, margin_top=6)
        folder = Gtk.Box(spacing=6, halign=Gtk.Align.CENTER)
        folder.append(Gtk.Image(icon_name="folder-symbolic", css_classes=["dim-label"]))
        folder.append(Gtk.Label(label=session.folder_name, css_classes=["dim-label"], ellipsize=Pango.EllipsizeMode.MIDDLE))
        box.append(folder)

        self.stack = Gtk.Stack(vhomogeneous=False, transition_type=Gtk.StackTransitionType.CROSSFADE)
        starting = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, height_request=280,
                           valign=Gtk.Align.CENTER, halign=Gtk.Align.CENTER)
        starting.append(Gtk.Spinner(spinning=True, width_request=32, height_request=32))
        starting.append(Gtk.Label(label=tr("Başlatılıyor…"), css_classes=["dim-label"]))
        self.stack.add_named(starting, "starting")
        self.running_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        self.stack.add_named(self.running_box, "running")
        self.failed_page = Adw.StatusPage(icon_name="network-wireless-offline-symbolic",
                                          title=tr("Oturum başlatılamadı"), height_request=220)
        self.stack.add_named(self.failed_page, "failed")
        self.stack.add_named(Adw.StatusPage(
            icon_name="emblem-ok-symbolic", title=tr("Oturum sona erdi"), height_request=220,
            description=tr("Telefondaki sayfa artık dosya gönderemez. Yeniden eklemek için yeni bir QR kod "
                           "oluşturun.")), "stopped")
        box.append(self.stack)

        # Gelen dosyalar
        self.list_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6, visible=False)
        self.list_title = Gtk.Label(xalign=0, css_classes=["heading"])
        self.list_box.append(self.list_title)
        self.rows = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE, css_classes=["boxed-list"])
        scroller = Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER, propagate_natural_height=True,
                                      max_content_height=180)
        scroller.set_child(self.rows)
        self.list_box.append(scroller)
        box.append(self.list_box)

        box.append(Gtk.Separator())
        footer = Gtk.Box(spacing=8)
        footer.append(Gtk.Image(icon_name="system-lock-screen-symbolic", css_classes=["dim-label"]))
        footer.append(Gtk.Label(label=tr("Uçtan uca şifreli · internete çıkmaz"), xalign=0, hexpand=True,
                                wrap=True, css_classes=["caption", "dim-label"]))
        self.button = Gtk.Button(label=tr("Durdur"), valign=Gtk.Align.CENTER, css_classes=["pill"])
        self.button.connect("clicked", lambda *_: self.close())
        footer.append(self.button)
        box.append(footer)
        toolbar.set_content(box)
        self.set_child(toolbar)

        # Kilitlenince oturum durur ve pencere kapanır.
        handler = state.connect("phase-changed", lambda *_: self.force_close())
        self.connect("closed", lambda *_: (state.disconnect(handler), self._finish()))
        self._start()

    # MARK: Akış

    def _start(self) -> None:
        session = self.session

        def work():
            host = primary_ipv4()
            if not host:
                raise ConnectionError(tr("Bu bilgisayar bir Wi-Fi ya da yerel ağa bağlı görünmüyor. "
                                         "Telefonla aynı ağa bağlanıp yeniden deneyin."))
            return session.start(host), phone_network_warning(host), host

        def finished(result, error):
            if self.phase != "starting":
                session.stop()
                return
            if error is not None:
                session.stop()
                message = str(error) if isinstance(error, ConnectionError) else \
                    tr("Oturum başlatılamadı: {error}", error=str(error) or error.__class__.__name__)
                self._set_failed(message)
                return
            url, warn, host = result
            self._show_running(url, host if warn else None)

        self.state.run_background(work, finished)

    def _show_running(self, url: str, unreachable_host: str | None = None) -> None:
        self.phase = "running"
        if unreachable_host:
            self.running_box.append(_network_warning(unreachable_host))
        frame = Gtk.Box(halign=Gtk.Align.CENTER, css_classes=["qr-frame"])
        frame.append(QRCodeView(url, size=240))
        self.running_box.append(frame)
        self.running_box.append(Gtk.Label(label=tr("Telefonun kamerasıyla okutun"), css_classes=["heading"]))
        self.running_box.append(Gtk.Label(
            label=tr("Açılan sayfada fotoğraf, video ya da dosya seçin. Dosyalar telefonda şifrelenir ve kasaya "
                     "şifreli olarak yazılır; telefon bu bilgisayarla aynı Wi-Fi ağında olmalı."),
            wrap=True, justify=Gtk.Justification.CENTER, max_width_chars=44, css_classes=["dim-label"]))
        status = Gtk.Box(spacing=16, halign=Gtk.Align.CENTER)
        timer_box = Gtk.Box(spacing=6)
        timer_box.append(Gtk.Image(icon_name="alarm-symbolic"))
        self.timer_label = Gtk.Label(css_classes=["numeric"])
        timer_box.append(self.timer_label)
        status.append(timer_box)
        device_box = Gtk.Box(spacing=6)
        self.device_icon = Gtk.Image(icon_name="phone-symbolic")
        device_box.append(self.device_icon)
        self.device_label = Gtk.Label()
        device_box.append(self.device_label)
        status.append(device_box)
        self.running_box.append(status)
        self.stack.set_visible_child_name("running")
        self._tick()
        self._timer = GLib.timeout_add(500, self._tick)

    def _tick(self) -> bool:
        self._refresh_list()
        if self.phase != "running":
            self._timer = 0
            return False
        left = self.session.seconds_left
        if left <= 0 or self.session.server.stopped:
            self._timer = 0
            self._set_stopped()
            return False
        self.timer_label.set_label(tr("{time} kaldı", time=f"{left // 60}:{left % 60:02d}"))
        devices = len(self.session.devices)
        self.device_label.set_label(tr("{n} cihaz bağlandı", n=devices) if devices else tr("Henüz bağlanan yok"))
        if devices:
            self.device_label.add_css_class("success")
            self.device_icon.add_css_class("success")
        return True

    def _refresh_list(self) -> None:
        items = self.session.snapshot()
        if items == self._shown:
            return
        self._shown = items
        self.list_box.set_visible(bool(items))
        saved = sum(1 for _n, i in items if i["state"] == "saved")
        self.list_title.set_label(tr("{n} dosya eklendi", n=saved))
        while (row := self.rows.get_row_at_index(0)) is not None:
            self.rows.remove(row)
        for _n, item in items:
            row = Gtk.Box(spacing=10, margin_start=10, margin_end=10, margin_top=7, margin_bottom=7)
            icon, css = _state_icon(item["state"])
            row.append(Gtk.Image(icon_name=icon, css_classes=[css] if css else [], valign=Gtk.Align.CENTER))
            texts = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3, hexpand=True)
            texts.append(Gtk.Label(label=item["name"], xalign=0, ellipsize=Pango.EllipsizeMode.MIDDLE))
            if item["state"] == "receiving":
                texts.append(Gtk.ProgressBar(fraction=min(1.0, item["received"] / max(item["size"], 1))))
            else:
                texts.append(Gtk.Label(label=_state_text(item["state"]), xalign=0, css_classes=["caption", "dim-label"]))
            row.append(texts)
            row.append(Gtk.Label(label=format_size(item["size"]), css_classes=["caption", "dim-label", "numeric"]))
            self.rows.append(row)

    def _set_failed(self, message: str) -> None:
        self.phase = "failed"
        self.failed_page.set_description(message)
        self.stack.set_visible_child_name("failed")
        self.button.set_label(tr("Kapat"))

    def _set_stopped(self) -> None:
        self.session.stop()
        self.phase = "stopped"
        self.stack.set_visible_child_name("stopped")
        self.button.set_label(tr("Kapat"))
        self._refresh_list()

    def _finish(self) -> None:
        if self._timer:
            GLib.source_remove(self._timer)
            self._timer = 0
        self.phase = "stopped"
        self.state.stop_phone_upload(self.session)
