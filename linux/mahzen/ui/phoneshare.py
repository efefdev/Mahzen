"""“Telefonda Göster” penceresi: QR kodu ve paylaşımın durumu. Kapatılınca paylaşım da durur."""

from __future__ import annotations

from gi.repository import Adw, GLib, Gtk

from ..core import qr
from ..core.phoneshare import PhoneShareSession, primary_ipv4
from ..i18n import tr

QUIET_ZONE = 4


def _summary(session: PhoneShareSession) -> str:
    parts = []
    if session.photo_count:
        parts.append(tr("{n} fotoğraf", n=session.photo_count))
    if session.video_count:
        parts.append(tr("{n} video", n=session.video_count))
    return f"{session.title} · " + ", ".join(parts)


class QRCodeView(Gtk.DrawingArea):
    """QR kodunu her boyutta keskin çizer (modüller tam piksele yuvarlanır)."""

    def __init__(self, text: str, size: int = 264):
        super().__init__(content_width=size, content_height=size, halign=Gtk.Align.CENTER)
        self.matrix = qr.encode(text)
        self.update_property([Gtk.AccessibleProperty.LABEL], [tr("Paylaşım QR kodu")])
        self.set_draw_func(self._draw)

    def _draw(self, _area, cr, width: int, height: int) -> None:
        count = len(self.matrix) + 2 * QUIET_ZONE
        scale = max(1, min(width, height) // count)
        ox = (width - scale * count) // 2 + QUIET_ZONE * scale
        oy = (height - scale * count) // 2 + QUIET_ZONE * scale
        cr.set_source_rgb(1, 1, 1)
        cr.paint()
        cr.set_source_rgb(0, 0, 0)
        for y, row in enumerate(self.matrix):
            for x, dark in enumerate(row):
                if dark:
                    cr.rectangle(ox + x * scale, oy + y * scale, scale, scale)
        cr.fill()


class PhoneShareDialog(Adw.Dialog):
    def __init__(self, state, session: PhoneShareSession):
        super().__init__(title=tr("Telefonda Göster"), content_width=440)
        self.state = state
        self.session = session
        self.phase = "starting"  # starting | running | failed | stopped
        self._timer = 0

        toolbar = Adw.ToolbarView()
        toolbar.add_top_bar(Adw.HeaderBar())
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=18, margin_start=24, margin_end=24,
                      margin_bottom=24, margin_top=6)
        box.append(Gtk.Label(label=_summary(session), css_classes=["dim-label"], wrap=True,
                             justify=Gtk.Justification.CENTER))

        self.stack = Gtk.Stack(vhomogeneous=False, transition_type=Gtk.StackTransitionType.CROSSFADE)
        starting = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, height_request=300,
                           valign=Gtk.Align.CENTER, halign=Gtk.Align.CENTER)
        starting.append(Gtk.Spinner(spinning=True, width_request=32, height_request=32))
        starting.append(Gtk.Label(label=tr("Başlatılıyor…"), css_classes=["dim-label"]))
        self.stack.add_named(starting, "starting")
        self.running_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        self.stack.add_named(self.running_box, "running")
        self.failed_page = Adw.StatusPage(icon_name="network-wireless-offline-symbolic",
                                          title=tr("Paylaşım başlatılamadı"), height_request=300)
        self.stack.add_named(self.failed_page, "failed")
        self.stack.add_named(Adw.StatusPage(
            icon_name="emblem-ok-symbolic", title=tr("Paylaşım sona erdi"), height_request=300,
            description=tr("Telefondaki sayfa artık açılmaz. Yeniden göstermek için yeni bir QR kod oluşturun.")),
            "stopped")
        box.append(self.stack)

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

        # Kilitlenince paylaşım durur ve pencere kapanır.
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
            return session.start(host)

        def finished(url, error):
            if self.phase != "starting":
                session.stop()
                return
            if error is not None:
                session.stop()
                message = str(error) if isinstance(error, ConnectionError) else \
                    tr("Paylaşım başlatılamadı: {error}", error=str(error) or error.__class__.__name__)
                self._set_failed(message)
                return
            self._show_running(url)

        self.state.run_background(work, finished)

    def _show_running(self, url: str) -> None:
        self.phase = "running"
        frame = Gtk.Box(halign=Gtk.Align.CENTER, css_classes=["qr-frame"])
        frame.append(QRCodeView(url))
        self.running_box.append(frame)
        self.running_box.append(Gtk.Label(label=tr("Telefonun kamerasıyla okutun"), css_classes=["heading"]))
        self.running_box.append(Gtk.Label(
            label=tr("Telefon bu bilgisayarla aynı Wi-Fi ağında olmalı. Dosyalar şifreli gelir, anahtar yalnızca "
                     "bu QR kodda bulunur."),
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
        self._timer = GLib.timeout_add_seconds(1, self._tick)

    def _tick(self) -> bool:
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

    def _finish(self) -> None:
        if self._timer:
            GLib.source_remove(self._timer)
            self._timer = 0
        self.phase = "stopped"
        self.state.stop_phone_share(self.session)
