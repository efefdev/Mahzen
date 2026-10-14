"""`python3 -m mahzen` → arayüz; `python3 -m mahzen cli …` → komut satırı."""

import sys


def run() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "cli":
        from .cli import main as cli_main
        return cli_main(sys.argv[2:])
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
