#!/bin/sh
# Mahzen'i kaldırır. Kasalara ve anahtar dosyalarına (~/.local/share/Mahzen/Anahtarlar) dokunmaz.
set -eu
PREFIX="${XDG_DATA_HOME:-$HOME/.local/share}"
rm -rf "$PREFIX/mahzen-app"
rm -f "$HOME/.local/bin/mahzen" "$HOME/.local/bin/mahzen-cli" "$PREFIX/applications/dev.efef.Mahzen.desktop"
for size in 16x16 32x32 48x48 64x64 128x128 256x256 512x512; do
    rm -f "$PREFIX/icons/hicolor/$size/apps/dev.efef.Mahzen.png"
done
rm -f "$PREFIX/icons/hicolor/scalable/apps/dev.efef.Mahzen.svg"
echo "✓ Mahzen kaldırıldı. Kasalarınız ve anahtar dosyalarınız yerinde duruyor."
