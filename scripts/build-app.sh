#!/bin/bash
# Mahzen.app paketini dist/ altına üretir (Apple Silicon + Intel, ad-hoc imzalı).
set -euo pipefail
cd "$(dirname "$0")/.."

ICON=Resources/AppIcon.icns
if [ ! -f "$ICON" ]; then
    echo "→ Simge çiziliyor"
    tmp=$(mktemp -d)
    swift scripts/make-icon.swift "$tmp/icon.png"
    set_dir="$tmp/AppIcon.iconset"
    mkdir "$set_dir"
    for s in 16 32 128 256 512; do
        sips -z $s $s "$tmp/icon.png" --out "$set_dir/icon_${s}x${s}.png" >/dev/null
        sips -z $((s * 2)) $((s * 2)) "$tmp/icon.png" --out "$set_dir/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$set_dir" -o "$ICON"
    rm -rf "$tmp"
fi

echo "→ Derleniyor (release, universal)"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Mahzen"

APP=dist/Mahzen.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Mahzen"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

xattr -cr "$APP"
echo "→ İmzalanıyor (ad-hoc)"
codesign --force --sign - --options runtime "$APP"
codesign --verify --strict "$APP"
echo "✓ $APP hazır"
