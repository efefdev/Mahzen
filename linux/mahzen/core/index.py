"""Kasanın şifreli dizini: dosya kayıtları, klasörler, notlar, parolalar ve tercihler.

Dizin, macOS sürümünün yazdığı JSON ile aynı biçimdedir. Kayıtlar sözlük olarak tutulur; böylece
bu sürümün bilmediği (macOS'un ileride ekleyeceği) alanlar okunup aynen geri yazılır, kaybolmaz.
Tarihler Swift'in `.iso8601` biçimindedir: ``2026-10-14T16:45:12Z`` (kesirli saniye yok).
Bu modül disk işi yapmaz; kalıcı silinen dosyaların kimliklerini döndürür.
"""

from __future__ import annotations

import re
import uuid
from datetime import datetime, timedelta, timezone

SECRET_CATEGORIES = ["login", "card", "wifi", "server", "note", "other"]
ACCENTS = ["orange", "indigo", "blue", "teal", "green", "pink", "red", "purple", "graphite"]

DEFAULT_GENERATOR = {
    "length": 20, "uppercase": True, "lowercase": True, "digits": True, "symbols": True, "avoidAmbiguous": True,
}

DEFAULT_PREFERENCES = {
    "displayName": "Mahzen",
    "accent": "orange",
    "appearance": "dark",
    "autoLockMinutes": 5,
    "clipboardClearSeconds": 30,
    "lockOnSleep": True,
    "hideFromScreenCapture": True,
    "noteFontSize": 15.0,
    "noteFontDesign": "default",
    "filesLayout": "grid",
    "generator": DEFAULT_GENERATOR,
    "trashRetentionDays": 30,
    "askToTrashOriginals": True,
    "backupReminderDays": 7,
}


# MARK: - Tarih ve kimlik yardımcıları

def now() -> str:
    return format_date(datetime.now(timezone.utc))


def format_date(d: datetime) -> str:
    return d.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_date(s: str | None) -> datetime | None:
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError:
        return None


def new_id() -> str:
    return str(uuid.uuid4()).upper()


def same_id(a: str | None, b: str | None) -> bool:
    if a is None or b is None:
        return a is None and b is None
    return a.upper() == b.upper()


_natural = re.compile(r"(\d+)")


def sort_key(name: str):
    """Finder'daki `localizedStandardCompare` benzeri: büyük/küçük harf duyarsız, sayılar sayı olarak."""
    return [int(p) if p.isdigit() else p.casefold() for p in _natural.split(name)]


# MARK: - Dizin

class VaultIndex:
    """Çözülmüş dizin. `data` JSON sözlüğünün kendisidir ve olduğu gibi kaydedilir."""

    def __init__(self, data: dict | None = None):
        d = dict(data or {})
        d.setdefault("version", 1)
        for key in ("files", "folders", "notes", "secrets"):
            if not isinstance(d.get(key), list):
                d[key] = []
        prefs = d.get("preferences") if isinstance(d.get("preferences"), dict) else {}
        merged = {**DEFAULT_PREFERENCES, **prefs}
        gen = merged.get("generator") if isinstance(merged.get("generator"), dict) else {}
        merged["generator"] = {**DEFAULT_GENERATOR, **gen}
        d["preferences"] = merged
        self.data = d
        for f in self.files:
            f.setdefault("tags", [])
            f.setdefault("favorite", False)
            f.setdefault("hasThumbnail", False)

    @property
    def files(self) -> list[dict]:
        return self.data["files"]

    @property
    def folders(self) -> list[dict]:
        return self.data["folders"]

    @property
    def notes(self) -> list[dict]:
        return self.data["notes"]

    @property
    def secrets(self) -> list[dict]:
        return self.data["secrets"]

    @property
    def preferences(self) -> dict:
        return self.data["preferences"]

    # MARK: Klasörler

    def folder(self, fid: str | None) -> dict | None:
        if fid is None:
            return None
        return next((f for f in self.folders if same_id(f["id"], fid)), None)

    def file(self, fid: str) -> dict | None:
        return next((f for f in self.files if same_id(f["id"], fid)), None)

    def child_folders(self, parent: str | None) -> list[dict]:
        return sorted(
            (f for f in self.folders if same_id(f.get("parentID"), parent) and not f.get("deletedAt")),
            key=lambda f: sort_key(f["name"]),
        )

    def live_files_in(self, folder: str | None) -> list[dict]:
        return [f for f in self.files if same_id(f.get("folderID"), folder) and not f.get("deletedAt")]

    @property
    def live_files(self) -> list[dict]:
        return [f for f in self.files if not f.get("deletedAt")]

    def path_to(self, fid: str | None) -> list[dict]:
        """Kökten klasöre kadar olan yol (kök hariç)."""
        result, seen = [], set()
        current = self.folder(fid)
        while current and current["id"].upper() not in seen:
            seen.add(current["id"].upper())
            result.insert(0, current)
            current = self.folder(current.get("parentID"))
        return result

    def descendant_folder_ids(self, fid: str) -> set[str]:
        """Klasörün altındaki tüm klasörler (kendisi hariç, silinmiş olanlar dahil). Büyük harfli kimlikler."""
        result: set[str] = set()
        queue = [fid.upper()]
        while queue:
            nxt = queue.pop()
            for child in self.folders:
                cid = child["id"].upper()
                if (child.get("parentID") or "").upper() == nxt and cid not in result:
                    result.add(cid)
                    queue.append(cid)
        return result

    def _tree(self, fid: str) -> set[str]:
        return self.descendant_folder_ids(fid) | {fid.upper()}

    @staticmethod
    def _in(tree: set[str], fid: str | None) -> bool:
        return fid is not None and fid.upper() in tree

    def live_file_count_in_tree(self, fid: str) -> int:
        tree = self._tree(fid)
        return sum(1 for f in self.files if not f.get("deletedAt") and self._in(tree, f.get("folderID")))

    def ensure_folder_path(self, names: list[str], parent: str | None) -> str | None:
        """`names` yolundaki klasörleri (yoksa oluşturarak) bulur; aynı adlı canlı klasör varsa onu kullanır."""
        current = parent
        for name in names:
            if not name:
                continue
            existing = next((f for f in self.folders if same_id(f.get("parentID"), current)
                             and not f.get("deletedAt") and f["name"] == name), None)
            if existing:
                current = existing["id"]
            else:
                current = self._append_folder(name, current)
        return current

    def _append_folder(self, name: str, parent: str | None) -> str:
        folder = {"id": new_id(), "name": name, "createdAt": now()}
        if parent is not None:
            folder["parentID"] = parent
        self.folders.append(folder)
        return folder["id"]

    def create_folder(self, name: str, parent: str | None) -> str:
        base = name.strip() or "Yeni Klasör"
        candidate, n = base, 2
        while any(same_id(f.get("parentID"), parent) and not f.get("deletedAt") and f["name"] == candidate
                  for f in self.folders):
            candidate = f"{base} {n}"
            n += 1
        return self._append_folder(candidate, parent)

    def rename_folder(self, fid: str, name: str) -> None:
        name = name.strip()
        folder = self.folder(fid)
        if name and folder:
            folder["name"] = name

    def move_files(self, ids: set[str], folder: str | None) -> None:
        ids = {i.upper() for i in ids}
        for f in self.files:
            if f["id"].upper() in ids:
                _set_optional(f, "folderID", folder)

    def move_folder(self, fid: str, parent: str | None) -> bool:
        """Klasörü kendi altına taşımaya izin vermez. Taşındıysa True."""
        if parent is not None and (same_id(parent, fid) or parent.upper() in self.descendant_folder_ids(fid)):
            return False
        folder = self.folder(fid)
        if not folder:
            return False
        _set_optional(folder, "parentID", parent)
        return True

    # MARK: Etiketler ve mükerrerler

    @property
    def all_tags(self) -> list[str]:
        return sorted({t for f in self.live_files for t in f.get("tags", [])}, key=sort_key)

    def set_tags(self, tags: list[str], ids: set[str]) -> None:
        clean = sorted({t.strip() for t in tags if t.strip()})
        ids = {i.upper() for i in ids}
        for f in self.files:
            if f["id"].upper() in ids:
                f["tags"] = list(clean)

    def existing_file_with_hash(self, sha: str) -> dict | None:
        """Aynı içerik kasada (çöp kutusu dışında) zaten varsa onu döndürür."""
        return next((f for f in self.files if f.get("sha256") == sha and not f.get("deletedAt")), None)

    # MARK: Çöp kutusu

    def trash_files(self, ids: set[str], date: str | None = None) -> None:
        date = date or now()
        ids = {i.upper() for i in ids}
        for f in self.files:
            if f["id"].upper() in ids and not f.get("deletedAt"):
                f["deletedAt"] = date

    def trash_folder(self, fid: str, date: str | None = None) -> None:
        """Klasörü ve içindekileri aynı zaman damgasıyla çöpe taşır; geri alırken birlikte dönerler."""
        date = date or now()
        tree = self._tree(fid)
        for f in self.folders:
            if f["id"].upper() in tree and not f.get("deletedAt"):
                f["deletedAt"] = date
        for f in self.files:
            if self._in(tree, f.get("folderID")) and not f.get("deletedAt"):
                f["deletedAt"] = date

    def restore_file(self, fid: str) -> None:
        f = self.file(fid)
        if not f:
            return
        f.pop("deletedAt", None)
        parent = f.get("folderID")
        if parent is not None:
            pf = self.folder(parent)
            if pf is None or pf.get("deletedAt"):
                f.pop("folderID", None)

    def restore_folder(self, fid: str) -> None:
        folder = self.folder(fid)
        if not folder or not folder.get("deletedAt"):
            return
        stamp = folder["deletedAt"]
        tree = self._tree(fid)
        for f in self.folders:
            if f["id"].upper() in tree and f.get("deletedAt") == stamp:
                f.pop("deletedAt", None)
        for f in self.files:
            if self._in(tree, f.get("folderID")) and f.get("deletedAt") == stamp:
                f.pop("deletedAt", None)
        parent = folder.get("parentID")
        if parent is not None:
            pf = self.folder(parent)
            if pf is None or pf.get("deletedAt"):
                folder.pop("parentID", None)

    def _find(self, items: list[dict], iid: str) -> dict | None:
        return next((x for x in items if same_id(x["id"], iid)), None)

    def trash_note(self, nid: str) -> None:
        if (n := self._find(self.notes, nid)):
            n["deletedAt"] = now()

    def restore_note(self, nid: str) -> None:
        if (n := self._find(self.notes, nid)):
            n.pop("deletedAt", None)

    def trash_secret(self, sid: str) -> None:
        if (s := self._find(self.secrets, sid)):
            s["deletedAt"] = now()

    def restore_secret(self, sid: str) -> None:
        if (s := self._find(self.secrets, sid)):
            s.pop("deletedAt", None)

    @property
    def trashed_folders(self) -> list[dict]:
        """Çöp kutusunda üst düzeyde gösterilecek klasörler (silinmiş bir klasörün içindekiler klasörle görünür)."""
        out = []
        for f in self.folders:
            if not f.get("deletedAt"):
                continue
            parent = self.folder(f.get("parentID"))
            if parent is None or parent.get("deletedAt") != f["deletedAt"]:
                out.append(f)
        return out

    @property
    def trashed_files(self) -> list[dict]:
        out = []
        for f in self.files:
            if not f.get("deletedAt"):
                continue
            parent = self.folder(f.get("folderID"))
            if parent is None or parent.get("deletedAt") != f["deletedAt"]:
                out.append(f)
        return out

    @property
    def trashed_notes(self) -> list[dict]:
        return [n for n in self.notes if n.get("deletedAt")]

    @property
    def trashed_secrets(self) -> list[dict]:
        return [s for s in self.secrets if s.get("deletedAt")]

    @property
    def trash_count(self) -> int:
        return (len(self.trashed_folders) + len(self.trashed_files)
                + len(self.trashed_notes) + len(self.trashed_secrets))

    # MARK: Kalıcı silme (şifreli içerikleri silinecek dosya kimliklerini döndürür)

    def purge_files(self, ids: set[str]) -> list[str]:
        ids = {i.upper() for i in ids}
        removed = [f["id"] for f in self.files if f["id"].upper() in ids]
        self.data["files"] = [f for f in self.files if f["id"].upper() not in ids]
        return removed

    def purge_folder(self, fid: str) -> list[str]:
        tree = self._tree(fid)
        self.data["folders"] = [f for f in self.folders if f["id"].upper() not in tree]
        return self.purge_files({f["id"] for f in self.files if self._in(tree, f.get("folderID"))})

    def purge_note(self, nid: str) -> None:
        self.data["notes"] = [n for n in self.notes if not same_id(n["id"], nid)]

    def purge_secret(self, sid: str) -> None:
        self.data["secrets"] = [s for s in self.secrets if not same_id(s["id"], sid)]

    def empty_trash(self) -> list[str]:
        removed: list[str] = []
        for f in [f for f in self.folders if f.get("deletedAt")]:
            if self.folder(f["id"]):
                removed += self.purge_folder(f["id"])
        removed += self.purge_files({f["id"] for f in self.files if f.get("deletedAt")})
        self.data["notes"] = [n for n in self.notes if not n.get("deletedAt")]
        self.data["secrets"] = [s for s in self.secrets if not s.get("deletedAt")]
        return removed

    def purge_expired(self, retention_days: int, at: datetime | None = None) -> list[str]:
        """Saklama süresi dolmuş öğeleri kalıcı siler."""
        if retention_days <= 0:
            return []
        cutoff = (at or datetime.now(timezone.utc)) - timedelta(days=retention_days)

        def expired(item: dict) -> bool:
            d = parse_date(item.get("deletedAt"))
            return d is not None and d < cutoff

        removed: list[str] = []
        for f in [f for f in self.folders if expired(f)]:
            if self.folder(f["id"]):
                removed += self.purge_folder(f["id"])
        removed += self.purge_files({f["id"] for f in self.files if expired(f)})
        self.data["notes"] = [n for n in self.notes if not expired(n)]
        self.data["secrets"] = [s for s in self.secrets if not expired(s)]
        return removed


# MARK: - Yeni kayıtlar (macOS'un zorunlu tuttuğu tüm alanlarla)

def new_file_record(fid: str, name: str, size: int, content_type: str | None, modified: str | None,
                    has_thumbnail: bool, folder_id: str | None, sha256: str | None) -> dict:
    rec = {
        "id": fid, "name": name, "size": size, "addedAt": now(), "hasThumbnail": has_thumbnail,
        "favorite": False, "tags": [],
    }
    for key, value in (("contentType", content_type), ("originalModifiedAt", modified),
                       ("folderID", folder_id), ("sha256", sha256)):
        if value is not None:
            rec[key] = value
    return rec


def new_note() -> dict:
    stamp = now()
    return {"id": new_id(), "title": "", "body": "", "createdAt": stamp, "updatedAt": stamp, "pinned": False}


def new_secret(category: str = "login") -> dict:
    stamp = now()
    return {
        "id": new_id(), "title": "", "username": "", "password": "", "url": "", "notes": "",
        "category": category, "favorite": False, "createdAt": stamp, "updatedAt": stamp,
    }


def _set_optional(d: dict, key: str, value) -> None:
    if value is None:
        d.pop(key, None)
    else:
        d[key] = value
