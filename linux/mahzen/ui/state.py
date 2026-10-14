"""Uygulama durumu: açık kasa, dizin, arka plan işleri, otomatik kilit ve pano (macOS'taki `AppState`)."""

from __future__ import annotations

import os
import shutil
import threading
import time
import uuid
from dataclasses import dataclass
from typing import Callable

import gi

gi.require_version("Gdk", "4.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gdk, GdkPixbuf, Gio, GLib, GObject  # noqa: E402

from ..core import paths  # noqa: E402
from ..core import vault as vaultmod  # noqa: E402
from ..core.errors import Cancelled, WrongPassword  # noqa: E402
from ..core.importplan import ImportPlan  # noqa: E402
from ..core.index import VaultIndex, new_file_record, new_id, new_note, now  # noqa: E402
from ..core.keyfiles import KeyfileStore  # noqa: E402
from ..core.vault import Vault  # noqa: E402
from ..core.filetypes import IMAGE_PREVIEWABLE, content_type_for, extension  # noqa: E402


@dataclass
class TaskProgress:
    title: str
    detail: str = ""
    fraction: float | None = None
    cancellable: bool = False


class CancelFlag:
    def __init__(self):
        self.value = False


def _error_text(e: BaseException) -> str:
    text = str(e)
    if isinstance(e, OSError) and e.strerror:
        text = e.strerror + (f": {e.filename}" if e.filename else "")
    return text or e.__class__.__name__


class AppState(GObject.Object):
    __gsignals__ = {
        "phase-changed": (GObject.SignalFlags.RUN_FIRST, None, ()),
        "index-changed": (GObject.SignalFlags.RUN_FIRST, None, ()),
        "prefs-changed": (GObject.SignalFlags.RUN_FIRST, None, ()),
        "task-changed": (GObject.SignalFlags.RUN_FIRST, None, ()),
        "toast": (GObject.SignalFlags.RUN_FIRST, None, (str,)),
        "alert": (GObject.SignalFlags.RUN_FIRST, None, (str, str)),
        "offer-trash-originals": (GObject.SignalFlags.RUN_FIRST, None, (object,)),
    }

    def __init__(self):
        super().__init__()
        self.settings = paths.load_settings()
        self.phase = "welcome"  # welcome | locked | unlocked
        self.vault_path: str | None = None
        self.vault: Vault | None = None
        self.index = VaultIndex()
        self.recovered_from_backup = False
        self.task: TaskProgress | None = None
        self.current_folder: str | None = None
        self.keyfiles = KeyfileStore.standard()
        self.thumbnails: dict[str, Gdk.Texture | None] = {}
        self._thumb_waiters: dict[str, list] = {}
        self.integrity_report = None
        self._session = uuid.uuid4()
        self._cancel = CancelFlag()
        self._save_source = 0
        self._last_activity = time.monotonic()
        self._failed_attempts = 0
        self._sensitive_clip: str | None = None
        self._clip_source = 0
        runtime = os.environ.get("XDG_RUNTIME_DIR") or GLib.get_tmp_dir()
        self.temp_root = os.path.join(runtime, f"Mahzen-{uuid.uuid4()}")
        self._remove_stale_temporary_folders(runtime)

        remembered = self.settings.get("lastVaultPath")
        for candidate in [*paths.portable_vault_paths(), remembered]:
            if candidate and vaultmod.exists(candidate):
                self.vault_path = candidate
                self.phase = "locked"
                break
        GLib.timeout_add_seconds(5, self._tick)

    # MARK: - Yardımcılar

    @property
    def prefs(self) -> dict:
        return self.index.preferences

    def is_current(self, token) -> bool:
        return token == self._session and self.phase == "unlocked" and self.vault is not None

    def toast(self, message: str) -> None:
        self.emit("toast", message)

    def alert(self, title: str, message: str = "") -> None:
        self.emit("alert", title, message)

    def note_activity(self) -> None:
        self._last_activity = time.monotonic()

    def set_task(self, task: TaskProgress | None) -> None:
        self.task = task
        self.emit("task-changed")

    def _remember(self, **values) -> None:
        self.settings.update(values)
        paths.save_settings(self.settings)

    @staticmethod
    def _remove_stale_temporary_folders(root: str) -> None:
        """Önceki bir çalışmadan (ör. çökme) kalan, 1 saatten eski şifresiz geçici klasörleri siler."""
        try:
            names = os.listdir(root)
        except OSError:
            return
        cutoff = time.time() - 3600
        for name in names:
            path = os.path.join(root, name)
            if name.startswith("Mahzen-") and os.path.isdir(path):
                try:
                    if os.path.getmtime(path) < cutoff:
                        shutil.rmtree(path, ignore_errors=True)
                except OSError:
                    pass

    def run_background(self, work: Callable[[], object], done: Callable[[object, BaseException | None], None]) -> None:
        """`work` iş parçacığında çalışır; `done(sonuç, hata)` ana döngüde çağrılır."""
        def runner():
            try:
                result, error = work(), None
            except Exception as e:  # noqa: BLE001
                result, error = None, e
            GLib.idle_add(lambda: done(result, error) and False)

        threading.Thread(target=runner, daemon=True).start()

    # MARK: - Kasa açma / kapama

    def select_vault(self, path: str) -> None:
        if not vaultmod.exists(path):
            self.alert("Kasa bulunamadı", "Bu klasör bir Mahzen kasası değil.")
            return
        self.vault_path = path
        self.phase = "locked"
        self.emit("phase-changed")

    def show_welcome(self) -> None:
        self.phase = "welcome"
        self.emit("phase-changed")

    def create_vault(self, folder: str, password: str, done: Callable[[str | None], None]) -> None:
        self.set_task(TaskProgress("Kasa oluşturuluyor", "Anahtar türetiliyor…"))

        def finished(vault, error):
            self.set_task(None)
            if error:
                done(_error_text(error))
                return
            done(None)
            self._open(vault, VaultIndex(), False)

        self.run_background(lambda: Vault.create(folder, password), finished)

    def unlock(self, password: str, done: Callable[[str | None], None]) -> None:
        path = self.vault_path
        if not path:
            done("Kasa seçilmedi.")
            return

        def work():
            vault = self._unlock_with_keyfiles(path, password)
            vault.clear_failed_attempts()
            index, recovered = vault.load_index()
            # Eski (PBKDF2) kasaları doğru parola elimizdeyken Argon2id'ye yükselt.
            if vault.needs_kdf_upgrade:
                vault.upgrade_kdf(password)
            return vault, index, recovered

        def finished(result, error):
            if error:
                message = _error_text(error)
                if isinstance(error, WrongPassword):
                    # Yanlış parola sınırı açıksa say; aşıldıysa anahtarlar yok edilir.
                    try:
                        wiped, remaining = vaultmod.record_failed_attempt(path)
                    except Exception:  # noqa: BLE001
                        wiped, remaining = False, None
                    if wiped:
                        done("Kasa silindi.")
                        self._vault_wiped(path)
                        return
                    if remaining == 1:
                        message = "Parola yanlış. Son deneme hakkı: bir yanlış daha kasayı siler."
                    elif remaining is not None:
                        message = f"Parola yanlış. Kalan deneme: {remaining}"
                # Arayüzde deneme hızını yavaşlatır; asıl koruma anahtar türetmenin maliyetidir.
                self._failed_attempts += 1
                delay = min(self._failed_attempts, 5)
                GLib.timeout_add_seconds(delay, lambda: done(message) and False)
                return
            self._failed_attempts = 0
            done(None)
            self._open(*result)

        self.run_background(work, finished)

    def _vault_wiped(self, path: str) -> None:
        """Yanlış parola sınırı aşıldı: anahtarlar yok edildi, kasa artık açılamaz."""
        self._failed_attempts = 0
        self.vault_path = None
        if self.settings.get("lastVaultPath") == path:
            self.settings.pop("lastVaultPath", None)
            paths.save_settings(self.settings)
        self.phase = "welcome"
        self.emit("phase-changed")
        self.alert("Kasa kalıcı olarak silindi",
                   "Yanlış parola sınırı aşıldığı için kasanın anahtarları yok edildi. Kasadaki veriler artık hiçbir "
                   "parolayla açılamaz. Klasörde kalan şifreli dosyalar işe yaramaz; silebilirsiniz.")

    def set_auto_wipe(self, attempts: int | None) -> None:
        """Yanlış parola sınırını açar (`attempts` dolu) veya kapatır (None)."""
        if not self.vault:
            return
        try:
            self.vault.set_auto_wipe(attempts)
        except Exception as e:  # noqa: BLE001
            self.alert("Ayar kaydedilemedi", _error_text(e))
        self.emit("prefs-changed")

    def _unlock_with_keyfiles(self, path: str, password: str) -> Vault:
        """Bu bilgisayarda kasa için bir anahtar dosyası varsa onunla açar; olmazsa yalnızca parolayla dener."""
        header = vaultmod.read_header(path)
        for keyfile in self.keyfiles.candidates(header.vault_id):
            try:
                return Vault.unlock(path, password, keyfile)
            except WrongPassword:
                continue
        return Vault.unlock(path, password)

    def _open(self, vault: Vault, index: VaultIndex, recovered: bool) -> None:
        self._session = uuid.uuid4()
        self.vault = vault
        self.index = index
        self.recovered_from_backup = recovered
        self.vault_path = vault.folder
        self.current_folder = None
        self.thumbnails.clear()
        self._last_activity = time.monotonic()
        self._remember(lastVaultPath=vault.folder, lockName=self.prefs.get("displayName", "Mahzen"),
                       lockAccent=self.prefs.get("accent"), lockAppearance=self.prefs.get("appearance"))
        self.phase = "unlocked"
        expired = self.index.purge_expired(int(self.prefs.get("trashRetentionDays", 30)))
        if expired:
            threading.Thread(target=lambda: [vault.delete_file(i) for i in expired], daemon=True).start()
        if recovered or expired:
            self.schedule_save()
        self.emit("phase-changed")
        self.emit("prefs-changed")
        if recovered:
            self.alert("Dizin yedekten kurtarıldı",
                       "Kasanın dizin dosyası okunamadı; bir önceki sürümü (index.enc.bak) kullanıldı. "
                       "Son değişikliklerden bazıları eksik olabilir.")

    def lock(self) -> None:
        """Her zaman anında kilitler. Çalışan bir işlem varsa durdurulur."""
        if self.phase != "unlocked":
            return
        self._cancel.value = True
        self.set_task(None)
        self.flush_save()
        self._session = uuid.uuid4()
        self.clear_sensitive_clipboard()
        self.vault = None
        self.index = VaultIndex()
        self.thumbnails.clear()
        self._thumb_waiters.clear()
        self.current_folder = None
        self.recovered_from_backup = False
        self.integrity_report = None
        self.wipe_temporary_files()
        self.phase = "locked" if self.vault_path and vaultmod.exists(self.vault_path) else "welcome"
        self.emit("phase-changed")

    def _tick(self) -> bool:
        """Otomatik kilit ve kasa diskinin çıkarılması denetimi."""
        if self.phase == "unlocked":
            minutes = int(self.prefs.get("autoLockMinutes", 5))
            if self.vault and not vaultmod.exists(self.vault.folder):
                # Disk çıkarıldı: hemen kilitle.
                self.lock()
            elif minutes > 0 and self.task is None and time.monotonic() - self._last_activity > minutes * 60:
                # Süren bir işlem (ekleme, yedekleme, tarama) varken hareketsizlik kilidi beklemeye alınır.
                self.lock()
        return True

    def lock_for_system_event(self) -> None:
        """Uyku / ekran kilidi: ayar açıksa kilitle."""
        if self.phase == "unlocked" and self.prefs.get("lockOnSleep", True):
            self.lock()

    # MARK: - Kaydetme

    def mutate(self, body: Callable[[VaultIndex], None], debounce: bool = False) -> None:
        if self.phase != "unlocked":
            return
        body(self.index)
        self.schedule_save(0.6 if debounce else 0.05)
        self.emit("index-changed")

    def update_prefs(self, **values) -> None:
        self.mutate(lambda idx: idx.preferences.update(values), debounce=True)
        self._remember(lockName=self.prefs.get("displayName"), lockAccent=self.prefs.get("accent"),
                       lockAppearance=self.prefs.get("appearance"))
        self.emit("prefs-changed")

    def schedule_save(self, delay: float = 0.05) -> None:
        if self._save_source:
            GLib.source_remove(self._save_source)
        self._save_source = GLib.timeout_add(int(delay * 1000), self._perform_save)

    def _perform_save(self) -> bool:
        self._save_source = 0
        self.flush_save()
        return False

    def flush_save(self) -> bool:
        if self._save_source:
            GLib.source_remove(self._save_source)
            self._save_source = 0
        if not self.vault or self.phase != "unlocked":
            return False
        try:
            self.vault.save_index(self.index)
            return True
        except Exception as e:  # noqa: BLE001
            self.alert("Kasa kaydedilemedi", _error_text(e))
            return False

    # MARK: - Dosya ekleme

    def import_files(self, sources: list[str], folder: str | None) -> None:
        vault = self.vault
        if not vault or self.task:
            return
        plan = ImportPlan.build(sources)
        if not plan.items:
            if plan.skipped_count:
                self.alert("Eklenecek dosya yok",
                           "Gizli dosyalar, kısayollar (sembolik bağlantılar) ve okunamayan öğeler kasaya eklenmez.")
            return
        token = self._session
        flag = CancelFlag()
        self._cancel = flag
        total = max(sum(i.size for i in plan.items), 1)
        self.set_task(TaskProgress("Şifreleniyor", fraction=0, cancellable=True))
        existing_hashes = {f.get("sha256") for f in self.index.live_files if f.get("sha256")}

        def work():
            done_bytes = 0
            last = 0.0
            results, failures, duplicates = [], [], []
            safely_stored: dict[str, int] = {}
            for i, item in enumerate(plan.items):
                if flag.value:
                    break
                name = os.path.basename(item.path)
                GLib.idle_add(self._update_task, token, f"Şifreleniyor ({i + 1}/{len(plan.items)})", name, None)
                fid = new_id()

                def progress(n: int) -> None:
                    nonlocal done_bytes, last
                    if flag.value:
                        raise Cancelled()
                    done_bytes += n
                    t = time.monotonic()
                    if t - last > 0.1:
                        last = t
                        GLib.idle_add(self._update_task, token, None, None, done_bytes / total)

                try:
                    digest = vault.import_file(item.path, fid, progress)
                except Cancelled:
                    vault.delete_file(fid)
                    break
                except Exception as e:  # noqa: BLE001
                    vault.delete_file(fid)
                    failures.append(f"{name}: {_error_text(e)}")
                    continue
                # Aynı içerik zaten kasadaysa yeni şifreli kopyayı at.
                if digest in existing_hashes:
                    vault.delete_file(fid)
                    duplicates.append(name)
                    safely_stored[item.source] = safely_stored.get(item.source, 0) + 1
                    continue
                existing_hashes.add(digest)
                has_thumb = False
                thumb = _make_thumbnail(item.path)
                if thumb:
                    try:
                        vault.write_thumbnail(thumb, fid)
                        has_thumb = True
                    except OSError:
                        pass
                results.append((item, fid, digest, has_thumb))
                safely_stored[item.source] = safely_stored.get(item.source, 0) + 1
            return results, failures, duplicates, safely_stored

        def finished(result, error):
            if not self.is_current(token):
                # Kilitlendiyse kayıt yeni oturuma yazılmaz; şifreli içerikler silinir.
                if result:
                    for _item, fid, _d, _t in result[0]:
                        vault.delete_file(fid)
                return
            self.set_task(None)
            if error:
                self.alert("Dosyalar eklenemedi", _error_text(error))
                return
            results, failures, duplicates, safely_stored = result

            def add(idx: VaultIndex) -> None:
                for item, fid, digest, has_thumb in results:
                    target = idx.ensure_folder_path(item.folder_path, folder)
                    name = os.path.basename(item.path)
                    idx.files.append(new_file_record(fid, name, item.size, content_type_for(name), item.modified,
                                                     has_thumb, target, digest))

            self.mutate(add)
            saved = self.flush_save()
            notes = []
            if failures:
                notes.append("Eklenemeyenler:\n" + "\n".join(failures[:8]))
            if plan.skipped_count:
                notes.append(f"{plan.skipped_count} öğe eklenmedi (gizli dosya, kısayol veya okunamayan öğe).")
            if duplicates:
                more = " …" if len(duplicates) > 6 else ""
                notes.append(f"{len(duplicates)} dosya kasada zaten vardı: " + ", ".join(duplicates[:6]) + more)
            if notes:
                self.alert(f"{len(results)} dosya şifrelendi", "\n\n".join(notes))
            else:
                self.toast(f"Durduruldu · {len(results)} dosya eklendi" if flag.value
                           else f"{len(results)} dosya şifrelendi")
            removable = plan.removable_sources(safely_stored)
            if saved and removable and self.prefs.get("askToTrashOriginals", True) and not flag.value:
                self.emit("offer-trash-originals", removable)

        self.run_background(work, finished)

    def _update_task(self, token, title, detail, fraction) -> bool:
        if token == self._session and self.task:
            if title is not None:
                self.task.title = title
            if detail is not None:
                self.task.detail = detail
            if fraction is not None:
                self.task.fraction = fraction
            self.emit("task-changed")
        return False

    def cancel_task(self) -> None:
        self._cancel.value = True

    def trash_originals(self, sources: list[str]) -> None:
        """Kasaya eklenen dosyaların orijinallerini sistemin çöp kutusuna taşır (kalıcı silmez)."""
        failed = []
        for s in sources:
            try:
                Gio.File.new_for_path(s).trash(None)
            except GLib.Error:
                failed.append(os.path.basename(s))
        if failed:
            self.alert("Bazı orijinaller çöpe taşınamadı", "\n".join(failed[:8]))
        else:
            self.toast("Orijinaller çöp kutusuna taşındı")

    # MARK: - Dosya okuma ve dışa aktarma

    def thumbnail(self, record: dict, callback: Callable[[Gdk.Texture | None], None]) -> None:
        """Küçük resmi çözüp önbelleğe alır. Yüklenirken gelen istekler sıraya girer."""
        fid = record["id"]
        if fid in self.thumbnails:
            callback(self.thumbnails[fid])
            return
        if fid in self._thumb_waiters:
            self._thumb_waiters[fid].append(callback)
            return
        vault, token = self.vault, self._session
        if not vault or not record.get("hasThumbnail"):
            callback(None)
            return
        self._thumb_waiters[fid] = [callback]

        def finished(data, error):
            waiters = self._thumb_waiters.pop(fid, [])
            if not self.is_current(token):
                return
            texture = None
            if not error and data:
                try:
                    texture = Gdk.Texture.new_from_bytes(GLib.Bytes.new(data))
                except GLib.Error:
                    texture = None
            self.thumbnails[fid] = texture
            for cb in waiters:
                cb(texture)

        self.run_background(lambda: vault.read_thumbnail(fid), finished)

    def read_file(self, record: dict, done: Callable[[bytes | None, BaseException | None], None]) -> None:
        vault, token = self.vault, self._session
        if not vault:
            return
        fid = record["id"]
        self.run_background(lambda: vault.read_file(fid), lambda d, e: done(d, e) if self.is_current(token) else None)

    def export_files(self, records: list[dict], directory: str) -> None:
        vault, token = self.vault, self._session
        if not vault or self.task:
            return
        flag = CancelFlag()
        self._cancel = flag
        total = max(sum(int(r.get("size", 0)) for r in records), 1)
        self.set_task(TaskProgress("Dışa aktarılıyor", fraction=0, cancellable=True))

        def work():
            done_bytes = 0
            failures = []
            for r in records:
                if flag.value:
                    break
                dest = _unique_path(directory, r["name"])
                GLib.idle_add(self._update_task, token, None, r["name"], None)

                def progress(n: int) -> None:
                    nonlocal done_bytes
                    if flag.value:
                        raise Cancelled()
                    done_bytes += n
                    GLib.idle_add(self._update_task, token, None, None, done_bytes / total)

                try:
                    vault.export_file(r["id"], dest, progress)
                except Cancelled:
                    break
                except Exception as e:  # noqa: BLE001
                    failures.append(f"{r['name']}: {_error_text(e)}")
            return failures

        def finished(failures, error):
            if not self.is_current(token):
                return
            self.set_task(None)
            if error or failures:
                self.alert("Bazı dosyalar aktarılamadı", _error_text(error) if error else "\n".join(failures[:8]))
            else:
                self.toast(f"{len(records)} dosya dışa aktarıldı")

        self.run_background(work, finished)

    def open_temporarily(self, record: dict) -> None:
        """Dosyayı geçici klasöre (oturum belleği, XDG_RUNTIME_DIR) çözüp varsayılan uygulamasıyla açar.
        Kilitlenince ve uygulama kapanınca silinir."""
        vault, token = self.vault, self._session
        if not vault or self.task:
            return
        directory = os.path.join(self.temp_root, str(uuid.uuid4()))
        dest = os.path.join(directory, os.path.basename(record["name"]) or "dosya")
        self.set_task(TaskProgress("Açılıyor", record["name"]))

        def work():
            os.makedirs(directory, mode=0o700, exist_ok=True)
            os.chmod(self.temp_root, 0o700)
            vault.export_file(record["id"], dest)

        def finished(_r, error):
            if not self.is_current(token):
                shutil.rmtree(directory, ignore_errors=True)
                return
            self.set_task(None)
            if error:
                shutil.rmtree(directory, ignore_errors=True)
                self.alert("Açılamadı", _error_text(error))
                return
            try:
                Gio.AppInfo.launch_default_for_uri(Gio.File.new_for_path(dest).get_uri(), None)
            except GLib.Error as e:
                self.alert("Açılamadı", e.message)

        self.run_background(work, finished)

    def wipe_temporary_files(self) -> None:
        shutil.rmtree(self.temp_root, ignore_errors=True)

    # MARK: - Dosya, klasör ve çöp işlemleri

    def trash_files(self, ids: set[str]) -> None:
        self.mutate(lambda idx: idx.trash_files(ids))
        self.toast("Çöp kutusuna taşındı" if len(ids) == 1 else f"{len(ids)} dosya çöp kutusuna taşındı")

    def trash_folder(self, fid: str) -> None:
        self.mutate(lambda idx: idx.trash_folder(fid))
        if self.current_folder:
            f = self.index.folder(self.current_folder)
            if f is None or f.get("deletedAt"):
                self.current_folder = None
        self.toast("Klasör çöp kutusuna taşındı")

    def discard_blobs(self, ids: list[str]) -> None:
        """Dizinden kalıcı olarak çıkarılan dosyaların şifreli içeriklerini siler (dizin önce kaydedilir)."""
        vault = self.vault
        if not vault or not ids:
            return
        self.flush_save()
        for i in ids:
            self.thumbnails.pop(i, None)
        threading.Thread(target=lambda: [vault.delete_file(i) for i in ids], daemon=True).start()

    def purge_file(self, fid: str) -> None:
        removed: list[str] = []
        self.mutate(lambda idx: removed.extend(idx.purge_files({fid})))
        self.discard_blobs(removed)

    def purge_folder(self, fid: str) -> None:
        removed: list[str] = []
        self.mutate(lambda idx: removed.extend(idx.purge_folder(fid)))
        self.discard_blobs(removed)

    def empty_trash(self) -> None:
        removed: list[str] = []
        self.mutate(lambda idx: removed.extend(idx.empty_trash()))
        self.discard_blobs(removed)
        self.flush_save()
        self.toast("Çöp kutusu boşaltıldı")

    def rename_file(self, fid: str, name: str) -> None:
        name = name.strip()
        if name:
            self.mutate(lambda idx: idx.file(fid).__setitem__("name", name) if idx.file(fid) else None)

    def toggle_favorite(self, ids: set[str]) -> None:
        def body(idx: VaultIndex) -> None:
            chosen = [f for f in idx.files if f["id"] in ids]
            make = any(not f.get("favorite") for f in chosen)
            for f in chosen:
                f["favorite"] = make
        self.mutate(body)

    def add_note(self) -> str:
        note = new_note()
        self.mutate(lambda idx: idx.notes.insert(0, note))
        return note["id"]

    def update_note(self, nid: str, **values) -> None:
        def body(idx: VaultIndex) -> None:
            for n in idx.notes:
                if n["id"] == nid:
                    n.update(values)
                    n["updatedAt"] = now()
        self.mutate(body, debounce=True)

    def save_secret(self, secret: dict) -> None:
        def body(idx: VaultIndex) -> None:
            secret["updatedAt"] = now()
            for i, s in enumerate(idx.secrets):
                if s["id"] == secret["id"]:
                    idx.secrets[i] = secret
                    return
            idx.secrets.insert(0, secret)
        self.mutate(body, debounce=True)

    # MARK: - Pano

    def copy(self, text: str, sensitive: bool = True, label: str = "Kopyalandı") -> None:
        clipboard = Gdk.Display.get_default().get_clipboard()
        clipboard.set(text)
        seconds = int(self.prefs.get("clipboardClearSeconds", 30))
        if sensitive and seconds > 0:
            self._sensitive_clip = text
            if self._clip_source:
                GLib.source_remove(self._clip_source)
            self._clip_source = GLib.timeout_add_seconds(seconds, self._clear_clip_timer)
            self.toast(f"{label} · {seconds} sn sonra panodan silinecek")
        else:
            self.toast(label)

    def _clear_clip_timer(self) -> bool:
        self._clip_source = 0
        self.clear_sensitive_clipboard()
        return False

    def clear_sensitive_clipboard(self) -> None:
        """Panoda hâlâ bizim kopyaladığımız parola duruyorsa siler."""
        secret = self._sensitive_clip
        self._sensitive_clip = None
        if self._clip_source:
            GLib.source_remove(self._clip_source)
            self._clip_source = 0
        if not secret:
            return
        display = Gdk.Display.get_default()
        if not display:
            return
        clipboard = display.get_clipboard()
        if clipboard.is_local():
            # Pano hâlâ bu uygulamada: içerik bizimdir, doğrudan temizle.
            clipboard.set("")
            return

        def got(cb, result):
            try:
                if cb.read_text_finish(result) == secret:
                    cb.set("")
            except GLib.Error:
                pass

        clipboard.read_text_async(None, got)

    # MARK: - Parola ve anahtar dosyası

    def change_password(self, current: str, new: str, done: Callable[[str | None], None]) -> None:
        vault = self.vault
        if not vault:
            return
        self.set_task(TaskProgress("Parola değiştiriliyor", "Anahtar türetiliyor…"))

        def finished(_r, error):
            self.set_task(None)
            done(_error_text(error) if error else None)
            if not error:
                self.emit("prefs-changed")

        self.run_background(lambda: vault.change_password(current, new), finished)

    def enable_keyfile(self, password: str, done: Callable[[str | None], None]) -> None:
        vault = self.vault
        if not vault:
            return
        vid = vault.vault_id
        # Bu kimlik için etkin bir anahtar varken anahtarsız açılmış kasa, büyük olasılıkla anahtar
        # dosyası eklenmeden önce alınmış bir yedektir. Bağlamak asıl kasanın anahtarını değiştirirdi.
        # (Yalnızca arşivde anahtar varsa kullanıcı anahtar dosyasını kapatmıştır; yeniden açabilir.)
        if not vault.requires_keyfile and self.keyfiles.load(vid) is not None:
            done("Bu bilgisayarda bu kasa için zaten bir anahtar dosyası var. Bu kopya büyük olasılıkla anahtar "
                 "dosyası eklenmeden önce alınmış bir yedek; asıl kasayı açıp oradan yönetin.")
            return
        keyfile = Vault.generate_keyfile()
        try:
            self.keyfiles.save(keyfile, vid)
        except OSError as e:
            done(f"Anahtar dosyası kaydedilemedi: {_error_text(e)}")
            return
        self.set_task(TaskProgress("Anahtar dosyası ekleniyor", "Anahtar türetiliyor…"))

        def finished(_r, error):
            self.set_task(None)
            if error:
                try:
                    self.keyfiles.archive(vid)
                except OSError:
                    pass
                done(_error_text(error))
            else:
                done(None)
                self.emit("prefs-changed")

        self.run_background(lambda: vault.set_keyfile(keyfile, password), finished)

    def disable_keyfile(self, password: str, done: Callable[[str | None], None]) -> None:
        vault = self.vault
        if not vault:
            return
        used = vault.keyfile_data
        vid = vault.vault_id
        self.set_task(TaskProgress("Anahtar dosyası kaldırılıyor", "Anahtar türetiliyor…"))

        def finished(_r, error):
            self.set_task(None)
            if error:
                done(_error_text(error))
                return
            if used is not None and self.keyfiles.load(vid) == used:
                try:
                    self.keyfiles.archive(vid)
                except OSError:
                    pass
            done(None)
            self.emit("prefs-changed")

        self.run_background(lambda: vault.set_keyfile(None, password), finished)

    def export_keyfile(self, path: str) -> None:
        if not self.vault or self.vault.keyfile_data is None:
            return
        try:
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "wb") as f:
                f.write(self.vault.keyfile_data)
            self.toast("Anahtar dosyası dışa aktarıldı")
        except OSError as e:
            self.alert("Dışa aktarılamadı", _error_text(e))

    def import_keyfile(self, path: str) -> None:
        """Başka bilgisayardan getirilen anahtar dosyasını bu kasa için bu bilgisayara kaydeder."""
        if not self.vault_path:
            return
        try:
            with open(path, "rb") as f:
                data = f.read(vaultmod.KEYFILE_LENGTH + 1)
            if len(data) != vaultmod.KEYFILE_LENGTH:
                self.alert("Geçersiz anahtar dosyası", "Mahzen anahtar dosyaları tam 64 bayttır.")
                return
            header = vaultmod.read_header(self.vault_path)
            self.keyfiles.save(data, header.vault_id)
            self.toast("Anahtar dosyası bu bilgisayara kaydedildi")
        except Exception as e:  # noqa: BLE001
            self.alert("Anahtar dosyası alınamadı", _error_text(e))

    # MARK: - Yedekleme ve bakım

    def backup_now(self, done: Callable[[], None] | None = None) -> None:
        vault, token = self.vault, self._session
        dest = self.prefs.get("backupPath")
        if not vault or self.task or not dest:
            return
        # Yedek diski bağlı değilse klasörü iç diske oluşturma: kullanıcı yedeği başka diskte sanır.
        if not os.path.isdir(os.path.dirname(dest.rstrip(os.sep)) or os.sep):
            self.alert("Yedek diski bağlı değil", f"Yedek konumu bulunamadı:\n{dest}\n\n"
                       "Yedek diskini bağlayın ya da Ayarlar'dan yeni bir konum seçin.")
            return
        if not self.flush_save():
            return
        flag = CancelFlag()
        self._cancel = flag
        file_ids = {f["id"] for f in self.index.files}
        thumb_ids = {f["id"] for f in self.index.files if f.get("hasThumbnail")}
        self.set_task(TaskProgress("Yedekleniyor", dest, 0, True))

        def progress(done_bytes: int, total: int) -> bool:
            GLib.idle_add(self._update_task, token, None, None, done_bytes / total if total else 1.0)
            return not flag.value

        def work():
            os.makedirs(dest, exist_ok=True)  # yalnızca son klasör; üstü yukarıda denetlendi
            return vault.backup(dest, file_ids, thumb_ids, progress)

        def finished(report, error):
            if not self.is_current(token):
                return
            self.set_task(None)
            if isinstance(error, Cancelled):
                self.toast("Yedekleme durduruldu")
            elif error:
                self.alert("Yedeklenemedi", _error_text(error))
            else:
                self.update_prefs(lastBackupAt=now())
                msg = f"Yedeklendi · {report.copied_files} yeni, {report.unchanged_files} değişmemiş"
                if report.missing_in_source:
                    self.alert("Yedeklendi, ama eksik dosyalar var",
                               f"{len(report.missing_in_source)} dosyanın şifreli içeriği kasada bulunamadı; "
                               "yedekteki kopyaları korundu. Bütünlük taraması yapın.")
                else:
                    self.toast(msg)
            if done:
                done()

        self.run_background(work, finished)

    def run_integrity_scan(self, done: Callable[[object], None]) -> None:
        vault, token = self.vault, self._session
        if not vault or self.task:
            return
        flag = CancelFlag()
        self._cancel = flag
        files = [dict(f) for f in self.index.files]
        self.set_task(TaskProgress("Bütünlük taraması", "Her dosya çözülerek doğrulanıyor…", 0, True))

        def progress(done_bytes: int, total: int) -> bool:
            GLib.idle_add(self._update_task, token, None, None, done_bytes / total if total else 1.0)
            return not flag.value

        def finished(report, error):
            if not self.is_current(token):
                return
            self.set_task(None)
            if isinstance(error, Cancelled):
                self.toast("Tarama durduruldu")
                return
            if error:
                self.alert("Tarama yapılamadı", _error_text(error))
                return

            def fill(idx: VaultIndex) -> None:
                for f in idx.files:
                    if not f.get("sha256") and f["id"] in report.hashes:
                        f["sha256"] = report.hashes[f["id"]]
                    if f["id"] in report.broken_thumbnails:
                        f["hasThumbnail"] = False

            self.mutate(fill)
            self.integrity_report = report
            done(report)

        self.run_background(lambda: vault.check_integrity(files, progress), finished)

    def restore_from_backup(self, ids: list[str], done: Callable[[list[str]], None]) -> None:
        vault, token = self.vault, self._session
        backup = self.prefs.get("backupPath")
        if not vault or not backup:
            done(["Yedek konumu seçilmedi."])
            return
        names = {f["id"]: f["name"] for f in self.index.files}

        def work():
            failures = []
            for fid in ids:
                try:
                    vault.restore_file_from_backup(fid, backup)
                except Exception as e:  # noqa: BLE001
                    failures.append(f"{names.get(fid, fid)}: {_error_text(e)}")
            return failures

        def finished(failures, error):
            if self.is_current(token):
                done([_error_text(error)] if error else failures)

        self.run_background(work, finished)

    def remove_orphans(self, orphan_paths: list[str]) -> None:
        if self.vault:
            self.vault.remove_orphans(orphan_paths)
            self.toast(f"{len(orphan_paths)} sahipsiz dosya silindi")


def _unique_path(directory: str, name: str) -> str:
    name = os.path.basename(name) or "dosya"
    path = os.path.join(directory, name)
    base, ext = os.path.splitext(name)
    n = 2
    while os.path.exists(path):
        path = os.path.join(directory, f"{base} {n}{ext}")
        n += 1
    return path


def _make_thumbnail(path: str) -> bytes | None:
    """Görseller için 440 piksellik JPEG küçük resim (macOS sürümüyle aynı biçim)."""
    if extension(path) not in IMAGE_PREVIEWABLE:
        return None
    try:
        if os.path.getsize(path) > 200 * 1024 * 1024:
            return None
        pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(path, 440, 440, True)
        pixbuf = pixbuf.apply_embedded_orientation() or pixbuf
        if pixbuf.get_has_alpha():
            # JPEG saydamlık taşımaz; beyaz zemine yerleştir.
            flat = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, False, 8, pixbuf.get_width(), pixbuf.get_height())
            flat.fill(0xFFFFFFFF)
            pixbuf.composite(flat, 0, 0, pixbuf.get_width(), pixbuf.get_height(), 0, 0, 1, 1,
                             GdkPixbuf.InterpType.BILINEAR, 255)
            pixbuf = flat
        ok, data = pixbuf.save_to_bufferv("jpeg", ["quality"], ["78"])
        return bytes(data) if ok else None
    except (GLib.Error, OSError):
        return None
