#!/bin/bash
# Mahzen Linux: kurulumu uçtan uca sınar. Gerçek kasalara dokunmaz; her şey geçici bir klasörde yapılır.
# Kullanım: linux/test.sh   (önce ./install.sh ile kurulmuş olmalı)
set -u
SRC="${MAHZEN_SRC:-$(cd "$(dirname "$0")" && pwd)}"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
APP="$DATA/mahzen-app"
CLI="$HOME/.local/bin/mahzen-cli"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export PYTHONDONTWRITEBYTECODE=1 XDG_CONFIG_HOME="$T/cfg"
PW='Deneme-Parola-2026!'
# Mesaj dili: MAHZEN_LANG (tr | en), yoksa sistem dili; Türkçe değilse İngilizce.
case "${MAHZEN_LANG:-}" in
  tr*|en*) UI_LANG="$MAHZEN_LANG" ;;
  *) UI_LANG="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" ;;
esac
case "$UI_LANG" in tr*|TR*) UI_LANG=tr ;; *) UI_LANG=en ;; esac
msg() { if [ "$UI_LANG" = tr ]; then printf '%s\n' "$1"; else printf '%s\n' "$2"; fi; }
pass=0; fail=0
ok() { echo "  ✓ $1"; pass=$((pass+1)); }
no() { echo "  ✗ $1"; fail=$((fail+1)); }
check() {
  local d="$1"; shift
  if "$@" >"$T/out" 2>&1; then ok "$d"; else no "$d"; tail -6 "$T/out" | sed 's/^/      /'; fi
}
cli() { printf '%s\n' "$1" | XDG_DATA_HOME="$T/data" "$CLI" "${@:2}" --parola-stdin; }

msg "1) Bağımlılıklar" "1) Dependencies"
check "Python 3.10+" python3 -c 'import sys; assert sys.version_info >= (3, 10), sys.version'
check "GTK 4 + libadwaita 1.5+" python3 -c 'import gi; gi.require_version("Gtk","4.0"); gi.require_version("Adw","1"); from gi.repository import Adw; v=(Adw.get_major_version(), Adw.get_minor_version()); assert v >= (1,5), v'
check "cryptography" python3 -c 'import cryptography'
check "argon2-cffi" python3 -c 'from argon2.low_level import hash_secret_raw'

msg "2) Kurulum" "2) Installation"
check "$(msg "uygulama dosyaları" "app files")" test -f "$APP/mahzen/__main__.py"
check "$(msg "mahzen komutu" "mahzen command")" test -x "$HOME/.local/bin/mahzen"
check "$(msg "mahzen-cli komutu" "mahzen-cli command")" test -x "$CLI"
check "$(msg "menü kısayolu" "menu entry")" test -f "$DATA/applications/dev.efef.Mahzen.desktop"
check "$(msg "uygulama simgesi" "app icon")" test -f "$DATA/icons/hicolor/256x256/apps/dev.efef.Mahzen.png"

msg "3) Çekirdek testleri (macOS kasalarıyla uyumluluk dahil)" "3) Core tests (including compatibility with macOS vaults)"
if [ -d "$SRC/tests" ]; then
  check "$(msg "birim testleri" "unit tests")" python3 -m unittest discover -s "$SRC/tests"
else
  no "$(msg "birim testleri: $SRC/tests bulunamadı (MAHZEN_SRC ile repo yolunu verin)" \
    "unit tests: $SRC/tests not found (set MAHZEN_SRC to the repository path)")"
fi

msg "4) Gerçek bir kasa (varsayılan ayar: Argon2id, 1 GB bellek)" "4) A real vault (default settings: Argon2id, 1 GB memory)"
start=$(date +%s.%N)
check "$(msg "kasa oluşturma" "creating a vault")" env PYTHONPATH="$APP" python3 -c "from mahzen.core.vault import Vault; Vault.create('$T/kasa', '$PW')"
elapsed=$(python3 -c "print(f'{$(date +%s.%N) - $start:.1f}')")
msg "      anahtar türetme süresi: $elapsed sn" "      key derivation time: $elapsed s"
mkdir -p "$T/girdi/Alt Klasör"
head -c 3145728 /dev/urandom > "$T/girdi/büyük dosya.bin"
echo "merhaba çğıöşü gizli-icerik-42" > "$T/girdi/Alt Klasör/not.txt"
check "$(msg "dosya ve klasör ekleme" "adding files and folders")" cli "$PW" ekle "$T/kasa" "$T/girdi"
check "$(msg "listeleme (klasör yapısı korunmuş)" "listing (folder structure preserved)")" sh -c "printf '%s\n' '$PW' | XDG_DATA_HOME='$T/data' '$CLI' listele '$T/kasa' --parola-stdin | grep -q 'girdi/Alt Klasör/not.txt'"
check "$(msg "dışa aktarılan dosya birebir aynı" "exported file is identical")" sh -c "printf '%s\n' '$PW' | XDG_DATA_HOME='$T/data' '$CLI' disari '$T/kasa' 'büyük dosya.bin' '$T/cikti' --parola-stdin && cmp '$T/girdi/büyük dosya.bin' '$T/cikti/büyük dosya.bin'"
check "$(msg "diskte düz içerik ve dosya adı yok" "no plaintext content or file names on disk")" sh -c "! grep -rqa -e 'gizli-icerik-42' -e 'büyük dosya' -e 'Alt Klasör' '$T/kasa'"
check "$(msg "aynı dosya ikinci kez eklenmiyor" "the same file is not added twice")" sh -c "printf '%s\n' '$PW' | XDG_DATA_HOME='$T/data' '$CLI' ekle '$T/kasa' '$T/girdi/büyük dosya.bin' --parola-stdin 2>&1 | grep -q -e 'Zaten kasada' -e 'Already in vault'"
check "$(msg "yanlış parola reddediliyor" "wrong password is rejected")" sh -c "! printf 'yanlis-parola-123\n' | XDG_DATA_HOME='$T/data' '$CLI' listele '$T/kasa' --parola-stdin"
check "$(msg "bütünlük taraması temiz" "integrity check is clean")" cli "$PW" dogrula "$T/kasa"
check "$(msg "yedek alınıyor ve yedek açılıyor" "backup is made and the backup opens")" sh -c "printf '%s\n' '$PW' | XDG_DATA_HOME='$T/data' '$CLI' yedekle '$T/kasa' '$T/yedek' --parola-stdin && printf '%s\n' '$PW' | XDG_DATA_HOME='$T/data' '$CLI' listele '$T/yedek' --parola-stdin | grep -q 'not.txt'"
cp -r "$T/kasa" "$T/kurcalanmis"
blob=$(find "$T/kurcalanmis/blobs" -name '*.mhz' -size +1M | head -1)
printf '\xff' | dd of="$blob" bs=1 seek=2000000 conv=notrunc status=none
check "$(msg "kurcalanmış dosya yakalanıyor" "tampered file is detected")" sh -c "! printf '%s\n' '$PW' | XDG_DATA_HOME='$T/data' '$CLI' dogrula '$T/kurcalanmis' --parola-stdin"

msg "5) Yanlış parola sınırı (3 denemede anahtar silinir)" "5) Wrong-password limit (keys are destroyed after 3 attempts)"
check "$(msg "sınırlı kasa oluşturma" "creating a vault with a limit")" env PYTHONPATH="$APP" python3 -c "
from mahzen.core.vault import Vault; from mahzen.core import crypto
Vault.create('$T/sinir', '$PW', crypto.KDFSettings(iterations=1, memory_kib=8192, parallelism=1)).set_auto_wipe(3)"
for i in 1 2 3; do printf 'yanlis\n' | XDG_DATA_HOME="$T/data" "$CLI" listele "$T/sinir" --parola-stdin >/dev/null 2>&1; done
check "$(msg "3 yanlışta vault.json silindi" "vault.json deleted after 3 wrong attempts")" test ! -e "$T/sinir/vault.json"
check "$(msg "şifreli dosyalar yerinde, ama açılmıyor" "encrypted files remain but cannot be opened")" sh -c "test -e '$T/sinir/index.enc' && ! printf '%s\n' '$PW' | XDG_DATA_HOME='$T/data' '$CLI' listele '$T/sinir' --parola-stdin"

msg "6) Arayüz" "6) Interface"
if systemd-detect-virt --vm --quiet 2>/dev/null && [ -z "${GSK_RENDERER:-}" ]; then msg "      sanal makine algılandı: yazılım çizimi (cairo) kullanılacak" "      virtual machine detected: software rendering (cairo) will be used"; fi
timeout 8 env XDG_DATA_HOME="$T/data" PYTHONPATH="$APP" python3 -m mahzen >"$T/gui" 2>&1; rc=$?
if [ $rc -eq 124 ] && ! grep -q Traceback "$T/gui"; then
  ok "$(msg "arayüz açılıyor ve 8 sn hatasız çalışıyor" "interface opens and runs for 8 s without errors")"
elif [ $rc -eq 0 ] && ! grep -q Traceback "$T/gui"; then
  ok "$(msg "arayüz: Mahzen zaten açık, açık pencereye geçildi" "interface: Mahzen is already running, switched to its window")"
else
  no "$(msg "arayüz açılmadı (çıkış kodu $rc)" "interface did not open (exit code $rc)")"; tail -12 "$T/gui" | sed 's/^/      /'
fi

echo
if [ $fail -eq 0 ]; then
  msg "✓ Tüm testler geçti ($pass/$pass)" "✓ All tests passed ($pass/$pass)"
else
  msg "✗ $fail test başarısız, $pass geçti" "✗ $fail tests failed, $pass passed"
fi
exit $fail
