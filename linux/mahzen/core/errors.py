"""Kasa hataları. Mesajlar macOS sürümüyle aynıdır."""

from ..i18n import tr


class VaultError(Exception):
    pass


class WrongPassword(VaultError):
    def __init__(self):
        super().__init__(tr("Parola yanlış."))


class Corrupted(VaultError):
    def __init__(self, detail: str):
        super().__init__(tr("Kasa verisi doğrulanamadı: {detail}", detail=detail))


class NotAVault(VaultError):
    def __init__(self):
        super().__init__(tr("Bu klasör bir Mahzen kasası değil."))


class AlreadyExists(VaultError):
    def __init__(self):
        super().__init__(tr("Bu konumda zaten bir kasa var."))


class UnsupportedVersion(VaultError):
    def __init__(self, version: int):
        super().__init__(tr("Bu kasa daha yeni bir Mahzen sürümüyle oluşturulmuş (biçim {version}).",
                            version=version))


class KDFFailed(VaultError):
    def __init__(self):
        super().__init__(tr("Anahtar türetilemedi."))


class PasswordTooShort(VaultError):
    def __init__(self, minimum: int):
        super().__init__(tr("Parola en az {minimum} karakter olmalı.", minimum=minimum))


class Cancelled(Exception):
    """Kullanıcı uzun süren bir işlemi durdurdu."""
