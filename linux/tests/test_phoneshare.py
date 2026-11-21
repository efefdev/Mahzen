"""“Telefonda Göster”, dikdörtgenle seçim ve önizlemede gezinme testleri.

Çalıştırmak için: ``python3 -m unittest discover -s linux/tests``

Şifreli akış biçimi macOS sürümüyle (`PhoneShare.swift`) bayt bayt aynı olmalıdır. Sabit anahtarlı çapraz
denetim akışının özeti aşağıda; macOS tarafında `MAHZEN_PHONE_FIXTURE=/yol/onek swift test --filter
PhoneShareTests` ile yazılan `onek.stream` / `onek.plain` dosyaları da aynı değişkenle bu teste verilebilir.
"""

import ast
import base64
import hashlib
import http.client
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from mahzen.core import crypto, phoneshare as ps, qr, selection as sel  # noqa: E402
from mahzen.core.errors import Corrupted  # noqa: E402
from mahzen.core.index import VaultIndex, new_file_record  # noqa: E402
from mahzen.core.vault import Vault  # noqa: E402

SMALL = crypto.KDFSettings(iterations=1, memory_kib=8192, parallelism=1)
FIXED_KEY = bytes(range(32))
# macOS'taki `PhoneShare.seal` çıktıları (sabit anahtar 00 01 … 1f).
SWIFT_EMPTY_STREAM0 = "00000010c76d3ca7753de65100c68c43e9823eed"
SWIFT_MERHABA_STREAM2 = "0000001747bb53b73e3bc47869866f39264e5078c57e2187af6399"
SWIFT_CROSSCHECK_SHA256 = "c514ccf091a35c535d093937ad7d4a15f7fee9aaad0de6a976d657852f5771d1"


def crosscheck_plain() -> bytes:
    """`PhoneShareTests.testWriteCrossCheckFixture` içindeki düz içerik."""
    return bytes(((i * 31 + i // 7) & 0xFF) for i in range(2 * ps.CHUNK_SIZE + 12345))


class StreamFormatTests(unittest.TestCase):
    key = ps.new_key()

    def test_round_trip_and_stream_length(self):
        n = ps.CHUNK_SIZE
        for size in [0, 1, n - 1, n, n + 1, 3 * n + 17]:
            data = os.urandom(size)
            sealed = ps.seal(data, self.key, 7)
            self.assertEqual(len(sealed), ps.stream_length(size), f"boyut {size}")
            self.assertEqual(ps.open_stream(sealed, self.key, 7), data, f"boyut {size}")

    def test_wrong_key_or_stream_fails(self):
        sealed = ps.seal(b"merhaba", self.key, 3)
        with self.assertRaises(Corrupted):
            ps.open_stream(sealed, ps.new_key(), 3)
        # Bir dosyanın akışı başka bir dosyanınkiymiş gibi sunulamaz.
        with self.assertRaises(Corrupted):
            ps.open_stream(sealed, self.key, 5)

    def test_tamper_truncation_and_reorder_are_detected(self):
        data = os.urandom(2 * ps.CHUNK_SIZE + 10)
        sealed = ps.seal(data, self.key, 1)
        tampered = bytearray(sealed)
        tampered[100] ^= 1
        with self.assertRaises(Corrupted):
            ps.open_stream(bytes(tampered), self.key, 1)
        frame = 4 + ps.CHUNK_SIZE + 16
        # Son çerçeveyi at: kalan son çerçeve "son değil" diye mühürlendiği için reddedilmeli.
        with self.assertRaises(Corrupted):
            ps.open_stream(sealed[:2 * frame], self.key, 1)
        swapped = sealed[frame:2 * frame] + sealed[:frame] + sealed[2 * frame:]
        with self.assertRaises(Corrupted):
            ps.open_stream(swapped, self.key, 1)
        with self.assertRaises(Corrupted):
            ps.open_stream(b"", self.key, 1)

    def test_manifest_is_encrypted(self):
        item = ps.ShareItem({"id": "A", "name": "pasaport-taramasi.jpg", "size": 10, "hasThumbnail": True},
                            ["Belgeler"], 0)
        sealed = ps.seal(ps.manifest_json("Tatil", 0, [item]), self.key, ps.MANIFEST_STREAM)
        self.assertNotIn(b"pasaport", sealed)

    def test_matches_swift_byte_for_byte(self):
        """Python'un şifrelediği akış macOS sürümünün (CryptoKit) çıktısıyla aynı."""
        self.assertEqual(ps.seal(b"", FIXED_KEY, 0).hex(), SWIFT_EMPTY_STREAM0)
        self.assertEqual(ps.seal(b"merhaba", FIXED_KEY, 2).hex(), SWIFT_MERHABA_STREAM2)
        self.assertEqual(ps.open_stream(bytes.fromhex(SWIFT_MERHABA_STREAM2), FIXED_KEY, 2), b"merhaba")
        sealed = ps.seal(crosscheck_plain(), FIXED_KEY, 5)
        self.assertEqual(hashlib.sha256(sealed).hexdigest(), SWIFT_CROSSCHECK_SHA256)

    def test_swift_fixture_files(self):
        """macOS testinin yazdığı akış (MAHZEN_PHONE_FIXTURE) Python'da çözülür ve Python'unkiyle aynıdır."""
        prefix = os.environ.get("MAHZEN_PHONE_FIXTURE")
        if not prefix:
            self.skipTest("çapraz denetim istenmedi (MAHZEN_PHONE_FIXTURE)")
        with open(prefix + ".stream", "rb") as f:
            stream = f.read()
        with open(prefix + ".plain", "rb") as f:
            plain = f.read()
        self.assertEqual(plain, crosscheck_plain())
        self.assertEqual(ps.open_stream(stream, FIXED_KEY, 5), plain)
        self.assertEqual(ps.seal(plain, FIXED_KEY, 5), stream)


class ShareListTests(unittest.TestCase):
    def test_media_kinds_and_mime(self):
        self.assertTrue(ps.is_shareable({"name": "a.JPG"}))
        self.assertTrue(ps.is_shareable({"name": "film.mov"}))
        self.assertTrue(ps.is_shareable({"name": "adsız", "contentType": "public.heic"}))
        self.assertFalse(ps.is_shareable({"name": "not.txt"}))
        self.assertFalse(ps.is_shareable({"name": "belge.pdf"}))
        self.assertEqual(ps.mime_type({"name": "a.jpeg"}), "image/jpeg")
        self.assertEqual(ps.mime_type({"name": "b.mov"}), "video/quicktime")
        self.assertEqual(ps.mime_type({"name": "adsız", "contentType": "public.mpeg-4"}), "video/mp4")

    def test_order_and_folder_paths(self):
        idx = VaultIndex()
        root = idx.create_folder("Tatil", None)
        sub = idx.create_folder("2026", root)
        other = idx.create_folder("Başka", None)
        for name, folder in [("b.jpg", root), ("a.mp4", sub), ("not.txt", root), ("c.png", root),
                             ("dışarıda.jpg", other)]:
            idx.files.append(new_file_record(os.urandom(16).hex().upper(), name, 1, None, None, False, folder, None))
        files = ps.folder_files(idx, root)
        self.assertEqual(sorted(r["name"] for r, _ in files), ["a.mp4", "b.jpg", "c.png", "not.txt"])
        items = ps.plan_items(files)
        self.assertEqual([(it.record["name"], it.path, it.index) for it in items],
                         [("b.jpg", [], 0), ("c.png", [], 1), ("a.mp4", ["2026"], 2)])
        manifest = json.loads(ps.manifest_json("Tatil", 123.5, items))
        self.assertEqual(manifest["title"], "Tatil")
        self.assertEqual(manifest["expiresAt"], 123.5)
        self.assertEqual(manifest["items"][2], {"index": 2, "name": "a.mp4", "path": ["2026"], "kind": "video",
                                                "mime": "video/mp4", "size": 1, "hasThumbnail": False})

    def test_session_needs_media(self):
        with self.assertRaises(ValueError):
            ps.PhoneShareSession(None, "x", [({"id": "A", "name": "not.txt"}, [])])

    def test_choose_ipv4(self):
        self.assertEqual(ps.choose_ipv4([("lo", "127.0.0.1"), ("docker0", "172.17.0.1"),
                                         ("enp3s0", "192.168.1.5"), ("wlp2s0", "192.168.1.9")]), "192.168.1.9")
        self.assertEqual(ps.choose_ipv4([("virbr0", "192.168.122.1"), ("eth0", "10.0.0.4")]), "10.0.0.4")
        self.assertIsNone(ps.choose_ipv4([("tun0", "10.8.0.2"), ("wlan0", "169.254.3.3")]))


class ViewerPageTests(unittest.TestCase):
    def test_csp_hash_matches_embedded_script(self):
        body, headers = ps.viewer_page()
        html = body.decode("utf-8")
        script = re.search(r"<script>(.*)</script>", html, re.S).group(1)
        digest = base64.b64encode(hashlib.sha256(script.encode()).digest()).decode()
        csp = headers["Content-Security-Policy"]
        self.assertIn(f"script-src 'sha256-{digest}'", csp)
        self.assertTrue(csp.startswith("default-src 'none'; "))
        self.assertIn("connect-src 'self'", csp)
        self.assertEqual(headers["X-Frame-Options"], "DENY")
        self.assertEqual(html.count("<script"), 1)
        self.assertNotIn("Mac'", html)
        self.assertNotIn("the Mac", html)

    def test_page_matches_macos_source(self):
        """Linux'taki sayfa, macOS'taki `PhoneShareViewer.swift` ile aynı (yalnızca "Mac" metinleri farklı)."""
        import sync_phone_viewer as sync
        if not os.path.exists(sync.SWIFT_SOURCE):
            self.skipTest("macOS kaynağı yok")
        with open(sync.LINUX_PAGE, encoding="utf-8") as f:
            self.assertEqual(f.read(), sync.linux_page_from_swift(),
                             "sayfa eski: python3 linux/tests/sync_phone_viewer.py ile yeniden aktarın")


class BrowserDecoderTests(unittest.TestCase):
    """Telefon sayfasındaki JavaScript çözücü (ChaCha20-Poly1305 + akış ayrıştırıcı) Python'un akışını açar.
    Node.js kuruluysa çalışır."""

    NODE_SCRIPT = r"""
const fs = require("fs");
const [code, keyHex, streamFile, plainFile, streamId] = process.argv.slice(2);
const MahzenStream = new Function(fs.readFileSync(code, "utf8") + "; return MahzenStream;")();
const key = Uint8Array.from(Buffer.from(keyHex, "hex"));
const data = new Uint8Array(fs.readFileSync(streamFile));
const dec = MahzenStream.decoder(key, Number(streamId));
const out = [];
for (let i = 0, step = 1; i < data.length; i += step, step = (step * 7 + 13) % 300000 + 1)
  for (const p of dec.push(data.subarray(i, i + step))) out.push(p);
out.push(dec.finish());
const plain = Buffer.concat(out.map((p) => Buffer.from(p)));
if (!plain.equals(fs.readFileSync(plainFile))) { console.error("farklı"); process.exit(1); }
let tampered = Uint8Array.from(data); tampered[40] ^= 1;
try { const d = MahzenStream.decoder(key, Number(streamId)); d.push(tampered); d.finish(); process.exit(2); }
catch (e) { console.log("ok"); }
"""

    def test_javascript_decoder_opens_python_stream(self):
        node = shutil.which("node")
        if not node:
            self.skipTest("node kurulu değil")
        html = ps.viewer_page()[0].decode("utf-8")
        script = re.search(r"<script>(.*)</script>", html, re.S).group(1)
        end = script.index("const MahzenStream")
        end = script.index("})();", end) + len("})();")
        tmp = tempfile.mkdtemp()
        try:
            key, plain = ps.new_key(), os.urandom(2 * ps.CHUNK_SIZE + 999)
            files = {"code.js": script[:end], "run.js": self.NODE_SCRIPT,
                     "stream.bin": ps.seal(plain, key, 9), "plain.bin": plain}
            for name, content in files.items():
                with open(os.path.join(tmp, name), "wb") as f:
                    f.write(content.encode() if isinstance(content, str) else content)
            result = subprocess.run([node, os.path.join(tmp, "run.js"), os.path.join(tmp, "code.js"), key.hex(),
                                     os.path.join(tmp, "stream.bin"), os.path.join(tmp, "plain.bin"), "9"],
                                    capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "ok")
        finally:
            shutil.rmtree(tmp)


class ServerTests(unittest.TestCase):
    """Gerçek bir kasadan, yerel döngü adresindeki sunucuya HTTP istekleriyle uçtan uca."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        cls.vault = Vault.create(os.path.join(cls.tmp, "kasa"), "doğru-at-pil-zımba-42", SMALL)
        cls.photo = os.urandom(3 * 1024 * 1024 + 77)
        cls.video = os.urandom(5000)
        cls.records = []
        for name, data in [("tatil.jpg", cls.photo), ("klip.mp4", cls.video), ("gizli-not.txt", b"gizli")]:
            path = os.path.join(cls.tmp, name)
            with open(path, "wb") as f:
                f.write(data)
            fid = os.urandom(16).hex().upper()
            cls.vault.import_file(path, fid)
            record = new_file_record(fid, name, len(data), None, None, name == "tatil.jpg", None, None)
            if record["hasThumbnail"]:
                cls.vault.write_thumbnail(b"kucuk-resim", fid)
            cls.records.append(record)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def setUp(self):
        self.session = ps.PhoneShareSession(self.vault, "Tatil", [(r, []) for r in self.records])
        url = self.session.start("127.0.0.1")
        match = re.fullmatch(r"http://127\.0\.0\.1:(\d+)/([A-Za-z0-9_-]{22})/#([A-Za-z0-9_-]{43})", url)
        self.assertIsNotNone(match, url)
        self.port, self.token = int(match.group(1)), match.group(2)
        self.key = base64.urlsafe_b64decode(match.group(3) + "=")

    def tearDown(self):
        self.session.stop()

    def get(self, path, method="GET"):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        conn.request(method, path)
        res = conn.getresponse()
        body = res.read()
        conn.close()
        return res, body

    def test_page_manifest_files_and_thumbnail(self):
        self.assertEqual(self.session.photo_count, 1)
        self.assertEqual(self.session.video_count, 1)
        res, body = self.get(f"/{self.token}/")
        self.assertEqual(res.status, 200)
        self.assertEqual(res.getheader("Content-Type"), "text/html; charset=utf-8")
        self.assertEqual(res.getheader("Cache-Control"), "no-store")
        self.assertEqual(res.getheader("Referrer-Policy"), "no-referrer")
        self.assertEqual(res.getheader("X-Content-Type-Options"), "nosniff")
        self.assertEqual(res.getheader("Content-Security-Policy"), ps.viewer_page()[1]["Content-Security-Policy"])
        self.assertEqual(body, ps.viewer_page()[0])

        res, body = self.get(f"/{self.token}/m")
        self.assertEqual(res.status, 200)
        self.assertNotIn(b"tatil", body)
        manifest = json.loads(ps.open_stream(body, self.key, ps.MANIFEST_STREAM))
        names = [it["name"] for it in manifest["items"]]
        self.assertEqual(names, ["klip.mp4", "tatil.jpg"])  # .txt paylaşılmaz
        self.assertAlmostEqual(manifest["expiresAt"], self.session.expires_at)

        photo_index = names.index("tatil.jpg")
        res, body = self.get(f"/{self.token}/f/{photo_index}")
        self.assertEqual(res.status, 200)
        self.assertEqual(int(res.getheader("Content-Length")), ps.stream_length(len(self.photo)))
        self.assertEqual(ps.open_stream(body, self.key, ps.file_stream(photo_index)), self.photo)
        res, body = self.get(f"/{self.token}/f/{names.index('klip.mp4')}")
        self.assertEqual(ps.open_stream(body, self.key, ps.file_stream(names.index("klip.mp4"))), self.video)

        res, body = self.get(f"/{self.token}/t/{photo_index}")
        self.assertEqual(ps.open_stream(body, self.key, ps.thumbnail_stream(photo_index)), b"kucuk-resim")
        # Küçük resmi olmayan dosya ve sınır dışı sıra bulunamaz.
        self.assertEqual(self.get(f"/{self.token}/t/{names.index('klip.mp4')}")[0].status, 404)
        self.assertEqual(self.get(f"/{self.token}/f/2")[0].status, 404)
        self.assertEqual(self.get(f"/{self.token}/f/-1")[0].status, 404)
        self.assertEqual(self.session.devices, {"127.0.0.1"})

    def test_rejections(self):
        self.assertEqual(self.get("/")[0].status, 404)
        self.assertEqual(self.get("/yanlis-jeton/m")[0].status, 404)
        self.assertEqual(self.get(f"/{self.token[:-1]}x/")[0].status, 404)
        self.assertEqual(self.get(f"/{self.token}/m", method="POST")[0].status, 405)
        res, _ = self.get(f"/{self.token}")
        self.assertEqual(res.status, 301)
        self.assertEqual(res.getheader("Location"), f"/{self.token}/")
        self.assertEqual(self.session.devices, set())  # reddedilen istekler cihaz sayılmaz

    def test_stop_closes_listener(self):
        self.session.stop()
        with self.assertRaises(OSError):
            socket.create_connection(("127.0.0.1", self.port), timeout=2).recv(1)

    def test_expired_share_is_gone(self):
        self.session.server.expires_at = time.time() - 1
        self.assertEqual(self.get(f"/{self.token}/m")[0].status, 404)


class QRTests(unittest.TestCase):
    def test_structure(self):
        url = "http://192.168.1.23:54321/" + "a" * 22 + "/#" + "b" * 43
        m = qr.encode(url)
        size = len(m)
        self.assertEqual(size, 41)  # 95 bayt, M düzeyi → sürüm 6
        self.assertTrue(all(len(row) == size for row in m))
        for cx, cy in ((0, 0), (size - 7, 0), (0, size - 7)):  # konum işaretleri
            self.assertTrue(all(m[cy][cx + i] and m[cy + 6][cx + i] for i in range(7)))
            self.assertFalse(m[cy + 1][cx + 1])
            self.assertTrue(m[cy + 3][cx + 3])
        self.assertEqual([m[6][x] for x in range(8, size - 8)], [x % 2 == 0 for x in range(8, size - 8)])
        self.assertTrue(m[size - 8][8])  # her zaman koyu modül

    def test_matches_reference_library(self):
        """Kuruluysa `qrcode` paketinin ürettiğiyle aynı matris (aynı sürüm ve maske)."""
        try:
            import qrcode
        except ImportError:
            self.skipTest("qrcode paketi kurulu değil")
        for n in (5, 30, 95, 150, 400):
            text = ("http://10.0.0.2:4000/" + "x7" * n)[:n]
            for mask in range(8):
                ref = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M, border=0, mask_pattern=mask)
                ref.add_data(text.encode(), optimize=0)
                ref.make(fit=True)
                self.assertEqual(qr.encode(text, version=ref.version, mask=mask), ref.get_matrix(), (n, mask))

    def test_too_long(self):
        with self.assertRaises(ValueError):
            qr.encode("x" * 3000)


class SelectionTests(unittest.TestCase):
    frames = {"a": (0, 0, 100, 80), "b": (110, 0, 100, 80), "c": (0, 90, 100, 80)}

    def test_marquee(self):
        rect = sel.rect_from_points((150, 40), (50, 10))
        self.assertEqual(rect, (50, 10, 100, 30))
        self.assertEqual(sel.marquee_selection(set(), self.frames, rect), {"a", "b"})
        self.assertEqual(sel.marquee_selection(set(), self.frames, (101, 81, 8, 8)), set())
        # Ctrl/Shift: mevcut seçim korunur, dikdörtgendekiler tersine çevrilir.
        self.assertEqual(sel.marquee_selection({"a", "c"}, self.frames, rect), {"b", "c"})

    def test_autoscroll_speed(self):
        self.assertEqual(sel.autoscroll_speed(200, 400), 0)
        self.assertLess(sel.autoscroll_speed(10, 400), 0)
        self.assertGreater(sel.autoscroll_speed(390, 400), 0)
        self.assertEqual(sel.autoscroll_speed(-500, 400), -sel.AUTOSCROLL_MAX)
        self.assertEqual(sel.autoscroll_speed(5000, 400), sel.AUTOSCROLL_MAX)

    def test_gtk_result_shapes(self):
        """GTK sürümlerine göre değişen dönüş biçimleri (ör. GTK 4.24'te translate_coordinates iki değer döner)."""
        from types import SimpleNamespace as NS
        point = NS(x=3.5, y=4)
        self.assertEqual(sel.point_from_result((True, point)), (3.5, 4.0))
        self.assertEqual(sel.point_from_result(point), (3.5, 4.0))
        self.assertIsNone(sel.point_from_result((False, point)))
        self.assertEqual(sel.point_from_result((True, 1.0, 2.0)), (1.0, 2.0))
        self.assertEqual(sel.point_from_result((1.0, 2.0)), (1.0, 2.0))
        self.assertIsNone(sel.point_from_result((False, 0.0, 0.0)))
        self.assertIsNone(sel.point_from_result(None))
        rect = NS(get_x=lambda: 1, get_y=lambda: 2, get_width=lambda: 30, get_height=lambda: 40)
        self.assertEqual(sel.rect_from_result((True, rect)), (1.0, 2.0, 30.0, 40.0))
        self.assertEqual(sel.rect_from_result(rect), (1.0, 2.0, 30.0, 40.0))
        self.assertIsNone(sel.rect_from_result((False, rect)))

    def test_ui_needs_no_cairo_bridge(self):
        """Arayüz cairo köprüsü (python3-gi-cairo) olmadan da çizebilmeli: draw_func ve translate_coordinates yok."""
        ui = os.path.join(os.path.dirname(__file__), "..", "mahzen", "ui")
        for name in os.listdir(ui):
            if name.endswith(".py"):
                with open(os.path.join(ui, name), encoding="utf-8") as f:
                    code = f.read()
                self.assertNotIn("set_draw_func", code, name)
                self.assertNotIn(".translate_coordinates(self", code, name)

    def test_step_position(self):
        self.assertEqual(sel.step_position(0, 1, 3), 1)
        self.assertIsNone(sel.step_position(0, -1, 3))
        self.assertIsNone(sel.step_position(2, 1, 3))


class TranslationTests(unittest.TestCase):
    def test_new_texts_have_english(self):
        """Bu özelliklerin arayüz metinlerinin hepsinin İngilizcesi var."""
        from mahzen.i18n_en import ENGLISH
        root = os.path.join(os.path.dirname(__file__), "..", "mahzen")
        missing = []
        for rel in ("ui/phoneshare.py", "ui/files.py", "ui/state.py", "core/phoneshare.py"):
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
