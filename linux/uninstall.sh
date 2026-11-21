#!/bin/sh
# Mahzen'i kaldırır. Kasalara ve anahtar dosyalarına (~/.local/share/Mahzen/Anahtarlar) dokunmaz.
set -eu
# Mesaj dili: MAHZEN_LANG (tr | en), yoksa sistem dili; Türkçe değilse İngilizce.
case "${MAHZEN_LANG:-}" in
    tr*|en*) UI_LANG="$MAHZEN_LANG" ;;
    *) UI_LANG="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" ;;
esac
case "$UI_LANG" in tr*|TR*) UI_LANG=tr ;; *) UI_LANG=en ;; esac
msg() { if [ "$UI_LANG" = tr ]; then printf '%s\n' "$1"; else printf '%s\n' "$2"; fi; }
PREFIX="${XDG_DATA_HOME:-$HOME/.local/share}"
rm -rf "$PREFIX/mahzen-app"
rm -f "$HOME/.local/bin/mahzen" "$HOME/.local/bin/mahzen-cli" "$PREFIX/applications/dev.efef.Mahzen.desktop"
for size in 16x16 32x32 48x48 64x64 128x128 256x256 512x512; do
    rm -f "$PREFIX/icons/hicolor/$size/apps/dev.efef.Mahzen.png"
done
rm -f "$PREFIX/icons/hicolor/scalable/apps/dev.efef.Mahzen.svg"
msg "✓ Mahzen kaldırıldı. Kasalarınız ve anahtar dosyalarınız yerinde duruyor." \
    "✓ Mahzen was removed. Your vaults and keyfiles are still in place."
