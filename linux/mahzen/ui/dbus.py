"""Oturum veriyolunda `dev.efef.Mahzen1` arayüzü: masaüstü kabuğu kasayı kilitleyebilsin ve durumunu görsün.

Ad `dev.efef.Mahzen` (GApplication'ın kendi adı), nesne `/dev/efef/Mahzen1`. Arayüz bilinçli olarak dar:
kasayı açmak veya içeriğini okumak yok; yalnızca kilit durumu, kilitleme ve kasa adları (yol değil).
Uygulama çalışmıyorsa arayüz de yoktur (D-Bus ile kendiliğinden başlatılmaz).

    gdbus call --session -d dev.efef.Mahzen -o /dev/efef/Mahzen1 -m dev.efef.Mahzen1.Lock
"""

from __future__ import annotations

import os

from gi.repository import Gio, GLib

OBJECT_PATH = "/dev/efef/Mahzen1"
INTERFACE = "dev.efef.Mahzen1"

INTROSPECTION = f"""<node>
  <interface name="{INTERFACE}">
    <!-- Kasa kilitli mi (açık kasa yoksa da true). -->
    <property name="Locked" type="b" access="read"/>
    <!-- Seçili kasanın klasör adı; tam yol verilmez. Kasa seçilmemişse boş. -->
    <property name="Vaults" type="as" access="read"/>
    <!-- Kasayı hemen kilitler. Kasa açıktı ve bu çağrıyla kilitlendiyse true döner. -->
    <method name="Lock">
      <arg name="locked_now" type="b" direction="out"/>
    </method>
    <signal name="LockedChanged">
      <arg name="locked" type="b"/>
    </signal>
  </interface>
</node>"""


class DBusService:
    """`AppState`'i veriyoluna yansıtır. `MahzenApp.do_dbus_register` içinde kaydedilir."""

    def __init__(self, state):
        self.state = state
        self._registrations: list[tuple[Gio.DBusConnection, int]] = []
        self._locked = self._is_locked()
        self._vaults = self._vault_names()
        state.connect("phase-changed", self._on_phase)

    def _is_locked(self) -> bool:
        return self.state.phase != "unlocked"

    def _vault_names(self) -> list[str]:
        path = self.state.vault_path
        return [os.path.basename(os.path.normpath(path))] if path else []

    def register(self, connection: Gio.DBusConnection) -> None:
        info = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION).interfaces[0]
        rid = connection.register_object(OBJECT_PATH, info, self._on_call, self._on_get_property, None)
        self._registrations.append((connection, rid))

    def unregister(self, connection: Gio.DBusConnection) -> None:
        for conn, rid in list(self._registrations):
            if conn is connection:
                conn.unregister_object(rid)
                self._registrations.remove((conn, rid))

    def _on_call(self, _conn, _sender, _path, _iface, method, _params, invocation) -> None:
        if method == "Lock":
            was_open = not self._is_locked()
            # Kullanıcının açık isteği: "uykuda kilitle" ayarından bağımsız, her zaman kilitler.
            self.state.lock()
            invocation.return_value(GLib.Variant("(b)", (was_open and self._is_locked(),)))
        else:
            invocation.return_dbus_error("org.freedesktop.DBus.Error.UnknownMethod", method)

    def _on_get_property(self, _conn, _sender, _path, _iface, name):
        if name == "Locked":
            return GLib.Variant("b", self._is_locked())
        if name == "Vaults":
            return GLib.Variant("as", self._vault_names())
        return None

    def _on_phase(self, *_args) -> None:
        locked, vaults = self._is_locked(), self._vault_names()
        changed = {}
        if locked != self._locked:
            changed["Locked"] = GLib.Variant("b", locked)
        if vaults != self._vaults:
            changed["Vaults"] = GLib.Variant("as", vaults)
        self._locked, self._vaults = locked, vaults
        if not changed:
            return
        for conn, _rid in self._registrations:
            try:
                conn.emit_signal(None, OBJECT_PATH, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                                 GLib.Variant("(sa{sv}as)", (INTERFACE, changed, [])))
                if "Locked" in changed:
                    conn.emit_signal(None, OBJECT_PATH, INTERFACE, "LockedChanged", GLib.Variant("(b)", (locked,)))
            except GLib.Error:
                pass
