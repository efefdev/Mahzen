"""Çekirdek testleri. Çalıştırmak için: ``python3 -m unittest discover -s linux/tests``

`fixtures/` altındaki kasalar macOS sürümüyle (Swift) oluşturulmuştur; Linux sürümünün onları
birebir açabildiğini doğrular. `fixtures/python-vault` ise bu sürümle oluşturulmuştur ve
macOS tarafındaki `LinuxCompatibilityTests` onu açar.
"""

import hashlib
import json
import os
import shutil
import sys
import tempfile
import unittest
import uuid

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from mahzen.core import blob, crypto, passwords  # noqa: E402
from mahzen.core.errors import Corrupted, PasswordTooShort, WrongPassword  # noqa: E402
from mahzen.core.importplan import ImportPlan  # noqa: E402
from mahzen.core.index import VaultIndex, new_file_record, new_note, new_secret  # noqa: E402
from mahzen.core.keyfiles import KeyfileStore  # noqa: E402
from mahzen.core.vault import Vault, read_header  # noqa: E402

FIXTURES = os.path.join(os.path.dirname(__file__), "fixtures")
SMALL = crypto.KDFSettings(iterations=1, memory_kib=8192, parallelism=1)
PASSWORD = "doğru-at-pil-zımba-42"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


class BlobTests(unittest.TestCase):
    key = os.urandom(32)

    def test_round_trip_across_chunk_boundaries(self):
        for size in [0, 1, 4095, 4096, 4097, 4096 * 3, 4096 * 3 + 17]:
            data = os.urandom(size)
            sealed = blob.encrypt_bytes(data, self.key, chunk_size=4096)
            self.assertEqual(blob.decrypt_bytes(sealed, self.key), data, f"boyut {size}")

    def test_wrong_key_fails(self):
        sealed = blob.encrypt_bytes(b"merhaba", self.key)
        with self.assertRaises(Corrupted):
            blob.decrypt_bytes(sealed, os.urandom(32))

    def test_tampering_is_detected(self):
        sealed = bytearray(blob.encrypt_bytes(os.urandom(10_000), self.key, chunk_size=4096))
        sealed[5000] ^= 1
        with self.assertRaises(Corrupted):
            blob.decrypt_bytes(bytes(sealed), self.key)

    def test_truncation_at_chunk_boundary_is_detected(self):
        sealed = blob.encrypt_bytes(os.urandom(4096 * 3), self.key, chunk_size=4096)
        truncated = sealed[: blob.HEADER_SIZE + 2 * (4096 + 16)]
        with self.assertRaises(Corrupted):
            blob.decrypt_bytes(truncated, self.key)

    def test_chunk_reordering_is_detected(self):
        sealed = blob.encrypt_bytes(os.urandom(4096 * 2 + 10), self.key, chunk_size=4096)
        h, c = blob.HEADER_SIZE, 4096 + 16
        swapped = sealed[:h] + sealed[h + c:h + 2 * c] + sealed[h:h + c] + sealed[h + 2 * c:]
        with self.assertRaises(Corrupted):
            blob.decrypt_bytes(swapped, self.key)

    def test_reader_random_access(self):
        data = os.urandom(4096 * 3 + 100)
        with tempfile.NamedTemporaryFile(delete=False) as f:
            f.write(blob.encrypt_bytes(data, self.key, chunk_size=4096))
        try:
            with blob.BlobReader(f.name, self.key) as r:
                self.assertEqual(r.plain_size, len(data))
                self.assertEqual(r.read(4000, 300), data[4000:4300])
                self.assertEqual(r.read(len(data) - 10, 100), data[-10:])
        finally:
            os.remove(f.name)

    def test_reader_rejects_appended_garbage(self):
        with tempfile.NamedTemporaryFile(delete=False) as f:
            f.write(blob.encrypt_bytes(os.urandom(5000), self.key, chunk_size=4096) + b"x" * 20)
        try:
            with self.assertRaises(Corrupted):
                blob.BlobReader(f.name, self.key)
        finally:
            os.remove(f.name)


class VaultTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="mahzen-test-")
        self.dir = os.path.join(self.tmp, "kasa")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_create_unlock_and_files(self):
        v = Vault.create(self.dir, PASSWORD, SMALL)
        src = os.path.join(self.tmp, "a.bin")
        data = os.urandom(blob.DEFAULT_CHUNK_SIZE + 123)
        with open(src, "wb") as f:
            f.write(data)
        fid = str(uuid.uuid4()).upper()
        digest = v.import_file(src, fid)
        self.assertEqual(digest, sha(data))
        idx = VaultIndex()
        idx.files.append(new_file_record(fid, "a.bin", len(data), None, None, False, None, digest))
        v.save_index(idx)

        again = Vault.unlock(self.dir, PASSWORD)
        loaded, recovered = again.load_index()
        self.assertFalse(recovered)
        self.assertEqual(loaded.files[0]["name"], "a.bin")
        self.assertEqual(again.read_file(fid), data)
        self.assertEqual(again.verify_file(fid), digest)

    def test_wrong_password(self):
        Vault.create(self.dir, PASSWORD, SMALL)
        with self.assertRaises(WrongPassword):
            Vault.unlock(self.dir, "yanlis-parola-123")

    def test_short_password_rejected(self):
        with self.assertRaises(PasswordTooShort):
            Vault.create(self.dir, "kısa", SMALL)

    def test_password_nfc_normalization(self):
        decomposed = "şifre-güzel-123"  # ş ve ü ayrık biçimde
        composed = "şifre-güzel-123"
        Vault.create(self.dir, decomposed, SMALL)
        Vault.unlock(self.dir, composed)

    def test_change_password_and_keyfile(self):
        v = Vault.create(self.dir, PASSWORD, SMALL)
        v.change_password(PASSWORD, "yeni-parola-çok-uzun", SMALL)
        v = Vault.unlock(self.dir, "yeni-parola-çok-uzun")
        keyfile = Vault.generate_keyfile()
        v.set_keyfile(keyfile, "yeni-parola-çok-uzun", SMALL)
        with self.assertRaises(WrongPassword):
            Vault.unlock(self.dir, "yeni-parola-çok-uzun")
        v = Vault.unlock(self.dir, "yeni-parola-çok-uzun", keyfile)
        self.assertTrue(v.requires_keyfile)
        v.set_keyfile(None, "yeni-parola-çok-uzun", SMALL)
        Vault.unlock(self.dir, "yeni-parola-çok-uzun")

    def test_index_backup_recovery(self):
        v = Vault.create(self.dir, PASSWORD, SMALL)
        idx = VaultIndex()
        idx.notes.append(new_note())
        v.save_index(idx)
        v.save_index(idx)  # .bak artık notu içeriyor
        with open(os.path.join(self.dir, "index.enc"), "r+b") as f:
            f.seek(20)
            f.write(b"\x00\x01\x02")
        loaded, recovered = v.load_index()
        self.assertTrue(recovered)
        self.assertEqual(len(loaded.notes), 1)

    def test_unknown_fields_survive(self):
        v = Vault.create(self.dir, PASSWORD, SMALL)
        idx = VaultIndex({"notes": [{**new_note(), "gelecekAlan": 42}], "yeniBolum": {"a": 1}})
        v.save_index(idx)
        loaded, _ = v.load_index()
        self.assertEqual(loaded.notes[0]["gelecekAlan"], 42)
        self.assertEqual(loaded.data["yeniBolum"], {"a": 1})

    def test_backup_and_integrity(self):
        v = Vault.create(self.dir, PASSWORD, SMALL)
        src = os.path.join(self.tmp, "a.txt")
        with open(src, "wb") as f:
            f.write(b"yedeklenecek")
        fid = str(uuid.uuid4()).upper()
        digest = v.import_file(src, fid)
        rec = new_file_record(fid, "a.txt", 12, None, None, False, None, digest)
        idx = VaultIndex()
        idx.files.append(rec)
        v.save_index(idx)

        dest = os.path.join(self.tmp, "yedek")
        report = v.backup(dest, {fid}, set())
        self.assertEqual(report.copied_files, 1)
        self.assertEqual(Vault.unlock(dest, PASSWORD).read_file(fid), b"yedeklenecek")
        self.assertEqual(v.backup(dest, {fid}, set()).unchanged_files, 1)

        with open(v.blob_path(fid), "r+b") as f:
            f.seek(10)
            f.write(b"\xff")
        orphan = os.path.join(self.dir, "blobs", "zz", "sahipsiz.mhz")
        os.makedirs(os.path.dirname(orphan))
        open(orphan, "wb").close()
        integrity = v.check_integrity([rec])
        self.assertIn(fid, integrity.problems)
        self.assertEqual(integrity.orphan_paths, [orphan])
        v.restore_file_from_backup(fid, dest)
        self.assertEqual(v.verify_file(fid), digest)

    def test_backup_refuses_inside_vault(self):
        v = Vault.create(self.dir, PASSWORD, SMALL)
        with self.assertRaises(Corrupted):
            v.backup(os.path.join(self.dir, "yedek"), set(), set())


class IndexTests(unittest.TestCase):
    def test_folders_trash_and_restore(self):
        idx = VaultIndex()
        a = idx.create_folder("A", None)
        b = idx.create_folder("B", a)
        self.assertEqual(idx.create_folder("A", None) != a, True)
        self.assertEqual(idx.folder(idx.child_folders(None)[1]["id"])["name"], "A 2")
        f = new_file_record("F1", "x", 1, None, None, False, b, None)
        idx.files.append(f)
        self.assertFalse(idx.move_folder(a, b))
        idx.trash_folder(a)
        self.assertEqual([x["id"] for x in idx.trashed_folders], [a])
        self.assertEqual(idx.trashed_files, [])
        idx.restore_folder(a)
        self.assertIsNone(idx.file("F1").get("deletedAt"))
        idx.trash_folder(a)
        self.assertEqual(idx.empty_trash(), ["F1"])
        self.assertEqual(idx.folders[0]["name"], "A 2")

    def test_purge_expired(self):
        idx = VaultIndex()
        n = new_note()
        n["deletedAt"] = "2020-01-01T00:00:00Z"
        idx.notes.append(n)
        idx.purge_expired(30)
        self.assertEqual(idx.notes, [])

    def test_ensure_folder_path_and_tags(self):
        idx = VaultIndex()
        leaf = idx.ensure_folder_path(["Tatil", "2026"], None)
        self.assertEqual(idx.ensure_folder_path(["Tatil", "2026"], None), leaf)
        idx.files.append(new_file_record("F", "x", 1, None, None, False, None, None))
        idx.set_tags([" b ", "a", "a", ""], {"F"})
        self.assertEqual(idx.all_tags, ["a", "b"])


class OtherTests(unittest.TestCase):
    def test_generator(self):
        opts = {"length": 24, "uppercase": True, "lowercase": True, "digits": True, "symbols": True,
                "avoidAmbiguous": True}
        pw = passwords.generate(opts)
        self.assertEqual(len(pw), 24)
        self.assertFalse(set(pw) & passwords.AMBIGUOUS)
        self.assertTrue(any(c.isdigit() for c in pw) and any(c.isupper() for c in pw))

    def test_strength(self):
        self.assertEqual(passwords.strength("aaaaaaaaaaaa")[0], 0)
        self.assertEqual(passwords.strength("parola123456")[0], 0)
        self.assertGreaterEqual(passwords.strength("x7#Kq!2mZ@9vLp$4")[0], 3)

    def test_keyfile_store_archives(self):
        tmp = tempfile.mkdtemp()
        try:
            store = KeyfileStore(os.path.join(tmp, "Anahtarlar"))
            vid = uuid.uuid4()
            store.save(b"1" * 64, vid)
            store.save(b"2" * 64, vid)
            self.assertEqual(store.candidates(vid), [b"2" * 64, b"1" * 64])
            self.assertEqual(oct(os.stat(store.path(vid)).st_mode & 0o777), "0o600")
        finally:
            shutil.rmtree(tmp)

    def test_import_plan_skips_hidden_and_links(self):
        tmp = tempfile.mkdtemp()
        try:
            root = os.path.join(tmp, "Tatil")
            os.makedirs(os.path.join(root, "2026"))
            open(os.path.join(root, "2026", "a.jpg"), "w").close()
            open(os.path.join(root, ".gizli"), "w").close()
            os.symlink("/etc/hostname", os.path.join(root, "bag"))
            plan = ImportPlan.build([root])
            self.assertEqual([i.folder_path for i in plan.items], [["Tatil", "2026"]])
            self.assertEqual(plan.skipped_count, 2)
            self.assertEqual(plan.removable_sources({root: 1}), [])
        finally:
            shutil.rmtree(tmp)


class MacOSCompatibilityTests(unittest.TestCase):
    """macOS sürümünün (Swift) oluşturduğu kasaları açar."""

    @classmethod
    def setUpClass(cls):
        with open(os.path.join(FIXTURES, "expected.json"), encoding="utf-8") as f:
            cls.expected = json.load(f)

    def test_swift_vault_contents(self):
        v = Vault.unlock(os.path.join(FIXTURES, "swift-vault"), self.expected["password"])
        self.assertFalse(v.needs_kdf_upgrade)
        idx, recovered = v.load_index()
        self.assertFalse(recovered)
        for exp in self.expected["files"]:
            rec = idx.file(exp["id"])
            self.assertEqual(rec["name"], exp["name"])
            data = v.read_file(exp["id"])
            self.assertEqual(len(data), exp["size"])
            self.assertEqual(sha(data), exp["sha256"])
            self.assertEqual(v.verify_file(exp["id"]), exp["sha256"])
            if exp["thumb"]:
                self.assertEqual(sha(v.read_thumbnail(exp["id"])), exp["thumb"])
        big = next(e for e in self.expected["files"] if e["name"] == "büyük.bin")
        with v.open_reader(big["id"]) as r:
            self.assertEqual(r.plain_size, big["size"])
        self.assertEqual(idx.preferences["accent"], "teal")
        self.assertEqual(idx.preferences["autoLockMinutes"], 7)
        self.assertEqual(idx.notes[0]["title"], "Not başlığı")
        self.assertEqual(idx.secrets[0]["password"], "P@rola-çok-gizli-123")
        self.assertEqual([f["name"] for f in idx.path_to(self.expected["folders"][1])], ["Belgeler", "2026"])
        self.assertEqual(len(idx.trashed_files), 1)
        self.assertEqual(idx.file(self.expected["files"][0]["id"])["tags"], ["iş", "önemli"])
        report = v.check_integrity(idx.files)
        self.assertEqual(report.problems, {})
        self.assertEqual(report.orphan_paths, [])

    def test_swift_vault_round_trip_keeps_it_readable(self):
        tmp = tempfile.mkdtemp()
        try:
            copy = os.path.join(tmp, "kasa")
            shutil.copytree(os.path.join(FIXTURES, "swift-vault"), copy)
            v = Vault.unlock(copy, self.expected["password"])
            idx, _ = v.load_index()
            idx.notes.append(new_note())
            v.save_index(idx)
            again, _ = Vault.unlock(copy, self.expected["password"]).load_index()
            self.assertEqual(len(again.notes), 2)
        finally:
            shutil.rmtree(tmp)

    def test_swift_keyfile_vault(self):
        folder = os.path.join(FIXTURES, "swift-keyfile-vault")
        with open(os.path.join(FIXTURES, "anahtar.mahzenkey"), "rb") as f:
            keyfile = f.read()
        with self.assertRaises(WrongPassword):
            Vault.unlock(folder, self.expected["password"])
        v = Vault.unlock(folder, self.expected["password"], keyfile)
        self.assertEqual(v.load_index()[0].notes[0]["title"], "anahtarlı")

    def test_swift_pbkdf2_vault_and_upgrade(self):
        tmp = tempfile.mkdtemp()
        try:
            copy = os.path.join(tmp, "kasa")
            shutil.copytree(os.path.join(FIXTURES, "swift-pbkdf2-vault"), copy)
            v = Vault.unlock(copy, self.expected["password"])
            self.assertTrue(v.needs_kdf_upgrade)
            v.upgrade_kdf(self.expected["password"], SMALL)
            v = Vault.unlock(copy, self.expected["password"])
            self.assertFalse(v.needs_kdf_upgrade)
            self.assertEqual(v.load_index()[0].notes[0]["title"], "eski")
        finally:
            shutil.rmtree(tmp)

    def test_python_fixture_is_current(self):
        """macOS testinin açtığı, bu sürümle oluşturulmuş kasa yerinde ve açılabiliyor."""
        folder = os.path.join(FIXTURES, "python-vault")
        if not os.path.exists(folder):
            self.skipTest("python-vault yok; make_python_fixture.py ile üretin")
        v = Vault.unlock(folder, PASSWORD)
        self.assertEqual(read_header(folder).vault_id, v.vault_id)
        self.assertGreater(len(v.load_index()[0].files), 0)


if __name__ == "__main__":
    unittest.main()
