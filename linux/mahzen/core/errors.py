"""Kasa hataları. Mesajlar macOS sürümüyle aynıdır."""


class VaultError(Exception):
    pass


class WrongPassword(VaultError):
    def __init__(self):
        super().__init__("Parola yanlış.")


class Corrupted(VaultError):
    def __init__(self, detail: str):
        super().__init__(f"Kasa verisi doğrulanamadı: {detail}")


class NotAVault(VaultError):
    def __init__(self):
        super().__init__("Bu klasör bir Mahzen kasası değil.")


class AlreadyExists(VaultError):
    def __init__(self):
        super().__init__("Bu konumda zaten bir kasa var.")


class UnsupportedVersion(VaultError):
    def __init__(self, version: int):
        super().__init__(f"Bu kasa daha yeni bir Mahzen sürümüyle oluşturulmuş (biçim {version}).")


class KDFFailed(VaultError):
    def __init__(self):
        super().__init__("Anahtar türetilemedi.")


class PasswordTooShort(VaultError):
    def __init__(self, minimum: int):
        super().__init__(f"Parola en az {minimum} karakter olmalı.")


class Cancelled(Exception):
    """Kullanıcı uzun süren bir işlemi durdurdu."""
