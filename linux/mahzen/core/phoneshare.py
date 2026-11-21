"""“Telefonda Göster”: kasadaki fotoğraf ve videoları aynı yerel ağdaki telefonda, uçtan uca şifreli gösterir.

macOS sürümüyle (`PhoneShare.swift`, `PhoneShareServer.swift`) birebir aynı biçim ve davranış:

- Oturum anahtarı (256 bit) yalnızca QR koddaki adresin `#` sonrasındadır; tarayıcı bu kısmı sunucuya
  hiç göndermez. Sunucu kasadaki dosyayı kendi içinde çözer ve bu anahtarla yeniden şifreler; ağda
  yalnızca şifreli bayt dolaşır. Çözme işini telefondaki tarayıcı yapar (ChaCha20-Poly1305, RFC 8439).
- Akış biçimi: art arda çerçeveler; her çerçeve `uzunluk (UInt32, big-endian)` + `şifreli metin + 16 bayt etiket`.
  Nonce (12 bayt) = akış kimliği (UInt32) + parça sırası (UInt64), big-endian.
  Ek doğrulanan veri = `"mahzen.phone.v1|"` + son parça bayrağı (`1`/`0`).
- Sunucu yalnızca bu oturumun rastgele adresine (`/<jeton>/…`) cevap verir, yalnızca seçilen dosyaları
  sunar, süre dolunca ya da durdurulunca dinlemeyi ve açık bağlantıları hemen keser.

Bu modül arayüzden bağımsızdır (GTK gerektirmez); oturum penceresi `ui/phoneshare.py` içindedir.
"""

from __future__ import annotations

import base64
import ctypes
import ctypes.util
import hashlib
import hmac
import json
import os
import socket
import struct
import sys
import threading
import time
from typing import Callable

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305

from ..i18n import tr
from .errors import Corrupted
from .filetypes import extension, kind_of
from .index import sort_key

CHUNK_SIZE = 1 << 20
TAG_SIZE = 16
AAD_PREFIX = b"mahzen.phone.v1|"
MANIFEST_STREAM = 0
LIFETIME = 10 * 60  # saniye
HEADER_LIMIT = 16 * 1024
IDLE_TIMEOUT = 30  # yanıt vermeyen bağlantılar bu kadar saniye sonra kapatılır
SEND_TIMEOUT = 120  # telefon bu kadar süre hiç veri almazsa aktarım bırakılır


def file_stream(index: int) -> int:
    """Akış kimlikleri: 0 = içerik listesi, 2i+1 = i. dosya, 2i+2 = i. dosyanın küçük resmi."""
    return 2 * index + 1


def thumbnail_stream(index: int) -> int:
    return 2 * index + 2


def new_key() -> bytes:
    return os.urandom(32)


def _nonce(stream: int, chunk: int) -> bytes:
    return struct.pack(">IQ", stream, chunk)


def _aad(final: bool) -> bytes:
    return AAD_PREFIX + (b"1" if final else b"0")


def stream_length(plain_size: int) -> int:
    """`plain_size` baytlık bir içeriğin şifreli akış uzunluğu (Content-Length için)."""
    chunks = max(1, (plain_size + CHUNK_SIZE - 1) // CHUNK_SIZE)
    return plain_size + chunks * (4 + TAG_SIZE)


def seal_frame(plain: bytes, key: bytes, stream: int, chunk: int, final: bool) -> bytes:
    """Bir parçayı çerçeve olarak şifreler."""
    sealed = ChaCha20Poly1305(key).encrypt(_nonce(stream, chunk), plain, _aad(final))
    return struct.pack(">I", len(sealed)) + sealed


def seal(data: bytes, key: bytes, stream: int) -> bytes:
    """Bellekteki küçük bir içeriği (liste, küçük resim) tek akış olarak şifreler."""
    out = bytearray()
    offset, chunk = 0, 0
    while True:
        end = min(offset + CHUNK_SIZE, len(data))
        out += seal_frame(data[offset:end], key, stream, chunk, end == len(data))
        offset, chunk = end, chunk + 1
        if offset >= len(data):
            return bytes(out)


def open_stream(data: bytes, key: bytes, stream: int) -> bytes:
    """Bir akışı çözer (testler ve doğrulama için; telefonda aynı işi tarayıcı yapar)."""
    aead = ChaCha20Poly1305(key)
    out = bytearray()
    offset, chunk = 0, 0
    while offset < len(data):
        if len(data) - offset < 4:
            raise Corrupted(tr("akış kesik"))
        (length,) = struct.unpack(">I", data[offset:offset + 4])
        offset += 4
        if length < TAG_SIZE or len(data) - offset < length:
            raise Corrupted(tr("akış kesik"))
        body = data[offset:offset + length]
        offset += length
        try:
            out += aead.decrypt(_nonce(stream, chunk), body, _aad(offset == len(data)))
        except InvalidTag:
            raise Corrupted(tr("içerik doğrulanamadı")) from None
        chunk += 1
    if chunk == 0:
        raise Corrupted(tr("akış boş"))
    return bytes(out)


def base64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


# MARK: - Paylaşılacak dosyalar

# Telefondaki tarayıcıya bildirilen içerik türleri (macOS'taki `preferredMIMEType` karşılıkları).
_MIME = {
    "jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "gif": "image/gif", "webp": "image/webp",
    "heic": "image/heic", "heif": "image/heif", "bmp": "image/bmp", "tif": "image/tiff", "tiff": "image/tiff",
    "svg": "image/svg+xml", "ico": "image/vnd.microsoft.icon",
    "mp4": "video/mp4", "m4v": "video/x-m4v", "mov": "video/quicktime", "mkv": "video/x-matroska",
    "webm": "video/webm", "avi": "video/avi",
}
_MIME_BY_UTI = {"public.jpeg": "image/jpeg", "public.png": "image/png", "public.heic": "image/heic",
                "public.heif": "image/heif", "com.apple.quicktime-movie": "video/quicktime",
                "public.mpeg-4": "video/mp4"}


def media_kind(record: dict) -> str | None:
    """Telefonda gösterilebilen tür: "image", "video" ya da None."""
    kind = kind_of(record)
    return kind if kind in ("image", "video") else None


def is_shareable(record: dict) -> bool:
    return media_kind(record) is not None


def mime_type(record: dict) -> str:
    return (_MIME.get(extension(record.get("name", "")))
            or _MIME_BY_UTI.get(record.get("contentType") or "")
            or "application/octet-stream")


def folder_files(index, folder_id: str) -> list[tuple[dict, list[str]]]:
    """Klasördeki (alt klasörler dahil) dosyalar; her biri paylaşılan klasöre göre yoluyla."""
    ids = {i.upper() for i in index.descendant_folder_ids(folder_id)} | {folder_id.upper()}
    base = len(index.path_to(folder_id))
    out = []
    for f in index.live_files:
        parent = f.get("folderID")
        if parent and parent.upper() in ids:
            out.append((f, [p["name"] for p in index.path_to(parent)[base:]]))
    return out


class ShareItem:
    def __init__(self, record: dict, path: list[str], index: int):
        self.record = record
        self.path = path
        self.index = index
        self.kind = media_kind(record) or "image"

    @property
    def id(self) -> str:
        return self.record["id"]

    @property
    def has_thumbnail(self) -> bool:
        return bool(self.record.get("hasThumbnail"))


def plan_items(files: list[tuple[dict, list[str]]]) -> list[ShareItem]:
    """Gösterilebilen dosyaları klasör yolu, sonra ada göre sıralar."""
    media = [(r, p) for r, p in files if is_shareable(r)]
    media.sort(key=lambda rp: (sort_key("/".join(rp[1])), sort_key(rp[0]["name"])))
    return [ShareItem(r, p, i) for i, (r, p) in enumerate(media)]


def manifest_json(title: str, expires_at: float, items: list[ShareItem]) -> bytes:
    """Telefona gönderilen içerik listesi. Şifreli gider; dosya adları da ağda görünmez."""
    return json.dumps({
        "title": title,
        "expiresAt": expires_at,
        "items": [{"index": it.index, "name": it.record["name"], "path": it.path, "kind": it.kind,
                   "mime": mime_type(it.record), "size": int(it.record.get("size", 0)),
                   "hasThumbnail": it.has_thumbnail} for it in items],
    }, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


# MARK: - Telefon sayfası

_PAGE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "phone_viewer.html")
_page_cache: tuple[bytes, dict[str, str]] | None = None


def viewer_page() -> tuple[bytes, dict[str, str]]:
    """Görüntüleyici sayfası ve güvenlik başlıkları. Sayfa yalnızca kendi gömülü betiğini çalıştırabilir,
    yalnızca kendi sunucusuna bağlanabilir."""
    global _page_cache
    if _page_cache is None:
        with open(_PAGE_PATH, encoding="utf-8") as f:
            html = f.read()
        start = html.index("<script>") + len("<script>")
        script = html[start:html.index("</script>", start)]
        digest = base64.b64encode(hashlib.sha256(script.encode("utf-8")).digest()).decode("ascii")
        headers = {
            "Content-Security-Policy": "; ".join([
                "default-src 'none'",
                f"script-src 'sha256-{digest}'",
                "style-src 'unsafe-inline'",
                "img-src blob: data:",
                "media-src blob:",
                "connect-src 'self'",
                "base-uri 'none'",
                "form-action 'none'",
                "frame-ancestors 'none'",
            ]),
            "X-Frame-Options": "DENY",
            "Cross-Origin-Opener-Policy": "same-origin",
            "Cross-Origin-Resource-Policy": "same-origin",
            "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
        }
        _page_cache = (html.encode("utf-8"), headers)
    return _page_cache


# MARK: - Sunucu

BASE_HEADERS = {
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
    "Connection": "close",
}


class PhoneShareServer:
    """Yerel ağda çalışan küçük HTTP sunucusu. Her bağlantı kendi iş parçacığında, tek istek sonra kapanır."""

    def __init__(self, vault, items: list[ShareItem], key: bytes, token: str, manifest: bytes,
                 expires_at: float | None = None):
        self.vault = vault
        self.items = items
        self.key = key
        self.token = token
        self.manifest = manifest
        self.expires_at = expires_at
        # Her başarılı istekte (uzak adres, sunulan dosya sırası ya da None) sunucu iş parçacığında çağrılır.
        self.on_request: Callable[[str, int | None], None] | None = None
        self._listener: socket.socket | None = None
        self._connections: set[socket.socket] = set()
        self._lock = threading.Lock()
        self._stopped = False

    def start(self, host: str) -> int:
        """Verilen yerel adreste rastgele bir portta dinlemeye başlar; port numarasını döndürür."""
        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind((host, 0))
        listener.listen(16)
        self._listener = listener
        threading.Thread(target=self._accept_loop, args=(listener,), daemon=True).start()
        return listener.getsockname()[1]

    @property
    def stopped(self) -> bool:
        return self._stopped

    def stop(self) -> None:
        with self._lock:
            self._stopped = True
            listener, self._listener = self._listener, None
            connections, self._connections = self._connections, set()
        for sock in [listener, *connections]:
            if sock is None:
                continue
            try:
                sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            try:
                sock.close()
            except OSError:
                pass

    def _expired(self) -> bool:
        return self.expires_at is not None and time.time() >= self.expires_at

    def _accept_loop(self, listener: socket.socket) -> None:
        while not self._stopped:
            try:
                conn, addr = listener.accept()
            except OSError:
                return
            with self._lock:
                if self._stopped:
                    conn.close()
                    return
                self._connections.add(conn)
            threading.Thread(target=self._serve, args=(conn, addr[0]), daemon=True).start()

    def _serve(self, conn: socket.socket, remote: str) -> None:
        try:
            conn.settimeout(IDLE_TIMEOUT)
            header = self._read_header(conn)
            if header is not None and not self._stopped:
                self._handle(conn, header, remote)
        except OSError:
            pass
        finally:
            with self._lock:
                self._connections.discard(conn)
            try:
                conn.close()
            except OSError:
                pass

    @staticmethod
    def _read_header(conn: socket.socket) -> bytes | None:
        """İstek başlığını okur (en fazla 16 KB; gövde beklenmez, yalnızca GET)."""
        buffer = b""
        while b"\r\n\r\n" not in buffer:
            if len(buffer) > HEADER_LIMIT:
                return None
            data = conn.recv(HEADER_LIMIT)
            if not data:
                return None
            buffer += data
        return buffer[:buffer.index(b"\r\n\r\n")]

    def _handle(self, conn: socket.socket, header: bytes, remote: str) -> None:
        request_line = header.split(b"\r", 1)[0].decode("utf-8", errors="replace")
        parts = request_line.split(" ")
        parts = [p for p in parts if p]
        if len(parts) < 2 or parts[0] != "GET":
            return self._respond(conn, "405 Method Not Allowed")
        path = parts[1].split("?", 1)[0]
        segments = [s for s in path.split("/") if s]
        # Jeton sabit zamanlı karşılaştırılır. Süresi dolan paylaşım da bulunamaz.
        if not segments or not hmac.compare_digest(segments[0].encode(), self.token.encode()) or self._expired():
            return self._respond(conn, "404 Not Found")
        rest = segments[1:]
        number = int(rest[1]) if len(rest) == 2 and rest[1].isdigit() and rest[1].isascii() else None
        valid = number is not None and 0 <= number < len(self.items)
        if not rest:
            if not path.endswith("/"):
                return self._respond(conn, "301 Moved Permanently", extra={"Location": f"/{self.token}/"})
            self._notify(remote, None)
            body, security = viewer_page()
            return self._respond(conn, "200 OK", "text/html; charset=utf-8", body, security)
        if rest == ["m"]:
            self._notify(remote, None)
            return self._send_sealed(conn, self.manifest, MANIFEST_STREAM)
        if rest[0] == "t" and valid and self.items[number].has_thumbnail:
            try:
                thumb = self.vault.read_thumbnail(self.items[number].id)
            except Exception:  # noqa: BLE001
                return self._respond(conn, "404 Not Found")
            return self._send_sealed(conn, thumb, thumbnail_stream(number))
        if rest[0] == "f" and valid:
            self._notify(remote, number)
            return self._send_file(conn, number)
        self._respond(conn, "404 Not Found")

    def _notify(self, remote: str, index: int | None) -> None:
        if self.on_request:
            self.on_request(remote, index)

    # MARK: Yanıtlar

    @staticmethod
    def _header_bytes(status: str, content_type: str | None, length: int, extra: dict[str, str]) -> bytes:
        lines = [f"HTTP/1.1 {status}", f"Content-Length: {length}"]
        if content_type:
            lines.append(f"Content-Type: {content_type}")
        for k, v in {**BASE_HEADERS, **extra}.items():
            lines.append(f"{k}: {v}")
        return ("\r\n".join(lines) + "\r\n\r\n").encode("utf-8")

    def _respond(self, conn: socket.socket, status: str, content_type: str | None = None, body: bytes = b"",
                 extra: dict[str, str] | None = None) -> None:
        conn.sendall(self._header_bytes(status, content_type, len(body), extra or {}) + body)

    def _send_sealed(self, conn: socket.socket, data: bytes, stream: int) -> None:
        try:
            sealed = seal(data, self.key, stream)
        except Exception:  # noqa: BLE001
            return self._respond(conn, "500 Internal Server Error")
        self._respond(conn, "200 OK", "application/octet-stream", sealed)

    def _send_file(self, conn: socket.socket, index: int) -> None:
        """Dosyayı kasadan parça parça çözüp yeniden şifreleyerek gönderir; bellekte en fazla bir parça tutulur."""
        try:
            reader = self.vault.open_reader(self.items[index].id)
        except Exception:  # noqa: BLE001
            return self._respond(conn, "500 Internal Server Error")
        with reader:
            size = reader.plain_size
            stream = file_stream(index)
            chunks = max(1, (size + CHUNK_SIZE - 1) // CHUNK_SIZE)
            conn.settimeout(SEND_TIMEOUT)
            conn.sendall(self._header_bytes("200 OK", "application/octet-stream", stream_length(size), {}))
            for chunk in range(chunks):
                if self._stopped:
                    return
                plain = reader.read(chunk * CHUNK_SIZE, CHUNK_SIZE)
                conn.sendall(seal_frame(plain, self.key, stream, chunk, chunk == chunks - 1))


class PhoneShareSession:
    """Bir paylaşım oturumu: içerik listesi, anahtar, jeton ve sunucu. Arayüzden bağımsız."""

    def __init__(self, vault, title: str, files: list[tuple[dict, list[str]]], lifetime: float = LIFETIME):
        self.items = plan_items(files)
        if not self.items:
            raise ValueError("no media")
        self.title = title
        self.photo_count = sum(1 for it in self.items if it.kind == "image")
        self.video_count = len(self.items) - self.photo_count
        self.expires_at = time.time() + lifetime
        self.key = new_key()
        self.token = base64url(os.urandom(16))
        self.devices: set[str] = set()
        self.url: str | None = None
        self.server = PhoneShareServer(vault, self.items, self.key, self.token,
                                       manifest_json(title, self.expires_at, self.items), self.expires_at)
        self.server.on_request = lambda remote, _i: self.devices.add(remote)

    def start(self, host: str) -> str:
        port = self.server.start(host)
        self.url = f"http://{host}:{port}/{self.token}/#{base64url(self.key)}"
        return self.url

    def stop(self) -> None:
        self.server.stop()

    @property
    def seconds_left(self) -> int:
        return max(0, int(self.expires_at - time.time()))


# MARK: - Yerel ağ adresi

# Telefonun ulaşamayacağı arayüzler: sanal makine/kapsayıcı köprüleri, VPN tünelleri, macOS'un AirDrop arayüzleri.
_SKIPPED_INTERFACES = ("lo", "docker", "br-", "virbr", "veth", "vnet", "tun", "tap", "wg", "tailscale", "zt",
                       "vmnet", "vboxnet", "lxc", "lxd", "podman", "cni", "flannel", "kube", "ppp",
                       "bridge", "utun", "awdl", "llw", "anpi", "ap", "gif", "stf")


class _SockAddr(ctypes.Structure):
    _fields_ = [("data", ctypes.c_ubyte * 16)]


class _IfAddrs(ctypes.Structure):
    pass


_IfAddrs._fields_ = [
    ("ifa_next", ctypes.POINTER(_IfAddrs)),
    ("ifa_name", ctypes.c_char_p),
    ("ifa_flags", ctypes.c_uint),
    ("ifa_addr", ctypes.POINTER(_SockAddr)),
]

_IFF_UP, _IFF_LOOPBACK, _IFF_RUNNING = 0x1, 0x8, 0x40


def _interfaces() -> list[tuple[str, str]]:
    """(arayüz adı, IPv4 adresi) çiftleri; açık, çalışan, geri döngü olmayan arayüzler."""
    libc = ctypes.CDLL(ctypes.util.find_library("c") or None, use_errno=True)
    head = ctypes.POINTER(_IfAddrs)()
    if libc.getifaddrs(ctypes.byref(head)) != 0:
        return []
    out = []
    try:
        node = head
        while node:
            ifa = node.contents
            flags = ifa.ifa_flags
            if ifa.ifa_addr and flags & _IFF_UP and flags & _IFF_RUNNING and not flags & _IFF_LOOPBACK:
                raw = bytes(ifa.ifa_addr.contents.data)
                # Linux: sa_family 16 bit; BSD/macOS: önce 8 bit uzunluk, sonra 8 bit aile.
                family = raw[1] if sys.platform == "darwin" else struct.unpack("=H", raw[:2])[0]
                if family == socket.AF_INET:
                    out.append((ifa.ifa_name.decode(errors="replace"), socket.inet_ntoa(raw[4:8])))
            node = ifa.ifa_next
    finally:
        libc.freeifaddrs(head)
    return out


def choose_ipv4(interfaces: list[tuple[str, str]]) -> str | None:
    """Telefonun ulaşabileceği adresi seçer: önce Wi-Fi (wl*, macOS'ta en0), sonra kablolu (en*, eth*)."""
    candidates = [(n, a) for n, a in interfaces
                  if not n.startswith(_SKIPPED_INTERFACES) and not a.startswith(("169.254.", "127."))]
    for test in (lambda n: n.startswith("wl") or n == "en0", lambda n: n.startswith(("en", "eth")), lambda n: True):
        for name, address in candidates:
            if test(name):
                return address
    return None


def primary_ipv4() -> str | None:
    """Bu bilgisayarın yerel ağdaki IPv4 adresi (Wi-Fi ya da kablolu)."""
    try:
        found = choose_ipv4(_interfaces())
    except (OSError, AttributeError):
        found = None
    if found:
        return found
    # Yedek yol: varsayılan rotanın kaynak adresi (paket gönderilmez).
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("192.0.2.1", 9))
            address = s.getsockname()[0]
    except OSError:
        return None
    return None if address.startswith(("127.", "169.254.", "0.")) else address
