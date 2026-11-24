"""Büyük dosyalar için parçalı AES-256-GCM akışı (macOS'taki `BlobCrypto.swift` ile aynı biçim).

Biçim: ``"MHZ1"`` + parça boyutu (UInt32, big-endian), ardından her parça için ``şifreli metin + 16 bayt etiket``.
Her dosyanın anahtarı kendine özeldir; nonce = parça sırası (8 bayt) + son parça bayrağı (4 bayt).
Böylece parçaların yer değiştirmesi, kesilmesi veya eklenmesi doğrulamada yakalanır.
"""

from __future__ import annotations

import hashlib
import os
import struct
import threading
import uuid
from typing import BinaryIO, Callable

from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from ..i18n import tr
from .errors import Corrupted

MAGIC = b"MHZ1"
DEFAULT_CHUNK_SIZE = 1 << 20
TAG_SIZE = 16
HEADER_SIZE = 8

Progress = Callable[[int], None] | None


def header(chunk_size: int) -> bytes:
    return MAGIC + struct.pack(">I", chunk_size)


def nonce(index: int, is_final: bool) -> bytes:
    return struct.pack(">QI", index, 1 if is_final else 0)


def _parse_header(hdr: bytes) -> int:
    if len(hdr) != HEADER_SIZE or hdr[:4] != MAGIC:
        raise Corrupted(tr("dosya başlığı geçersiz"))
    chunk_size = struct.unpack(">I", hdr[4:])[0]
    if not 4096 <= chunk_size <= (64 << 20):
        raise Corrupted(tr("parça boyutu geçersiz"))
    return chunk_size


def read_fully(f: BinaryIO, count: int) -> bytes:
    buf = bytearray()
    while len(buf) < count:
        chunk = f.read(count - len(buf))
        if not chunk:
            break
        buf += chunk
    return bytes(buf)


def encrypt_stream(read: Callable[[int], bytes], write: Callable[[bytes], None], key: bytes,
                   chunk_size: int = DEFAULT_CHUNK_SIZE, progress: Progress = None) -> None:
    """`read(n)` en fazla n bayt döndürür; yalnızca dosya sonunda n'den az döndürmelidir."""
    hdr = header(chunk_size)
    write(hdr)
    aes = AESGCM(key)
    index = 0
    current = read(chunk_size)
    while True:
        nxt = read(chunk_size) if len(current) == chunk_size else b""
        is_final = not nxt
        write(aes.encrypt(nonce(index, is_final), current, hdr))
        if progress:
            progress(len(current))
        if is_final:
            return
        current = nxt
        index += 1


def decrypt_stream(read: Callable[[int], bytes], write: Callable[[bytes], None], key: bytes,
                   progress: Progress = None) -> None:
    hdr = read(HEADER_SIZE)
    chunk_size = _parse_header(hdr)
    full = chunk_size + TAG_SIZE
    aes = AESGCM(key)
    index = 0
    current = read(full)
    while True:
        if len(current) < TAG_SIZE:
            raise Corrupted(tr("dosya kesik"))
        nxt = read(full) if len(current) == full else b""
        is_final = not nxt
        try:
            plain = aes.decrypt(nonce(index, is_final), current, hdr)
        except InvalidTag:
            raise Corrupted(tr("içerik doğrulanamadı (bozulmuş, değiştirilmiş veya yanlış anahtar)")) from None
        write(plain)
        if progress:
            progress(len(plain))
        if is_final:
            return
        current = nxt
        index += 1


def write_atomically(destination: str, body: Callable[[BinaryIO], None]) -> None:
    """Önce gizli bir geçici dosyaya yazar, başarılıysa yerine taşır; yarım dosya bırakmaz."""
    directory, name = os.path.split(destination)
    tmp = os.path.join(directory, f".{name}.{str(uuid.uuid4()).upper()}.tmp")
    try:
        with open(tmp, "xb") as out:
            body(out)
            out.flush()
            os.fsync(out.fileno())
        os.replace(tmp, destination)
    except BaseException:
        try:
            os.remove(tmp)
        except OSError:
            pass
        raise


class BlobWriter:
    """Parça parça gelen düz içeriği doğrudan şifreli dosya biçimine yazar ("Telefondan Ekle").

    macOS'taki `BlobWriter.swift` ile aynı: içerik bellekte en fazla bir parça kadar tutulur, diske yalnızca şifreli
    bayt yazılır. Önce gizli bir geçici dosyaya yazılır; `finish()` başarılı olunca yerine taşınır. `cancel()`
    geçici dosyayı siler. Çıktı, aynı içerikle `encrypt_stream` çıktısıyla bayt bayt aynıdır.
    """

    def __init__(self, destination: str, key: bytes, chunk_size: int = DEFAULT_CHUNK_SIZE):
        directory, name = os.path.split(destination)
        os.makedirs(directory, exist_ok=True)
        self.destination = destination
        self.temporary = os.path.join(directory, f".{name}.{str(uuid.uuid4()).upper()}.tmp")
        self.plain_size = 0
        self._aes = AESGCM(key)
        self._chunk_size = chunk_size
        self._header = header(chunk_size)
        self._buffer = bytearray()
        self._index = 0
        self._hasher = hashlib.sha256()
        self._closed = False
        self._file = open(self.temporary, "xb")
        try:
            self._file.write(self._header)
        except BaseException:
            self.cancel()
            raise

    def append(self, data: bytes) -> None:
        """Düz içeriğin bir sonraki bölümü. Dolan parçalar hemen yazılır; son parça `finish()` ile yazılır."""
        if self._closed:
            raise ValueError("BlobWriter kapandı")
        self._hasher.update(data)
        self.plain_size += len(data)
        self._buffer += data
        offset = 0
        while len(self._buffer) - offset > self._chunk_size:
            self._seal(bytes(self._buffer[offset:offset + self._chunk_size]), False)
            offset += self._chunk_size
        if offset:
            del self._buffer[:offset]

    def finish(self) -> str:
        """Son parçayı yazar, diske işler ve yerine taşır; düz içeriğin SHA-256 özetini (onaltılık) döndürür."""
        if self._closed:
            raise ValueError("BlobWriter kapandı")
        try:
            self._seal(bytes(self._buffer), True)
            self._buffer = bytearray()
            self._file.flush()
            os.fsync(self._file.fileno())
            self._file.close()
            self._closed = True
            os.replace(self.temporary, self.destination)
        except BaseException:
            self.cancel()
            raise
        return self._hasher.hexdigest()

    def cancel(self) -> None:
        """Yazmayı bırakır ve geçici dosyayı siler. Birden çok kez çağrılabilir."""
        if not self._closed:
            self._closed = True
            try:
                self._file.close()
            except OSError:
                pass
        self._buffer = bytearray()
        try:
            os.remove(self.temporary)
        except OSError:
            pass

    def _seal(self, plain: bytes, is_final: bool) -> None:
        self._file.write(self._aes.encrypt(nonce(self._index, is_final), plain, self._header))
        self._index += 1


def encrypt_file(source: str, destination: str, key: bytes, progress: Progress = None) -> str:
    """Şifrelerken düz içeriğin SHA-256 özetini (onaltılık) de hesaplar (mükerrer dosya tespiti için)."""
    hasher = hashlib.sha256()
    with open(source, "rb") as src:
        def read(n: int) -> bytes:
            chunk = read_fully(src, n)
            hasher.update(chunk)
            return chunk
        write_atomically(destination, lambda out: encrypt_stream(read, out.write, key, progress=progress))
    return hasher.hexdigest()


def decrypt_file(source: str, destination: str, key: bytes, progress: Progress = None) -> None:
    with open(source, "rb") as src:
        write_atomically(destination, lambda out: decrypt_stream(lambda n: read_fully(src, n), out.write, key, progress))


def encrypt_bytes(data: bytes, key: bytes, chunk_size: int = DEFAULT_CHUNK_SIZE) -> bytes:
    pos = 0
    out = bytearray()

    def read(n: int) -> bytes:
        nonlocal pos
        chunk = data[pos:pos + n]
        pos += len(chunk)
        return chunk

    encrypt_stream(read, out.extend, key, chunk_size)
    return bytes(out)


def decrypt_bytes(data: bytes, key: bytes) -> bytes:
    pos = 0
    out = bytearray()

    def read(n: int) -> bytes:
        nonlocal pos
        chunk = data[pos:pos + n]
        pos += len(chunk)
        return chunk

    decrypt_stream(read, out.extend, key)
    return bytes(out)


def decrypt_file_to_bytes(source: str, key: bytes) -> bytes:
    out = bytearray()
    with open(source, "rb") as src:
        decrypt_stream(lambda n: read_fully(src, n), out.extend, key)
    return bytes(out)


class BlobReader:
    """Şifreli bir dosyanın istenen bayt aralığını, yalnızca ilgili parçaları çözerek okur.
    Düz içerik diske hiç yazılmaz."""

    def __init__(self, path: str, key: bytes):
        self._f = open(path, "rb")
        self._aes = AESGCM(key)
        self._lock = threading.Lock()
        self._cached_index = -1
        self._cached = b""
        try:
            self._header = read_fully(self._f, HEADER_SIZE)
            self.chunk_size = _parse_header(self._header)
            self._blob_size = self._f.seek(0, os.SEEK_END)
            body = self._blob_size - HEADER_SIZE
            full = self.chunk_size + TAG_SIZE
            if body < TAG_SIZE:
                raise Corrupted(tr("dosya kesik"))
            self.chunk_count = (body + full - 1) // full
            self.plain_size = body - self.chunk_count * TAG_SIZE
            # Boyut kimliği doğrulanmamış dosya uzunluğundan geliyor: son parçayı baştan "son" olarak doğrula.
            self._decrypt_chunk(self.chunk_count - 1)
        except BaseException:
            self._f.close()
            raise

    def close(self) -> None:
        self._f.close()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()

    def read(self, offset: int, length: int) -> bytes:
        with self._lock:
            if offset < 0 or offset >= self.plain_size or length <= 0:
                return b""
            end = min(offset + length, self.plain_size)
            out = bytearray()
            position = offset
            while position < end:
                index = position // self.chunk_size
                chunk = self._decrypt_chunk(index)
                start = position - index * self.chunk_size
                take = min(len(chunk) - start, end - position)
                if take <= 0:
                    raise Corrupted(tr("beklenmeyen dosya sonu"))
                out += chunk[start:start + take]
                position += take
            return bytes(out)

    def _decrypt_chunk(self, index: int) -> bytes:
        if index == self._cached_index:
            return self._cached
        full = self.chunk_size + TAG_SIZE
        start = HEADER_SIZE + index * full
        length = min(full, self._blob_size - start)
        self._f.seek(start)
        raw = read_fully(self._f, length)
        if len(raw) != length or length < TAG_SIZE:
            raise Corrupted(tr("dosya kesik"))
        try:
            plain = self._aes.decrypt(nonce(index, index == self.chunk_count - 1), raw, self._header)
        except InvalidTag:
            raise Corrupted(tr("içerik doğrulanamadı")) from None
        self._cached_index, self._cached = index, plain
        return plain
