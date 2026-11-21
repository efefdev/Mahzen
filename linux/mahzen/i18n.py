"""Dil desteği: Türkçe kaynak metin anahtardır; etkin dil İngilizceyse `i18n_en` sözlüğündeki karşılığı döner.

Dil sırası: kayıtlı tercih (`ayarlar.json` → "language": "system" | "tr" | "en") → `MAHZEN_LANG` ortam
değişkeni → sistem dili (LC_ALL / LC_MESSAGES / LANG). Sistem dili Türkçeyse Türkçe, başka her dilde İngilizce.
Dil bir kez belirlenir; tercih değişince uygulama yeniden başlatıldığında uygulanır.
"""

from __future__ import annotations

import os

LANGUAGES = ("system", "tr", "en")

_language: str | None = None
_english: dict | None = None


def system_language() -> str:
    for name in ("LC_ALL", "LC_MESSAGES", "LANG"):
        value = os.environ.get(name)
        if value:
            return "tr" if value.lower().startswith("tr") else "en"
    return "en"


def preference() -> str:
    """Kayıtlı tercih; yoksa ya da geçersizse "system"."""
    from .core import paths
    value = paths.load_settings().get("language")
    return value if value in LANGUAGES else "system"


def _resolve() -> str:
    for value in (preference(), (os.environ.get("MAHZEN_LANG") or "").strip().lower()[:2]):
        if value in ("tr", "en"):
            return value
    return system_language()


def language() -> str:
    """Etkin dil: "tr" ya da "en"."""
    global _language
    if _language is None:
        _language = _resolve()
    return _language


def set_language(code: str | None) -> None:
    """Etkin dili değiştirir; None verilirse ilk kullanımda yeniden belirlenir."""
    global _language
    _language = code if code in ("tr", "en") else None


def tr(text: str, _ctx: str | None = None, **values) -> str:
    """Metni etkin dilde döndürür. Değişkenler adlandırılmış `str.format` alanlarıdır: tr("{n} öğe", n=5).
    Sözlükteki karşılık (tekil, çoğul) ikilisiyse `n` değerine göre seçilir. Aynı Türkçe metnin iki ayrı
    İngilizce karşılığı gerekiyorsa `_ctx` verilir; sözlükte "metin|bağlam" anahtarı aranır."""
    global _english
    if language() == "en":
        if _english is None:
            from .i18n_en import ENGLISH
            _english = ENGLISH
        found = _english.get(f"{text}|{_ctx}" if _ctx else text)
        if isinstance(found, tuple):
            found = found[0] if values.get("n") == 1 else found[1]
        if found is not None:
            text = found
    return text.format(**values) if values else text


def decimal(value: float, digits: int = 1) -> str:
    """Ondalık sayı: Türkçede virgül, İngilizcede nokta."""
    text = f"{value:.{digits}f}"
    return text.replace(".", ",") if language() == "tr" else text


def grouped(value: int) -> str:
    """Binlik ayırıcılı tam sayı: Türkçede nokta, İngilizcede virgül."""
    text = f"{value:,}"
    return text.replace(",", ".") if language() == "tr" else text
