"""`python3 -m mahzen` → arayüz; `python3 -m mahzen cli …` → komut satırı."""

import os
import subprocess
import sys


def _in_virtual_machine() -> bool:
    """Sanal makinede mi çalışıyoruz? (UTM/QEMU, VMware, VirtualBox, Parallels, Apple Virtualization)"""
    try:
        return subprocess.run(["systemd-detect-virt", "--vm", "--quiet"], timeout=3).returncode == 0
    except (OSError, subprocess.SubprocessError):
        pass
    try:
        with open("/sys/class/dmi/id/product_name", encoding="utf-8", errors="ignore") as f:
            product = f.read().lower()
        return any(k in product for k in ("qemu", "kvm", "vmware", "virtualbox", "parallels", "virtual"))
    except OSError:
        return False


def _choose_renderer() -> None:
    """Sanal makinelerin ekran kartı sürücüleri (virgl, venus…) GTK 4'ün Vulkan/OpenGL çizicisinde
    çökebiliyor ve masaüstünü de etkileyebiliyor. Kullanıcı bir seçim yapmadıysa sanal makinede
    yazılım çizicisini (cairo) kullan. MAHZEN_GPU=1 ile ekran kartı zorlanabilir."""
    if "GSK_RENDERER" in os.environ or os.environ.get("MAHZEN_GPU") == "1":
        return
    if _in_virtual_machine():
        os.environ["GSK_RENDERER"] = "cairo"


def run() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "cli":
        from .cli import main as cli_main
        return cli_main(sys.argv[2:])
    _choose_renderer()
    try:
        from .ui.app import main
    except (ImportError, ValueError) as e:
        print(f"Arayüz başlatılamadı: {e}\n"
              "GTK4, libadwaita (1.5+) ve PyGObject kurulu olmalı. Kurulum için: linux/install.sh",
              file=sys.stderr)
        return 1
    return main(sys.argv)


if __name__ == "__main__":
    sys.exit(run())
