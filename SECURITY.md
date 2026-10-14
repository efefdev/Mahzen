# Güvenlik Politikası

Mahzen bir şifreleme uygulamasıdır; güvenlik açıklarını bildirenlere teşekkür ederiz.

## Desteklenen sürümler

Yalnızca `main` dalındaki en güncel sürüm desteklenir.

## Açık bildirme

**Lütfen güvenlik açıklarını herkese açık bir Issue olarak paylaşmayın.**

Bunun yerine GitHub'ın gizli bildirim özelliğini kullanın: depodaki **Security** sekmesi → **Report a vulnerability**. Bildirim yalnızca proje sahibi tarafından görülür.

Bildiriminizde mümkünse şunlara yer verin:

- Açığın kısa açıklaması ve etkisi
- Yeniden üretme adımları (kavram kanıtı varsa ekleyin)
- Etkilenen dosya/fonksiyon ve sürüm (commit)
- Önerdiğiniz çözüm (isteğe bağlı)

## Süreç

- Bildirimler en geç **7 gün** içinde yanıtlanmaya çalışılır.
- Doğrulanan açıklar düzeltildikten sonra, isterseniz adınızla birlikte duyurulur.
- Düzeltme yayımlanana kadar ayrıntıların paylaşılmamasını rica ederiz.

## Kapsam

Kapsamda: şifreleme ve anahtar yönetimi (`Sources/MahzenCore`), kasa biçimi, uygulamanın veri sızdırabilecek davranışları (geçici dosyalar, pano, kilit).

Kapsam dışı: yerel olarak zaten yönetici yetkisine sahip bir saldırgan, fiziksel erişimle cihaza yüklenen kötü amaçlı yazılım, kullanıcının zayıf parola seçimi ve `Sources/CArgon2` altındaki değiştirilmemiş Argon2 referans kodu (bunlar için [P-H-C/phc-winner-argon2](https://github.com/P-H-C/phc-winner-argon2) deposuna bildirin).

Bilinen sınırlar README'nin **"Sınırlar"** bölümünde listelenmiştir.
