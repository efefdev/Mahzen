# Mahzen

**Dosyaların, notların ve parolaların için şifreli, taşınabilir bir kasa.**

Mahzen; dosyalarını, notlarını ve parolalarını tek bir şifreli klasörde saklayan yerel bir macOS uygulamasıdır. Uygulama ile kasa yan yana bir SSD'de durabilir ve her Mac'te açılabilir. İnternete hiçbir şey gönderilmez, hesap gerekmez.

> 🪟 **Windows sürümü yakında geliyor.** Kasa biçimi platformdan bağımsız tasarlandı; Windows uygulaması aynı kasayı açabilecek.

<p align="center">
  <img src="docs/ekran/kilit.png" width="49%" alt="Kilit ekranı">
  <img src="docs/ekran/dosyalar.png" width="49%" alt="Dosyalar">
</p>
<p align="center">
  <img src="docs/ekran/parolalar.png" width="49%" alt="Parolalar">
  <img src="docs/ekran/notlar.png" width="49%" alt="Notlar">
</p>

## Özellikler

**Dosyalar**
- Sürükle-bırak ile ekleme; sürüklenen klasörlerin yapısı korunur
- Kasa içinde iç içe klasörler, etiketler, favoriler, arama ve filtreler
- Görsel, PDF ve metinleri uygulama içinde önizleme
- Video ve sesleri **diske şifresiz kopya yazmadan** oynatma (şifre bellekte, parça parça çözülür)
- Finder'a sürükleyerek dışa aktarma, aynı dosyanın iki kez eklenmesini önleme
- Ekledikten sonra orijinalleri Mac'in Çöp Kutusu'na taşıma seçeneği

**Notlar ve parolalar**
- Renkli, sabitlenebilir notlar; yazı tipi ve boyutu ayarlanabilir
- Hesap, kart, Wi-Fi ve sunucu kayıtları; parola üretici ve güç ölçer
- Kopyalanan parola, seçilen süre sonunda panodan otomatik silinir

**Güvenlik ve bakım**
- Hareketsizlikte, uykuda, ekran kilidinde ve SSD çıkarıldığında otomatik kilit
- İsteğe bağlı: kasayı bir Mac'e bağlayan **anahtar dosyası** (parola + o Mac'te saklanan rastgele dosya)
- Pencereyi ekran görüntüsü, kayıt ve ekran paylaşımında gizleme
- Çöp Kutusu (ayarlanabilir süre), tek tıkla artımlı yedek, yedek hatırlatması
- Bütünlük taraması: her dosyayı çözerek doğrular, bozuk olanları yedekten geri yükler

**Görünüm**
- Açık / koyu / sistem teması, 9 vurgu rengi, ızgara veya liste görünümü
- Saatli kilit ekranı, Caps Lock uyarısı, Türkçe arayüz

## Şifreleme nasıl çalışıyor?

| Katman | Yöntem |
|---|---|
| Veri şifreleme | **AES-256-GCM** (Apple CryptoKit). Her dosya kendi anahtarıyla, 1 MB'lık parçalar halinde şifrelenir. |
| Paroladan anahtar | **Argon2id** — 1 GB bellek, 3 geçiş, 4 iş parçacığı (release derlemede, Apple Silicon'da deneme başına ~0,7 sn). Ekran kartıyla toplu tahmini pahalılaştırır. |
| Anahtar hiyerarşisi | Rastgele 256 bitlik ana anahtar, paroladan türetilen anahtarla sarılır. Dosya, küçük resim ve dizin anahtarları ana anahtardan HKDF-SHA256 ile türetilir. |
| Anahtar dosyası (isteğe bağlı) | Sarma anahtarı = HKDF(Argon2id(parola) ‖ 512 bit rastgele dosya). Kasa başlığında anahtar dosyasına dair hiçbir alan yoktur. |
| Bütünlük | Parçaların sırası ve "son parça" bilgisi nonce'a bağlıdır; değiştirilen, yer değiştirilen, kesilen veya sonuna veri eklenen dosyalar — oynatıcının rastgele erişimli okumasında da — reddedilir. |

Kasa klasöründe yalnızca rastgele adlı şifreli dosyalar bulunur; **dosya adları, klasörler, etiketler, notlar ve parolalar da şifrelidir.**

```
Mahzen Kasası/
├── vault.json        şifresiz başlık: tuz, Argon2id ayarları, sarılmış ana anahtar (sır içermez)
├── index.enc         şifreli dizin (+ index.enc.bak: bir önceki sürüm)
├── blobs/xx/<id>.mhz şifreli dosya içerikleri
└── thumbs/<id>.mhz   şifreli küçük resimler
```

Uygulamada açık anahtarlı şifreleme (RSA/ECC) bulunmaz; bu yüzden kuantum bilgisayarların kırabildiği türden bir bileşen yoktur. Grover algoritması AES-256'nın etkin gücünü yaklaşık 128 bite indirir; bu hâlâ pratikte kırılamaz kabul edilir. Zayıf bir parolayı ise hiçbir algoritma kurtaramaz.

### Sınırlar — lütfen okuyun

- **Bağımsız güvenlik denetiminden geçmedi.** Kullanılan yapı taşları (CryptoKit, Argon2 referans uygulaması) denetlenmiş kütüphanelerdir; ancak bunları birleştiren Mahzen kodu denetlenmemiştir. Hayati önemde veriler için VeraCrypt veya Cryptomator gibi denetlenmiş araçları değerlendirin.
- **Güvenlik parolanızın gücüne bağlıdır.** Rastgele seçilmiş 5+ kelime veya 12+ rastgele karakter önerilir.
- **Parola unutulursa veriler kurtarılamaz.** Anahtar dosyası kullanılıyorsa onun da yedeği alınmalıdır.
- Dosya **boyutları ve sayısı** kasa klasörüne bakan biri tarafından görülebilir.
- "Geçici Aç" ve Finder'a sürükleme, kasa dışında şifresiz kopya oluşturur (kilitte ve bir sonraki açılışta temizlenir).
- Kasa klasörüne yazabilen biri dizin dosyasını eski bir kopyasıyla değiştirerek notları/parolaları eski hâline döndürebilir; bu henüz tespit edilmiyor.
- Parola değiştirmek veya anahtar dosyası eklemek ana anahtarı yenilemez; eski bir başlık kopyası ile eski parola, verileri açmaya yeter.

## Kurulum

### Hazır uygulama
[Sürümler](../../releases) sayfasına eklenecek. Şimdilik kaynaktan derleyin.

### Kaynaktan derleme

Gereksinimler: macOS 14+, **tam Xcode 15.3 veya üstü** (Swift 5.10+; Apple Silicon + Intel tek pakette derlendiği için yalnızca Komut Satırı Araçları yetmez)

```bash
git clone https://github.com/efefdev/Mahzen.git
cd Mahzen
./scripts/build-app.sh      # dist/Mahzen.app (Apple Silicon + Intel)
```

Uygulamayı SSD'ye taşımak için `dist/Mahzen.app` klasörünü SSD'nin köküne kopyalayın. İlk açılışta kasa, uygulamanın yanında `Mahzen Kasası` olarak oluşturulur.

Uygulama ad-hoc imzalıdır (Apple tarafından noterize edilmemiştir). Kendi derlediğiniz kopya uyarısız açılır. İnternetten indirilmiş bir kopyayı açarken macOS uyarı verirse:
- **macOS 15 ve sonrası:** Önce açmayı deneyin, sonra **Sistem Ayarları → Gizlilik ve Güvenlik** sayfasının altındaki **"Yine de Aç"** düğmesini kullanın.
- **macOS 14:** Finder'da sağ tık → **Aç**.

### Testler

```bash
swift test
```

43 test; şifreleme, parça doğrulama, kurcalama/kesme tespiti, Argon2 referans test vektörleri, anahtar dosyası (arşivleme dahil), içe aktarma planı, yedekleme ve bütünlük taramasını kapsar.

## Proje yapısı

```
Sources/
├── CArgon2/      Argon2 resmi referans uygulaması (değiştirilmeden, CC0/Apache-2.0)
├── MahzenCore/   Şifreleme, kasa biçimi, yedekleme, bütünlük taraması (arayüzden bağımsız)
└── Mahzen/       SwiftUI uygulaması
Tests/            Çekirdek testleri
scripts/          Uygulama paketleme ve simge üretme
```

## Yol haritası

- [ ] **Windows uygulaması** (yakında)
- [ ] Hazır derlenmiş sürümler
- [ ] Markdown notlar, notlara dosya ekleme
- [ ] Parola sağlığı ekranı (zayıf / tekrar kullanılan parolalar)
- [ ] ⌘K hızlı arama, menü çubuğu simgesi

## Lisans

Mahzen, **[PolyForm Noncommercial 1.0.0](LICENSE)** lisansıyla yayımlanır. Kaynak kodu açıktır; **ticari olmayan** her amaçla kullanabilir, inceleyebilir, değiştirebilir ve paylaşabilirsiniz.

| ✅ Serbest | ❌ İzin gerektirir |
|---|---|
| Kişisel kullanım, öğrenme, araştırma, deneme | Satmak, ücretli hizmete veya ürüne dahil etmek |
| Okul, dernek, kâr amacı gütmeyen kuruluşlarda kullanım | Bir şirketin ticari faaliyetinde kullanmak |
| Değiştirip ticari olmayan amaçla paylaşmak (lisans metni ve telif bildirimiyle) | |

Ticari kullanım için GitHub üzerinden iletişime geçin.

> Not: Ticari kullanımı kısıtladığı için bu lisans, OSI tanımına göre "açık kaynak" değil, **kaynağı açık (source-available)** bir lisanstır.

`Sources/CArgon2` altındaki Argon2 kodu kendi lisansıyla (CC0 1.0 veya Apache 2.0) dağıtılır; ayrıntılar için [Sources/CArgon2/LICENSE](Sources/CArgon2/LICENSE) dosyasına bakın.
