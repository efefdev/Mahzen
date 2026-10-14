"""Açılmış bir kasa (macOS'taki `Vault.swift` ve `Maintenance.swift` ile aynı biçim).

Klasör düzeni::

    vault.json          başlık (tuz, anahtar türetme ayarları, sarılmış ana anahtar)
    index.enc           şifreli dizin (+ index.enc.bak bir önceki sürüm)
    blobs/xx/<id>.mhz   şifreli dosya içerikleri
    thumbs/<id>.mhz     şifreli küçük resimler
"""

from __future__ import annotations

import base64
import json
import os
import shutil
import uuid
from dataclasses import dataclass, field
from typing import Callable

from cryptography.exceptions import InvalidTag

from . import blob, crypto
from .errors import (AlreadyExists, Cancelled, Corrupted, KDFFailed, NotAVault, PasswordTooShort,
                     UnsupportedVersion, WrongPassword)
from .index import VaultIndex, now

CURRENT_VERSION = 2
KEYFILE_LENGTH = 64
AUTO_WIPE_MIN, AUTO_WIPE_MAX = 3, 99
DEFAULT_AUTO_WIPE_ATTEMPTS = 5
MINIMUM_PASSWORD_LENGTH = 10

HEADER_NAME = "vault.json"
HEADER_BACKUP_NAME = "vault.json.bak"
INDEX_NAME = "index.enc"
INDEX_BACKUP_NAME = "index.enc.bak"
README_NAME = "OKU-BENİ.txt"

README = """Bu klasör bir Mahzen şifreli kasasıdır.

• İçindeki her şey (dosyalar, dosya adları, notlar, parolalar) AES-256-GCM ile şifrelidir.
• Açmak için Mahzen uygulamasını ve kasa parolasını kullanın.
• Klasördeki dosyaları elle değiştirmeyin, silmeyin veya yeniden adlandırmayın.
• Yedek almak için bu klasörün tamamını başka bir diske kopyalayın.
• Parola unutulursa veriler kurtarılamaz; parolanın bir kopyasını güvenli bir yerde saklayın."""


def _password_length(password: str) -> int:
    import unicodedata
    return len(unicodedata.normalize("NFC", password))


def exists(folder: str) -> bool:
    return os.path.isfile(os.path.join(folder, HEADER_NAME))


def wrap_aad(vault_id: uuid.UUID) -> bytes:
    return f"mahzen.keywrap.v1|{crypto.uuid_string(vault_id)}".encode()


def key_encryption_key(password: str, params: dict, keyfile: bytes | None) -> bytes:
    """Sarma anahtarı: Argon2id(parola); anahtar dosyası varsa ikisi HKDF ile birleştirilir.
    Anahtar dosyası eksik ya da yanlışsa sonuç yalnızca "yanlış parola"dır."""
    from_password = crypto.derive_key(password, params)
    if keyfile is None:
        return from_password
    return crypto.hkdf(from_password + keyfile, params["salt"], b"mahzen.kek.keyfile.v1")


# MARK: - Başlık (vault.json)

class Header:
    """`vault.json`. Ham sözlük saklanır; bilinmeyen alanlar korunur."""

    def __init__(self, raw: dict):
        self.raw = raw

    @property
    def vault_id(self) -> uuid.UUID:
        return uuid.UUID(self.raw["vaultID"])

    @property
    def version(self) -> int:
        return int(self.raw.get("version", 1))

    @property
    def kdf(self) -> dict:
        k = dict(self.raw["kdf"])
        k["salt"] = base64.b64decode(k["salt"])
        return k

    @property
    def wrapped_master_key(self) -> bytes:
        return base64.b64decode(self.raw["wrappedMasterKey"])

    @property
    def wipe_after_failed_attempts(self) -> int | None:
        value = self.raw.get("wipeAfterFailedAttempts")
        return int(value) if isinstance(value, int) and value > 0 else None

    @property
    def failed_attempts(self) -> int:
        value = self.raw.get("failedAttempts")
        return int(value) if isinstance(value, int) and value > 0 else 0

    @property
    def kdf_summary(self) -> str:
        k = self.raw["kdf"]
        if k.get("algorithm") == crypto.ARGON2ID and k.get("memoryKiB") and k.get("parallelism"):
            return (f"Argon2id · {k['memoryKiB'] // 1024} MB · {k['iterations']} geçiş · "
                    f"{k['parallelism']} iş parçacığı")
        return f"PBKDF2-HMAC-SHA512 · {k['iterations']:,} tur".replace(",", ".")


def _encode_kdf(params: dict) -> dict:
    out = {k: v for k, v in params.items() if v is not None}
    out["salt"] = base64.b64encode(params["salt"]).decode()
    return out


def read_header(folder: str) -> Header:
    path = os.path.join(folder, HEADER_NAME)
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError:
        raise NotAVault() from None
    try:
        raw = json.loads(data)
        header = Header(raw)
        _ = header.vault_id, header.kdf, header.wrapped_master_key
    except Exception:
        raise Corrupted("vault.json okunamadı") from None
    if raw.get("format") != "mahzen-vault":
        raise NotAVault()
    if header.version > CURRENT_VERSION:
        raise UnsupportedVersion(header.version)
    return header


def _write_json_atomic(path: str, payload: bytes) -> None:
    blob.write_atomically(path, lambda out: out.write(payload))


def write_header(header: Header, folder: str) -> None:
    payload = json.dumps(header.raw, indent=2, sort_keys=True, ensure_ascii=False).encode()
    _write_json_atomic(os.path.join(folder, HEADER_NAME), payload)


# MARK: - Yanlış parola sınırı
#
# Art arda belirli sayıda yanlış paroladan sonra kasanın anahtarları yok edilir (macOS'taki `AutoWipe.swift`).
# Ayar ve sayaç kilitliyken okunabilmesi için şifresiz başlıkta durur. Sınır aşılınca sarılmış ana anahtarı
# taşıyan vault.json (ve varsa vault.json.bak) rastgele baytlarla ezilip silinir; kasa kalıcı olarak açılamaz.
# Bu koruma Mahzen uygulamaları içindir: kasayı önceden kopyalayan ya da vault.json'u elle düzenleyen biri
# sayaçtan etkilenmez; yedekler kendi başlıklarıyla açılmaya devam eder.

def record_failed_attempt(folder: str) -> tuple[bool, int | None]:
    """Yanlış bir parola denemesini kaydeder. (silindi_mi, kalan_deneme) döndürür; sınır kapalıysa kalan None.
    Sayaç yazılamazsa (ör. salt okunur disk) deneme sayılmaz."""
    header = read_header(folder)
    limit = header.wipe_after_failed_attempts
    if limit is None:
        return False, None
    count = header.failed_attempts + 1
    if count >= limit:
        destroy_keys(folder)
        return True, 0
    header.raw["failedAttempts"] = count
    try:
        write_header(header, folder)
    except OSError:
        pass
    return False, limit - count


def remaining_attempts(folder: str) -> int | None:
    try:
        header = read_header(folder)
    except Exception:  # noqa: BLE001
        return None
    limit = header.wipe_after_failed_attempts
    return None if limit is None else max(limit - header.failed_attempts, 0)


def destroy_keys(folder: str) -> None:
    """Ana anahtarı taşıyan başlık dosyalarını rastgele baytlarla ezip siler. Geri alınamaz."""
    first_error: OSError | None = None
    for name in (HEADER_NAME, HEADER_BACKUP_NAME):
        path = os.path.join(folder, name)
        if not os.path.exists(path):
            continue
        try:
            size = os.path.getsize(path)
            with open(path, "r+b") as f:
                f.write(os.urandom(max(size, 512)))
                f.flush()
                os.fsync(f.fileno())
            os.remove(path)
        except OSError as e:
            try:
                os.remove(path)
            except OSError:
                first_error = first_error or e
    if first_error:
        raise first_error


# MARK: - Bakım raporları

@dataclass
class BackupReport:
    copied_files: int = 0
    copied_bytes: int = 0
    unchanged_files: int = 0
    removed_files: int = 0
    missing_in_source: list[str] = field(default_factory=list)


@dataclass
class IntegrityReport:
    checked_files: int = 0
    checked_bytes: int = 0
    # dosya kimliği → "missing" | "hashMismatch" | "damaged: <ayrıntı>"
    problems: dict[str, str] = field(default_factory=dict)
    hashes: dict[str, str] = field(default_factory=dict)
    broken_thumbnails: set[str] = field(default_factory=set)
    orphan_paths: list[str] = field(default_factory=list)
    orphan_bytes: int = 0
    index_backup_readable: bool = True


ProgressFn = Callable[[int, int], bool]


class Vault:
    """Açılmış bir kasa. Anahtarlar yalnızca bu nesne yaşadığı sürece bellekte durur."""

    def __init__(self, folder: str, header: Header, master: bytes, keyfile: bytes | None):
        self.folder = folder
        self.header = header
        self._master = master
        self._keyfile = keyfile
        self.index_key = crypto.subkey(master, header.vault_id, "mahzen.index.v1")

    # MARK: Oluşturma / açma

    @property
    def vault_id(self) -> uuid.UUID:
        return self.header.vault_id

    @property
    def requires_keyfile(self) -> bool:
        """Bu nesne bir anahtar dosyasıyla mı açıldı? (Yalnızca açık kasa bilir; başlık bunu söylemez.)"""
        return self._keyfile is not None

    @property
    def keyfile_data(self) -> bytes | None:
        return self._keyfile

    @staticmethod
    def generate_keyfile() -> bytes:
        return crypto.random_bytes(KEYFILE_LENGTH)

    @classmethod
    def create(cls, folder: str, password: str, kdf: crypto.KDFSettings = crypto.RECOMMENDED,
               keyfile: bytes | None = None) -> "Vault":
        if _password_length(password) < MINIMUM_PASSWORD_LENGTH:
            raise PasswordTooShort(MINIMUM_PASSWORD_LENGTH)
        if exists(folder):
            raise AlreadyExists()
        os.makedirs(os.path.join(folder, "blobs"), exist_ok=True)
        os.makedirs(os.path.join(folder, "thumbs"), exist_ok=True)

        vault_id = uuid.uuid4()
        params = kdf.params(crypto.random_bytes(32))
        kek = key_encryption_key(password, params, keyfile)
        master = crypto.random_bytes(32)
        header = Header({
            "format": "mahzen-vault",
            "version": CURRENT_VERSION,
            "vaultID": crypto.uuid_string(vault_id),
            "createdAt": now(),
            "cipher": "AES-256-GCM",
            "kdf": _encode_kdf(params),
            "wrappedMasterKey": base64.b64encode(crypto.seal(master, kek, wrap_aad(vault_id))).decode(),
        })
        write_header(header, folder)
        vault = cls(folder, header, master, keyfile)
        vault.save_index(VaultIndex())
        try:
            with open(os.path.join(folder, README_NAME), "w", encoding="utf-8") as f:
                f.write(README)
        except OSError:
            pass
        return vault

    @classmethod
    def unlock(cls, folder: str, password: str, keyfile: bytes | None = None) -> "Vault":
        header = read_header(folder)
        kek = key_encryption_key(password, header.kdf, keyfile)
        try:
            master = crypto.open_sealed(header.wrapped_master_key, kek, wrap_aad(header.vault_id))
        except InvalidTag:
            raise WrongPassword() from None
        return cls(folder, header, master, keyfile)

    def change_password(self, current: str, new: str, kdf: crypto.KDFSettings = crypto.RECOMMENDED) -> None:
        """Ana anahtar değişmez, yalnızca yeni parolayla yeniden sarılır; dosyalar yeniden şifrelenmez."""
        if _password_length(new) < MINIMUM_PASSWORD_LENGTH:
            raise PasswordTooShort(MINIMUM_PASSWORD_LENGTH)
        Vault.unlock(self.folder, current, self._keyfile)
        self._rewrap(new, kdf, self._keyfile)

    def set_keyfile(self, new_keyfile: bytes | None, password: str,
                    kdf: crypto.KDFSettings = crypto.RECOMMENDED) -> None:
        """Anahtar dosyası zorunluluğunu açar (`new_keyfile` dolu) veya kapatır (None). Parola doğrulanır."""
        if new_keyfile is not None and len(new_keyfile) < 32:
            raise Corrupted("anahtar dosyası çok kısa")
        Vault.unlock(self.folder, password, self._keyfile)
        self._rewrap(password, kdf, new_keyfile)
        self._keyfile = new_keyfile

    @property
    def needs_kdf_upgrade(self) -> bool:
        """Eski (PBKDF2) kasa mı? Doğru parolayla açıldıktan sonra `upgrade_kdf` ile yükseltilir."""
        return self.header.raw["kdf"].get("algorithm") != crypto.ARGON2ID or self.header.version < 2

    def upgrade_kdf(self, password: str, kdf: crypto.KDFSettings = crypto.RECOMMENDED) -> None:
        """Yalnızca bu nesneyi açan parolayla çağrılmalıdır."""
        self._rewrap(password, kdf, self._keyfile)

    def clear_failed_attempts(self) -> None:
        """Başarılı açılıştan sonra sayacı sıfırlar."""
        if self.header.failed_attempts <= 0:
            return
        raw = dict(self.header.raw)
        raw.pop("failedAttempts", None)
        try:
            write_header(Header(raw), self.folder)
            self.header = Header(raw)
        except OSError:
            pass

    def set_auto_wipe(self, attempts: int | None) -> None:
        """Yanlış parola sınırını açar (`attempts` dolu) veya kapatır (None). Sayaç sıfırlanır."""
        if attempts is not None and not AUTO_WIPE_MIN <= attempts <= AUTO_WIPE_MAX:
            raise Corrupted(f"deneme sınırı {AUTO_WIPE_MIN}–{AUTO_WIPE_MAX} arasında olmalı")
        raw = dict(self.header.raw)
        raw.pop("failedAttempts", None)
        if attempts is None:
            raw.pop("wipeAfterFailedAttempts", None)
        else:
            raw["wipeAfterFailedAttempts"] = attempts
        write_header(Header(raw), self.folder)
        self.header = Header(raw)

    def _rewrap(self, password: str, kdf: crypto.KDFSettings, keyfile: bytes | None) -> None:
        params = kdf.params(crypto.random_bytes(32))
        kek = key_encryption_key(password, params, keyfile)
        aad = wrap_aad(self.vault_id)
        wrapped = crypto.seal(self._master, kek, aad)
        # Yazmadan önce yeni başlığın gerçekten açılabildiğini doğrula.
        if crypto.open_sealed(wrapped, kek, aad) != self._master:
            raise KDFFailed()
        raw = dict(self.header.raw)
        raw["version"] = CURRENT_VERSION
        raw["kdf"] = _encode_kdf(params)
        raw["wrappedMasterKey"] = base64.b64encode(wrapped).decode()
        header_path = os.path.join(self.folder, HEADER_NAME)
        backup_path = os.path.join(self.folder, HEADER_BACKUP_NAME)
        _silent_remove(backup_path)
        try:
            shutil.copyfile(header_path, backup_path)
        except OSError:
            pass
        updated = Header(raw)
        write_header(updated, self.folder)
        _silent_remove(backup_path)
        self.header = updated

    # MARK: Dizin

    @property
    def _index_aad(self) -> bytes:
        return f"mahzen.index.v1|{crypto.uuid_string(self.vault_id)}".encode()

    def load_index(self) -> tuple[VaultIndex, bool]:
        """(dizin, yedekten_kurtarıldı_mı)"""
        try:
            return self._read_index(os.path.join(self.folder, INDEX_NAME)), False
        except Exception as error:
            try:
                return self._read_index(os.path.join(self.folder, INDEX_BACKUP_NAME)), True
            except Exception:
                raise error from None

    def save_index(self, index: VaultIndex) -> None:
        payload = json.dumps(index.data, ensure_ascii=False, separators=(",", ":")).encode()
        sealed = crypto.seal(payload, self.index_key, self._index_aad)
        path = os.path.join(self.folder, INDEX_NAME)
        backup = os.path.join(self.folder, INDEX_BACKUP_NAME)
        if os.path.exists(path):
            _silent_remove(backup)
            try:
                shutil.copyfile(path, backup)
            except OSError:
                pass
        _write_json_atomic(path, sealed)

    def _read_index(self, path: str) -> VaultIndex:
        try:
            with open(path, "rb") as f:
                data = f.read()
        except OSError:
            raise Corrupted("dizin dosyası bulunamadı") from None
        try:
            plain = crypto.open_sealed(data, self.index_key, self._index_aad)
        except InvalidTag:
            raise Corrupted("dizin doğrulanamadı") from None
        return VaultIndex(json.loads(plain))

    # MARK: Dosyalar

    def blob_path(self, fid: str) -> str:
        name = fid.lower()
        return os.path.join(self.folder, "blobs", name[:2], name + ".mhz")

    def thumbnail_path(self, fid: str) -> str:
        return os.path.join(self.folder, "thumbs", fid.lower() + ".mhz")

    def file_key(self, fid: str) -> bytes:
        return crypto.subkey(self._master, self.vault_id, f"mahzen.file.v1|{fid.upper()}")

    def _thumbnail_key(self, fid: str) -> bytes:
        return crypto.subkey(self._master, self.vault_id, f"mahzen.thumb.v1|{fid.upper()}")

    def import_file(self, source: str, fid: str, progress: blob.Progress = None) -> str:
        """Dosyayı şifreleyip kasaya yazar; düz içeriğin SHA-256 özetini (onaltılık) döndürür."""
        dest = self.blob_path(fid)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        return blob.encrypt_file(source, dest, self.file_key(fid), progress)

    def export_file(self, fid: str, destination: str, progress: blob.Progress = None) -> None:
        blob.decrypt_file(self.blob_path(fid), destination, self.file_key(fid), progress)

    def open_reader(self, fid: str) -> blob.BlobReader:
        return blob.BlobReader(self.blob_path(fid), self.file_key(fid))

    def read_file(self, fid: str) -> bytes:
        return blob.decrypt_file_to_bytes(self.blob_path(fid), self.file_key(fid))

    def write_thumbnail(self, data: bytes, fid: str) -> None:
        sealed = blob.encrypt_bytes(data, self._thumbnail_key(fid))
        path = self.thumbnail_path(fid)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        _write_json_atomic(path, sealed)

    def read_thumbnail(self, fid: str) -> bytes:
        with open(self.thumbnail_path(fid), "rb") as f:
            return blob.decrypt_bytes(f.read(), self._thumbnail_key(fid))

    def delete_file(self, fid: str) -> None:
        _silent_remove(self.blob_path(fid))
        _silent_remove(self.thumbnail_path(fid))

    # MARK: Yedekleme

    def backup(self, destination: str, file_ids: set[str], thumbnail_ids: set[str],
               progress: ProgressFn = lambda done, total: True) -> BackupReport:
        """Kasayı `destination` klasörüne artımlı olarak yedekler. Şifreli dosyalar olduğu gibi kopyalanır;
        yedek aynı parolayla açılır. Dizin ve başlık en son yazılır, böylece yarıda kalan yedek de tutarlıdır.
        `progress(kopyalanan, toplam)` False döndürürse işlem durur."""
        source = os.path.realpath(self.folder)
        target = os.path.realpath(destination)
        if target == source or target.startswith(source + os.sep) or source.startswith(target + os.sep):
            raise Corrupted("yedek konumu kasanın kendisi veya içi olamaz")
        if exists(destination):
            if read_header(destination).vault_id != self.vault_id:
                raise Corrupted("seçilen klasörde başka bir kasa var")

        # Tutarlı bir anlık görüntü: dizin ve başlık baştan belleğe alınır.
        header_data = _read(os.path.join(self.folder, HEADER_NAME))
        index_data = _read(os.path.join(self.folder, INDEX_NAME))
        try:
            index_backup_data = _read(os.path.join(self.folder, INDEX_BACKUP_NAME))
        except OSError:
            index_backup_data = None

        report = BackupReport()
        jobs: list[tuple[str, str, int]] = []

        def plan(src: str, rel: str, fid: str | None) -> None:
            size = _file_size(src)
            if size is None:
                if fid:
                    report.missing_in_source.append(fid)
                return
            dst = os.path.join(destination, rel)
            if _file_size(dst) == size:
                report.unchanged_files += 1
            else:
                jobs.append((src, dst, size))

        for fid in file_ids:
            plan(self.blob_path(fid), self._relative(self.blob_path(fid)), fid)
        for fid in thumbnail_ids:
            plan(self.thumbnail_path(fid), self._relative(self.thumbnail_path(fid)), None)

        total = sum(j[2] for j in jobs)
        done = 0
        if not progress(0, total):
            raise Cancelled()
        for src, dst, size in jobs:
            os.makedirs(os.path.dirname(dst), exist_ok=True)

            def step(n: int) -> bool:
                nonlocal done
                done += n
                return progress(done, total)

            _copy_file(src, dst, step)
            report.copied_files += 1
            report.copied_bytes += size

        # Kaynakta kalıcı silinmiş öğelerin yedekteki kopyalarını temizle.
        keep = {self._relative(self.blob_path(i)) for i in file_ids} | \
               {self._relative(self.thumbnail_path(i)) for i in thumbnail_ids}
        for sub in ("blobs", "thumbs"):
            for path in _walk_files(os.path.join(destination, sub)):
                if self._relative(path) not in keep:
                    _silent_remove(path)
                    report.removed_files += 1

        if index_backup_data is not None:
            _write_json_atomic(os.path.join(destination, INDEX_BACKUP_NAME), index_backup_data)
        _write_json_atomic(os.path.join(destination, INDEX_NAME), index_data)
        _write_json_atomic(os.path.join(destination, HEADER_NAME), header_data)
        try:
            with open(os.path.join(destination, README_NAME), "w", encoding="utf-8") as f:
                f.write(README)
        except OSError:
            pass
        return report

    # MARK: Bütünlük taraması

    def check_integrity(self, files: list[dict], progress: ProgressFn = lambda d, t: True) -> IntegrityReport:
        """Her dosyayı baştan sona çözerek doğrular (AES-GCM etiketleri), özetini hesaplar,
        küçük resimleri ve sahipsiz dosyaları denetler. Diske hiçbir şey yazmaz."""
        report = IntegrityReport()
        total = sum(int(f.get("size", 0)) for f in files)
        done = 0
        if not progress(0, total):
            raise Cancelled()
        for f in files:
            fid = f["id"]
            report.checked_files += 1

            def step(n: int) -> bool:
                nonlocal done
                done += n
                return progress(done, total)

            try:
                digest = self.verify_file(fid, step)
                report.hashes[fid] = digest
                if f.get("sha256") and f["sha256"] != digest:
                    report.problems[fid] = "hashMismatch"
            except Cancelled:
                raise
            except Exception as e:
                report.problems[fid] = "missing" if _file_size(self.blob_path(fid)) is None else f"damaged: {e}"
            report.checked_bytes += int(f.get("size", 0))
            if f.get("hasThumbnail"):
                try:
                    self.read_thumbnail(fid)
                except Exception:
                    report.broken_thumbnails.add(fid)

        referenced = {self._relative(self.blob_path(f["id"])) for f in files} | \
                     {self._relative(self.thumbnail_path(f["id"])) for f in files if f.get("hasThumbnail")}
        for sub in ("blobs", "thumbs"):
            for path in _walk_files(os.path.join(self.folder, sub)):
                name = os.path.basename(path)
                # exFAT'ta macOS'un öznitelik dosyaları ve Finder dosyaları kasaya ait değildir.
                if name.startswith("._") or name == ".DS_Store":
                    continue
                if self._relative(path) not in referenced:
                    report.orphan_paths.append(path)
                    report.orphan_bytes += _file_size(path) or 0
        try:
            data = _read(os.path.join(self.folder, INDEX_BACKUP_NAME))
            try:
                crypto.open_sealed(data, self.index_key, self._index_aad)
            except InvalidTag:
                report.index_backup_readable = False
        except OSError:
            pass
        return report

    def verify_file(self, fid: str, progress: Callable[[int], bool] = lambda n: True) -> str:
        """Dosyayı çözerek doğrular ve düz içeriğin SHA-256 özetini döndürür."""
        import hashlib
        hasher = hashlib.sha256()

        def write(chunk: bytes) -> None:
            hasher.update(chunk)
            if not progress(len(chunk)):
                raise Cancelled()

        with open(self.blob_path(fid), "rb") as f:
            blob.decrypt_stream(lambda n: blob.read_fully(f, n), write, self.file_key(fid))
        return hasher.hexdigest()

    def restore_file_from_backup(self, fid: str, backup_folder: str) -> None:
        """Yedekteki kopyayı önce doğrular, sağlamsa kasadaki bozuk/eksik dosyanın yerine koyar."""
        if not exists(backup_folder) or read_header(backup_folder).vault_id != self.vault_id:
            raise Corrupted("yedek bu kasaya ait değil")
        backup_blob = os.path.join(backup_folder, self._relative(self.blob_path(fid)))
        with open(backup_blob, "rb") as f:
            blob.decrypt_stream(lambda n: blob.read_fully(f, n), lambda _: None, self.file_key(fid))
        dest = self.blob_path(fid)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        _copy_file(backup_blob, dest, lambda n: True)

    def remove_orphans(self, paths: list[str]) -> None:
        root = os.path.realpath(self.folder) + os.sep
        for p in paths:
            if os.path.realpath(p).startswith(root):
                _silent_remove(p)

    def _relative(self, path: str) -> str:
        """Kasa içindeki göreli yol ("blobs/ab/<id>.mhz" veya "thumbs/<id>.mhz")."""
        parts = os.path.normpath(path).split(os.sep)
        for i in range(len(parts) - 1, -1, -1):
            if parts[i] in ("blobs", "thumbs"):
                return "/".join(parts[i:])
        return parts[-1]


# MARK: - Yardımcılar

def _read(path: str) -> bytes:
    with open(path, "rb") as f:
        return f.read()


def _silent_remove(path: str) -> None:
    try:
        os.remove(path)
    except OSError:
        pass


def _file_size(path: str) -> int | None:
    try:
        return os.stat(path).st_size
    except OSError:
        return None


def _walk_files(root: str):
    for dirpath, _dirs, names in os.walk(root):
        for name in names:
            path = os.path.join(dirpath, name)
            if os.path.isfile(path) and not os.path.islink(path):
                yield path


def _copy_file(source: str, destination: str, progress: Callable[[int], bool]) -> None:
    """4 MB'lık parçalarla kopyalar; önce geçici dosyaya yazar, bitince yerine taşır."""
    with open(source, "rb") as src:
        def body(out) -> None:
            while chunk := src.read(4 << 20):
                out.write(chunk)
                if not progress(len(chunk)):
                    raise Cancelled()
        blob.write_atomically(destination, body)
