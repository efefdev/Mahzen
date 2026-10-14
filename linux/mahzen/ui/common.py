"""Arayüz yardımcıları: dosya türleri, biçimlendirme, iletişim kutuları."""

from __future__ import annotations

import os
from datetime import datetime

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, GLib, Gtk  # noqa: E402

from ..core.filetypes import (ICONS, IMAGE_PREVIEWABLE, content_type_for, extension,  # noqa: E402,F401
                              icon_for, kind_of)
from ..core.index import parse_date  # noqa: E402


def format_size(size: int) -> str:
    units = ["bayt", "KB", "MB", "GB", "TB"]
    value = float(size)
    for unit in units:
        if value < 1000 or unit == units[-1]:
            if unit == "bayt":
                return f"{int(value)} bayt"
            return f"{value:.1f} {unit}".replace(".", ",")
        value /= 1000
    return f"{size} bayt"


_MONTHS = ["Oca", "Şub", "Mar", "Nis", "May", "Haz", "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"]


def format_date(value: str | None, with_time: bool = True) -> str:
    d = parse_date(value)
    if not d:
        return "—"
    local = d.astimezone()
    text = f"{local.day} {_MONTHS[local.month - 1]} {local.year}"
    if with_time:
        text += f" {local.hour:02d}:{local.minute:02d}"
    return text


def relative_date(value: str | None) -> str:
    d = parse_date(value)
    if not d:
        return "—"
    delta = datetime.now(d.tzinfo) - d
    if delta.days == 0:
        return f"Bugün {d.astimezone().hour:02d}:{d.astimezone().minute:02d}"
    if delta.days == 1:
        return "Dün"
    if delta.days < 7:
        return f"{delta.days} gün önce"
    return format_date(value, with_time=False)


# MARK: - İletişim kutuları

def alert(parent: Gtk.Widget, title: str, body: str = "") -> None:
    dialog = Adw.AlertDialog(heading=title, body=body)
    dialog.add_response("ok", "Tamam")
    dialog.present(parent)


def confirm(parent: Gtk.Widget, title: str, body: str, action: str, callback, destructive: bool = True) -> None:
    dialog = Adw.AlertDialog(heading=title, body=body)
    dialog.add_response("cancel", "Vazgeç")
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
    dialog.add_response("cancel", "Vazgeç")
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
    entry.set_property("placeholder-text", "Kasa parolası")
    dialog.set_extra_child(entry)
    dialog.add_response("cancel", "Vazgeç")
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
