"""Ayarlar: görünüm, güvenlik, anahtar dosyası, çöp kutusu, yedekleme ve bakım."""

from __future__ import annotations

import os

from gi.repository import Adw, Gio, GLib, Gtk

from ..core import vault as vaultmod
from ..core.passwords import STRENGTH_LABELS, strength
from .common import alert, ask_password, confirm, format_date, format_size

ACCENT_TITLES = [("indigo", "Çivit"), ("blue", "Mavi"), ("teal", "Turkuaz"), ("green", "Yeşil"),
                 ("orange", "Turuncu"), ("pink", "Pembe"), ("red", "Kırmızı"), ("purple", "Mor"),
                 ("graphite", "Grafit")]
APPEARANCES = [("system", "Sistem"), ("light", "Açık"), ("dark", "Koyu")]
FONT_DESIGNS = [("default", "Sistem"), ("serif", "Serif"), ("rounded", "Yuvarlak"), ("monospaced", "Eş aralıklı")]


class SettingsPage(Adw.Bin):
    def __init__(self, state, make_header):
        super().__init__()
        self.state = state
        self._loading = False
        toolbar = Adw.ToolbarView()
        toolbar.add_top_bar(make_header("Ayarlar"))
        page = Adw.PreferencesPage()
        toolbar.set_content(page)
        self.set_child(toolbar)

        # Görünüm
        look = Adw.PreferencesGroup(title="Görünüm")
        self.name_row = Adw.EntryRow(title="Kasa adı", show_apply_button=True)
        self.name_row.connect("apply", lambda r: self._pref(displayName=r.get_text().strip() or "Mahzen"))
        look.add(self.name_row)
        self.appearance_row = self._combo("Tema", [t for _, t in APPEARANCES],
                                          lambda i: self._pref(appearance=APPEARANCES[i][0]))
        look.add(self.appearance_row)
        self.accent_row = self._combo("Vurgu rengi", [t for _, t in ACCENT_TITLES],
                                      lambda i: self._pref(accent=ACCENT_TITLES[i][0]))
        look.add(self.accent_row)
        self.font_row = self._combo("Not yazı tipi", [t for _, t in FONT_DESIGNS],
                                    lambda i: self._pref(noteFontDesign=FONT_DESIGNS[i][0]))
        look.add(self.font_row)
        self.font_size_row = self._spin("Not yazı boyutu", 11, 28, lambda v: self._pref(noteFontSize=float(v)))
        look.add(self.font_size_row)
        page.add(look)

        # Güvenlik
        security = Adw.PreferencesGroup(title="Güvenlik")
        self.autolock_row = self._spin("Hareketsizlikte otomatik kilit (dakika)", 0, 240,
                                       lambda v: self._pref(autoLockMinutes=int(v)), subtitle="0 = kapalı")
        security.add(self.autolock_row)
        self.sleep_row = Adw.SwitchRow(title="Uykuda ve ekran kilitlenince kilitle")
        self.sleep_row.connect("notify::active", lambda r, _p: self._pref(lockOnSleep=r.get_active()))
        security.add(self.sleep_row)
        self.clip_row = self._spin("Kopyalanan parolayı panodan sil (saniye)", 0, 600,
                                   lambda v: self._pref(clipboardClearSeconds=int(v)), subtitle="0 = silme")
        security.add(self.clip_row)
        self.kdf_row = Adw.ActionRow(title="Şifreleme", subtitle_selectable=True)
        security.add(self.kdf_row)
        change = Adw.ButtonRow(title="Parolayı Değiştir…") if hasattr(Adw, "ButtonRow") else None
        if change:
            change.connect("activated", lambda *_: self._change_password())
            security.add(change)
        else:
            row = Adw.ActionRow(title="Ana parola", activatable=True)
            btn = Gtk.Button(label="Değiştir…", valign=Gtk.Align.CENTER)
            btn.connect("clicked", lambda *_: self._change_password())
            row.add_suffix(btn)
            row.set_activatable_widget(btn)
            security.add(row)
        page.add(security)

        # Yanlış parola sınırı
        wipe = Adw.PreferencesGroup(
            title="Yanlış parola sınırı",
            description="Açıkken art arda bu kadar yanlış parola girilirse kasanın anahtarları yok edilir ve kasadaki "
                        "her şey kalıcı olarak açılamaz hale gelir; geri alınamaz. Sayaç doğru parolayla açılınca "
                        "sıfırlanır. Anahtar dosyalı bir kasayı başka bir bilgisayarda açmaya çalışmak da yanlış "
                        "deneme sayılır. Yedekler bu ayardan etkilenmez.")
        self.wipe_row = Adw.SwitchRow(title="Yanlış parolada kasayı kalıcı olarak sil")
        self.wipe_row.connect("notify::active", self._on_wipe_toggled)
        wipe.add(self.wipe_row)
        self.wipe_count_row = Adw.SpinRow.new_with_range(vaultmod.AUTO_WIPE_MIN, vaultmod.AUTO_WIPE_MAX, 1)
        self.wipe_count_row.set_title("Deneme sayısı")
        self.wipe_count_row.connect(
            "notify::value", lambda r, _p: None if self._loading else self.state.set_auto_wipe(int(r.get_value())))
        wipe.add(self.wipe_count_row)
        page.add(wipe)

        # Anahtar dosyası
        keyfile = Adw.PreferencesGroup(
            title="Anahtar dosyası",
            description="Etkinleştirilirse kasa parola ile birlikte bu bilgisayarda saklanan rastgele bir dosya "
                        "ister. Başka bir bilgisayarda açmak için anahtar dosyasını dışa aktarıp orada içe "
                        "aktarın. Anahtar dosyası kaybolursa kasa açılamaz; yedeğini alın.")
        self.keyfile_row = Adw.ActionRow(title="Anahtar dosyası")
        self.keyfile_btn = Gtk.Button(valign=Gtk.Align.CENTER)
        self.keyfile_btn.connect("clicked", lambda *_: self._toggle_keyfile())
        self.keyfile_row.add_suffix(self.keyfile_btn)
        keyfile.add(self.keyfile_row)
        self.keyfile_export_row = Adw.ActionRow(title="Anahtar dosyasını dışa aktar",
                                                subtitle="Yedek almak veya başka bir bilgisayara taşımak için")
        export_btn = Gtk.Button(label="Dışa Aktar…", valign=Gtk.Align.CENTER)
        export_btn.connect("clicked", lambda *_: self._export_keyfile())
        self.keyfile_export_row.add_suffix(export_btn)
        keyfile.add(self.keyfile_export_row)
        page.add(keyfile)

        # Çöp kutusu
        trash = Adw.PreferencesGroup(title="Çöp kutusu")
        self.retention_row = self._spin("Öğeleri şu kadar gün sonra kalıcı sil", 0, 365,
                                        lambda v: self._pref(trashRetentionDays=int(v)), subtitle="0 = silme")
        trash.add(self.retention_row)
        self.ask_trash_row = Adw.SwitchRow(title="Ekledikten sonra orijinalleri çöpe taşımayı sor")
        self.ask_trash_row.connect("notify::active", lambda r, _p: self._pref(askToTrashOriginals=r.get_active()))
        trash.add(self.ask_trash_row)
        page.add(trash)

        # Yedekleme
        backup = Adw.PreferencesGroup(
            title="Yedekleme",
            description="Şifreli dosyalar olduğu gibi kopyalanır; yedek aynı parolayla açılır. "
                        "Yalnızca değişen dosyalar kopyalanır.")
        self.backup_path_row = Adw.ActionRow(title="Yedek konumu", subtitle_selectable=True)
        choose = Gtk.Button(label="Seç…", valign=Gtk.Align.CENTER)
        choose.connect("clicked", lambda *_: self._choose_backup())
        self.backup_path_row.add_suffix(choose)
        backup.add(self.backup_path_row)
        self.backup_now_row = Adw.ActionRow(title="Son yedek")
        self.backup_btn = Gtk.Button(label="Şimdi Yedekle", valign=Gtk.Align.CENTER, css_classes=["suggested-action"])
        self.backup_btn.connect("clicked", lambda *_: self.state.backup_now(self.refresh))
        self.backup_now_row.add_suffix(self.backup_btn)
        backup.add(self.backup_now_row)
        self.reminder_row = self._spin("Son yedekten bu kadar gün sonra hatırlat", 0, 90,
                                       lambda v: self._pref(backupReminderDays=int(v)), subtitle="0 = hatırlatma")
        backup.add(self.reminder_row)
        page.add(backup)

        # Bakım
        maintenance = Adw.PreferencesGroup(title="Bakım")
        scan_row = Adw.ActionRow(title="Bütünlük taraması",
                                 subtitle="Her dosyayı çözerek doğrular; bozuk olanları yedekten geri yükler.")
        scan_btn = Gtk.Button(label="Tara", valign=Gtk.Align.CENTER)
        scan_btn.connect("clicked", lambda *_: self.state.run_integrity_scan(self._show_report))
        scan_row.add_suffix(scan_btn)
        maintenance.add(scan_row)
        self.location_row = Adw.ActionRow(title="Kasa konumu", subtitle_selectable=True)
        show = Gtk.Button(icon_name="folder-open-symbolic", tooltip_text="Dosya yöneticisinde göster",
                          valign=Gtk.Align.CENTER, css_classes=["flat"])
        show.connect("clicked", lambda *_: self._show_folder())
        self.location_row.add_suffix(show)
        maintenance.add(self.location_row)
        self.stats_row = Adw.ActionRow(title="İçerik")
        maintenance.add(self.stats_row)
        page.add(maintenance)

        state.connect("prefs-changed", lambda *_: self.refresh())
        state.connect("phase-changed", lambda *_: self.refresh())

    # MARK: - Yardımcılar

    def _combo(self, title, items, on_change) -> Adw.ComboRow:
        row = Adw.ComboRow(title=title, model=Gtk.StringList.new(items))
        row.connect("notify::selected", lambda r, _p: None if self._loading else on_change(r.get_selected()))
        return row

    def _spin(self, title, low, high, on_change, subtitle="") -> Adw.SpinRow:
        row = Adw.SpinRow.new_with_range(low, high, 1)
        row.set_title(title)
        if subtitle:
            row.set_subtitle(subtitle)
        row.connect("notify::value", lambda r, _p: None if self._loading else on_change(r.get_value()))
        return row

    def _pref(self, **values) -> None:
        if not self._loading and self.state.phase == "unlocked":
            self.state.update_prefs(**values)

    def refresh(self, *_args) -> None:
        if self.state.phase != "unlocked" or not self.state.vault:
            return
        p = self.state.prefs
        v = self.state.vault
        self._loading = True
        self.name_row.set_text(p.get("displayName") or "Mahzen")
        self.appearance_row.set_selected(_index_of(APPEARANCES, p.get("appearance")))
        self.accent_row.set_selected(_index_of(ACCENT_TITLES, p.get("accent")))
        self.font_row.set_selected(_index_of(FONT_DESIGNS, p.get("noteFontDesign")))
        self.font_size_row.set_value(float(p.get("noteFontSize", 15)))
        self.autolock_row.set_value(int(p.get("autoLockMinutes", 5)))
        self.sleep_row.set_active(bool(p.get("lockOnSleep", True)))
        self.clip_row.set_value(int(p.get("clipboardClearSeconds", 30)))
        self.kdf_row.set_subtitle(f"AES-256-GCM · {v.header.kdf_summary}")
        enabled = v.requires_keyfile
        self.keyfile_row.set_subtitle("Etkin: kasa parola + bu bilgisayardaki anahtar dosyasıyla açılıyor" if enabled
                                      else "Kapalı: kasa yalnızca parolayla açılıyor")
        self.keyfile_btn.set_label("Kapat…" if enabled else "Etkinleştir…")
        self.keyfile_export_row.set_visible(enabled)
        limit = v.header.wipe_after_failed_attempts
        self.wipe_row.set_active(limit is not None)
        self.wipe_count_row.set_visible(limit is not None)
        self.wipe_count_row.set_value(limit or vaultmod.DEFAULT_AUTO_WIPE_ATTEMPTS)
        self.retention_row.set_value(int(p.get("trashRetentionDays", 30)))
        self.ask_trash_row.set_active(bool(p.get("askToTrashOriginals", True)))
        self.backup_path_row.set_subtitle(p.get("backupPath") or "Seçilmedi")
        self.backup_now_row.set_subtitle(format_date(p.get("lastBackupAt")) if p.get("lastBackupAt") else "Hiç")
        self.backup_btn.set_sensitive(bool(p.get("backupPath")))
        self.reminder_row.set_value(int(p.get("backupReminderDays", 7)))
        self.location_row.set_subtitle(v.folder)
        idx = self.state.index
        total = sum(int(f.get("size", 0)) for f in idx.live_files)
        notes = sum(1 for n in idx.notes if not n.get("deletedAt"))
        secrets = sum(1 for s in idx.secrets if not s.get("deletedAt"))
        self.stats_row.set_subtitle(f"{len(idx.live_files)} dosya ({format_size(total)}) · {notes} not · "
                                    f"{secrets} parola kaydı")
        self._loading = False

    def _show_folder(self) -> None:
        if self.state.vault:
            Gtk.FileLauncher.new(Gio.File.new_for_path(self.state.vault.folder)).launch(self.get_root(), None, None)

    # MARK: - Parola

    def _change_password(self) -> None:
        dialog = Adw.AlertDialog(heading="Parolayı değiştir",
                                 body="Dosyalar yeniden şifrelenmez; ana anahtar yeni parolayla yeniden sarılır.")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        current = Gtk.PasswordEntry(show_peek_icon=True)
        current.set_property("placeholder-text", "Mevcut parola")
        new = Gtk.PasswordEntry(show_peek_icon=True)
        new.set_property("placeholder-text", f"Yeni parola (en az {vaultmod.MINIMUM_PASSWORD_LENGTH} karakter)")
        repeat = Gtk.PasswordEntry(show_peek_icon=True, activates_default=True)
        repeat.set_property("placeholder-text", "Yeni parola (tekrar)")
        meter = Gtk.Label(css_classes=["caption", "dim-label"], xalign=0)
        for w in (current, new, repeat, meter):
            box.append(w)
        dialog.set_extra_child(box)
        dialog.add_response("cancel", "Vazgeç")
        dialog.add_response("ok", "Değiştir")
        dialog.set_response_appearance("ok", Adw.ResponseAppearance.SUGGESTED)
        dialog.set_response_enabled("ok", False)
        dialog.set_default_response("ok")
        dialog.set_close_response("cancel")

        def validate(*_):
            pw = new.get_text()
            meter.set_text(f"Parola gücü: {STRENGTH_LABELS[strength(pw)[0]]}" if pw else "")
            dialog.set_response_enabled("ok", bool(current.get_text()) and pw == repeat.get_text()
                                        and len(pw) >= vaultmod.MINIMUM_PASSWORD_LENGTH)

        for w in (current, new, repeat):
            w.connect("changed", validate)

        def on_response(_d, response):
            if response != "ok":
                return
            self.state.change_password(current.get_text(), new.get_text(), lambda err: alert(
                self, "Parola değiştirilemedi", err) if err else self.state.toast("Parola değiştirildi"))

        dialog.connect("response", on_response)
        dialog.present(self)
        GLib.idle_add(lambda: current.grab_focus() and False)

    # MARK: - Yanlış parola sınırı

    def _on_wipe_toggled(self, row, _pspec) -> None:
        if self._loading:
            return
        if not row.get_active():
            self.state.set_auto_wipe(None)
            return
        n = vaultmod.DEFAULT_AUTO_WIPE_ATTEMPTS
        dialog = Adw.AlertDialog(
            heading="Yanlış parola sınırı açılsın mı?",
            body=f"Art arda {n} yanlış parola girilirse kasa kalıcı olarak silinir ve hiçbir şekilde geri "
                 "getirilemez. Deneme sayısını sonra değiştirebilirsiniz. Güncel bir yedeğiniz olduğundan emin olun.")
        dialog.add_response("cancel", "Vazgeç")
        dialog.add_response("ok", f"{n} Yanlış Denemede Sil")
        dialog.set_response_appearance("ok", Adw.ResponseAppearance.DESTRUCTIVE)
        dialog.set_default_response("cancel")
        dialog.set_close_response("cancel")

        def on_response(_d, response):
            if response == "ok":
                self.state.set_auto_wipe(n)
            else:
                self.refresh()  # anahtarı geri kapat

        dialog.connect("response", on_response)
        dialog.present(self)

    # MARK: - Anahtar dosyası

    def _toggle_keyfile(self) -> None:
        v = self.state.vault
        if not v:
            return
        if v.requires_keyfile:
            ask_password(self, "Anahtar dosyası kapatılsın mı?",
                         "Kasa bundan sonra yalnızca parolayla açılır. Mevcut anahtar dosyası silinmez, arşivlenir.",
                         "Kapat", lambda pw: self.state.disable_keyfile(pw, self._keyfile_done("kapatıldı")))
        else:
            ask_password(self, "Anahtar dosyası etkinleştirilsin mi?",
                         "Bu bilgisayarda rastgele bir anahtar dosyası oluşturulur ve kasa bundan sonra parola ile "
                         "birlikte bu dosyayı ister. Başka bilgisayarlarda açmak için dosyayı dışa aktarmanız gerekir.",
                         "Etkinleştir", lambda pw: self.state.enable_keyfile(pw, self._keyfile_done("etkinleştirildi")))

    def _keyfile_done(self, verb: str):
        def done(error):
            if error:
                alert(self, "Anahtar dosyası değiştirilemedi", error)
            else:
                self.state.toast(f"Anahtar dosyası {verb}")
                self.refresh()
        return done

    def _export_keyfile(self) -> None:
        dialog = Gtk.FileDialog(title="Anahtar dosyasını kaydet", initial_name="Mahzen.mahzenkey", modal=True)

        def done(d, result):
            try:
                f = d.save_finish(result)
            except GLib.Error:
                return
            if f and f.get_path():
                self.state.export_keyfile(f.get_path())

        dialog.save(self.get_root(), None, done)

    # MARK: - Yedekleme

    def _choose_backup(self) -> None:
        dialog = Gtk.FileDialog(title="Yedeğin konulacağı klasörü seç", modal=True)

        def done(d, result):
            try:
                folder = d.select_folder_finish(result)
            except GLib.Error:
                return
            path = folder.get_path() if folder else None
            if not path:
                return
            # Seçilen klasör zaten bu kasanın yedeğiyse onu kullan; değilse içine bir alt klasör aç.
            if not vaultmod.exists(path):
                path = os.path.join(path, "Mahzen Kasası Yedek")
            self.state.update_prefs(backupPath=path)
            self.refresh()

        dialog.select_folder(self.get_root(), None, done)

    # MARK: - Bütünlük raporu

    def _show_report(self, report) -> None:
        idx = self.state.index
        lines = [f"{report.checked_files} dosya ({format_size(report.checked_bytes)}) doğrulandı."]
        names = {f["id"]: f["name"] for f in idx.files}
        problems = list(report.problems.items())
        if not problems and not report.orphan_paths and not report.broken_thumbnails and report.index_backup_readable:
            alert(self, "Her şey yolunda", lines[0] + "\nHiçbir sorun bulunmadı.")
            return
        for fid, problem in problems[:12]:
            text = {"missing": "eksik", "hashMismatch": "içerik özeti tutmuyor"}.get(problem, "bozuk")
            lines.append(f"• {names.get(fid, fid)}: {text}")
        if len(problems) > 12:
            lines.append(f"… ve {len(problems) - 12} dosya daha")
        if report.broken_thumbnails:
            lines.append(f"{len(report.broken_thumbnails)} küçük resim okunamadı (kaldırıldı).")
        if report.orphan_paths:
            lines.append(f"{len(report.orphan_paths)} sahipsiz dosya ({format_size(report.orphan_bytes)}).")
        if not report.index_backup_readable:
            lines.append("Dizin yedeği (index.enc.bak) okunamıyor; bir sonraki kayıtta yenilenecek.")

        dialog = Adw.AlertDialog(heading="Tarama sonucu", body="\n".join(lines))
        dialog.add_response("close", "Kapat")
        if report.orphan_paths:
            dialog.add_response("orphans", "Sahipsizleri Sil")
            dialog.set_response_appearance("orphans", Adw.ResponseAppearance.DESTRUCTIVE)
        if problems and self.state.prefs.get("backupPath"):
            dialog.add_response("restore", "Yedekten Geri Yükle")
            dialog.set_response_appearance("restore", Adw.ResponseAppearance.SUGGESTED)

        def on_response(_d, response):
            if response == "orphans":
                confirm(self, "Sahipsiz dosyalar silinsin mi?",
                        "Bunlar dizinde kaydı olmayan şifreli dosyalardır (ör. yarım kalmış eklemeler).",
                        "Sil", lambda: self.state.remove_orphans(report.orphan_paths))
            elif response == "restore":
                self.state.restore_from_backup([fid for fid, _ in problems], lambda failures: alert(
                    self, "Bazı dosyalar geri yüklenemedi", "\n".join(failures[:8])) if failures
                    else self.state.toast("Yedekten geri yüklendi"))

        dialog.connect("response", on_response)
        dialog.present(self)


def _index_of(pairs, key) -> int:
    for i, (k, _t) in enumerate(pairs):
        if k == key:
            return i
    return 0
