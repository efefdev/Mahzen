"""Arayüz yardımcıları: dosya türleri, biçimlendirme, iletişim kutuları."""

from __future__ import annotations

import os
from datetime import datetime

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
gi.require_version("Graphene", "1.0")
from gi.repository import Adw, Gdk, GLib, Graphene, Gtk  # noqa: E402

from ..core.filetypes import (ICONS, IMAGE_PREVIEWABLE, content_type_for, extension,  # noqa: E402,F401
                              icon_for, kind_of)
from ..core.index import parse_date  # noqa: E402
from ..core.selection import point_from_result, rect_from_result  # noqa: E402
from ..i18n import decimal, tr  # noqa: E402


def format_size(size: int) -> str:
    units = ["", "KB", "MB", "GB", "TB"]
    value = float(size)
    for unit in units:
        if value < 1000 or unit == units[-1]:
            if not unit:
                return tr("{n} bayt", n=int(value))
            return f"{decimal(value)} {unit}"
        value /= 1000
    return tr("{n} bayt", n=size)


MONTHS = [tr("Ocak"), tr("Şubat"), tr("Mart"), tr("Nisan"), tr("Mayıs"), tr("Haziran"),
          tr("Temmuz"), tr("Ağustos"), tr("Eylül"), tr("Ekim"), tr("Kasım"), tr("Aralık")]


def format_date(value: str | None, with_time: bool = True) -> str:
    d = parse_date(value)
    if not d:
        return "—"
    local = d.astimezone()
    # Kısa ay adı iki dilde de tam adın ilk üç harfidir.
    text = tr("{day} {month} {year}", day=local.day, month=MONTHS[local.month - 1][:3], year=local.year)
    if with_time:
        text += f" {local.hour:02d}:{local.minute:02d}"
    return text


def relative_date(value: str | None) -> str:
    d = parse_date(value)
    if not d:
        return "—"
    delta = datetime.now(d.tzinfo) - d
    if delta.days == 0:
        return tr("Bugün {time}", time=f"{d.astimezone().hour:02d}:{d.astimezone().minute:02d}")
    if delta.days == 1:
        return tr("Dün")
    if delta.days < 7:
        return tr("{n} gün önce", n=delta.days)
    return format_date(value, with_time=False)


# MARK: - Çizim ve konum (cairo köprüsü gerektirmez)

def rgba(red: float, green: float, blue: float, alpha: float = 1.0) -> Gdk.RGBA:
    color = Gdk.RGBA()
    color.red, color.green, color.blue, color.alpha = red, green, blue, alpha
    return color


def fill_rect(snapshot: Gtk.Snapshot, x: float, y: float, width: float, height: float, color: Gdk.RGBA) -> None:
    snapshot.append_color(color, Graphene.Rect().init(x, y, width, height))


def widget_point(source: Gtk.Widget, target: Gtk.Widget, x: float, y: float) -> tuple[float, float] | None:
    """Bir noktayı `source` koordinatlarından `target` koordinatlarına çevirir."""
    if hasattr(source, "compute_point"):
        try:
            found = point_from_result(source.compute_point(target, Graphene.Point().init(x, y)))
        except (TypeError, ValueError):
            found = None
        if found is not None:
            return found
    try:
        return point_from_result(source.translate_coordinates(target, x, y))
    except (AttributeError, TypeError, ValueError):
        return None


def widget_bounds(widget: Gtk.Widget, target: Gtk.Widget) -> tuple[float, float, float, float] | None:
    """Öğenin `target` koordinatlarındaki dikdörtgeni."""
    try:
        return rect_from_result(widget.compute_bounds(target))
    except (TypeError, ValueError):
        return None


# MARK: - İletişim kutuları

def alert(parent: Gtk.Widget, title: str, body: str = "") -> None:
    dialog = Adw.AlertDialog(heading=title, body=body)
    dialog.add_response("ok", tr("Tamam"))
    dialog.present(parent)


def confirm(parent: Gtk.Widget, title: str, body: str, action: str, callback, destructive: bool = True) -> None:
    dialog = Adw.AlertDialog(heading=title, body=body)
    dialog.add_response("cancel", tr("Vazgeç"))
    dialog.add_response("ok", action)
    dialog.set_response_appearance(
        "ok", Adw.ResponseAppearance.DESTRUCTIVE if destructive else Adw.ResponseAppearance.SUGGESTED)
    dialog.set_default_response("cancel")
    dialog.set_close_response("cancel")
    dialog.connect("response", lambda _d, r: callback() if r == "ok" else None)
    dialog.present(parent)


def ask_text(parent: Gtk.Widget, title: str, initial: str, action: str, callback, body: str = "") -> None:
    """Tek satırlık metin sorar (ad değiştirme, yeni klasör vb.)."""
    dialog = Adw.AlertDialog(heading=title, body=body)
    entry = Gtk.Entry(text=initial, activates_default=True)
    dialog.set_extra_child(entry)
    dialog.add_response("cancel", tr("Vazgeç"))
    dialog.add_response("ok", action)
    dialog.set_response_appearance("ok", Adw.ResponseAppearance.SUGGESTED)
    dialog.set_default_response("ok")
    dialog.set_close_response("cancel")

    def on_response(_d, response):
        if response == "ok" and entry.get_text().strip():
            callback(entry.get_text().strip())

    dialog.connect("response", on_response)
    dialog.present(parent)
    GLib.idle_add(lambda: (entry.grab_focus(), entry.select_region(0, len(os.path.splitext(initial)[0])))[-1] and False)


def ask_password(parent: Gtk.Widget, title: str, body: str, action: str, callback) -> None:
    dialog = Adw.AlertDialog(heading=title, body=body)
    entry = Gtk.PasswordEntry(show_peek_icon=True, activates_default=True)
    entry.set_property("placeholder-text", tr("Kasa parolası"))
    dialog.set_extra_child(entry)
    dialog.add_response("cancel", tr("Vazgeç"))
    dialog.add_response("ok", action)
    dialog.set_response_appearance("ok", Adw.ResponseAppearance.SUGGESTED)
    dialog.set_default_response("ok")
    dialog.set_close_response("cancel")
    dialog.connect("response", lambda _d, r: callback(entry.get_text()) if r == "ok" and entry.get_text() else None)
    dialog.present(parent)
    GLib.idle_add(lambda: entry.grab_focus() and False)


def clear_box(box: Gtk.Widget) -> None:
    child = box.get_first_child()
    while child is not None:
        nxt = child.get_next_sibling()
        if isinstance(box, (Gtk.ListBox, Gtk.FlowBox)):
            box.remove(child)
        else:
            box.remove(child)
        child = nxt


def icon_button(icon: str, tooltip: str, callback=None, flat: bool = True) -> Gtk.Button:
    b = Gtk.Button(icon_name=icon, tooltip_text=tooltip, valign=Gtk.Align.CENTER)
    if flat:
        b.add_css_class("flat")
    if callback:
        b.connect("clicked", lambda *_: callback())
    return b
