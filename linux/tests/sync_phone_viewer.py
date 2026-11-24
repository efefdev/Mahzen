"""Telefon sayfalarını macOS kaynağından Linux sürümüne aktarır.

- Görüntüleyici (`PhoneShareViewer.swift` → `phone_viewer.html`): iki sürümde aynıdır; yalnızca "Mac" geçen
  kullanıcı metinleri "bilgisayar" olur.
- Yükleme sayfası (`PhoneUploadPage.swift` → `phone_upload.html`, "Telefondan Ekle"): birebir aynıdır. Şifreleme
  kodunu görüntüleyiciden alır.

Kullanım (repo kökünden):

    python3 linux/tests/sync_phone_viewer.py

`test_phoneshare` ve `test_phoneupload` aktarılmış sayfaların Swift kaynağıyla aynı kaldığını denetler.
"""

from __future__ import annotations

import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
SWIFT_SOURCE = os.path.join(HERE, "..", "..", "Sources", "Mahzen", "PhoneShare", "PhoneShareViewer.swift")
LINUX_PAGE = os.path.join(HERE, "..", "mahzen", "core", "phone_viewer.html")
SWIFT_UPLOAD_SOURCE = os.path.join(HERE, "..", "..", "Sources", "Mahzen", "PhoneShare", "PhoneUploadPage.swift")
LINUX_UPLOAD_PAGE = os.path.join(HERE, "..", "mahzen", "core", "phone_upload.html")
# Görüntüleyici betiğinde şifreleme kısmının bittiği yer (`PhoneShareViewer.cryptoScript` ile aynı).
CRYPTO_END_MARKER = '\n\n(() => {\n  "use strict";'

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


def _html_template(source: str) -> str:
    match = re.search(r'static let html: String = """\n(.*?)\n    """', source, re.S)
    if not match:
        raise ValueError("html şablonu bulunamadı")
    lines = match.group(1).split("\n")
    return "\n".join(line[4:] if line.startswith("    ") else line.lstrip(" ") for line in lines)


def swift_viewer_html(source: str) -> str:
    """Swift'teki `PhoneShareViewer.html` değerini aynen kurar."""
    template = _html_template(source)
    for name in ("css", "body", "script"):
        template = template.replace(f"\\({name})", _raw_block(source, name))
    return template


def crypto_script(viewer_source: str) -> str:
    """`PhoneShareViewer.cryptoScript`: görüntüleyici betiğinin şifreleme kısmı."""
    script = _raw_block(viewer_source, "script")
    return script[:script.index(CRYPTO_END_MARKER)]


def swift_upload_html(upload_source: str, viewer_source: str) -> str:
    """Swift'teki `PhoneUploadPage.html` değerini aynen kurar (betik = şifreleme kısmı + yükleme betiği)."""
    template = _html_template(upload_source)
    for name in ("css", "body"):
        template = template.replace(f"\\({name})", _raw_block(upload_source, name))
    script = crypto_script(viewer_source) + "\n" + _raw_block(upload_source, "uploadScript")
    return template.replace("\\(script)", script)


def linux_wording(html: str) -> str:
    for old, new in LINUX_WORDING:
        html = html.replace(old, new)
    return html


def linux_page_from_swift() -> str:
    with open(SWIFT_SOURCE, encoding="utf-8") as f:
        return linux_wording(swift_viewer_html(f.read()))


def linux_upload_page_from_swift() -> str:
    with open(SWIFT_UPLOAD_SOURCE, encoding="utf-8") as f:
        upload = f.read()
    with open(SWIFT_SOURCE, encoding="utf-8") as f:
        viewer = f.read()
    return swift_upload_html(upload, viewer)


if __name__ == "__main__":
    for path, page in ((LINUX_PAGE, linux_page_from_swift()), (LINUX_UPLOAD_PAGE, linux_upload_page_from_swift())):
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(page)
        print(f"yazıldı: {os.path.normpath(path)} ({len(page.encode())} bayt)")
