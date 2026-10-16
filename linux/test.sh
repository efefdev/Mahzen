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
pass=0; fail=0
ok() { echo "  ✓ $1"; pass=$((pass+1)); }
no() { echo "  ✗ $1"; fail=$((fail+1)); }
check() {
  local d="$1"; shift
  if "$@" >"$T/out" 2>&1; then ok "$d"; else no "$d"; tail -6 "$T/out" | sed 's/^/      /'; fi
}
cli() { printf '%s\n' "$1" | XDG_DATA_HOME="$T/data" "$CLI" "${@:2}" --parola-stdin; }

echo "1) Bağımlılıklar"
check "Python 3.10+" python3 -c 'import sys; assert sys.version_info >= (3, 10), sys.version'
check "GTK 4 + libadwaita 1.5+" python3 -c 'import gi; gi.require_version("Gtk","4.0"); gi.require_version("Adw","1"); from gi.repository import Adw; v=(Adw.get_major_version(), Adw.get_minor_version()); assert v >= (1,5), v'
check "cryptography" python3 -c 'import cryptography'
check "argon2-cffi" python3 -c 'from argon2.low_level import hash_secret_raw'

echo "2) Kurulum"
check "uygulama dosyaları" test -f "$APP/mahzen/__main__.py"
check "mahzen komutu" test -x "$HOME/.local/bin/mahzen"
check "mahzen-cli komutu" test -x "$CLI"
check "menü kısayolu" test -f "$DATA/applications/dev.efef.Mahzen.desktop"
check "uygulama simgesi" test -f "$DATA/icons/hicolor/256x256/apps/dev.efef.Mahzen.png"

echo "3) Çekirdek testleri (macOS kasalarıyla uyumluluk dahil)"
if [ -d "$SRC/tests" ]; then
  check "birim testleri" python3 -m unittest discover -s "$SRC/tests"
else
  no "birim testleri: $SRC/tests bulunamadı (MAHZEN_SRC ile repo yolunu verin)"
fi

echo "4) Gerçek bir kasa (varsayılan ayar: Argon2id, 1 GB bellek)"
start=$(date +%s.%N)
check "kasa oluşturma" env PYTHONPATH="$APP" python3 -c "from mahzen.core.vault import Vault; Vault.create('$T/kasa', '$PW')"
echo "      anahtar türetme süresi: $(python3 -c "print(f'{$(date +%s.%N) - $start:.1f}')") sn"
mkdir -p "$T/girdi/Alt Klasör"
head -c 3145728 /dev/urandom > "$T/girdi/büyük dosya.bin"
echo "merhaba çğıöşü gizli-icerik-42" > "$T/girdi/Alt Klasör/not.txt"
check "dosya ve klasör ekleme" cli "$PW" ekle "$T/kasa" "$T/girdi"
check "listeleme (klasör yapısı korunmuş)" sh -c "printf '%s\n' '$PW' | XDG_DATA_HOME='$T/data' '$CLI' listele '$T/kasa' --parola-stdin | grep -q 'girdi/Alt Klasör/not.txt'"
check "dışa aktarılan dosya birebir aynı" sh -c "printf '%s\n' '$PW' | XDG_DATA_HOME='$T/data' '$CLI' disari '$T/kasa' 'büyük dosya.bin' '$T/cikti' --parola-stdin && cmp '$T/girdi/büyük dosya.bin' '$T/cikti/büyük dosya.bin'"
check "diskte düz içerik ve dosya adı yok" sh -c "! grep -rqa -e 'gizli-icerik-42' -e 'büyük dosya' -e 'Alt Klasör' '$T/kasa'"
check "aynı dosya ikinci kez eklenmiyor" sh -c "printf '%s\n' '$PW' | XDG_DATA_HOME='$T/data' '$CLI' ekle '$T/kasa' '$T/girdi/büyük dosya.bin' --parola-stdin 2>&1 | grep -q 'Zaten kasada'"
check "yanlış parola reddediliyor" sh -c "! printf 'yanlis-parola-123\n' | XDG_DATA_HOME='$T/data' '$CLI' listele '$T/kasa' --parola-stdin"
check "bütünlük taraması temiz" cli "$PW" dogrula "$T/kasa"
check "yedek alınıyor ve yedek açılıyor" sh -c "printf '%s\n' '$PW' | XDG_DATA_HOME='$T/data' '$CLI' yedekle '$T/kasa' '$T/yedek' --parola-stdin && printf '%s\n' '$PW' | XDG_DATA_HOME='$T/data' '$CLI' listele '$T/yedek' --parola-stdin | grep -q 'not.txt'"
cp -r "$T/kasa" "$T/kurcalanmis"
blob=$(find "$T/kurcalanmis/blobs" -name '*.mhz' -size +1M | head -1)
printf '\xff' | dd of="$blob" bs=1 seek=2000000 conv=notrunc status=none
check "kurcalanmış dosya yakalanıyor" sh -c "! printf '%s\n' '$PW' | XDG_DATA_HOME='$T/data' '$CLI' dogrula '$T/kurcalanmis' --parola-stdin"

echo "5) Yanlış parola sınırı (3 denemede anahtar silinir)"
check "sınırlı kasa oluşturma" env PYTHONPATH="$APP" python3 -c "
from mahzen.core.vault import Vault; from mahzen.core import crypto
Vault.create('$T/sinir', '$PW', crypto.KDFSettings(iterations=1, memory_kib=8192, parallelism=1)).set_auto_wipe(3)"
for i in 1 2 3; do printf 'yanlis\n' | XDG_DATA_HOME="$T/data" "$CLI" listele "$T/sinir" --parola-stdin >/dev/null 2>&1; done
check "3 yanlışta vault.json silindi" test ! -e "$T/sinir/vault.json"
check "şifreli dosyalar yerinde, ama açılmıyor" sh -c "test -e '$T/sinir/index.enc' && ! printf '%s\n' '$PW' | XDG_DATA_HOME='$T/data' '$CLI' listele '$T/sinir' --parola-stdin"

echo "6) Arayüz"
if systemd-detect-virt --vm --quiet 2>/dev/null && [ -z "${GSK_RENDERER:-}" ]; then echo "      sanal makine algılandı: yazılım çizimi (cairo) kullanılacak"; fi
timeout 8 env XDG_DATA_HOME="$T/data" PYTHONPATH="$APP" python3 -m mahzen >"$T/gui" 2>&1; rc=$?
if [ $rc -eq 124 ] && ! grep -q Traceback "$T/gui"; then
  ok "arayüz açılıyor ve 8 sn hatasız çalışıyor"
elif [ $rc -eq 0 ] && ! grep -q Traceback "$T/gui"; then
  ok "arayüz: Mahzen zaten açık, açık pencereye geçildi"
else
  no "arayüz açılmadı (çıkış kodu $rc)"; tail -12 "$T/gui" | sed 's/^/      /'
fi

echo
if [ $fail -eq 0 ]; then echo "✓ Tüm testler geçti ($pass/$pass)"; else echo "✗ $fail test başarısız, $pass geçti"; fi
exit $fail
