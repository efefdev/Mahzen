"""Anahtar dosyalarını bu bilgisayarda saklar; kasa diskine asla yazılmaz (macOS'taki `KeyfileStore.swift`).

Dosya adı yalnızca kasa kimliğidir; kasanın kendisinde bu dosyaya dair hiçbir iz yoktur.
Hiçbir anahtar dosyası silinmez ya da üzerine yazılmaz: değişen veya kaldırılan anahtar
``<kimlik>.arsiv-<zaman>`` adıyla arşivlenir ve kilit açılırken arşivdekiler de denenir.
"""

from __future__ import annotations

import os
import uuid
from datetime import datetime, timezone

from .paths import data_dir


class KeyfileStore:
    def __init__(self, directory: str):
        self.directory = directory

    @classmethod
    def standard(cls) -> "KeyfileStore":
        return cls(os.path.join(data_dir(), "Anahtarlar"))

    def path(self, vault_id: uuid.UUID) -> str:
        return os.path.join(self.directory, str(vault_id).lower())

    def load(self, vault_id: uuid.UUID) -> bytes | None:
        try:
            with open(self.path(vault_id), "rb") as f:
                return f.read()
        except OSError:
            return None

    def candidates(self, vault_id: uuid.UUID) -> list[bytes]:
        """Denenecek tüm anahtarlar: önce etkin olan, sonra arşivdekiler (yeniden eskiye), tekrarsız."""
        prefix = str(vault_id).lower() + ".arsiv-"
        try:
            names = sorted((n for n in os.listdir(self.directory) if n.startswith(prefix)), reverse=True)
        except OSError:
            names = []
        found: list[bytes] = []
        active = self.load(vault_id)
        if active is not None:
            found.append(active)
        for name in names:
            try:
                with open(os.path.join(self.directory, name), "rb") as f:
                    found.append(f.read())
            except OSError:
                pass
        seen, unique = set(), []
        for k in found:
            if k not in seen:
                seen.add(k)
                unique.append(k)
        return unique

    def save(self, keyfile: bytes, vault_id: uuid.UUID) -> None:
        """Yazar ve geri okuyup doğrular. Farklı bir anahtar zaten varsa önce arşivlenir."""
        os.makedirs(self.directory, mode=0o700, exist_ok=True)
        os.chmod(self.directory, 0o700)
        existing = self.load(vault_id)
        if existing is not None:
            if existing == keyfile:
                return
            self.archive(vault_id)
        target = self.path(vault_id)
        tmp = target + ".tmp"
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "wb") as f:
            f.write(keyfile)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, target)
        if self.load(vault_id) != keyfile:
            raise OSError(f"Anahtar dosyası yazılamadı: {target}")

    def archive(self, vault_id: uuid.UUID) -> None:
        """Etkin anahtarı arşive taşır (silmez). Etkin anahtar yoksa bir şey yapmaz."""
        source = self.path(vault_id)
        if not os.path.exists(source):
            return
        stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H%M%SZ")
        base = os.path.join(self.directory, f"{str(vault_id).lower()}.arsiv-{stamp}")
        target, n = base, 2
        while os.path.exists(target):
            target = f"{base}-{n}"
            n += 1
        os.rename(source, target)
