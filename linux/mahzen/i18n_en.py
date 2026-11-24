"""İngilizce sözlük: Türkçe kaynak metin → İngilizce karşılık.

Karşılık bir (tekil, çoğul) ikilisiyse `tr(..., n=…)` çağrısındaki `n` değerine göre seçilir.
"metin|bağlam" biçimindeki anahtarlar `tr(metin, _ctx="bağlam")` çağrıları içindir.
"""

ENGLISH = {
    # Genel düğmeler ve kısa etiketler
    "Tamam": "OK",
    "Vazgeç": "Cancel",
    "Kapat": "Close",
    "Kapat|anahtar": "Turn Off",
    "Kapat…|anahtar": "Turn Off…",
    "Kaydet": "Save",
    "Sil": "Delete",
    "Aç": "Open",
    "Geri": "Back",
    "Menü": "Menu",
    "Durdur": "Stop",
    "Oluştur": "Create",
    "Değiştir": "Change",
    "Değiştir…": "Change…",
    "Seç…": "Choose…",
    "Kopyala": "Copy",
    "Kopyalandı": "Copied",
    "Adsız": "Untitled",
    "Sistem": "System",
    "Dil / Language": "Language / Dil",
    "Yeniden başlatınca uygulanır · Applies after restart": "Applies after restart · Yeniden başlatınca uygulanır",

    # Bölümler
    "Dosyalar": "Files",
    "Notlar": "Notes",
    "Parolalar": "Passwords",
    "Çöp Kutusu": "Trash",
    "Ayarlar": "Settings",
    "Klasörler": "Folders",

    # Birimler, sayılar, tarihler
    "{n} bayt": ("{n} byte", "{n} bytes"),
    "{n} dosya": ("{n} file", "{n} files"),
    "{n} klasör": ("{n} folder", "{n} folders"),
    "{n} not": ("{n} note", "{n} notes"),
    "{n} parola kaydı": ("{n} password entry", "{n} password entries"),
    "{n} dosya ({size})": ("{n} file ({size})", "{n} files ({size})"),
    "{items} seçili": "{items} selected",
    "{day} {month} {year}": "{month} {day}, {year}",
    "{day} {month} {weekday}": "{weekday}, {month} {day}",
    "Bugün {time}": "Today {time}",
    "Dün": "Yesterday",
    "{n} gün önce": ("{n} day ago", "{n} days ago"),
    "Ocak": "January",
    "Şubat": "February",
    "Mart": "March",
    "Nisan": "April",
    "Mayıs": "May",
    "Haziran": "June",
    "Temmuz": "July",
    "Ağustos": "August",
    "Eylül": "September",
    "Ekim": "October",
    "Kasım": "November",
    "Aralık": "December",
    "Pazartesi": "Monday",
    "Salı": "Tuesday",
    "Çarşamba": "Wednesday",
    "Perşembe": "Thursday",
    "Cuma": "Friday",
    "Cumartesi": "Saturday",
    "Pazar": "Sunday",

    # Renkler
    "Renk yok": "No Color",
    "Çivit": "Indigo",
    "Mavi": "Blue",
    "Turkuaz": "Teal",
    "Yeşil": "Green",
    "Turuncu": "Orange",
    "Pembe": "Pink",
    "Kırmızı": "Red",
    "Mor": "Purple",
    "Grafit": "Graphite",

    # Parola gücü
    "Çok zayıf": "Very weak",
    "Zayıf": "Weak",
    "Orta": "Fair",
    "Güçlü": "Strong",
    "Çok güçlü": "Very strong",
    "Parola gücü: {label}": "Password strength: {label}",

    # Kasa hataları
    "Parola yanlış.": "Wrong password.",
    "Kasa verisi doğrulanamadı: {detail}": "Vault data could not be verified: {detail}",
    "Bu klasör bir Mahzen kasası değil.": "This folder is not a Mahzen vault.",
    "Bu konumda zaten bir kasa var.": "There is already a vault at this location.",
    "Bu kasa daha yeni bir Mahzen sürümüyle oluşturulmuş (biçim {version}).":
        "This vault was created with a newer version of Mahzen (format {version}).",
    "Anahtar türetilemedi.": "Could not derive the key.",
    "Parola en az {minimum} karakter olmalı.": "The password must be at least {minimum} characters.",
    "dosya başlığı geçersiz": "invalid file header",
    "parça boyutu geçersiz": "invalid chunk size",
    "dosya kesik": "file is truncated",
    "içerik doğrulanamadı (bozulmuş, değiştirilmiş veya yanlış anahtar)":
        "content could not be verified (corrupted, modified or wrong key)",
    "içerik doğrulanamadı": "content could not be verified",
    "beklenmeyen dosya sonu": "unexpected end of file",
    "bilinmeyen anahtar türetme yöntemi: {algorithm}": "unknown key derivation method: {algorithm}",
    "Argon2id ayarları eksik": "Argon2id settings are missing",
    "vault.json okunamadı": "vault.json could not be read",
    "anahtar dosyası çok kısa": "keyfile is too short",
    "deneme sınırı {low}–{high} arasında olmalı": "attempt limit must be between {low} and {high}",
    "yedek konumu kasanın kendisi veya içi olamaz": "the backup location cannot be the vault itself or inside it",
    "yedek bu kasaya ait değil": "the backup does not belong to this vault",
    "dizin dosyası bulunamadı": "index file not found",
    "dizin doğrulanamadı": "index could not be verified",
    "seçilen klasörde başka bir kasa var": "the selected folder contains a different vault",
    "Anahtar dosyası yazılamadı: {path}": "Could not write the keyfile: {path}",
    "Ayarlar kaydedilemedi: {error}": "Could not save settings: {error}",
    "PBKDF2-HMAC-SHA512 · {rounds} tur": "PBKDF2-HMAC-SHA512 · {rounds} rounds",
    "Argon2id · {memory} MB · {n} geçiş · {threads} iş parçacığı":
        "Argon2id · {memory} MB · passes: {n} · threads: {threads}",
    "Yeni Klasör": "New Folder",

    # Başlatma
    "Arayüz başlatılamadı: {error}\nGTK4, libadwaita (1.5+) ve PyGObject kurulu olmalı. Kurulum için: linux/install.sh":
        "Could not start the interface: {error}\n"
        "GTK4, libadwaita (1.5+) and PyGObject must be installed. To install: linux/install.sh",

    # Komut satırı
    "Mahzen şifreli kasası için komut satırı.": "Command line for the Mahzen encrypted vault.",
    "komut": "command",
    "kasa": "vault",
    "dosya": "file",
    "hedef": "target",
    "kaynak": "source",
    "DOSYA": "FILE",
    "kasa klasörü": "vault folder",
    "parolayı standart girdiden oku": "read the password from standard input",
    "anahtar dosyası (.mahzenkey)": "keyfile (.mahzenkey)",
    "kasa başlığını göster (parola gerekmez)": "show the vault header (no password needed)",
    "dosyaları listele": "list files",
    "çöp kutusundakileri de göster": "also show files in the trash",
    "dosyayı şifresini çözerek dışa aktar": "decrypt and export a file",
    "dosya adı ya da kimliğin başı": "file name or the start of its ID",
    "hedef klasör": "target folder",
    "dosya veya klasörleri şifreleyip ekle": "encrypt and add files or folders",
    "eklenecek dosya ya da klasör": "file or folder to add",
    "bütünlük taraması": "integrity check",
    "artımlı yedek al": "make an incremental backup",
    "yedek klasörü": "backup folder",
    "Kasa parolası: ": "Vault password: ",
    "Kasa kimliği : {value}": "Vault ID      : {value}",
    "Biçim        : {value}": "Format        : {value}",
    "Oluşturulma  : {value}": "Created       : {value}",
    "Şifreleme    : {value}": "Encryption    : {value}",
    "Yanlış parola: {value}": "Wrong password: {value}",
    "{n} denemede kasa silinir (şu an {failed} yanlış)": "vault is erased after {n} attempts ({failed} wrong so far)",
    "sınır yok": "no limit",
    "Yanlış parola sınırı aşıldı: kasanın anahtarları yok edildi, kasa kalıcı olarak silindi.":
        "Wrong-password limit exceeded: the vault's keys were destroyed and the vault is permanently erased.",
    "Kalan deneme: {remaining}": "Attempts left: {remaining}",
    " (çöpte)": " (in trash)",
    "Bulunamadı: {name}": "Not found: {name}",
    "Zaten var, atlandı: {path}": "Already exists, skipped: {path}",
    "Zaten kasada: {name}": "Already in vault: {name}",
    "Eklendi: {name}": "Added: {name}",
    "{n} öğe atlandı (gizli dosya, kısayol veya okunamayan öğe).":
        ("{n} item skipped (hidden file, shortcut or unreadable item).",
         "{n} items skipped (hidden files, shortcuts or unreadable items)."),
    "{n} dosya şifrelendi.": ("{n} file encrypted.", "{n} files encrypted."),
    "{n} dosya ({size}) doğrulandı.": ("{n} file ({size}) verified.", "{n} files ({size}) verified."),
    "SORUN  {name}: {problem}": "PROBLEM  {name}: {problem}",
    "{n} sahipsiz dosya ({size}).": ("{n} orphaned file ({size}).", "{n} orphaned files ({size})."),
    "Dizin yedeği okunamıyor.": "The index backup cannot be read.",
    "{n} dosya kopyalandı ({size}), {unchanged} değişmemiş, {removed} eski kopya silindi.":
        ("{n} file copied ({size}), {unchanged} unchanged, {removed} old copies removed.",
         "{n} files copied ({size}), {unchanged} unchanged, {removed} old copies removed."),

    # Ana pencere
    "Klavye Kısayolları": "Keyboard Shortcuts",
    "Mahzen Hakkında": "About Mahzen",
    "Kilitle (Ctrl+L)": "Lock (Ctrl+L)",
    "Dizin yedekten kurtarıldı.": "The index was recovered from its backup.",
    "Kasanın henüz yedeği yok": "This vault has no backup yet",
    "Son yedek {n} gün önce": ("Last backup {n} day ago", "Last backup {n} days ago"),
    "Önce bir yedek konumu seçin": "Choose a backup location first",
    "Orijinaller çöp kutusuna taşınsın mı?": "Move the originals to the trash?",
    "Şifreli kopyaları kasaya güvenle yazıldı: {names}\n\nOrijinaller sistemin çöp kutusuna taşınır (kalıcı silinmez).":
        "Their encrypted copies were safely written to the vault: {names}\n\n"
        "The originals are moved to the system trash (not permanently deleted).",
    "Çöpe Taşı": "Move to Trash",
    "Lisans için depodaki LICENSE dosyasına bakın.": "See the LICENSE file in the repository for the license.",
    "Dosyalar, notlar ve parolalar için şifreli, taşınabilir kasa.\n"
    "AES-256-GCM + Argon2id. macOS sürümüyle aynı kasayı açar.":
        "Encrypted, portable vault for files, notes and passwords.\n"
        "AES-256-GCM + Argon2id. Opens the same vault as the macOS version.",
    "Genel": "General",
    "Kasayı kilitle": "Lock the vault",
    "Çıkış": "Quit",
    "Dosyalar / Notlar / Parolalar / Çöp": "Files / Notes / Passwords / Trash",
    "Dosya ekle": "Add files",
    "Yeni klasör": "New folder",
    "Ara": "Search",
    "Seçileni çöpe taşı": "Move selection to trash",
    "Üst klasör": "Parent folder",
    "Notlar ve parolalar": "Notes and passwords",
    "Yeni not / kayıt": "New note / entry",

    # İletişim kutuları
    "Kasa parolası": "Vault password",

    # Karşılama, kasa oluşturma, kilit ekranı
    "Dosyaların, notların ve parolaların için\nşifreli, taşınabilir bir kasa.":
        "An encrypted, portable vault\nfor your files, notes and passwords.",
    "Yeni Kasa Oluştur": "Create New Vault",
    "Yeni Kasa Oluştur…": "Create New Vault…",
    "Var Olan Kasayı Aç…": "Open Existing Vault…",
    "Başka Kasa Aç…": "Open Another Vault…",
    "Anahtar Dosyası İçe Aktar…": "Import Keyfile…",
    "Kasa klasörünü seç": "Choose the vault folder",
    "macOS'ta oluşturulan kasalar da açılır: kasa klasörünü seçmeniz yeterli.":
        "Vaults created on macOS open too: just choose the vault folder.",
    "Yeni kasa": "New vault",
    "Konum": "Location",
    "Kasanın oluşturulacağı klasörü seç": "Choose where to create the vault",
    "Ana parola": "Master password",
    "En az {minimum} karakter. Rastgele seçilmiş 5+ kelime veya 12+ rastgele karakter önerilir.":
        "At least {minimum} characters. 5+ randomly chosen words or 12+ random characters are recommended.",
    "Parola": "Password",
    "Parola (tekrar)": "Password (again)",
    "Bu parolayı unutursam kasadaki verilerin hiçbir şekilde kurtarılamayacağını anlıyorum.":
        "I understand that if I forget this password, the data in the vault cannot be recovered in any way.",
    "Kasayı Oluştur": "Create Vault",
    "Parolalar eşleşmiyor": "Passwords do not match",
    "Bu konumda zaten bir kasa var": "There is already a vault at this location",
    "Klasör boş değil": "Folder is not empty",
    "Kasa boş bir klasöre ya da yeni bir klasöre oluşturulmalı.":
        "A vault must be created in an empty folder or a new one.",
    "Kasa oluşturulamadı": "Could not create the vault",
    "Kilidi aç": "Unlock",
    "Caps Lock açık": "Caps Lock is on",
    "Anahtar türetiliyor…": "Deriving key…",
    "Anahtar dosyasını seç": "Choose the keyfile",

    # Dosyalar
    "Dosya ekle (Ctrl+O)": "Add files (Ctrl+O)",
    "Kasaya klasör ekle": "Add a folder to the vault",
    "Yeni klasör (Ctrl+Shift+N)": "New folder (Ctrl+Shift+N)",
    "Ara (Ctrl+F)": "Search (Ctrl+F)",
    "Görünümü değiştir": "Switch view",
    "Yedekle": "Back Up",
    "Kasada ara": "Search the vault",
    "Yalnızca favoriler": "Favorites only",
    "Etikete göre süz": "Filter by tag",
    "Bu klasör boş": "This folder is empty",
    "Kasa boş": "The vault is empty",
    "Dosyaları buraya sürükleyin ya da + düğmesiyle ekleyin.\nHer şey eklenirken bu bilgisayarda şifrelenir.":
        "Drag files here or add them with the + button.\nEverything is encrypted on this computer as it is added.",
    "Sonuç yok": "No results",
    "Aramayı veya filtreleri değiştirin.": "Try a different search or filters.",
    "Favoriler": "Favorites",
    "Favori": "Favorite",
    "Arama: {query}": "Search: {query}",
    "Tüm dosyalar": "All files",
    "Çöp kutusuna taşı (Delete)": "Move to trash (Delete)",
    "Etiketler": "Tags",
    "Etiketler…": "Tags…",
    "Taşı": "Move",
    "Taşı…": "Move…",
    "Dışa aktar": "Export",
    "Dışa Aktar": "Export",
    "Dışa Aktar…": "Export…",
    "Yeniden Adlandır": "Rename",
    "Yeniden Adlandır…": "Rename…",
    "Çöp Kutusuna Taşı": "Move to Trash",
    "Önizle": "Preview",
    "Geçici Olarak Aç": "Open Temporarily",
    "Geçici olarak aç": "Open temporarily",
    "Taşınamadı": "Could not move",
    "Bir klasör kendi içine taşınamaz.": "A folder cannot be moved into itself.",
    "Taşındı: {name}": "Moved to {name}",
    "Kasaya eklenecek klasörleri seç": "Choose folders to add to the vault",
    "Kasaya eklenecek dosyaları seç": "Choose files to add to the vault",
    "Şifrele ve Ekle": "Encrypt and Add",
    "Klasörü yeniden adlandır": "Rename folder",
    "Dosyayı yeniden adlandır": "Rename file",
    "Etiketleri virgülle ayırın. Hepsini silmek için alanı boşaltıp kaydedin.":
        "Separate tags with commas. To remove them all, clear the field and save.",
    "Hedef klasörü seçin.": "Choose the destination folder.",
    "Şifresi çözülmüş kopyaların kaydedileceği klasör": "Folder to save the decrypted copies to",
    "Şifresi çözülmüş kopyanın kaydedileceği klasör": "Folder to save the decrypted copy to",
    "Dosya geçici olarak açılsın mı?": "Open the file temporarily?",
    "Dosyanın şifresiz bir kopyası oturumun geçici klasörüne yazılır ve kasa kilitlenince ya da "
    "uygulama kapanınca silinir. Açan uygulama kendi önbelleğinde iz bırakabilir.":
        "An unencrypted copy of the file is written to the session's temporary folder and deleted when the vault "
        "is locked or the app closes. The app that opens it may leave traces in its own cache.",
    "Bir daha sorma": "Don't ask again",
    "Dosya çözülemedi": "Could not decrypt the file",
    "Bu görsel biçimi önizlenemiyor.": "This image format cannot be previewed.",
    "Bu dosya türü uygulama içinde önizlenemiyor.\nGeçici olarak açabilir ya da dışa aktarabilirsiniz.":
        "This file type cannot be previewed in the app.\nYou can open it temporarily or export it.",
    "Eklendi: {date}": "Added: {date}",

    # Notlar
    "Notlarda ara": "Search notes",
    "Yeni not (Ctrl+N)": "New note (Ctrl+N)",
    "Sabitle": "Pin",
    "Renk": "Color",
    "Çöp kutusuna taşı": "Move to trash",
    "Not": "Note",
    "Başlık": "Title",
    "Not seçilmedi": "No note selected",
    "Soldan bir not seçin ya da yeni bir not ekleyin.": "Select a note on the left or add a new one.",
    "Başlıksız not": "Untitled note",
    "Düzenlendi: {date}": "Edited: {date}",
    "Oluşturuldu: {date}": "Created: {date}",
    "Not çöp kutusuna taşındı": "Note moved to trash",

    # Parolalar
    "Hesap": "Login",
    "Kart": "Card",
    "Sunucu": "Server",
    "Gizli not": "Secure note",
    "Diğer": "Other",
    "Tümü": "All",
    "Parolalarda ara": "Search passwords",
    "Yeni kayıt (Ctrl+N)": "New entry (Ctrl+N)",
    "Kayıt": "Entry",
    "Bir kayıt seç": "Select an entry",
    "Henüz parola kaydı yok": "No password entries yet",
    "Hesap, kart, Wi-Fi ve sunucu bilgilerini şifreli saklayın.":
        "Keep login, card, Wi-Fi and server details encrypted.",
    "Tür": "Type",
    "Kullanıcı adı / e-posta": "Username / email",
    "Güçlü parola üret": "Generate a strong password",
    "Adres (URL)": "Address (URL)",
    "Tarayıcıda aç": "Open in browser",
    "Parola üretici ayarları": "Password generator settings",
    "Uzunluk": "Length",
    "Büyük harf": "Uppercase",
    "Küçük harf": "Lowercase",
    "Rakam": "Digits",
    "Simge": "Symbols",
    "Karışabilen karakterleri kullanma (O0Il1)": "Avoid look-alike characters (O0Il1)",
    "Parola kopyalandı": "Password copied",
    "{label} · {seconds} sn sonra panodan silinecek": "{label} · clears from clipboard in {seconds} s",
    "Kayıt çöp kutusuna taşındı": "Entry moved to trash",

    # Çöp kutusu
    "Boşalt": "Empty",
    "Çöp kutusu boş": "Trash is empty",
    "Çöp kutusu boşaltılsın mı?": "Empty the trash?",
    "İçindeki her şey kalıcı olarak silinir; bu geri alınamaz.":
        "Everything in it is permanently deleted; this cannot be undone.",
    "Kalıcı Olarak Sil": "Delete Permanently",
    "Kalıcı olarak sil": "Delete permanently",
    "Geri yükle": "Restore",
    "Geri yüklendi": "Restored",
    "Çöp kutusundaki öğeler {n} gün sonra kalıcı olarak silinir.":
        ("Items in the trash are permanently deleted after {n} day.",
         "Items in the trash are permanently deleted after {n} days."),
    "Çöp kutusundaki öğeler siz boşaltana kadar saklanır.": "Items in the trash are kept until you empty it.",
    "Silindi: {date}": "Deleted: {date}",
    "“{name}” kalıcı olarak silinsin mi?": "Permanently delete “{name}”?",
    "Bu işlem geri alınamaz.": "This cannot be undone.",
    "Çöp kutusuna taşındı": "Moved to trash",
    "{n} dosya çöp kutusuna taşındı": ("{n} file moved to trash", "{n} files moved to trash"),
    "Klasör çöp kutusuna taşındı": "Folder moved to trash",
    "Çöp kutusu boşaltıldı": "Trash emptied",

    # Ayarlar
    "Görünüm": "Appearance",
    "Kasa adı": "Vault name",
    "Tema": "Theme",
    "Açık": "Light",
    "Koyu": "Dark",
    "Vurgu rengi": "Accent color",
    "Not yazı tipi": "Note font",
    "Not yazı boyutu": "Note font size",
    "Serif": "Serif",
    "Yuvarlak": "Rounded",
    "Eş aralıklı": "Monospaced",
    "Güvenlik": "Security",
    "Hareketsizlikte otomatik kilit (dakika)": "Auto-lock when idle (minutes)",
    "0 = kapalı": "0 = off",
    "Uykuda ve ekran kilitlenince kilitle": "Lock on sleep and screen lock",
    "Kopyalanan parolayı panodan sil (saniye)": "Clear copied password from clipboard (seconds)",
    "0 = silme": "0 = never",
    "Şifreleme": "Encryption",
    "Parolayı Değiştir…": "Change Password…",
    "Parolayı değiştir": "Change password",
    "Dosyalar yeniden şifrelenmez; ana anahtar yeni parolayla yeniden sarılır.":
        "Files are not re-encrypted; the master key is re-wrapped with the new password.",
    "Mevcut parola": "Current password",
    "Yeni parola (en az {minimum} karakter)": "New password (at least {minimum} characters)",
    "Yeni parola (tekrar)": "New password (again)",
    "Parola değiştirilemedi": "Could not change the password",
    "Parola değiştirildi": "Password changed",
    "Parola değiştiriliyor": "Changing password",
    "Yanlış parola sınırı": "Wrong-password limit",
    "Açıkken art arda bu kadar yanlış parola girilirse kasanın anahtarları yok edilir ve kasadaki "
    "her şey kalıcı olarak açılamaz hale gelir; geri alınamaz. Sayaç doğru parolayla açılınca "
    "sıfırlanır. Anahtar dosyalı bir kasayı başka bir bilgisayarda açmaya çalışmak da yanlış "
    "deneme sayılır. Yedekler bu ayardan etkilenmez.":
        "When on, entering this many wrong passwords in a row destroys the vault's keys and everything in the "
        "vault becomes permanently unreadable; this cannot be undone. The counter resets when the vault is "
        "unlocked with the correct password. Trying to open a keyfile-protected vault on another computer also "
        "counts as a wrong attempt. Backups are not affected by this setting.",
    "Yanlış parolada kasayı kalıcı olarak sil": "Permanently erase the vault on wrong passwords",
    "Deneme sayısı": "Number of attempts",
    "Yanlış parola sınırı açılsın mı?": "Turn on the wrong-password limit?",
    "Art arda {n} yanlış parola girilirse kasa kalıcı olarak silinir ve hiçbir şekilde geri "
    "getirilemez. Deneme sayısını sonra değiştirebilirsiniz. Güncel bir yedeğiniz olduğundan emin olun.":
        "If {n} wrong passwords are entered in a row, the vault is permanently erased and cannot be recovered "
        "in any way. You can change the number of attempts later. Make sure you have an up-to-date backup.",
    "{n} Yanlış Denemede Sil": "Erase After {n} Wrong Attempts",
    "Ayar kaydedilemedi": "Could not save the setting",
    "Anahtar dosyası": "Keyfile",
    "Etkinleştirilirse kasa parola ile birlikte bu bilgisayarda saklanan rastgele bir dosya "
    "ister. Başka bir bilgisayarda açmak için anahtar dosyasını dışa aktarıp orada içe "
    "aktarın. Anahtar dosyası kaybolursa kasa açılamaz; yedeğini alın.":
        "When enabled, the vault requires a random file stored on this computer in addition to the password. "
        "To open it on another computer, export the keyfile and import it there. If the keyfile is lost, the "
        "vault cannot be opened; keep a backup of it.",
    "Etkin: kasa parola + bu bilgisayardaki anahtar dosyasıyla açılıyor":
        "On: the vault opens with the password + the keyfile on this computer",
    "Kapalı: kasa yalnızca parolayla açılıyor": "Off: the vault opens with the password only",
    "Etkinleştir": "Turn On",
    "Etkinleştir…": "Turn On…",
    "Anahtar dosyasını dışa aktar": "Export the keyfile",
    "Yedek almak veya başka bir bilgisayara taşımak için": "To back it up or move it to another computer",
    "Anahtar dosyası kapatılsın mı?": "Turn off the keyfile?",
    "Kasa bundan sonra yalnızca parolayla açılır. Mevcut anahtar dosyası silinmez, arşivlenir.":
        "From now on the vault opens with the password only. The current keyfile is archived, not deleted.",
    "Anahtar dosyası etkinleştirilsin mi?": "Turn on the keyfile?",
    "Bu bilgisayarda rastgele bir anahtar dosyası oluşturulur ve kasa bundan sonra parola "
    "ile birlikte bu dosyayı ister. Başka bilgisayarlarda açmak için dosyayı dışa "
    "aktarmanız gerekir.":
        "A random keyfile is created on this computer, and from now on the vault requires it in addition to the "
        "password. To open the vault on other computers you will need to export the file.",
    "Anahtar dosyası değiştirilemedi": "Could not change the keyfile setting",
    "Anahtar dosyası kapatıldı": "Keyfile turned off",
    "Anahtar dosyası etkinleştirildi": "Keyfile turned on",
    "Anahtar dosyasını kaydet": "Save the keyfile",
    "Çöp kutusu": "Trash",
    "Öğeleri şu kadar gün sonra kalıcı sil": "Permanently delete items after this many days",
    "Ekledikten sonra orijinalleri çöpe taşımayı sor": "Ask to move originals to the trash after adding",
    "Yedekleme": "Backup",
    "Şifreli dosyalar olduğu gibi kopyalanır; yedek aynı parolayla açılır. Yalnızca değişen dosyalar kopyalanır.":
        "Encrypted files are copied as they are; the backup opens with the same password. "
        "Only changed files are copied.",
    "Yedek konumu": "Backup location",
    "Seçilmedi": "Not chosen",
    "Son yedek": "Last backup",
    "Hiç": "Never",
    "Şimdi Yedekle": "Back Up Now",
    "Son yedekten bu kadar gün sonra hatırlat": "Remind this many days after the last backup",
    "0 = hatırlatma": "0 = no reminder",
    "Yedeğin konulacağı klasörü seç": "Choose a folder for the backup",
    "Bakım": "Maintenance",
    "Bütünlük taraması": "Integrity check",
    "Her dosyayı çözerek doğrular; bozuk olanları yedekten geri yükler.":
        "Verifies every file by decrypting it; restores damaged ones from the backup.",
    "Tara": "Check",
    "Kasa konumu": "Vault location",
    "Dosya yöneticisinde göster": "Show in file manager",
    "İçerik": "Contents",

    # Bütünlük raporu
    "Her şey yolunda": "Everything is fine",
    "Hiçbir sorun bulunmadı.": "No problems found.",
    "eksik": "missing",
    "bozuk": "damaged",
    "içerik özeti tutmuyor": "content hash does not match",
    "… ve {n} dosya daha": ("… and {n} more file", "… and {n} more files"),
    "{n} küçük resim okunamadı (kaldırıldı).":
        ("{n} thumbnail could not be read (removed).", "{n} thumbnails could not be read (removed)."),
    "Dizin yedeği (index.enc.bak) okunamıyor; bir sonraki kayıtta yenilenecek.":
        "The index backup (index.enc.bak) cannot be read; it will be rewritten on the next save.",
    "Tarama sonucu": "Check result",
    "Sahipsizleri Sil": "Delete Orphans",
    "Yedekten Geri Yükle": "Restore from Backup",
    "Sahipsiz dosyalar silinsin mi?": "Delete orphaned files?",
    "Bunlar dizinde kaydı olmayan şifreli dosyalardır (ör. yarım kalmış eklemeler).":
        "These are encrypted files with no entry in the index (e.g. interrupted imports).",
    "Bazı dosyalar geri yüklenemedi": "Some files could not be restored",
    "Yedekten geri yüklendi": "Restored from backup",
    "{n} sahipsiz dosya silindi": ("{n} orphaned file deleted", "{n} orphaned files deleted"),
    "Her dosya çözülerek doğrulanıyor…": "Verifying every file by decrypting it…",
    "Tarama durduruldu": "Check stopped",
    "Tarama yapılamadı": "Could not run the check",

    # Kasa durumu ve uzun işlemler
    "Kasa bulunamadı": "Vault not found",
    "Kasa oluşturuluyor": "Creating vault",
    "Kasa seçilmedi.": "No vault selected.",
    "Kasa silindi.": "Vault erased.",
    "Parola yanlış. Son deneme hakkı: bir yanlış daha kasayı siler.":
        "Wrong password. Last attempt: one more wrong password erases the vault.",
    "Parola yanlış. Kalan deneme: {remaining}": "Wrong password. Attempts left: {remaining}",
    "Kasa kalıcı olarak silindi": "Vault permanently erased",
    "Yanlış parola sınırı aşıldığı için kasanın anahtarları yok edildi. Kasadaki veriler artık "
    "hiçbir parolayla açılamaz. Klasörde kalan şifreli dosyalar işe yaramaz; silebilirsiniz.":
        "The vault's keys were destroyed because the wrong-password limit was exceeded. The data in the vault "
        "can no longer be opened with any password. The encrypted files left in the folder are useless; you "
        "can delete them.",
    "Dizin yedekten kurtarıldı": "Index recovered from backup",
    "Kasanın dizin dosyası okunamadı; bir önceki sürümü (index.enc.bak) kullanıldı. "
    "Son değişikliklerden bazıları eksik olabilir.":
        "The vault's index file could not be read; its previous version (index.enc.bak) was used. "
        "Some recent changes may be missing.",
    "Kasa kaydedilemedi": "Could not save the vault",
    "Eklenecek dosya yok": "No files to add",
    "Gizli dosyalar, kısayollar (sembolik bağlantılar) ve okunamayan öğeler "
    "kasaya eklenmez.":
        "Hidden files, shortcuts (symbolic links) and unreadable items are not added to the vault.",
    "Şifreleniyor": "Encrypting",
    "Şifreleniyor ({done}/{total})": "Encrypting ({done}/{total})",
    "Dosyalar eklenemedi": "Could not add the files",
    "Eklenemeyenler:": "Could not be added:",
    "{n} öğe eklenmedi (gizli dosya, kısayol veya okunamayan öğe).":
        ("{n} item was not added (hidden file, shortcut or unreadable item).",
         "{n} items were not added (hidden files, shortcuts or unreadable items)."),
    "{n} dosya kasada zaten vardı: {names}":
        ("{n} file was already in the vault: {names}", "{n} files were already in the vault: {names}"),
    "{n} dosya şifrelendi": ("{n} file encrypted", "{n} files encrypted"),
    "Durduruldu · {n} dosya eklendi": ("Stopped · {n} file added", "Stopped · {n} files added"),
    "Bazı orijinaller çöpe taşınamadı": "Some originals could not be moved to the trash",
    "Orijinaller çöp kutusuna taşındı": "Originals moved to the trash",
    "Dışa aktarılıyor": "Exporting",
    "Bazı dosyalar aktarılamadı": "Some files could not be exported",
    "{n} dosya dışa aktarıldı": ("{n} file exported", "{n} files exported"),
    "Dışa aktarılamadı": "Could not export",
    "Açılıyor": "Opening",
    "Açılamadı": "Could not open",
    "Bu bilgisayarda bu kasa için zaten bir anahtar dosyası var. Bu kopya büyük olasılıkla anahtar "
    "dosyası eklenmeden önce alınmış bir yedek; asıl kasayı açıp oradan yönetin.":
        "This computer already has a keyfile for this vault. This copy is most likely a backup made before the "
        "keyfile was added; open the main vault and manage it from there.",
    "Anahtar dosyası kaydedilemedi: {error}": "Could not save the keyfile: {error}",
    "Anahtar dosyası ekleniyor": "Adding keyfile",
    "Anahtar dosyası kaldırılıyor": "Removing keyfile",
    "Anahtar dosyası dışa aktarıldı": "Keyfile exported",
    "Geçersiz anahtar dosyası": "Invalid keyfile",
    "Mahzen anahtar dosyaları tam 64 bayttır.": "Mahzen keyfiles are exactly 64 bytes.",
    "Anahtar dosyası bu bilgisayara kaydedildi": "Keyfile saved on this computer",
    "Anahtar dosyası alınamadı": "Could not import the keyfile",
    "Yedek diski bağlı değil": "Backup disk is not connected",
    "Yedek konumu bulunamadı:\n{path}\n\nYedek diskini bağlayın ya da Ayarlar'dan yeni bir konum seçin.":
        "Backup location not found:\n{path}\n\nConnect the backup disk or choose a new location in Settings.",
    "Yedek konumu seçilmedi.": "No backup location chosen.",
    "Yedekleniyor": "Backing up",
    "Yedekleme durduruldu": "Backup stopped",
    "Yedeklenemedi": "Could not back up",
    "Yedeklendi · {copied} yeni, {unchanged} değişmemiş": "Backed up · {copied} new, {unchanged} unchanged",
    "Yedeklendi, ama eksik dosyalar var": "Backed up, but some files are missing",
    "{n} dosyanın şifreli içeriği kasada bulunamadı; "
    "yedekteki kopyaları korundu. Bütünlük taraması yapın.":
        ("The encrypted content of {n} file was not found in the vault; its copy in the backup was kept. "
         "Run an integrity check.",
         "The encrypted content of {n} files was not found in the vault; their copies in the backup were kept. "
         "Run an integrity check."),

    # Telefonda Göster
    "Telefonda Göster": "Show on Phone",
    "Telefonda Göster…": "Show on Phone…",
    "Telefonda göster": "Show on phone",
    "{n} öğe": ("{n} item", "{n} items"),
    "{n} fotoğraf": ("{n} photo", "{n} photos"),
    "{n} video": ("{n} video", "{n} videos"),
    "Gösterilecek fotoğraf ya da video yok": "No photos or videos to show",
    "Telefonda yalnızca fotoğraflar ve videolar gösterilebilir.": "Only photos and videos can be shown on the phone.",
    "Başlatılıyor…": "Starting…",
    "Paylaşım QR kodu": "Sharing QR code",
    "Telefon bağlanamayabilir": "Your phone may not be able to connect",
    "Bu bilgisayar bir sanal makine gibi görünüyor ve paylaşım adresi ({address}) sanal makinenin kendi özel "
    "ağında. Wi-Fi'deki telefon bu adrese büyük olasılıkla ulaşamaz. Sanal makinenin ağ ayarını köprü (bridged) "
    "moduna alıp paylaşımı yeniden başlatın.":
        "This computer looks like a virtual machine, and the sharing address ({address}) is on the virtual "
        "machine's own private network. A phone on Wi-Fi most likely can't reach it. Switch the virtual "
        "machine's network to bridged mode and start sharing again.",
    "Telefonun kamerasıyla okutun": "Scan with your phone's camera",
    "Telefon bu bilgisayarla aynı Wi-Fi ağında olmalı. Dosyalar şifreli gelir, anahtar yalnızca bu QR kodda bulunur.":
        "The phone must be on the same Wi-Fi network as this computer. Files arrive encrypted; the key exists only "
        "in this QR code.",
    "{time} kaldı": "{time} left",
    "Henüz bağlanan yok": "No one connected yet",
    "{n} cihaz bağlandı": ("{n} device connected", "{n} devices connected"),
    "Uçtan uca şifreli · internete çıkmaz": "End-to-end encrypted · never leaves your network",
    "Paylaşım başlatılamadı": "Couldn't start sharing",
    "Paylaşım başlatılamadı: {error}": "Couldn't start sharing: {error}",
    "Bu bilgisayar bir Wi-Fi ya da yerel ağa bağlı görünmüyor. Telefonla aynı ağa bağlanıp yeniden deneyin.":
        "This computer doesn't appear to be on Wi-Fi or a local network. Join the same network as the phone and "
        "try again.",
    "Paylaşım sona erdi": "Sharing ended",
    "Telefondaki sayfa artık açılmaz. Yeniden göstermek için yeni bir QR kod oluşturun.":
        "The page on the phone no longer opens. Create a new QR code to show the files again.",
    "akış kesik": "stream is truncated",
    "akış boş": "stream is empty",

    # Önizlemede gezinme
    "Önceki (←)": "Previous (←)",
    "Sonraki (→)": "Next (→)",
    "Önizlemede önceki / sonraki dosya": "Previous / next file in preview",

    # Telefondan Ekle
    "Telefondan Ekle": "Add from Phone",
    "Telefondan Ekle…": "Add from Phone…",
    "Dosya Seç…": "Choose Files…",
    "Diğer ekleme yolları": "More ways to add",
    "Açılan sayfada fotoğraf, video ya da dosya seçin. Dosyalar telefonda şifrelenir ve kasaya şifreli olarak "
    "yazılır; telefon bu bilgisayarla aynı Wi-Fi ağında olmalı.":
        "Choose photos, videos or files on the page that opens. Files are encrypted on the phone and written to "
        "the vault encrypted; the phone must be on the same Wi-Fi network as this computer.",
    "Oturum başlatılamadı": "Couldn't start the session",
    "Oturum başlatılamadı: {error}": "Couldn't start the session: {error}",
    "Oturum sona erdi": "Session ended",
    "Telefondaki sayfa artık dosya gönderemez. Yeniden eklemek için yeni bir QR kod oluşturun.":
        "The page on the phone can no longer send files. To add more, create a new QR code.",
    "{n} dosya eklendi": ("{n} file added", "{n} files added"),
    "{n} dosya telefondan eklendi": ("{n} file added from the phone", "{n} files added from the phone"),
    "Kasaya eklendi": "Added to the vault",
    "Kasada zaten vardı": "Already in the vault",
    "Telefonda durduruldu": "Stopped on the phone",
    "Telefondan veri gelmedi": "No data arrived from the phone",
    "Bağlantı koptu": "Connection lost",
    "Doğrulanamadı": "Failed verification",
    "Dosya çok büyük": "File is too large",
    "Diskte yer yok": "Not enough disk space",
    "Kasaya yazılamadı": "Couldn't write to the vault",
    "Geçersiz istek": "Invalid request",
    "akış bozuk": "stream is corrupted",
}
