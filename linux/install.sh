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

# Mesaj dili: MAHZEN_LANG (tr | en), yoksa sistem dili; Türkçe değilse İngilizce.
case "${MAHZEN_LANG:-}" in
    tr*|en*) UI_LANG="$MAHZEN_LANG" ;;
    *) UI_LANG="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" ;;
esac
case "$UI_LANG" in tr*|TR*) UI_LANG=tr ;; *) UI_LANG=en ;; esac
msg() { if [ "$UI_LANG" = tr ]; then printf '%s\n' "$1"; else printf '%s\n' "$2"; fi; }

install_deps() {
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get install -y python3 python3-gi gir1.2-gtk-4.0 gir1.2-adw-1 python3-gi-cairo python3-cryptography python3-argon2
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y python3 python3-gobject gtk4 libadwaita python3-cryptography python3-argon2-cffi
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm python python-gobject python-cairo gtk4 libadwaita python-cryptography python-argon2-cffi
    elif command -v zypper >/dev/null 2>&1; then
        sudo zypper install -y python3 python3-gobject python3-gobject-Gdk python3-gobject-cairo typelib-1_0-Gtk-4_0 typelib-1_0-Adw-1 \
            python3-cryptography python3-argon2-cffi
    else
        msg "Paket yöneticisi tanınmadı. Şunları kurun: Python 3.10+, PyGObject, GTK 4, libadwaita 1.5+," \
            "Package manager not recognized. Install these: Python 3.10+, PyGObject, GTK 4, libadwaita 1.5+,"
        msg "python cryptography ve argon2-cffi." "python cryptography and argon2-cffi."
    fi
}

check_deps() {
    UI_LANG="$UI_LANG" python3 - <<'PY'
import os
import sys
turkish = os.environ.get("UI_LANG") == "tr"
missing = []
try:
    import gi
    gi.require_version("Gtk", "4.0"); gi.require_version("Adw", "1")
    from gi.repository import Adw
    if (Adw.get_major_version(), Adw.get_minor_version()) < (1, 5):
        found = f"{Adw.get_major_version()}.{Adw.get_minor_version()}"
        missing.append(f"libadwaita 1.5+ (bulunan {found})" if turkish else f"libadwaita 1.5+ (found {found})")
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
    print(("Eksik bağımlılıklar:" if turkish else "Missing dependencies:") + "\n  - " + "\n  - ".join(missing))
    sys.exit(1)
PY
}

if [ "${1:-}" != "--no-deps" ]; then
    msg "→ Bağımlılıklar kuruluyor (yönetici parolası istenebilir)…" \
        "→ Installing dependencies (you may be asked for the administrator password)…"
    install_deps
fi
msg "→ Bağımlılıklar denetleniyor…" "→ Checking dependencies…"
check_deps

msg "→ Uygulama kopyalanıyor: $APP_DIR" "→ Copying the app: $APP_DIR"
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

# Uygulama menüsünü yenile (KDE menüsü yeni girdileri ancak önbellek yenilenince gösterir).
command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 >/dev/null 2>&1 || true
command -v kbuildsycoca5 >/dev/null 2>&1 && kbuildsycoca5 >/dev/null 2>&1 || true

# ~/.local/bin PATH'te değilse kabuk ayarına ekle (oturum açılırken klasör yoksa sistem eklemiyor).
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
        for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
            [ -f "$rc" ] || continue
            grep -qs 'mahzen: ~/.local/bin' "$rc" || printf '\n# mahzen: ~/.local/bin\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
        done
        PATH_NOTE=1 ;;
esac

echo
msg "✓ Mahzen kuruldu. Uygulama menüsünden açın ya da terminalde: mahzen" \
    "✓ Mahzen is installed. Open it from the app menu or run in a terminal: mahzen"
if [ -n "${PATH_NOTE:-}" ]; then
    msg "  Not: $BIN_DIR kabuk ayarına eklendi; yeni bir terminal açın ya da: source ~/.bashrc" \
        "  Note: $BIN_DIR was added to your shell profile; open a new terminal or run: source ~/.bashrc"
fi
msg "  Kurulumu sınamak için: $DIR/test.sh" "  To test the installation: $DIR/test.sh"
