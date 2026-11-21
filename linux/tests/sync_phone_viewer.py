"""Telefon görüntüleyici sayfasını macOS kaynağından (`PhoneShareViewer.swift`) Linux sürümüne aktarır.

Sayfa iki sürümde aynıdır; yalnızca "Mac" geçen kullanıcı metinleri "bilgisayar" olur. Kullanım (repo kökünden):

    python3 linux/tests/sync_phone_viewer.py

`test_core.PhoneShareViewerTests` aktarılmış sayfanın Swift kaynağıyla aynı kaldığını denetler.
"""

from __future__ import annotations

import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
SWIFT_SOURCE = os.path.join(HERE, "..", "..", "Sources", "Mahzen", "PhoneShare", "PhoneShareViewer.swift")
LINUX_PAGE = os.path.join(HERE, "..", "mahzen", "core", "phone_viewer.html")

# Sıra önemli: uzun ifadeler önce.
LINUX_WORDING = [
    ("Mac'e ulaşılamadı", "Bilgisayara ulaşılamadı"),
    ("Yeniden görmek için Mac'teki Mahzen'de", "Yeniden görmek için bilgisayardaki Mahzen'de"),
    ("Mac'teki Mahzen paylaşımı kapattı.", "Bilgisayardaki Mahzen paylaşımı kapattı."),
    ("Mac'teki paylaşım kapandı", "Bilgisayardaki paylaşım kapandı"),
    ("QR kodu Mac'teki Mahzen'den", "QR kodu bilgisayardaki Mahzen'den"),
    ("ya da Mac'te durdurulmuş.", "ya da bilgisayarda durdurulmuş."),
    ("Telefon ile Mac aynı", "Telefon ile bilgisayar aynı"),
    ("Couldn't reach the Mac", "Couldn't reach the computer"),
    ("The phone and the Mac must", "The phone and the computer must"),
    ("on the Mac", "on the computer"),
]


def _raw_block(source: str, name: str) -> str:
    """`private static let <name> = #\"\"\"` … `\"\"\"#` arasındaki ham metin (kapanış sütun 0'da: girinti yok)."""
    match = re.search(rf'static let {name} = #"""\n(.*?)\n"""#', source, re.S)
    if not match:
        raise ValueError(f"{name} bulunamadı")
    return match.group(1)


def swift_viewer_html(source: str) -> str:
    """Swift'teki `PhoneShareViewer.html` değerini aynen kurar."""
    match = re.search(r'static let html: String = """\n(.*?)\n    """', source, re.S)
    if not match:
        raise ValueError("html şablonu bulunamadı")
    lines = match.group(1).split("\n")
    template = "\n".join(line[4:] if line.startswith("    ") else line.lstrip(" ") for line in lines)
    for name in ("css", "body", "script"):
        template = template.replace(f"\\({name})", _raw_block(source, name))
    return template


def linux_wording(html: str) -> str:
    for old, new in LINUX_WORDING:
        html = html.replace(old, new)
    return html


def linux_page_from_swift() -> str:
    with open(SWIFT_SOURCE, encoding="utf-8") as f:
        return linux_wording(swift_viewer_html(f.read()))


if __name__ == "__main__":
    page = linux_page_from_swift()
    with open(LINUX_PAGE, "w", encoding="utf-8", newline="") as f:
        f.write(page)
    print(f"yazıldı: {os.path.normpath(LINUX_PAGE)} ({len(page.encode())} bayt)")
