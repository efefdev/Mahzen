"""`python3 -m mahzen` → arayüz; `python3 -m mahzen cli …` → komut satırı."""

import os
import sys


def _choose_renderer() -> None:
    """Sanal makinelerin ekran kartı sürücüleri (virgl, venus…) GTK 4'ün Vulkan/OpenGL çizicisinde
    çökebiliyor ve masaüstünü de etkileyebiliyor. Kullanıcı bir seçim yapmadıysa sanal makinede
    yazılım çizicisini (cairo) kullan. MAHZEN_GPU=1 ile ekran kartı zorlanabilir."""
    if "GSK_RENDERER" in os.environ or os.environ.get("MAHZEN_GPU") == "1":
        return
    from .core.virt import in_virtual_machine
    if in_virtual_machine():
        os.environ["GSK_RENDERER"] = "cairo"


def run() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "cli":
        from .cli import main as cli_main
        return cli_main(sys.argv[2:])
    _choose_renderer()
    try:
        from .ui.app import main
    except (ImportError, ValueError) as e:
        from .i18n import tr
        print(tr("Arayüz başlatılamadı: {error}\n"
                 "GTK4, libadwaita (1.5+) ve PyGObject kurulu olmalı. Kurulum için: linux/install.sh", error=e),
              file=sys.stderr)
        return 1
    return main(sys.argv)


if __name__ == "__main__":
    sys.exit(run())
