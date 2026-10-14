"""`fixtures/python-vault` kasasını Linux sürümüyle yeniden üretir.

macOS tarafındaki `LinuxCompatibilityTests` bu kasayı açar. Biçim değişirse yeniden çalıştırın:
``python3 linux/tests/make_python_fixture.py``
"""

import hashlib
import json
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from mahzen.core import crypto  # noqa: E402
from mahzen.core.index import VaultIndex, new_file_record, new_id, new_note, new_secret  # noqa: E402
from mahzen.core.vault import Vault  # noqa: E402

FIXTURES = os.path.join(os.path.dirname(__file__), "fixtures")
PASSWORD = "doğru-at-pil-zımba-42"


def main() -> None:
    out = os.path.join(FIXTURES, "python-vault")
    shutil.rmtree(out, ignore_errors=True)
    v = Vault.create(out, PASSWORD, crypto.KDFSettings(iterations=1, memory_kib=8192, parallelism=1))
    idx = VaultIndex()
    folder = idx.create_folder("Linux Klasörü", None)
    expected = []
    with tempfile.TemporaryDirectory() as tmp:
        for name, data, parent, ctype in [
            ("linux.txt", "Linux'tan merhaba! Çğıöşü\n".encode(), folder, "public.plain-text"),
            ("parçalı.bin", bytes((i * 7 + i // 13) & 0xFF for i in range(1_050_000)), None, None),
        ]:
            src = os.path.join(tmp, name)
            with open(src, "wb") as f:
                f.write(data)
            fid = new_id()
            digest = v.import_file(src, fid)
            idx.files.append(new_file_record(fid, name, len(data), ctype, None, name == "linux.txt", parent, digest))
            if name == "linux.txt":
                v.write_thumbnail(b"linux-kucuk-resim", fid)
            expected.append({"id": fid, "name": name, "size": len(data), "sha256": digest})
    note = new_note()
    note.update(title="Linux notu", body="Satır 1\nSatır 2", pinned=True)
    idx.notes.append(note)
    secret = new_secret("wifi")
    secret.update(title="Ev Wi-Fi", password="wifi-parolası-123")
    idx.secrets.append(secret)
    trashed = new_secret()
    trashed.update(title="Silinen", deletedAt="2026-10-01T10:00:00Z")
    idx.secrets.append(trashed)
    idx.preferences["accent"] = "green"
    v.save_index(idx)
    with open(os.path.join(FIXTURES, "python-expected.json"), "w", encoding="utf-8") as f:
        json.dump({"password": PASSWORD, "files": expected, "folder": folder,
                   "thumb": hashlib.sha256(b"linux-kucuk-resim").hexdigest()}, f, ensure_ascii=False, indent=2)
    print("Oluşturuldu:", out)


if __name__ == "__main__":
    main()
