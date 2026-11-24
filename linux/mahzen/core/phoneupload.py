"""“Telefondan Ekle”: telefondaki tarayıcı dosyaları kendisi şifreleyip yerel ağ üzerinden yükler; bilgisayar gelen
akışı bellekte çözer ve doğrudan kasanın şifreli biçimine yazar. Düz içerik hiçbir an diske yazılmaz.

macOS sürümüyle (`PhoneUpload.swift`, `PhoneUploadServer.swift`) birebir aynı biçim ve davranış:

- Şifreleme "Telefonda Göster" ile aynıdır (`phoneshare`): oturum anahtarı (256 bit) yalnızca QR koddaki adresin
  `#` sonrasındadır; akış biçimi aynı çerçevelerdir (ChaCha20-Poly1305).
- Akış kimlikleri: 0 = oturum bilgisi (bilgisayar → telefon); n. yükleme için 2n = dosya bilgisi, 2n+1 = içerik.
  Yükleme numaralarını bilgisayar dağıtır ve her birini bir kez kabul eder.
- Uç noktalar (hepsi `/<jeton>/` altında): `GET /` sayfa, `GET s` oturum bilgisi, `POST n` yeni numara,
  `POST u/<n>/0` dosya bilgisi, `POST u/<n>/<p>` içerik çerçeveleri (sonuncusu `?end=1`), `POST x/<n>` iptal.
- Gelen her bayt önce oturum anahtarıyla doğrulanır, sonra kasanın anahtarıyla şifrelenip yazılır. Yarım kalan,
  iptal edilen ya da uzun süre parça gelmeyen yüklemelerin geçici dosyaları silinir.

Bu modül arayüzden bağımsızdır (GTK gerektirmez); oturum penceresi `ui/phoneupload.py` içindedir.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import math
import os
import socket
import threading
import time
from typing import Callable

from ..i18n import tr
from .phoneshare import (BASE_HEADERS, CHUNK_SIZE, HEADER_LIMIT, IDLE_TIMEOUT, TAG_SIZE, StreamDecoder, base64url,
                         new_key, open_stream, seal)

STATUS_STREAM = 0
MAX_FILE_SIZE = 8_000_000_000  # tek dosya için üst sınır (8 GB)
FRAMES_PER_PART = 4
MAX_PART_LENGTH = FRAMES_PER_PART * (4 + CHUNK_SIZE + TAG_SIZE)
MAX_META_LENGTH = 8 * 1024
MAX_OPEN_UPLOADS = 4
UPLOAD_IDLE_TIMEOUT = 90  # bu kadar saniye parça gelmeyen yükleme bırakılır
RESERVE_SPACE = 64 << 20  # diskte dosyadan sonra boş kalması gereken alan
LIFETIME = 10 * 60


def meta_stream(number: int) -> int:
    return 2 * number


def content_stream(number: int) -> int:
    return 2 * number + 1


def sanitize_name(raw: str) -> str:
    """Kasada kullanılacak güvenli dosya adı: yol ayırıcıları ve denetim karakterleri atılır, en fazla 200 karakter."""
    last = raw.replace("\\", "/").split("/")
    name = next((p for p in reversed(last) if p), "")
    name = "".join(ch for ch in name if ch >= " " and ch not in "\x7f﻿" and not 0x80 <= ord(ch) < 0xA0).strip()
    name = name.lstrip(".")
    if len(name) > 200:
        base, dot, ext = name.rpartition(".")
        keep = "." + ext if dot and 0 < len(ext) <= 16 else ""
        name = name[:200 - len(keep)] + keep
    return name or tr("dosya")


def status_json(folder: str, expires_at: float) -> bytes:
    """Telefona gönderilen oturum bilgisi. Oturum boyunca değişmez."""
    return json.dumps({"folder": folder, "expiresAt": expires_at, "maxFileSize": MAX_FILE_SIZE,
                       "framesPerPart": FRAMES_PER_PART}, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


class UploadMeta:
    def __init__(self, name: str, size: int, type_: str | None, modified: float | None):
        self.name = name
        self.size = size
        self.type = type_
        self.modified = modified

    @property
    def safe_name(self) -> str:
        return sanitize_name(self.name)

    @classmethod
    def parse(cls, plain: bytes) -> "UploadMeta":
        data = json.loads(plain.decode("utf-8"))
        if not isinstance(data, dict):
            raise ValueError("meta")
        name, size = data.get("name"), data.get("size")
        type_, modified = data.get("type"), data.get("modified")
        if not isinstance(name, str) or not isinstance(size, int) or isinstance(size, bool) or size < 0:
            raise ValueError("meta")
        if type_ is not None and not isinstance(type_, str):
            raise ValueError("meta")
        if modified is not None and (not isinstance(modified, (int, float)) or isinstance(modified, bool)):
            raise ValueError("meta")
        return cls(name, size, type_, float(modified) if modified is not None else None)

    @property
    def modified_seconds(self) -> float | None:
        m = self.modified
        return m / 1000 if m is not None and math.isfinite(m) and m > 0 else None


class UploadFailure(Exception):
    """Yükleme reddedildi. `code` telefona gönderilen kısa hata kodudur (macOS ile aynı)."""

    def __init__(self, code: str, detail: str = ""):
        super().__init__(detail or code)
        self.code = code


class UploadReceiver:
    """Bir yüklemenin alıcısı: ağdan bağımsız durum makinesi (macOS'taki `PhoneUploadReceiver`).
    Doğrulanmamış hiçbir bayt diske ulaşmaz."""

    def __init__(self, number: int, key: bytes, make_writer: Callable[[str], object],
                 free_space: Callable[[], int | None] = lambda: None, max_file_size: int = MAX_FILE_SIZE,
                 file_id: str | None = None):
        import uuid
        self.number = number
        self.file_id = file_id or str(uuid.uuid4()).upper()
        self.meta: UploadMeta | None = None
        self.received = 0
        self.finished = False
        self._key = key
        self._make_writer = make_writer
        self._free_space = free_space
        self._max = max_file_size
        self._decoder = StreamDecoder(key, content_stream(number))
        self._writer = None
        self._next_part = 0

    @classmethod
    def for_vault(cls, number: int, key: bytes, vault, max_file_size: int = MAX_FILE_SIZE) -> "UploadReceiver":
        return cls(number, key, vault.begin_import, vault.available_capacity, max_file_size)

    def expects(self, part: int) -> bool:
        return not self.finished and part == self._next_part

    def receive_meta(self, sealed: bytes) -> UploadMeta:
        if not self.expects(0):
            raise UploadFailure("order")
        try:
            if len(sealed) > MAX_META_LENGTH:
                raise ValueError("meta")
            meta = UploadMeta.parse(open_stream(sealed, self._key, meta_stream(self.number)))
        except Exception:  # noqa: BLE001 — yanlış anahtar, bozuk istek, geçersiz JSON
            raise UploadFailure("meta") from None
        if meta.size > self._max:
            raise UploadFailure("too-large")
        free = self._free_space()
        if free is not None and free < meta.size + RESERVE_SPACE:
            raise UploadFailure("no-space")
        try:
            self._writer = self._make_writer(self.file_id)
        except OSError as e:
            raise UploadFailure("io", str(e)) from None
        self.meta = meta
        self._next_part = 1
        return meta

    def consume(self, data: bytes) -> None:
        if self._writer is None or self.meta is None or self.finished or self._next_part < 1:
            raise UploadFailure("order")
        try:
            parts = self._decoder.push(data)
        except Exception:  # noqa: BLE001
            raise UploadFailure("crypto") from None
        self._write(parts)

    def end_part(self, final: bool) -> str | None:
        """İçerik parçası bitti. `final` ise dosya kasaya taşınır ve SHA-256 özeti döner."""
        if self._writer is None or self.meta is None or self.finished or self._next_part < 1:
            raise UploadFailure("order")
        self._next_part += 1
        if not final:
            return None
        try:
            last = self._decoder.finish()
        except Exception:  # noqa: BLE001
            raise UploadFailure("crypto") from None
        self._write([last])
        if self.received != self.meta.size:
            raise UploadFailure("crypto")
        try:
            digest = self._writer.finish()
        except OSError as e:
            raise UploadFailure("io", str(e)) from None
        self.finished = True
        self._writer = None
        return digest

    def cancel(self) -> None:
        if self._writer is not None:
            self._writer.cancel()
            self._writer = None
        self.finished = True

    def _write(self, parts: list[bytes]) -> None:
        for part in parts:
            if self.received + len(part) > self.meta.size:
                raise UploadFailure("crypto")
            try:
                self._writer.append(part)
            except OSError as e:
                raise UploadFailure("io", str(e)) from None
            self.received += len(part)


# MARK: - Telefon sayfası

_PAGE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "phone_upload.html")
_page_cache: tuple[bytes, dict[str, str]] | None = None


def upload_page() -> tuple[bytes, dict[str, str]]:
    """Yükleme sayfası ve güvenlik başlıkları (macOS'taki `PhoneUploadPage.securityHeaders` ile aynı)."""
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
                "img-src data:",
                "connect-src 'self'",
                "base-uri 'none'",
                "form-action 'none'",
                "frame-ancestors 'none'",
            ]),
            "X-Frame-Options": "DENY",
            "Cross-Origin-Opener-Policy": "same-origin",
            "Cross-Origin-Resource-Policy": "same-origin",
            "Permissions-Policy": "microphone=(), geolocation=()",
        }
        _page_cache = (html.encode("utf-8"), headers)
    return _page_cache


# MARK: - Sunucu

class Completed:
    def __init__(self, number: int, meta: UploadMeta, file_id: str, sha256: str):
        self.number = number
        self.meta = meta
        self.file_id = file_id
        self.sha256 = sha256


class _Upload:
    def __init__(self, receiver: UploadReceiver):
        self.receiver = receiver
        self.last_activity = time.monotonic()
        self.conn: socket.socket | None = None
        self.lock = threading.Lock()  # alıcıya aynı anda tek iş parçacığı dokunur


class PhoneUploadServer:
    """Yerel ağda çalışan küçük HTTP sunucusu. Her bağlantı kendi iş parçacığında, tek istek sonra kapanır.

    Olaylar (`on_event`) sunucu iş parçacığında çağrılır: ("connected", adres), ("started", n, meta),
    ("progress", n, bayt), ("failed", n, kod), ("cancelled", n). `on_completed(Completed)` biten her yükleme için
    çağrılır ve "saved" | "duplicate" | "rejected" döndürür (çağıran gerekirse arayüzü bekler); atanmamışsa ya da
    sunucu durmuşsa dosya `discard` ile silinir.
    """

    def __init__(self, key: bytes, token: str, status: bytes, expires_at: float,
                 make_receiver: Callable[[int], UploadReceiver], discard: Callable[[str], None]):
        self.key = key
        self.token = token
        self.status = status
        self.expires_at = expires_at
        self.make_receiver = make_receiver
        self.discard = discard
        self.on_event: Callable[..., None] | None = None
        self.on_completed: Callable[[Completed], str] | None = None
        self._listener: socket.socket | None = None
        self._connections: set[socket.socket] = set()
        self._uploads: dict[int, _Upload] = {}
        self._next = 1
        self._lock = threading.Lock()
        self._stopped = False

    @property
    def stopped(self) -> bool:
        return self._stopped

    def start(self, host: str) -> int:
        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind((host, 0))
        listener.listen(16)
        self._listener = listener
        threading.Thread(target=self._accept_loop, args=(listener,), daemon=True).start()
        threading.Thread(target=self._sweep_loop, daemon=True).start()
        return listener.getsockname()[1]

    def stop(self) -> None:
        with self._lock:
            self._stopped = True
            listener, self._listener = self._listener, None
            connections, self._connections = self._connections, set()
            uploads, self._uploads = self._uploads, {}
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
        for upload in uploads.values():
            with upload.lock:
                upload.receiver.cancel()

    def open_uploads(self) -> int:
        with self._lock:
            return len(self._uploads)

    def _emit(self, *event) -> None:
        if self.on_event:
            self.on_event(*event)

    def _drop(self, number: int, event: tuple | None) -> None:
        with self._lock:
            upload = self._uploads.pop(number, None)
        if upload is None:
            return
        if upload.conn is not None:
            try:
                upload.conn.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        with upload.lock:
            upload.receiver.cancel()
        if event:
            self._emit(*event)

    def _sweep_loop(self) -> None:
        """Uzun süre parça gelmeyen yüklemeleri bırakır (telefon kilitlendi, sayfa kapandı, ağ koptu)."""
        while not self._stopped:
            time.sleep(5)
            now = time.monotonic()
            with self._lock:
                stale = [n for n, u in self._uploads.items() if now - u.last_activity > UPLOAD_IDLE_TIMEOUT]
            for n in stale:
                self._drop(n, ("failed", n, "timeout"))

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
            got = self._read_header(conn)
            if got is not None and not self._stopped:
                self._handle(conn, got[0], got[1], remote)
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
    def _read_header(conn: socket.socket) -> tuple[bytes, bytes] | None:
        buffer = b""
        while b"\r\n\r\n" not in buffer:
            if len(buffer) > HEADER_LIMIT:
                return None
            data = conn.recv(HEADER_LIMIT)
            if not data:
                return None
            buffer += data
        end = buffer.index(b"\r\n\r\n")
        return buffer[:end], buffer[end + 4:]

    def _handle(self, conn: socket.socket, header: bytes, leftover: bytes, remote: str) -> None:
        lines = header.decode("utf-8", errors="replace").split("\r\n")
        parts = [p for p in lines[0].split(" ") if p]
        if len(parts) < 2:
            return self._respond(conn, "400 Bad Request")
        method, target = parts[0], parts[1]
        path, _, query = target.partition("?")
        length: int | None = None
        chunked = False
        for line in lines[1:]:
            name, sep, value = line.partition(":")
            if not sep:
                continue
            name, value = name.strip().lower(), value.strip()
            if name == "content-length":
                if not value.isdigit() or not value.isascii() or (length is not None and length != int(value)):
                    return self._respond(conn, "400 Bad Request")
                length = int(value)
            elif name == "transfer-encoding":
                chunked = True
        segments = [s for s in path.split("/") if s]
        if not segments or not hmac.compare_digest(segments[0].encode(), self.token.encode()) \
                or time.time() >= self.expires_at or self._stopped:
            return self._respond(conn, "404 Not Found")
        rest = segments[1:]
        head = rest[0] if rest else None

        if method == "GET" and head is None:
            if not path.endswith("/"):
                return self._respond(conn, "301 Moved Permanently", extra={"Location": f"/{self.token}/"})
            self._emit("connected", remote)
            body, security = upload_page()
            return self._respond(conn, "200 OK", "text/html; charset=utf-8", body, security)
        if method == "GET" and rest == ["s"]:
            self._emit("connected", remote)
            return self._respond(conn, "200 OK", "application/octet-stream", seal(self.status, self.key, STATUS_STREAM))
        if method == "POST" and rest == ["n"]:
            if (length or 0) != 0 or chunked:
                return self._fail(conn, "411 Length Required", "length")
            with self._lock:
                if len(self._uploads) >= MAX_OPEN_UPLOADS:
                    busy = True
                else:
                    busy = False
                    number = self._next
                    self._next += 1
                    self._uploads[number] = _Upload(self.make_receiver(number))
            if busy:
                return self._fail(conn, "429 Too Many Requests", "busy")
            return self._json(conn, {"n": number})
        if method == "POST" and head == "x" and len(rest) == 2:
            if _is_number(rest[1]):
                self._drop(int(rest[1]), ("cancelled", int(rest[1])))
            return self._json(conn, {})
        if method == "POST" and head == "u" and len(rest) == 3:
            if not (_is_number(rest[1]) and _is_number(rest[2])):
                return self._fail(conn, "409 Conflict", "order")
            number, part = int(rest[1]), int(rest[2])
            with self._lock:
                upload = self._uploads.get(number)
            if upload is None:
                return self._fail(conn, "409 Conflict", "order", drain=(leftover, length))
            if length is None or chunked:
                self._drop(number, ("failed", number, "length"))
                return self._fail(conn, "411 Length Required", "length")
            if upload.conn is not None or not upload.receiver.expects(part):
                self._drop(number, ("failed", number, "order"))
                return self._fail(conn, "409 Conflict", "order", drain=(leftover, length))
            if length > (MAX_META_LENGTH if part == 0 else MAX_PART_LENGTH):
                self._drop(number, ("failed", number, "length"))
                return self._fail(conn, "413 Content Too Large", "length")
            final = "end=1" in query.split("&")
            return self._receive(conn, upload, number, part, final, length, leftover)
        self._respond(conn, "404 Not Found" if method in ("GET", "POST") else "405 Method Not Allowed")

    # MARK: Yükleme gövdesi

    def _receive(self, conn, upload: _Upload, number: int, part: int, final: bool, length: int,
                 leftover: bytes) -> None:
        upload.conn = conn
        upload.last_activity = time.monotonic()
        conn.settimeout(UPLOAD_IDLE_TIMEOUT)
        receiver = upload.receiver
        remaining = length
        collected = bytearray()
        chunk = leftover[:remaining]
        try:
            while True:
                if chunk:
                    remaining -= len(chunk)
                    upload.last_activity = time.monotonic()
                    with upload.lock:
                        if self._uploads.get(number) is not upload:
                            return  # iptal edildi ya da süresi doldu
                        if part == 0:
                            collected += chunk
                        else:
                            receiver.consume(chunk)
                if remaining == 0:
                    break
                try:
                    chunk = conn.recv(min(remaining, 256 * 1024))
                except OSError:
                    chunk = b""
                if not chunk:
                    # Telefon isteği yarıda kesti: yükleme bırakılır, geçici dosya silinir.
                    self._drop(number, ("failed", number, "net"))
                    return
            upload.conn = None
            with upload.lock:
                if self._uploads.get(number) is not upload:
                    return
                if part == 0:
                    meta = receiver.receive_meta(bytes(collected))
                    self._emit("started", number, meta)
                    return self._json(conn, {})
                digest = receiver.end_part(final)
            if digest is None:
                self._emit("progress", number, receiver.received)
                return self._json(conn, {})
        except UploadFailure as failure:
            self._drop(number, ("failed", number, failure.code))
            status = {"too-large": "413 Content Too Large", "no-space": "507 Insufficient Storage",
                      "io": "500 Internal Server Error"}.get(failure.code, "400 Bad Request")
            return self._fail(conn, status, failure.code)
        with self._lock:
            self._uploads.pop(number, None)
        completed = Completed(number, receiver.meta, receiver.file_id, digest)
        outcome = "rejected"
        if self.on_completed is not None and not self._stopped:
            try:
                outcome = self.on_completed(completed)
            except Exception:  # noqa: BLE001
                outcome = "rejected"
        if outcome not in ("saved", "duplicate"):
            self.discard(receiver.file_id)
            return self._respond(conn, "404 Not Found")
        self._json(conn, {"result": outcome})

    # MARK: Yanıtlar

    def _respond(self, conn, status: str, content_type: str | None = None, body: bytes = b"",
                 extra: dict[str, str] | None = None) -> None:
        lines = [f"HTTP/1.1 {status}", f"Content-Length: {len(body)}"]
        if content_type:
            lines.append(f"Content-Type: {content_type}")
        for k, v in {**BASE_HEADERS, **(extra or {})}.items():
            lines.append(f"{k}: {v}")
        conn.sendall(("\r\n".join(lines) + "\r\n\r\n").encode("utf-8") + body)

    def _json(self, conn, obj: dict, status: str = "200 OK") -> None:
        self._respond(conn, status, "application/json", json.dumps(obj, sort_keys=True, separators=(",", ":")).encode())

    def _fail(self, conn, status: str, code: str, drain: tuple[bytes, int | None] | None = None) -> None:
        if drain is not None:
            self._drain(conn, *drain)
        self._json(conn, {"error": code}, status)

    @staticmethod
    def _drain(conn, leftover: bytes, length: int | None) -> None:
        """Reddedilen isteğin (sınır içindeki) gövdesini okuyup atar; yoksa tarayıcı yanıtı göremeden bağlantı
        sıfırlanır ve telefon hatayı "ulaşılamadı" sanır."""
        if length is None or length > MAX_PART_LENGTH:
            return
        remaining = length - len(leftover)
        try:
            while remaining > 0:
                data = conn.recv(min(remaining, 256 * 1024))
                if not data:
                    return
                remaining -= len(data)
        except OSError:
            pass


def _is_number(s: str) -> bool:
    return s.isascii() and s.isdigit() and len(s) < 10


class PhoneUploadSession:
    """Bir "Telefondan Ekle" oturumu: anahtar, jeton, sunucu ve gelen dosyaların listesi. Arayüzden bağımsız.

    `items`: yükleme numarası → {"name", "size", "received", "state"}; state: receiving | saved | duplicate |
    failed:<kod> | cancelled. Sunucu iş parçacıklarından güncellenir; okurken `lock` kullanın.
    """

    def __init__(self, vault, folder_id: str | None, folder_name: str, lifetime: float = LIFETIME):
        self.folder_id = folder_id
        self.folder_name = folder_name
        self.expires_at = time.time() + lifetime
        self.key = new_key()
        self.token = base64url(os.urandom(16))
        self.devices: set[str] = set()
        self.items: dict[int, dict] = {}
        self.lock = threading.Lock()
        self.url: str | None = None
        self.accept: Callable[[Completed], str] | None = None
        self.server = PhoneUploadServer(
            self.key, self.token, status_json(folder_name, self.expires_at), self.expires_at,
            lambda n: UploadReceiver.for_vault(n, self.key, vault), vault.delete_file)
        self.server.on_event = self._on_event
        self.server.on_completed = self._on_completed

    def start(self, host: str) -> str:
        port = self.server.start(host)
        self.url = f"http://{host}:{port}/{self.token}/#{base64url(self.key)}"
        return self.url

    def stop(self) -> None:
        self.server.stop()
        with self.lock:
            for item in self.items.values():
                if item["state"] == "receiving":
                    item["state"] = "cancelled"

    @property
    def seconds_left(self) -> int:
        return max(0, int(self.expires_at - time.time()))

    @property
    def saved_count(self) -> int:
        with self.lock:
            return sum(1 for i in self.items.values() if i["state"] == "saved")

    def snapshot(self) -> list[tuple[int, dict]]:
        with self.lock:
            return [(n, dict(i)) for n, i in sorted(self.items.items())]

    def _on_event(self, kind: str, *args) -> None:
        with self.lock:
            if kind == "connected":
                self.devices.add(args[0])
            elif kind == "started":
                number, meta = args
                self.items[number] = {"name": meta.safe_name, "size": meta.size, "received": 0, "state": "receiving"}
            elif args and args[0] in self.items:
                item = self.items[args[0]]
                if kind == "progress":
                    item["received"] = args[1]
                elif kind == "failed":
                    item["state"] = "failed:" + args[1]
                elif kind == "cancelled":
                    item["state"] = "cancelled"

    def _on_completed(self, completed: Completed) -> str:
        accept = self.accept
        outcome = accept(completed) if accept is not None and not self.server.stopped else "rejected"
        with self.lock:
            item = self.items.get(completed.number)
            if item is not None:
                item["received"] = item["size"]
                item["state"] = outcome if outcome in ("saved", "duplicate") else "failed:io"
        return outcome
