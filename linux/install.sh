#!/bin/sh
# Mahzen Linux kurulumu: bağımlılıkları dağıtımın paket yöneticisiyle kurar, uygulamayı
# ~/.local altına kopyalar (yönetici izni yalnızca bağımlılıklar için gerekir).
#
#   ./install.sh            bağımlılıklar + uygulama
#   ./install.sh --no-deps  yalnızca uygulama (bağımlılıklar zaten kuruluysa)
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
PREFIX="${XDG_DATA_HOME:-$HOME/.local/share}"
APP_DIR="$PREFIX/mahzen-app"
BIN_DIR="$HOME/.local/bin"

install_deps() {
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get install -y python3 python3-gi gir1.2-gtk-4.0 gir1.2-adw-1 python3-cryptography python3-argon2
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y python3 python3-gobject gtk4 libadwaita python3-cryptography python3-argon2-cffi
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm python python-gobject gtk4 libadwaita python-cryptography python-argon2-cffi
    elif command -v zypper >/dev/null 2>&1; then
        sudo zypper install -y python3 python3-gobject python3-gobject-Gdk typelib-1_0-Gtk-4_0 typelib-1_0-Adw-1 \
            python3-cryptography python3-argon2-cffi
    else
        echo "Paket yöneticisi tanınmadı. Şunları kurun: Python 3.10+, PyGObject, GTK 4, libadwaita 1.5+,"
        echo "python cryptography ve argon2-cffi."
    fi
}

check_deps() {
    python3 - <<'PY'
import sys
missing = []
try:
    import gi
    gi.require_version("Gtk", "4.0"); gi.require_version("Adw", "1")
    from gi.repository import Adw
    if (Adw.get_major_version(), Adw.get_minor_version()) < (1, 5):
        missing.append(f"libadwaita 1.5+ (bulunan {Adw.get_major_version()}.{Adw.get_minor_version()})")
except (ImportError, ValueError) as e:
    missing.append(f"GTK4/libadwaita/PyGObject ({e})")
for mod, name in (("cryptography", "python cryptography"), ("argon2", "argon2-cffi")):
    try:
        __import__(mod)
    except ImportError:
        missing.append(name)
if sys.version_info < (3, 10):
    missing.append("Python 3.10+")
if missing:
    print("Eksik bağımlılıklar:\n  - " + "\n  - ".join(missing))
    sys.exit(1)
PY
}

if [ "${1:-}" != "--no-deps" ]; then
    echo "→ Bağımlılıklar kuruluyor (yönetici parolası istenebilir)…"
    install_deps
fi
echo "→ Bağımlılıklar denetleniyor…"
check_deps

echo "→ Uygulama kopyalanıyor: $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR" "$BIN_DIR" "$PREFIX/applications"
cp -R "$DIR/mahzen" "$DIR/data" "$APP_DIR/"
find "$APP_DIR" -name '__pycache__' -type d -prune -exec rm -rf {} +

cat > "$BIN_DIR/mahzen" <<SH
#!/bin/sh
PYTHONPATH="$APP_DIR\${PYTHONPATH:+:\$PYTHONPATH}" exec python3 -m mahzen "\$@"
SH
cat > "$BIN_DIR/mahzen-cli" <<SH
#!/bin/sh
PYTHONPATH="$APP_DIR\${PYTHONPATH:+:\$PYTHONPATH}" exec python3 -m mahzen cli "\$@"
SH
chmod +x "$BIN_DIR/mahzen" "$BIN_DIR/mahzen-cli"

for size in 16x16 32x32 48x48 64x64 128x128 256x256 512x512; do
    mkdir -p "$PREFIX/icons/hicolor/$size/apps"
    cp "$DIR/data/icons/hicolor/$size/apps/dev.efef.Mahzen.png" "$PREFIX/icons/hicolor/$size/apps/"
done
mkdir -p "$PREFIX/icons/hicolor/scalable/apps"
cp "$DIR/data/icons/hicolor/scalable/apps/dev.efef.Mahzen.svg" "$PREFIX/icons/hicolor/scalable/apps/"
sed "s|^Exec=mahzen|Exec=$BIN_DIR/mahzen|" "$DIR/data/dev.efef.Mahzen.desktop" > "$PREFIX/applications/dev.efef.Mahzen.desktop"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$PREFIX/applications" || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t "$PREFIX/icons/hicolor" || true

echo
echo "✓ Mahzen kuruldu. Uygulama menüsünden açın ya da terminalde: mahzen"
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "  Not: $BIN_DIR PATH içinde değil; terminalden çalıştırmak için PATH'e ekleyin." ;;
esac
