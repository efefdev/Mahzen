"""Kasanın kullandığı ilkel şifreleme işlemleri (macOS'taki `Crypto.swift` ile birebir aynı).

- Paroladan anahtar: Argon2id (bellek yoğun; eski kasalarda PBKDF2-HMAC-SHA512), tuz 32 bayt.
- Ana anahtar: rastgele 256 bit; paroladan türetilen anahtarla AES-256-GCM ile sarılır.
- Alt anahtarlar: ana anahtardan HKDF-SHA256 ile (dizin, her dosya ve her küçük resim için ayrı).
"""

from __future__ import annotations

import hashlib
import os
import unicodedata
import uuid
from dataclasses import dataclass

from argon2.low_level import Type, hash_secret_raw
from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

from .errors import Corrupted, KDFFailed

PBKDF2 = "PBKDF2-HMAC-SHA512"
ARGON2ID = "Argon2id"


@dataclass(frozen=True)
class KDFSettings:
    """Yeni başlıklar için anahtar türetme ayarı."""

    algorithm: str = ARGON2ID
    iterations: int = 3
    memory_kib: int | None = 1024 * 1024
    parallelism: int | None = 4

    def params(self, salt: bytes) -> dict:
        p = {"algorithm": self.algorithm, "iterations": self.iterations, "salt": salt}
        if self.algorithm == ARGON2ID:
            p["memoryKiB"] = self.memory_kib
            p["parallelism"] = self.parallelism
        return p


# Varsayılan: Argon2id, 1 GB bellek, 3 geçiş, 4 iş parçacığı (macOS sürümüyle aynı).
RECOMMENDED = KDFSettings()


def password_bytes(password: str) -> bytes:
    """Parolayı Unicode NFC biçimine getirir; aynı parola farklı klavyelerde aynı baytlara dönüşür."""
    return unicodedata.normalize("NFC", password).encode("utf-8")


def derive_key(password: str, params: dict) -> bytes:
    algorithm = params.get("algorithm")
    salt = params["salt"]
    if algorithm == PBKDF2:
        try:
            return hashlib.pbkdf2_hmac("sha512", password_bytes(password), salt, int(params["iterations"]), 32)
        except Exception as e:
            raise KDFFailed() from e
    if algorithm == ARGON2ID:
        memory, parallelism = params.get("memoryKiB"), params.get("parallelism")
        if memory is None or parallelism is None:
            raise Corrupted("Argon2id ayarları eksik")
        return argon2id(password, salt, int(params["iterations"]), int(memory), int(parallelism))
    raise Corrupted(f"bilinmeyen anahtar türetme yöntemi: {algorithm}")


def argon2id(password: str, salt: bytes, time: int, memory_kib: int, parallelism: int) -> bytes:
    try:
        return hash_secret_raw(
            password_bytes(password), salt,
            time_cost=time, memory_cost=memory_kib, parallelism=parallelism,
            hash_len=32, type=Type.ID, version=19,
        )
    except Exception as e:
        raise KDFFailed() from e


def random_bytes(count: int) -> bytes:
    return os.urandom(count)


def hkdf(key_material: bytes, salt: bytes, info: bytes) -> bytes:
    return HKDF(algorithm=hashes.SHA256(), length=32, salt=salt, info=info).derive(key_material)


def subkey(master: bytes, vault_id: uuid.UUID, info: str) -> bytes:
    return hkdf(master, vault_id.bytes, info.encode("utf-8"))


def seal(data: bytes, key: bytes, aad: bytes) -> bytes:
    """AES-256-GCM, CryptoKit'in `combined` biçiminde: 12 bayt nonce + şifreli metin + 16 bayt etiket."""
    nonce = os.urandom(12)
    return nonce + AESGCM(key).encrypt(nonce, data, aad)


def open_sealed(data: bytes, key: bytes, aad: bytes) -> bytes:
    """Doğrulanamazsa `InvalidTag` fırlatır."""
    if len(data) < 28:
        raise InvalidTag()
    return AESGCM(key).decrypt(data[:12], data[12:], aad)


def uuid_string(u: uuid.UUID) -> str:
    """Swift'in `UUID.uuidString` biçimi (büyük harf); anahtar türetme bilgilerinde kullanılır."""
    return str(u).upper()
