"""Kasaya eklenecek dosyaların listesi ve atlanan öğelerin hesabı (macOS'taki `ImportPlanner.swift`).

Klasör eklendiğinde gizli dosyalar, sembolik bağlantılar ve okunamayan öğeler kasaya eklenmez.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from datetime import datetime, timezone

from .index import format_date


@dataclass
class ImportItem:
    path: str
    size: int
    modified: str | None
    folder_path: list[str]  # eklenen klasörün kasada yeniden oluşturulacak yolu (ör. ["Tatil", "2026"])
    source: str  # kullanıcının seçtiği/sürüklediği üst öğe


@dataclass
class ImportPlan:
    items: list[ImportItem] = field(default_factory=list)
    skipped: dict[str, list[str]] = field(default_factory=dict)

    @property
    def skipped_count(self) -> int:
        return sum(len(v) for v in self.skipped.values())

    @classmethod
    def build(cls, paths: list[str]) -> "ImportPlan":
        plan = cls()
        for source in paths:
            source = os.path.abspath(source)
            if os.path.islink(source):
                plan._skip(source, source)
            elif os.path.isdir(source):
                plan._walk(source)
            elif os.path.isfile(source):
                item = _item(source, [], source)
                if item:
                    plan.items.append(item)
                else:
                    plan._skip(source, source)
            else:
                plan._skip(source, source)
        return plan

    def _walk(self, source: str) -> None:
        root_name = os.path.basename(source.rstrip(os.sep))

        def on_error(err: OSError) -> None:
            self._skip(source, err.filename or source)

        for dirpath, dirnames, filenames in os.walk(source, onerror=on_error):
            rel = os.path.relpath(dirpath, source)
            parts = [] if rel == "." else rel.split(os.sep)
            for d in list(dirnames):
                full = os.path.join(dirpath, d)
                if d.startswith(".") or os.path.islink(full):
                    self._skip(source, full)
                    dirnames.remove(d)
            for name in filenames:
                full = os.path.join(dirpath, name)
                if name.startswith("."):
                    # .DS_Store gibi Finder dosyaları kullanıcı verisi değildir; sayılmaz.
                    if name != ".DS_Store":
                        self._skip(source, full)
                    continue
                if os.path.islink(full) or not os.path.isfile(full):
                    self._skip(source, full)
                    continue
                item = _item(full, [root_name] + parts, source)
                if item:
                    self.items.append(item)
                else:
                    self._skip(source, full)

    def _skip(self, source: str, path: str) -> None:
        self.skipped.setdefault(source, []).append(os.path.basename(path))

    def removable_sources(self, safely_stored: dict[str, int]) -> list[str]:
        """Orijinali güvenle çöpe taşınabilecek kaynaklar: içindeki her dosya kasaya girmiş (veya zaten
        kasadaymış) ve hiçbir öğesi atlanmamış olanlar."""
        expected: dict[str, int] = {}
        for item in self.items:
            expected[item.source] = expected.get(item.source, 0) + 1
        return [s for s, count in expected.items()
                if safely_stored.get(s) == count and not self.skipped.get(s)]


def _item(path: str, folder_path: list[str], source: str) -> ImportItem | None:
    try:
        st = os.stat(path)
        if not os.access(path, os.R_OK):
            return None
    except OSError:
        return None
    modified = format_date(datetime.fromtimestamp(st.st_mtime, tz=timezone.utc))
    return ImportItem(path, st.st_size, modified, folder_path, source)
