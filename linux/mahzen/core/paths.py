"""XDG dizinleri ve uygulama yanındaki taşınabilir kasa konumu."""

from __future__ import annotations

import json
import os
import sys

APP_DIR_NAME = "Mahzen"
DEFAULT_VAULT_NAME = "Mahzen Kasası"


def data_dir() -> str:
    base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return os.path.join(base, APP_DIR_NAME)


def config_path() -> str:
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(base, APP_DIR_NAME, "ayarlar.json")


def portable_vault_paths() -> list[str]:
    """Uygulamanın yanındaki kasa: diskte uygulama ile `Mahzen Kasası` yan yana durur.

    `mahzen.sh` başlatıcısı kendi klasörünü MAHZEN_APP_DIR olarak bildirir; kurulu sürümde bu değişken yoktur.
    Uygulama klasörü bir üst klasördeki kasaya da bakar: SSD'nin kökünde macOS'un `Mahzen.app`'i,
    `Mahzen Kasası` ve Linux'un `Mahzen-Linux` klasörü yan yana durabilir; iki sistem aynı kasayı açar.
    """
    app_dir = os.environ.get("MAHZEN_APP_DIR")
    if not app_dir:
        return []
    app_dir = os.path.abspath(app_dir)
    return [os.path.join(app_dir, DEFAULT_VAULT_NAME), os.path.join(os.path.dirname(app_dir), DEFAULT_VAULT_NAME)]


def default_new_vault_path() -> str:
    """Yeni kasanın önerilen konumu: taşınabilir kullanımda uygulamanın yanı, değilse ev klasörü."""
    app_dir = os.environ.get("MAHZEN_APP_DIR")
    if app_dir:
        return os.path.join(os.path.dirname(os.path.abspath(app_dir)), DEFAULT_VAULT_NAME)
    return os.path.join(os.path.expanduser("~"), DEFAULT_VAULT_NAME)


def load_settings() -> dict:
    try:
        with open(config_path(), encoding="utf-8") as f:
            data = json.load(f)
            return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save_settings(settings: dict) -> None:
    path = config_path()
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(settings, f, ensure_ascii=False, indent=2)
        os.replace(tmp, path)
    except OSError as e:
        print(f"Ayarlar kaydedilemedi: {e}", file=sys.stderr)
