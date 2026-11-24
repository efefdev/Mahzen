"""“Telefondan Ekle” testleri: parça parça çözme, kasaya akışla yazma, yükleme alıcısı, sunucu ve telefon sayfası.

Çalıştırmak için: ``python3 -m unittest discover -s linux/tests``

Telefon sayfasındaki JavaScript şifreleyici Node.js kuruluysa sayfanın kendisinden çalıştırılır; çıktısı Python'da
çözülür. ``MAHZEN_UPLOAD_FIXTURE=/yol/onek`` verilirse büyük dosyanın akışı ``onek.stream`` / ``onek.plain`` olarak
yazılır; macOS tarafında aynı değişkenle ``swift test --filter PhoneUploadTests`` bu dosyaları Swift'te çözer.
"""

import ast
import hashlib
import http.client
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from mahzen.core import blob, crypto, phoneshare as ps, phoneupload as pu  # noqa: E402
from mahzen.core.errors import Corrupted  # noqa: E402
from mahzen.core.vault import Vault  # noqa: E402

SMALL = crypto.KDFSettings(iterations=1, memory_kib=8192, parallelism=1)
FIXED_KEY = bytes(range(32))
# `PhoneUploadTests.swift` içindeki değerler: sabit anahtarla JavaScript şifreleyicinin (`MahzenUpload.seal`) çıktıları.
JS_MESSAGE_STREAM7 = "00000026ce82694bab1a3dff756f99521c445a8179df065f1ea2ac457e2c24c6c0df6309a0c5e841acda"
JS_EMPTY_STREAM6 = "0000001086e0d882adcfcfd14518c46c2cbdd412"
FRAME = 4 + ps.CHUNK_SIZE + ps.TAG_SIZE


def decode_in_pieces(sealed: bytes, key: bytes, stream: int) -> bytes:
    dec = ps.StreamDecoder(key, stream)
    out, offset, step = bytearray(), 0, 1
    while offset < len(sealed):
        for p in dec.push(sealed[offset:offset + step]):
            out += p
        offset += step
        step = (step * 7 + 13) % 300000 + 1
    out += dec.finish()
    return bytes(out)


def phone_parts(data: bytes, key: bytes, meta: dict, number: int) -> tuple[bytes, list[bytes]]:
    """Telefonun yapacağı gibi: dosya bilgisi akışı ve `FRAMES_PER_PART` çerçevelik içerik parçaları."""
    sealed_meta = ps.seal(json.dumps(meta).encode(), key, pu.meta_stream(number))
    content = ps.seal(data, key, pu.content_stream(number))
    size = pu.FRAMES_PER_PART * FRAME
    return sealed_meta, [content[i:i + size] for i in range(0, len(content), size)]


def read(path: str) -> bytes:
    with open(path, "rb") as f:
        return f.read()


def blob_files(vault) -> list[str]:
    out = []
    for root, _dirs, files in os.walk(os.path.join(vault.folder, "blobs")):
        out += [os.path.join(root, f) for f in files]
    return out


class StreamDecoderTests(unittest.TestCase):
    key = ps.new_key()

    def test_matches_seal(self):
        n = ps.CHUNK_SIZE
        for size in [0, 1, n - 1, n, n + 1, 3 * n + 17]:
            data = os.urandom(size)
            self.assertEqual(decode_in_pieces(ps.seal(data, self.key, 9), self.key, 9), data, f"boyut {size}")

    def test_rejects_tampering_and_truncation(self):
        data = os.urandom(2 * ps.CHUNK_SIZE + 10)
        sealed = ps.seal(data, self.key, 3)
        tampered = bytearray(sealed)
        tampered[200] ^= 1
        for bad in (bytes(tampered), sealed[:2 * FRAME], sealed[:2 * FRAME + 7]):
            with self.assertRaises(Corrupted):
                decode_in_pieces(bad, self.key, 3)
        with self.assertRaises(Corrupted):
            decode_in_pieces(sealed, self.key, 5)  # başka bir akışın çerçeveleri
        with self.assertRaises(Corrupted):
            ps.StreamDecoder(self.key, 3).finish()
        with self.assertRaises(Corrupted):
            ps.StreamDecoder(self.key, 3).push(b"\x7f\x00\x00\x00")


class BlobWriterTests(unittest.TestCase):
    def test_matches_encrypt_stream_and_cancel_cleans_up(self):
        tmp = tempfile.mkdtemp()
        try:
            key = os.urandom(32)
            for size in [0, 1, 4095, 4096, 4097, 3 * 4096 + 5, 100000]:
                data = os.urandom(size)
                path = os.path.join(tmp, "blobs", "ab", f"{size}.mhz")
                writer = blob.BlobWriter(path, key, 4096)
                offset, step = 0, 1
                while offset < size:
                    writer.append(data[offset:offset + step])
                    offset += step
                    step = step * 3 + 1
                digest = writer.finish()
                self.assertEqual(read(path), blob.encrypt_bytes(data, key, 4096), f"boyut {size}")
                self.assertEqual(digest, hashlib.sha256(data).hexdigest())
            cancelled = blob.BlobWriter(os.path.join(tmp, "blobs", "cd", "iptal.mhz"), key)
            cancelled.append(os.urandom(3 << 20))
            cancelled.cancel()
            self.assertEqual(os.listdir(os.path.join(tmp, "blobs", "cd")), [])
        finally:
            shutil.rmtree(tmp)


class ReceiverTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.vault = Vault.create(os.path.join(self.tmp, "kasa"), "doğru-at-pil-zımba-42", SMALL)
        self.key = ps.new_key()

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def test_writes_encrypted_file_to_vault(self):
        data = os.urandom(9 * ps.CHUNK_SIZE + 777)
        meta = {"name": "IMG_0001.HEIC", "size": len(data), "type": "image/heic", "modified": 1700000000000}
        sealed_meta, parts = phone_parts(data, self.key, meta, 3)
        self.assertNotIn(b"IMG_0001", sealed_meta)
        r = pu.UploadReceiver.for_vault(3, self.key, self.vault)
        got = r.receive_meta(sealed_meta)
        self.assertEqual((got.name, got.size, got.type, got.modified_seconds),
                         ("IMG_0001.HEIC", len(data), "image/heic", 1700000000.0))
        digest = None
        for i, part in enumerate(parts):
            self.assertTrue(r.expects(i + 1))
            for start in range(0, len(part), 300001):
                r.consume(part[start:start + 300001])
            digest = r.end_part(i == len(parts) - 1)
        self.assertEqual(digest, hashlib.sha256(data).hexdigest())
        self.assertEqual(self.vault.read_file(r.file_id), data)
        self.assertEqual(len(blob_files(self.vault)), 1)
        self.assertNotIn(data[:64], read(self.vault.blob_path(r.file_id)))

    def test_rejects_bad_input_and_cleans_up(self):
        data = os.urandom(2 * ps.CHUNK_SIZE + 5)
        meta = {"name": "video.mov", "size": len(data)}
        sealed_meta, parts = phone_parts(data, self.key, meta, 1)
        v, k = self.vault, self.key

        def expect(code, body):
            with self.assertRaises(pu.UploadFailure) as ctx:
                body()
            self.assertEqual(ctx.exception.code, code)

        expect("meta", lambda: pu.UploadReceiver.for_vault(2, k, v).receive_meta(sealed_meta))
        expect("meta", lambda: pu.UploadReceiver.for_vault(1, ps.new_key(), v).receive_meta(sealed_meta))
        expect("meta", lambda: pu.UploadReceiver.for_vault(1, k, v).receive_meta(
            ps.seal(b'{"name": 3, "size": 1}', k, pu.meta_stream(1))))
        expect("too-large", lambda: pu.UploadReceiver.for_vault(1, k, v, max_file_size=1000).receive_meta(sealed_meta))
        expect("no-space", lambda: pu.UploadReceiver(1, k, v.begin_import, lambda: 1 << 20).receive_meta(sealed_meta))
        expect("order", lambda: pu.UploadReceiver.for_vault(1, k, v).consume(parts[0]))
        twice = pu.UploadReceiver.for_vault(1, k, v)
        twice.receive_meta(sealed_meta)
        expect("order", lambda: twice.receive_meta(sealed_meta))
        self.assertFalse(twice.expects(2))
        twice.cancel()

        tampered = pu.UploadReceiver.for_vault(1, k, v)
        tampered.receive_meta(sealed_meta)
        bad = bytearray(parts[0])
        bad[50] ^= 1
        expect("crypto", lambda: (tampered.consume(bytes(bad)), tampered.end_part(True)))
        tampered.cancel()

        truncated = pu.UploadReceiver.for_vault(1, k, v)
        truncated.receive_meta(sealed_meta)
        truncated.consume(parts[0][:2 * FRAME])
        expect("crypto", lambda: truncated.end_part(True))
        truncated.cancel()

        lying = pu.UploadReceiver.for_vault(1, k, v)
        lying.receive_meta(ps.seal(json.dumps({"name": "x", "size": 10}).encode(), k, pu.meta_stream(1)))
        expect("crypto", lambda: (lying.consume(parts[0]), lying.end_part(True)))
        lying.cancel()

        abandoned = pu.UploadReceiver.for_vault(1, k, v)
        abandoned.receive_meta(sealed_meta)
        abandoned.consume(parts[0][:FRAME + 100])
        abandoned.cancel()
        self.assertEqual(blob_files(v), [])

    def test_name_is_sanitized(self):
        self.assertEqual(pu.sanitize_name("IMG_0001.JPG"), "IMG_0001.JPG")
        self.assertEqual(pu.sanitize_name("../../etc/passwd"), "passwd")
        self.assertEqual(pu.sanitize_name("C:\\Users\\a\\rapor.pdf"), "rapor.pdf")
        self.assertEqual(pu.sanitize_name(".gizli"), "gizli")
        self.assertEqual(pu.sanitize_name("a\x00b\nc.txt"), "abc.txt")
        long = pu.sanitize_name("u" * 300 + ".mp4")
        self.assertEqual(len(long), 200)
        self.assertTrue(long.endswith(".mp4"))
        self.assertTrue(pu.sanitize_name("/"))


class UploadPageTests(unittest.TestCase):
    def test_csp_hash_matches_embedded_script(self):
        body, headers = pu.upload_page()
        html = body.decode("utf-8")
        script = re.search(r"<script>(.*)</script>", html, re.S).group(1)
        import base64
        digest = base64.b64encode(hashlib.sha256(script.encode()).digest()).decode()
        csp = headers["Content-Security-Policy"]
        self.assertIn(f"script-src 'sha256-{digest}'", csp)
        self.assertTrue(csp.startswith("default-src 'none'; "))
        self.assertIn("connect-src 'self'", csp)
        self.assertEqual(html.count("<script"), 1)
        self.assertNotIn("Mac'", html)
        self.assertNotIn("the Mac", html)

    def test_page_matches_macos_source(self):
        """Linux'taki yükleme sayfası macOS'taki `PhoneUploadPage.swift` ile birebir aynı."""
        import sync_phone_viewer as sync
        if not os.path.exists(sync.SWIFT_UPLOAD_SOURCE):
            self.skipTest("macOS kaynağı yok")
        with open(sync.LINUX_UPLOAD_PAGE, encoding="utf-8") as f:
            self.assertEqual(f.read(), sync.linux_upload_page_from_swift(),
                             "sayfa eski: python3 linux/tests/sync_phone_viewer.py ile yeniden aktarın")

    def test_uses_viewer_crypto(self):
        """Şifreleme kodu görüntüleyici sayfasıyla aynı (iki kopya ayrışamaz)."""
        viewer = ps.viewer_page()[0].decode("utf-8")
        upload = pu.upload_page()[0].decode("utf-8")
        crypto_part = viewer[viewer.index("<script>") + 8:viewer.index('\n\n(() => {\n  "use strict";')]
        self.assertIn("const MahzenStream", crypto_part)
        self.assertTrue(upload[upload.index("<script>") + 8:].startswith(crypto_part + "\n"))
        self.assertIn("const MahzenUpload", upload)


class BrowserEncoderTests(unittest.TestCase):
    """Telefon sayfasındaki JavaScript şifreleyici (sayfanın kendisinden) Python ve Swift'in açtığı akışı üretir.
    Node.js kuruluysa çalışır."""

    NODE_SCRIPT = r"""
const fs = require("fs");
const [code, outPrefix] = process.argv.slice(2);
const { MahzenUpload } = new Function(fs.readFileSync(code, "utf8") + "; return { MahzenUpload };")();
const key = Uint8Array.from({ length: 32 }, (_, i) => i);
const hex = (b) => Buffer.from(b).toString("hex");
(async () => {
  const size = 2 * 1048576 + 4321, data = new Uint8Array(size);
  for (let i = 0; i < size; i++) data[i] = (i * 13 + (i >> 9)) & 255;
  const file = new Blob([data]), parts = [];
  for (let first = 0; first < MahzenUpload.chunkCount(size); first += 2)
    parts.push(Buffer.from(await MahzenUpload.fileFrames(key, 9, file, first, 2)));
  fs.writeFileSync(outPrefix + ".stream", Buffer.concat(parts));
  fs.writeFileSync(outPrefix + ".plain", data);
  console.log(JSON.stringify({
    message7: hex(MahzenUpload.seal(key, 7, new TextEncoder().encode("Mahzen telefondan ekle"))),
    empty6: hex(MahzenUpload.seal(key, 6, new Uint8Array(0))),
    emptyFile: hex(await MahzenUpload.fileFrames(key, 11, new Blob([]), 0, 4)),
  }));
})();
"""

    def test_javascript_encoder_output_decrypts(self):
        node = shutil.which("node")
        if not node:
            self.skipTest("node kurulu değil")
        html = pu.upload_page()[0].decode("utf-8")
        script = re.search(r"<script>(.*)</script>", html, re.S).group(1)
        end = script.index("})();", script.index("const MahzenUpload")) + len("})();")
        tmp = tempfile.mkdtemp()
        try:
            for name, content in {"code.js": script[:end], "run.js": self.NODE_SCRIPT}.items():
                with open(os.path.join(tmp, name), "w", encoding="utf-8") as f:
                    f.write(content)
            prefix = os.environ.get("MAHZEN_UPLOAD_FIXTURE") or os.path.join(tmp, "js")
            result = subprocess.run([node, os.path.join(tmp, "run.js"), os.path.join(tmp, "code.js"), prefix],
                                    capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stderr)
            out = json.loads(result.stdout)
            self.assertEqual(out["message7"], JS_MESSAGE_STREAM7)
            self.assertEqual(out["empty6"], JS_EMPTY_STREAM6)
            self.assertEqual(ps.open_stream(bytes.fromhex(out["message7"]), FIXED_KEY, 7), b"Mahzen telefondan ekle")
            self.assertEqual(ps.open_stream(bytes.fromhex(out["emptyFile"]), FIXED_KEY, 11), b"")
            with open(prefix + ".stream", "rb") as f:
                stream = f.read()
            with open(prefix + ".plain", "rb") as f:
                plain = f.read()
            self.assertEqual(decode_in_pieces(stream, FIXED_KEY, 9), plain)
        finally:
            shutil.rmtree(tmp)

    def test_python_seal_matches_javascript_vectors(self):
        self.assertEqual(ps.seal(b"Mahzen telefondan ekle", FIXED_KEY, 7).hex(), JS_MESSAGE_STREAM7)
        self.assertEqual(ps.seal(b"", FIXED_KEY, 6).hex(), JS_EMPTY_STREAM6)


class ServerTests(unittest.TestCase):
    """Gerçek bir kasaya, yerel döngü adresindeki sunucuya HTTP istekleriyle uçtan uca."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        cls.vault = Vault.create(os.path.join(cls.tmp, "kasa"), "doğru-at-pil-zımba-42", SMALL)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def setUp(self):
        self.saved: list = []
        self.session = pu.PhoneUploadSession(self.vault, None, "Tatil")
        self.session.accept = self.accept
        url = self.session.start("127.0.0.1")
        match = re.fullmatch(r"http://127\.0\.0\.1:(\d+)/([A-Za-z0-9_-]{22})/#([A-Za-z0-9_-]{43})", url)
        self.assertIsNotNone(match, url)
        self.port, self.token = int(match.group(1)), match.group(2)
        import base64
        self.key = base64.urlsafe_b64decode(match.group(3) + "=")

    def tearDown(self):
        self.session.stop()

    def accept(self, completed):
        if any(c.sha256 == completed.sha256 for c in self.saved):
            self.vault.delete_file(completed.file_id)
            return "duplicate"
        self.saved.append(completed)
        return "saved"

    def request(self, path, method="GET", body=None):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=30)
        conn.request(method, f"/{self.token}/{path}", body=body)
        res = conn.getresponse()
        data = res.read()
        conn.close()
        return res, data

    def upload(self, name: str, data: bytes, type_=None) -> tuple[int, dict]:
        res, body = self.request("n", "POST")
        n = json.loads(body)["n"]
        sealed_meta, parts = phone_parts(data, self.key, {"name": name, "size": len(data), "type": type_}, n)
        res, body = self.request(f"u/{n}/0", "POST", sealed_meta)
        if res.status != 200:
            return res.status, json.loads(body or b"{}")
        for i, part in enumerate(parts):
            res, body = self.request(f"u/{n}/{i + 1}" + ("?end=1" if i == len(parts) - 1 else ""), "POST", part)
            if res.status != 200:
                break
        return res.status, json.loads(body or b"{}")

    def test_page_status_upload_and_duplicate(self):
        res, body = self.request("")
        self.assertEqual(res.status, 200)
        self.assertEqual(body, pu.upload_page()[0])
        self.assertEqual(res.getheader("Content-Security-Policy"), pu.upload_page()[1]["Content-Security-Policy"])
        self.assertEqual(res.getheader("Cache-Control"), "no-store")
        res, body = self.request("s")
        status = json.loads(ps.open_stream(body, self.key, pu.STATUS_STREAM))
        self.assertEqual((status["folder"], status["maxFileSize"], status["framesPerPart"]),
                         ("Tatil", pu.MAX_FILE_SIZE, pu.FRAMES_PER_PART))

        data = os.urandom(6 * ps.CHUNK_SIZE + 321)
        self.assertEqual(self.upload("belge.bin", data), (200, {"result": "saved"}))
        self.assertEqual(self.vault.read_file(self.saved[0].file_id), data)
        self.assertEqual(self.upload("kopya.bin", data), (200, {"result": "duplicate"}))
        self.assertEqual(self.upload("bos.txt", b""), (200, {"result": "saved"}))
        items = [i for _n, i in self.session.snapshot()]
        self.assertEqual([(i["name"], i["state"]) for i in items],
                         [("belge.bin", "saved"), ("kopya.bin", "duplicate"), ("bos.txt", "saved")])
        self.assertEqual(self.session.devices, {"127.0.0.1"})
        self.assertFalse([p for p in blob_files(self.vault) if p.endswith(".tmp")])

    def test_cancel_partial_and_limits(self):
        before = set(blob_files(self.vault))
        data = os.urandom(6 * ps.CHUNK_SIZE)
        # İptal: bir parça gönderildikten sonra.
        n = json.loads(self.request("n", "POST")[1])["n"]
        sealed_meta, parts = phone_parts(data, self.key, {"name": "iptal.mov", "size": len(data)}, n)
        self.assertEqual(self.request(f"u/{n}/0", "POST", sealed_meta)[0].status, 200)
        self.assertEqual(self.request(f"u/{n}/1", "POST", parts[0])[0].status, 200)
        self.assertEqual(self.request(f"x/{n}", "POST")[0].status, 200)
        self.assertEqual(self.request(f"u/{n}/2", "POST", parts[1])[0].status, 409)
        # Yarıda kesilen istek (telefon kapandı): bağlantı düşer, yükleme bırakılır.
        n = json.loads(self.request("n", "POST")[1])["n"]
        sealed_meta, parts = phone_parts(data, self.key, {"name": "yarim.mov", "size": len(data)}, n)
        self.request(f"u/{n}/0", "POST", sealed_meta)
        import socket
        s = socket.create_connection(("127.0.0.1", self.port))
        s.sendall(f"POST /{self.token}/u/{n}/1 HTTP/1.1\r\nContent-Length: {len(parts[0])}\r\n\r\n".encode()
                  + parts[0][:FRAME + 500])
        time.sleep(0.3)
        s.close()
        for _ in range(50):
            if self.session.server.open_uploads() == 0:
                break
            time.sleep(0.1)
        self.assertEqual(self.session.server.open_uploads(), 0)
        self.assertEqual(set(blob_files(self.vault)), before, "iptal ve yarım yüklemelerden dosya kalmamalı")
        states = {i["name"]: i["state"] for _n, i in self.session.snapshot()}
        self.assertEqual(states, {"iptal.mov": "cancelled", "yarim.mov": "failed:net"})

        # Sınırlar: gövde boyutu, aynı anda açık yükleme sayısı, yanlış anahtar.
        n = json.loads(self.request("n", "POST")[1])["n"]
        res, body = self.request(f"u/{n}/0", "POST", b"\0" * (pu.MAX_META_LENGTH + 1))
        self.assertEqual((res.status, json.loads(body)), (413, {"error": "length"}))
        for _ in range(pu.MAX_OPEN_UPLOADS):
            self.request("n", "POST")
        res, body = self.request("n", "POST")
        self.assertEqual((res.status, json.loads(body)), (429, {"error": "busy"}))
        res, body = self.request("u/1/0", "POST", ps.seal(b"{}", ps.new_key(), 2))
        self.assertIn(res.status, (400, 409))

    def test_rejections(self):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        for path in ("/", "/yanlis-jeton/s", f"/{self.token[:-1]}x/"):
            conn.request("GET", path)
            res = conn.getresponse()
            res.read()
            self.assertEqual(res.status, 404, path)
            conn.close()
        res, _ = self.request("u/9/0", "POST", b"x")
        self.assertEqual(res.status, 409)
        res, _ = self.request("s", "PUT")
        self.assertEqual(res.status, 405)
        self.session.server.expires_at = time.time() - 1
        self.assertEqual(self.request("s")[0].status, 404)

    def test_rejected_upload_is_discarded(self):
        """Kasa kilitlendiyse (kabul edilmezse) kasaya taşınmış dosya silinir ve telefon oturumu kapalı görür."""
        self.session.accept = lambda c: "rejected"
        before = set(blob_files(self.vault))
        status, _ = self.upload("x.bin", os.urandom(1000))
        self.assertEqual(status, 404)
        self.assertEqual(set(blob_files(self.vault)), before)

    def test_stop_cancels_open_upload(self):
        before = set(blob_files(self.vault))
        n = json.loads(self.request("n", "POST")[1])["n"]
        data = os.urandom(6 * ps.CHUNK_SIZE)
        sealed_meta, parts = phone_parts(data, self.key, {"name": "dur.mov", "size": len(data)}, n)
        self.request(f"u/{n}/0", "POST", sealed_meta)
        self.request(f"u/{n}/1", "POST", parts[0])
        self.session.stop()
        self.assertEqual(set(blob_files(self.vault)), before)
        self.assertEqual(self.session.snapshot()[0][1]["state"], "cancelled")


class TranslationTests(unittest.TestCase):
    def test_new_texts_have_english(self):
        from mahzen.i18n_en import ENGLISH
        root = os.path.join(os.path.dirname(__file__), "..", "mahzen")
        missing = []
        for rel in ("ui/phoneupload.py", "ui/files.py", "ui/state.py", "core/phoneupload.py", "core/phoneshare.py"):
            with open(os.path.join(root, rel), encoding="utf-8") as f:
                tree = ast.parse(f.read())
            for node in ast.walk(tree):
                if isinstance(node, ast.Call) and getattr(node.func, "id", None) == "tr" and node.args \
                        and isinstance(node.args[0], ast.Constant) and isinstance(node.args[0].value, str):
                    text = node.args[0].value
                    ctx = next((k.value.value for k in node.keywords if k.arg == "_ctx"), None)
                    if (f"{text}|{ctx}" if ctx else text) not in ENGLISH:
                        missing.append(f"{rel}: {text}")
        self.assertEqual(missing, [])


if __name__ == "__main__":
    unittest.main()
