#!/bin/sh
# Mahzen'i kurmadan, bu klasörden çalıştırır (ör. SSD'den taşınabilir kullanım).
# Kasa, bu klasörün içinde ya da bir üst klasörde "Mahzen Kasası" adıyla aranır.
# Komut satırı için: ./mahzen.sh cli --help
DIR="$(cd "$(dirname "$0")" && pwd)"
export MAHZEN_APP_DIR="$DIR"
export PYTHONPATH="$DIR${PYTHONPATH:+:$PYTHONPATH}"
exec python3 -m mahzen "$@"
