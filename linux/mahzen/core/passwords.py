"""Parola üretici ve güç ölçer (macOS'taki `Passwords.swift` ile aynı kurallar)."""

from __future__ import annotations

import math
import secrets

UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
LOWER = "abcdefghijklmnopqrstuvwxyz"
DIGITS = "0123456789"
SYMBOLS = "!@#$%^&*()-_=+[]{};:,.<>?/~"
AMBIGUOUS = set("O0oIl1|`'\"")

STRENGTH_LABELS = ["Çok zayıf", "Zayıf", "Orta", "Güçlü", "Çok güçlü"]
COMMON = ["password", "parola", "sifre", "şifre", "123456", "qwerty", "asdf", "abc123", "111111",
          "admin", "letmein", "iloveyou"]


def generate(options: dict) -> str:
    """Seçilen her karakter sınıfından en az bir karakter içeren, CSPRNG ile üretilmiş parola."""
    classes = []
    if options.get("uppercase", True):
        classes.append(UPPER)
    if options.get("lowercase", True):
        classes.append(LOWER)
    if options.get("digits", True):
        classes.append(DIGITS)
    if options.get("symbols", True):
        classes.append(SYMBOLS)
    if not classes:
        classes = [LOWER]
    if options.get("avoidAmbiguous", True):
        classes = ["".join(c for c in cls if c not in AMBIGUOUS) for cls in classes]
    length = max(int(options.get("length", 20)), len(classes))
    chars = [secrets.choice(cls) for cls in classes]
    pool = "".join(classes)
    while len(chars) < length:
        chars.append(secrets.choice(pool))
    # Fisher–Yates, CSPRNG ile
    for i in range(len(chars) - 1, 0, -1):
        j = secrets.randbelow(i + 1)
        chars[i], chars[j] = chars[j], chars[i]
    return "".join(chars)


def strength(password: str) -> tuple[int, float]:
    """(puan 0…4, bit)"""
    if not password:
        return 0, 0.0
    pool = 0
    if any(c.isascii() and c.islower() for c in password):
        pool += 26
    if any(c.isascii() and c.isupper() for c in password):
        pool += 26
    if any(c.isdigit() for c in password):
        pool += 10
    if any(c.isascii() and not c.isalpha() and not c.isdigit() for c in password):
        pool += 33
    if any(not c.isascii() for c in password):
        pool += 60
    # Tekrarlayan karakterler etkin uzunluğu düşürür ("aaaaaaaaaa" uzun ama zayıf).
    effective = min(len(password), len(set(password)) * 2)
    bits = effective * math.log2(max(pool, 2))
    lowered = password.lower()
    if any(c in lowered for c in COMMON):
        bits = min(bits, 30)
    if bits < 36:
        score = 0
    elif bits < 50:
        score = 1
    elif bits < 64:
        score = 2
    elif bits < 90:
        score = 3
    else:
        score = 4
    return score, bits
