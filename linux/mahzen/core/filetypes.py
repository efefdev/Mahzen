"""Dosya türleri: uzantıdan macOS UTI'si ve önizleme türü (arayüzden bağımsız)."""

from __future__ import annotations

import os

# Uzantı → (macOS UTI, tür). macOS sürümü önizleme türünü `contentType` (UTI) alanından anlar;
# bu yüzden Linux'ta eklenen dosyalara da aynı tanımlayıcılar yazılır.
_TYPES = {
    "jpg": ("public.jpeg", "image"), "jpeg": ("public.jpeg", "image"), "png": ("public.png", "image"),
    "gif": ("com.compuserve.gif", "image"), "webp": ("org.webmproject.webp", "image"),
    "heic": ("public.heic", "image"), "heif": ("public.heif", "image"), "bmp": ("com.microsoft.bmp", "image"),
    "tif": ("public.tiff", "image"), "tiff": ("public.tiff", "image"), "svg": ("public.svg-image", "image"),
    "ico": ("com.microsoft.ico", "image"),
    "pdf": ("com.adobe.pdf", "pdf"),
    "txt": ("public.plain-text", "text"), "md": ("net.daringfireball.markdown", "text"),
    "csv": ("public.comma-separated-values-text", "text"), "json": ("public.json", "text"),
    "xml": ("public.xml", "text"), "log": ("com.apple.log", "text"), "yaml": ("public.yaml", "text"),
    "yml": ("public.yaml", "text"), "py": ("public.python-script", "text"), "sh": ("public.shell-script", "text"),
    "swift": ("public.swift-source", "text"), "js": ("com.netscape.javascript-source", "text"),
    "html": ("public.html", "text"), "htm": ("public.html", "text"), "css": ("public.css", "text"),
    "c": ("public.c-source", "text"), "h": ("public.c-header", "text"), "rtf": ("public.rtf", "document"),
    "mp4": ("public.mpeg-4", "video"), "m4v": ("com.apple.m4v-video", "video"),
    "mov": ("com.apple.quicktime-movie", "video"), "mkv": ("org.matroska.mkv", "video"),
    "webm": ("org.webmproject.webm", "video"), "avi": ("public.avi", "video"),
    "mp3": ("public.mp3", "audio"), "m4a": ("com.apple.m4a-audio", "audio"), "wav": ("com.microsoft.waveform-audio", "audio"),
    "aac": ("public.aac-audio", "audio"), "flac": ("org.xiph.flac", "audio"), "ogg": ("org.xiph.ogg", "audio"),
    "zip": ("public.zip-archive", "archive"), "gz": ("org.gnu.gnu-zip-archive", "archive"),
    "tar": ("public.tar-archive", "archive"), "7z": ("org.7-zip.7-zip-archive", "archive"),
    "rar": ("com.rarlab.rar-archive", "archive"),
    "doc": ("com.microsoft.word.doc", "document"), "docx": ("org.openxmlformats.wordprocessingml.document", "document"),
    "xls": ("com.microsoft.excel.xls", "sheet"), "xlsx": ("org.openxmlformats.spreadsheetml.sheet", "sheet"),
    "ppt": ("com.microsoft.powerpoint.ppt", "slides"),
    "pptx": ("org.openxmlformats.presentationml.presentation", "slides"),
    "odt": ("org.oasis-open.opendocument.text", "document"),
    "ods": ("org.oasis-open.opendocument.spreadsheet", "sheet"),
    "odp": ("org.oasis-open.opendocument.presentation", "slides"),
    "pages": ("com.apple.iwork.pages.sffpages", "document"), "numbers": ("com.apple.iwork.numbers.sffnumbers", "sheet"),
    "key": ("com.apple.iwork.keynote.sffkey", "slides"),
}

# macOS'ta eklenen dosyalarda yalnızca UTI vardır; türünü ondan da çıkar.
_UTI_KIND = {uti: kind for uti, kind in _TYPES.values()}
_UTI_KIND.update({"public.text": "text", "public.utf8-plain-text": "text", "public.source-code": "text",
                  "public.movie": "video", "public.audio": "audio", "public.image": "image"})

ICONS = {
    "folder": "folder-symbolic", "image": "image-x-generic-symbolic", "pdf": "x-office-document-symbolic",
    "text": "text-x-generic-symbolic", "video": "video-x-generic-symbolic", "audio": "audio-x-generic-symbolic",
    "archive": "package-x-generic-symbolic", "document": "x-office-document-symbolic",
    "sheet": "x-office-spreadsheet-symbolic", "slides": "x-office-presentation-symbolic",
    "other": "text-x-generic-symbolic",
}

IMAGE_PREVIEWABLE = {"jpg", "jpeg", "png", "gif", "webp", "bmp", "tif", "tiff", "svg", "ico", "heic", "heif"}


def extension(name: str) -> str:
    return os.path.splitext(name)[1].lstrip(".").lower()


def content_type_for(name: str) -> str | None:
    t = _TYPES.get(extension(name))
    return t[0] if t else None


def kind_of(record: dict) -> str:
    t = _TYPES.get(extension(record.get("name", "")))
    if t:
        return t[1]
    return _UTI_KIND.get(record.get("contentType") or "", "other")


def icon_for(record: dict) -> str:
    return ICONS.get(kind_of(record), ICONS["other"])
