/// Türkçe kaynak metin → İngilizce karşılığı. Sayıya göre değişen metinlerde "tekil|çoğul".
let englishStrings: [String: String] = [
    "Parola yanlış.":
        "Wrong password.",
    "Kasa verisi doğrulanamadı: {0}":
        "The vault data couldn't be verified: {0}",
    "Bu klasör bir Mahzen kasası değil.":
        "This folder isn't a Mahzen vault.",
    "Bu konumda zaten bir kasa var.":
        "There's already a vault at this location.",
    "Bu kasa daha yeni bir Mahzen sürümüyle oluşturulmuş (biçim {0}).":
        "This vault was created with a newer version of Mahzen (format {0}).",
    "Anahtar türetilemedi.":
        "The key couldn't be derived.",
    "Parola en az {0} karakter olmalı.":
        "The password must be at least {0} characters.",
    "deneme sınırı {0}–{1} arasında olmalı":
        "the attempt limit must be between {0} and {1}",
    "dosya başlığı geçersiz":
        "invalid file header",
    "parça boyutu geçersiz":
        "invalid chunk size",
    "dosya kesik":
        "file is truncated",
    "içerik doğrulanamadı (bozulmuş, değiştirilmiş veya yanlış anahtar)":
        "content failed verification (corrupted, modified, or wrong key)",
    "beklenmeyen dosya sonu":
        "unexpected end of file",
    "içerik doğrulanamadı":
        "content failed verification",
    "Argon2id ayarları eksik":
        "Argon2id parameters are missing",
    "bilinmeyen anahtar türetme yöntemi: {0}":
        "unknown key derivation method: {0}",
    "yedek konumu kasanın kendisi veya içi olamaz":
        "the backup location can't be the vault itself or inside it",
    "seçilen klasörde başka bir kasa var":
        "the selected folder contains a different vault",
    "yedek bu kasaya ait değil":
        "the backup doesn't belong to this vault",
    "akış kesik":
        "stream is truncated",
    "akış boş":
        "stream is empty",
    "vault.json okunamadı":
        "vault.json couldn't be read",
    "anahtar dosyası çok kısa":
        "keyfile is too short",
    "dizin dosyası bulunamadı":
        "index file not found",
    "dizin doğrulanamadı":
        "index failed verification",
    "Argon2id · {0} MB · {1} geçiş · {2} iş parçacığı":
        "Argon2id · {0} MB · {1} passes · {2} threads",
    "PBKDF2-HMAC-SHA512 · {0} tur":
        "PBKDF2-HMAC-SHA512 · {0} iterations",
    "Yeni Klasör":
        "New Folder",
    "Çok zayıf":
        "Very weak",
    "Zayıf":
        "Weak",
    "Orta":
        "Fair",
    "Güçlü":
        "Strong",
    "Çok güçlü":
        "Very strong",
    "Dosyalar":
        "Files",
    "Notlar":
        "Notes",
    "Parolalar":
        "Passwords",
    "Çöp Kutusu":
        "Trash",
    "Ayarlar":
        "Settings",
    "Kasa":
        "Vault",
    "Kilitle":
        "Lock",
    "Dosya Ekle…":
        "Add Files…",
    "Yeni Not":
        "New Note",
    "Anahtar Dosyası İçe Aktar…":
        "Import Keyfile…",
    "Şimdi Yedekle":
        "Back Up Now",
    "Bütünlük Taraması…":
        "Integrity Check…",
    "Yeni Parola Kaydı":
        "New Password Entry",
    "Kasa bulunamadı":
        "Vault Not Found",
    "Kasa oluşturuluyor":
        "Creating vault",
    "Bu Mac için anahtar türetme gücü ayarlanıyor…":
        "Tuning key derivation strength for this Mac…",
    "Kasa oluşturulamadı":
        "Couldn't Create the Vault",
    "Kasa seçilmedi.":
        "No vault selected.",
    "Kasa silindi.":
        "The vault has been wiped.",
    "Parola yanlış. Son deneme hakkı: bir yanlış daha kasayı siler.":
        "Wrong password. Last attempt: one more wrong password wipes the vault.",
    "Parola yanlış. Kalan deneme: {0}":
        "Wrong password. Attempts left: {0}",
    "Kasa kalıcı olarak silindi":
        "The Vault Was Permanently Wiped",
    "Yanlış parola sınırı aşıldığı için kasanın anahtarları yok edildi. Kasadaki veriler artık hiçbir parolayla açılamaz. Klasörde kalan şifreli dosyalar işe yaramaz; silebilirsiniz.":
        "The wrong-password limit was exceeded, so the vault's keys were destroyed. Its contents can no longer be opened with any password. The encrypted files left in the folder are useless; you can delete them.",
    "Ayar kaydedilemedi":
        "Couldn't Save the Setting",
    "Kasa kilitli.":
        "The vault is locked.",
    "Bu Mac'te bu kasa için zaten bir anahtar dosyası var. Açtığın kasa, anahtar dosyası eklenmeden önce alınmış bir yedek olabilir. Asıl kasayı korumak için işlem yapılmadı; asıl kasayı açıp oradan devam et.":
        "This Mac already has a keyfile for this vault. The vault you opened may be a backup made before the keyfile was added. Nothing was changed, to protect the original vault; open the original and continue from there.",
    "Anahtar dosyası bu Mac'e kaydedilemedi: {0}":
        "The keyfile couldn't be saved on this Mac: {0}",
    "Kasa artık yalnızca parolayla açılıyor":
        "The vault now opens with the password alone",
    "Anahtar dosyasının yedeği":
        "Keyfile Backup",
    "SSD'den ayrı, güvendiğin bir yere kaydet. Dosya adı içeriği belli etmesin.":
        "Save it somewhere you trust, away from the SSD. Pick a file name that doesn't give away what it is.",
    "Bu konum seçilemez":
        "This Location Can't Be Used",
    "Anahtar dosyasının yedeği kasayla aynı diskte olursa koruma anlamını yitirir.":
        "A keyfile backup on the same disk as the vault defeats the purpose of the protection.",
    "Kaydedilemedi":
        "Couldn't Save",
    "Anahtar dosyasının yedeği kaydedildi":
        "Keyfile backup saved",
    "Önce kasayı seç":
        "Choose a Vault First",
    "Anahtar dosyası, seçili kasa için içe aktarılır.":
        "The keyfile is imported for the selected vault.",
    "Anahtar dosyasını seç":
        "Choose the Keyfile",
    "Geçersiz dosya":
        "Invalid File",
    "Seçilen dosya bir Mahzen anahtar dosyası değil.":
        "The selected file isn't a Mahzen keyfile.",
    "Anahtar dosyası içe aktarıldı (öncekisi arşivlendi)":
        "Keyfile imported (the previous one was archived)",
    "Anahtar dosyası içe aktarıldı":
        "Keyfile imported",
    "İçe aktarılamadı":
        "Couldn't Import",
    "Parola değiştirildi":
        "Password changed",
    "SSD çıkarılmış olabilir.":
        "The SSD may have been disconnected.",
    "Kasaya eklenecek dosyaları seç":
        "Choose files to add to the vault",
    "Şifrele ve Ekle":
        "Encrypt and Add",
    "Eklenecek dosya yok":
        "Nothing to Add",
    "Gizli dosyalar, paketler (ör. Keynote belgeleri), kısayollar ve okunamayan öğeler kasaya eklenmez.":
        "Hidden files, packages (e.g. Keynote documents), aliases, and unreadable items aren't added to the vault.",
    "Şifreleniyor":
        "Encrypting",
    "Şifreleniyor ({0}/{1})":
        "Encrypting ({0}/{1})",
    "Eklenemeyenler:\n":
        "Couldn't be added:\n",
    "{0} öğe eklenmedi (gizli dosya, paket, kısayol veya okunamayan öğe); bunları içeren klasörlerin orijinalleri çöpe önerilmedi.":
        "{0} item wasn't added (hidden file, package, alias, or unreadable item); the original of the folder containing it wasn't offered for the Trash.|{0} items weren't added (hidden files, packages, aliases, or unreadable items); the originals of the folders containing them weren't offered for the Trash.",
    "{0} dosya kasada zaten vardı: ":
        "{0} file was already in the vault: |{0} files were already in the vault: ",
    "Durduruldu · {0} dosya eklendi":
        "Stopped · {0} file added|Stopped · {0} files added",
    "{0} dosya şifrelendi":
        "{0} file encrypted|{0} files encrypted",
    "Yedeğin tutulacağı yeri seç (tercihen başka bir disk)":
        "Choose where to keep the backup (preferably another disk)",
    "Burada Yedekle":
        "Back Up Here",
    "Yedek, kasanın kendi klasörünün içinde olamaz.":
        "The backup can't be inside the vault's own folder.",
    "Yedek, kasayla aynı diskte olacak":
        "The backup will be on the same disk as the vault",
    "Disk bozulur ya da kaybolursa kasa ve yedeği birlikte gider. Mümkünse başka bir disk seç.":
        "If the disk fails or is lost, the vault and its backup go together. Choose another disk if you can.",
    "Yine de Kullan":
        "Use Anyway",
    "Vazgeç":
        "Cancel",
    "Yedek diski bağlı değil":
        "Backup Disk Not Connected",
    "{0} bulunamadı. Diski bağlayıp tekrar dene ya da Ayarlar'dan konumu değiştir.":
        "{0} wasn't found. Connect the disk and try again, or change the location in Settings.",
    "Yedekleniyor":
        "Backing up",
    "Yedek alındı, ama {0} dosya kasada bulunamadı":
        "Backed up, but {0} file is missing from the vault|Backed up, but {0} files are missing from the vault",
    "Bu dosyaların yedekteki eski kopyaları korundu. Ayarlar → Bütünlük Taraması ile ayrıntıları gör ve yedekten geri yükle.":
        "The older copies of these files in the backup were kept. Go to Settings → Integrity Check to see the details and restore them from the backup.",
    "Yedek güncel":
        "Backup is up to date",
    "Yedeklendi: {0} dosya · {1}":
        "Backed up: {0} file · {1}|Backed up: {0} files · {1}",
    "Yedekleme durduruldu (önceki yedek bozulmadı)":
        "Backup stopped (the previous backup is intact)",
    "Yedeklenemedi":
        "Couldn't Back Up",
    "Bütünlük taraması":
        "Integrity check",
    "{0} dosya çözülerek doğrulanıyor":
        "Decrypting and verifying {0} file|Decrypting and verifying {0} files",
    "Tarama durduruldu":
        "Check stopped",
    "Tarama tamamlanamadı":
        "Couldn't Complete the Check",
    "Yedek konumu yok":
        "No backup location",
    "{0} artık dosya temizlendi":
        "{0} leftover file removed|{0} leftover files removed",
    "\"{0}\" orijinali Çöp Kutusu'na taşınsın mı?":
        "Move the original of “{0}” to the Trash?",
    "{0} öğenin orijinali Çöp Kutusu'na taşınsın mı?":
        "Move the originals of {0} items to the Trash?",
    "Şifreli kopyaları artık kasada. Orijinaller Mac'in Çöp Kutusu'na gider; tamamen silinmeleri için Çöp Kutusu'nu boşaltman gerekir.":
        "The encrypted copies are now in the vault. The originals go to the Mac's Trash; empty the Trash to remove them completely.",
    "Çöp Kutusu'na Taşı":
        "Move to Trash",
    "Orijinalleri Sakla":
        "Keep Originals",
    "Bir daha sorma (Ayarlar'dan açılabilir)":
        "Don't ask again (can be turned back on in Settings)",
    "Orijinaller taşınamadı":
        "Couldn't Move the Originals",
    "{0} orijinal Çöp Kutusu'na taşındı":
        "{0} original moved to the Trash|{0} originals moved to the Trash",
    "Taşındı: {0}":
        "Moved to {0}",
    "Şifresi çözülmüş kopyaların kaydedileceği klasör":
        "Folder for the decrypted copies",
    "Dışa Aktar":
        "Export",
    "Dışa aktarılıyor":
        "Exporting",
    "Dışa aktarma durduruldu":
        "Export stopped",
    "{0} dosya dışa aktarıldı":
        "{0} file exported|{0} files exported",
    "Bazı dosyalar aktarılamadı":
        "Some Files Couldn't Be Exported",
    "Dosya geçici olarak açılsın mı?":
        "Open the file temporarily?",
    "Dosyanın şifresiz bir kopyası bu Mac'in geçici klasörüne yazılır ve kasa kilitlenince ya da uygulama kapanınca silinir. Açan uygulama (ör. Önizleme) kendi önbelleğinde iz bırakabilir.":
        "An unencrypted copy of the file is written to this Mac's temporary folder and deleted when the vault locks or the app quits. The app that opens it (e.g. Preview) may leave traces in its own cache.",
    "Aç":
        "Open",
    "Bir daha sorma":
        "Don't ask again",
    "Açılıyor":
        "Opening",
    "Açılamadı":
        "Couldn't Open",
    "Çöp Kutusu'na taşındı":
        "Moved to Trash",
    "{0} dosya Çöp Kutusu'na taşındı":
        "{0} file moved to Trash|{0} files moved to Trash",
    "Klasör Çöp Kutusu'na taşındı":
        "Folder moved to Trash",
    "Taşınamadı":
        "Couldn't Move",
    "Bir klasör kendi içine taşınamaz.":
        "A folder can't be moved into itself.",
    "Çöp Kutusu boşaltıldı":
        "Trash emptied",
    "Not Çöp Kutusu'na taşındı":
        "Note moved to Trash",
    "Kayıt Çöp Kutusu'na taşındı":
        "Entry moved to Trash",
    "Kopyalandı":
        "Copied",
    "{0} · {1} sn sonra panodan silinecek":
        "{0} · clears from the clipboard in {1} sec",
    "Çivit":
        "Indigo",
    "Mavi":
        "Blue",
    "Turkuaz":
        "Teal",
    "Yeşil":
        "Green",
    "Turuncu":
        "Orange",
    "Pembe":
        "Pink",
    "Kırmızı":
        "Red",
    "Mor":
        "Purple",
    "Grafit":
        "Graphite",
    "Sistem":
        "System",
    "Açık":
        "Light",
    "Koyu":
        "Dark",
    "Yuvarlak":
        "Rounded",
    "Eş aralıklı":
        "Monospaced",
    "Hesap":
        "Login",
    "Kart":
        "Card",
    "Sunucu":
        "Server",
    "Gizli not":
        "Secure note",
    "Diğer":
        "Other",
    "Bu Mac bir Wi-Fi ya da yerel ağa bağlı görünmüyor. Telefonla aynı ağa bağlanıp yeniden deneyin.":
        "This Mac doesn't appear to be on Wi-Fi or a local network. Join the same network as the phone and try again.",
    "Paylaşım başlatılamadı: {0}":
        "Couldn't start sharing: {0}",
    "{0} öğe":
        "{0} item|{0} items",
    "Gösterilecek fotoğraf ya da video yok":
        "No Photos or Videos to Show",
    "Telefonda yalnızca fotoğraflar ve videolar gösterilebilir.":
        "Only photos and videos can be shown on the phone.",
    "Telefonda Göster":
        "Show on Phone",
    "Uçtan uca şifreli · internete çıkmaz":
        "End-to-end encrypted · never leaves your network",
    "Durdur":
        "Stop",
    "Kapat":
        "Close",
    "{0} fotoğraf":
        "{0} photo|{0} photos",
    "{0} video":
        "{0} video|{0} videos",
    "Başlatılıyor…":
        "Starting…",
    "Paylaşım QR kodu":
        "Sharing QR code",
    "iPhone'un kamerasıyla okutun":
        "Scan with your iPhone's camera",
    "Telefon bu Mac ile aynı Wi-Fi ağında olmalı. Dosyalar şifreli gelir, anahtar yalnızca bu QR kodda bulunur.":
        "The phone must be on the same Wi-Fi network as this Mac. Files arrive encrypted; the key exists only in this QR code.",
    "{0} kaldı":
        "{0} left",
    "Henüz bağlanan yok":
        "No one connected yet",
    "{0} cihaz bağlandı":
        "{0} device connected|{0} devices connected",
    "Paylaşım başlatılamadı":
        "Couldn't Start Sharing",
    "Paylaşım sona erdi":
        "Sharing Ended",
    "Telefondaki sayfa artık açılmaz. Yeniden göstermek için yeni bir QR kod oluşturun.":
        "The page on the phone no longer opens. Create a new QR code to show the files again.",
    "Gizle":
        "Hide",
    "Göster":
        "Show",
    "{0} kopyalandı":
        "{0} copied",
    "Kopyala":
        "Copy",
    "En yeni":
        "Newest",
    "En eski":
        "Oldest",
    "Ada göre":
        "By name",
    "En büyük":
        "Largest",
    "Tümü":
        "All",
    "Favoriler":
        "Favorites",
    "Görseller":
        "Images",
    "Videolar":
        "Videos",
    "Belgeler":
        "Documents",
    "Dosya":
        "File",
    "{0} dosya · {1}":
        "{0} file · {1}|{0} files · {1}",
    "Tüm kasada ara":
        "Search the whole vault",
    "Tüm kasa":
        "Whole vault",
    "{0} seçili":
        "{0} selected",
    "Filtre":
        "Filter",
    "Filtrele":
        "Filter",
    "Tüm etiketler":
        "All Tags",
    "Etiket":
        "Tag",
    "Etikete göre filtrele":
        "Filter by tag",
    "Sırala":
        "Sort",
    "Görünüm":
        "View",
    "Izgara":
        "Grid",
    "Liste":
        "List",
    "Yeni klasör":
        "New folder",
    "Ekle":
        "Add",
    "Dosya ekle (⌘O)":
        "Add files (⌘O)",
    "Şifrelemek için bırak → {0}":
        "Drop to encrypt → {0}",
    "Dosyaları buraya sürükle":
        "Drag files here",
    "Eklediğin her dosya, adıyla birlikte şifrelenip kasaya yazılır. Klasör sürüklersen yapısı korunur.":
        "Every file you add is encrypted, name included, and written to the vault. Drag in a folder and its structure is kept.",
    "Dosya Seç…":
        "Choose Files…",
    "Sonuç yok":
        "No Results",
    "Arama, filtre veya etiketle eşleşen dosya bulunamadı.":
        "No files match the search, filter, or tag.",
    "Klasör boş":
        "Empty Folder",
    "Dosyaları buraya sürükleyebilir ya da başka klasörlerden taşıyabilirsin.":
        "Drag files here or move them in from other folders.",
    "Ad":
        "Name",
    "Etiketler":
        "Tags",
    "Tür":
        "Kind",
    "Klasör":
        "Folder",
    "Boyut":
        "Size",
    "Eklenme":
        "Added",
    "Yeniden Adlandır…":
        "Rename…",
    "Renk":
        "Color",
    "Varsayılan":
        "Default",
    "Telefonda Göster…":
        "Show on Phone…",
    "Önizle":
        "Preview",
    "Geçici Olarak Aç":
        "Open Temporarily",
    "Bulunduğu Klasöre Git":
        "Go to Enclosing Folder",
    "Etiketler…":
        "Tags…",
    "Favorilerden Çıkar":
        "Remove from Favorites",
    "Favorilere Ekle":
        "Add to Favorites",
    "Dışa Aktar…":
        "Export…",
    "{0} Dosyayı Dışa Aktar…":
        "Export {0} Files…",
    "{0} Dosyayı Çöp Kutusu'na Taşı":
        "Move {0} Files to Trash",
    "Taşı":
        "Move to",
    "Dosyalar (en üst)":
        "Files (top level)",
    "{0} dosya":
        "{0} file|{0} files",
    "Henüz etiket yok. Aşağıdan ilk etiketini ekle.":
        "No tags yet. Add your first one below.",
    "Yeni etiket":
        "New tag",
    "Kaydet":
        "Save",
    "Önceki (←)":
        "Previous (←)",
    "Sonraki (→)":
        "Next (→)",
    "Geçici Aç":
        "Open Temporarily",
    "Şifre çözülüyor…":
        "Decrypting…",
    "Uygulama içi önizleme yok":
        "No In-App Preview",
    "Bu biçim ({0}) macOS tarafından oynatılamıyor. \"Geçici Aç\" ile başka bir oynatıcıda açabilirsin.":
        "macOS can't play this format ({0}). Use “Open Temporarily” to open it in another player.",
    "Bu tür dosyalar ({0}) uygulama içinde gösterilemiyor. \"Geçici Aç\" ile varsayılan uygulamasında açabilirsin.":
        "Files of this kind ({0}) can't be shown in the app. Use “Open Temporarily” to open it in its default app.",
    "Dosya önizleme için çok büyük. \"Geçici Aç\" veya \"Dışa Aktar\" kullan.":
        "The file is too large to preview. Use “Open Temporarily” or “Export”.",
    "Dosya içeriği okunamadı.":
        "The file's contents couldn't be read.",
    "Yeniden adlandır":
        "Rename",
    "Parola":
        "Password",
    "Kilidi aç (↩)":
        "Unlock (↩)",
    "Kilit açıldı":
        "Unlocked",
    "Mahzen kilitli":
        "Mahzen is locked",
    "Anahtar türetiliyor…":
        "Deriving key…",
    "Caps Lock açık":
        "Caps Lock is on",
    "Çevrimdışı":
        "Offline",
    "Başka bir kasa aç veya yeni oluştur":
        "Open another vault or create a new one",
    "Dosyaların, notların ve parolaların için\nşifreli, taşınabilir bir kasa.":
        "An encrypted, portable vault for\nyour files, notes, and passwords.",
    "Her şey şifreli":
        "Everything encrypted",
    "Dosya adları, notlar ve parolalar dahil; AES-256-GCM ve Argon2id.":
        "File names, notes, and passwords included; AES-256-GCM and Argon2id.",
    "Seninle taşınır":
        "Goes where you go",
    "Kasa, uygulamanın yanında SSD'de durur; her Mac'te açılır.":
        "The vault sits on the SSD next to the app and opens on any Mac.",
    "Tamamen çevrimdışı":
        "Fully offline",
    "Hiçbir şey internete gönderilmez, hesap gerekmez.":
        "Nothing is sent to the internet, and no account is needed.",
    "Yeni kasa oluştur":
        "Create a new vault",
    "Mevcut kasayı aç…":
        "Open an existing vault…",
    "Mahzen kasa klasörünü seç":
        "Choose the Mahzen vault folder",
    "En az {0} karakter":
        "At least {0} characters",
    "Parolalar eşleşmiyor":
        "Passwords don't match",
    "Yeni kasa":
        "New vault",
    "Konum":
        "Location",
    "Değiştir…":
        "Change…",
    "Ana parola":
        "Master password",
    "Parolayı tekrarla":
        "Repeat password",
    "Uzun bir cümle iyi bir paroladır: \"mor-kedi 7 kez çay demledi!\"":
        "A long phrase makes a good password: “purple-cat brewed tea 7 times!”",
    "Daha uzun bir parola önerilir.":
        "A longer password is recommended.",
    "Harika.":
        "Great.",
    "Bu parolayı unutursam kasadaki verilerin **hiçbir şekilde** kurtarılamayacağını anlıyorum.":
        "I understand that if I forget this password, the data in the vault **cannot be recovered in any way**.",
    "Kasayı Oluştur":
        "Create Vault",
    "Kasanın oluşturulacağı yer (ör. SSD)":
        "Where to create the vault (e.g. an SSD)",
    "Burada Oluştur":
        "Create Here",
    "Dizin dosyası okunamadı; son yedekten geri yüklendi. En son birkaç değişiklik eksik olabilir.":
        "The index file couldn't be read, so it was restored from the last backup copy. Your most recent changes may be missing.",
    "Tamam":
        "OK",
    "{0} şifreli":
        "{0} encrypted",
    "Kasayı kilitle (⌘L)":
        "Lock the vault (⌘L)",
    "Kasa sağlam":
        "The vault is intact",
    "{0} dosyada sorun var":
        "{0} file has a problem|{0} files have problems",
    "{0} dosya · {1} baştan sona çözülerek doğrulandı":
        "{0} file · {1} fully decrypted and verified|{0} files · {1} fully decrypted and verified",
    "Yedekten Geri Yükle":
        "Restore from Backup",
    "Yedek konumu ayarlanmamış; bozuk dosyalar geri yüklenemez.":
        "No backup location is set, so damaged files can't be restored.",
    "Geri yüklenemeyenler:\n":
        "Couldn't be restored:\n",
    "{0} artık dosya ({1})":
        "{0} leftover file ({1})|{0} leftover files ({1})",
    "Temizle":
        "Clean Up",
    "Kasada hiçbir kayda ait olmayan şifreli dosyalar veya yarıda kalmış yazmalar. Silinmeleri güvenlidir.":
        "Encrypted files that don't belong to any entry in the vault, or interrupted writes. They're safe to delete.",
    "{0} bozuk küçük resim kaldırıldı (dosyaların kendisi sağlam)":
        "{0} damaged thumbnail removed (the file itself is intact)|{0} damaged thumbnails removed (the files themselves are intact)",
    "Dizin yedeği (index.enc.bak) okunamıyor; bir sonraki kayıtta yenilenecek.":
        "The index backup (index.enc.bak) can't be read; it will be rewritten on the next save.",
    "Şifreli dosya kasada bulunamadı":
        "The encrypted file is missing from the vault",
    "Bozuk veya değiştirilmiş — {0}":
        "Damaged or modified — {0}",
    "İçerik, eklendiği andakinden farklı":
        "The content differs from when it was added",
    "{0} dosya yedekten geri yüklendi":
        "{0} file restored from backup|{0} files restored from backup",
    "Sonra":
        "Later",
    "Son yedek {0} alındı.":
        "Last backup was {0}.",
    "Kasan henüz hiç yedeklenmedi. SSD bozulur ya da kaybolursa her şey gider.":
        "Your vault has never been backed up. If the SSD fails or is lost, everything is gone.",
    "Henüz not yok":
        "No Notes Yet",
    "Bir not seç":
        "Select a Note",
    "Notların başlıkları ve içerikleriyle birlikte şifrelenir.":
        "Your notes are encrypted, titles and contents alike.",
    "{0} not":
        "{0} note|{0} notes",
    "Notlarda ara":
        "Search notes",
    "Renk yok":
        "No Color",
    "Not rengi":
        "Note color",
    "Sabitlemeyi kaldır":
        "Unpin",
    "Sabitle":
        "Pin",
    "Üste sabitle":
        "Pin to top",
    "Sil":
        "Delete",
    "Notu sil":
        "Delete note",
    "Yeni not (⌘N)":
        "New note (⌘N)",
    "Bu not Çöp Kutusu'na taşınsın mı?":
        "Move this note to the Trash?",
    "Başlıksız not":
        "Untitled note",
    "Ek metin yok":
        "No additional text",
    "Başlık":
        "Title",
    "Düzenlendi: {0}":
        "Edited: {0}",
    "{0} karakter":
        "{0} character|{0} characters",
    "Henüz parola kaydı yok":
        "No Password Entries Yet",
    "Bir kayıt seç":
        "Select an Entry",
    "Hesaplar, kart bilgileri, Wi-Fi ve sunucu parolaları burada şifreli saklanır.":
        "Logins, card details, Wi-Fi and server passwords are stored here, encrypted.",
    "Yeni Kayıt":
        "New Entry",
    "{0} kayıt":
        "{0} entry|{0} entries",
    "Parolalarda ara":
        "Search passwords",
    "Yeni parola kaydı (⇧⌘N)":
        "New password entry (⇧⌘N)",
    "Bu kayıt Çöp Kutusu'na taşınsın mı?":
        "Move this entry to the Trash?",
    "Adsız":
        "Untitled",
    "Favorilerden çıkar":
        "Remove from favorites",
    "Favorilere ekle":
        "Add to favorites",
    "Kullanıcı adı":
        "Username",
    "Web sitesi":
        "Website",
    "Oluşturuldu {0} · Güncellendi {1}":
        "Created {0} · Updated {1}",
    "Düzenle":
        "Edit",
    "Yeni kayıt":
        "New entry",
    "ör. Gmail":
        "e.g. Gmail",
    "e-posta veya kullanıcı adı":
        "email or username",
    "Güçlü parola üret":
        "Generate a strong password",
    "Favori":
        "Favorite",
    "Parola üretici":
        "Password generator",
    "Yeniden üret":
        "Regenerate",
    "Uzunluk":
        "Length",
    "Büyük harf (A–Z)":
        "Uppercase (A–Z)",
    "Küçük harf (a–z)":
        "Lowercase (a–z)",
    "Rakam (0–9)":
        "Digits (0–9)",
    "Sembol (!@#…)":
        "Symbols (!@#…)",
    "Karışan karakterleri çıkar (O/0, l/1)":
        "Avoid look-alike characters (O/0, l/1)",
    "Parola kopyalandı":
        "Password copied",
    "Bu Parolayı Kullan":
        "Use This Password",
    "Tema":
        "Theme",
    "Vurgu rengi":
        "Accent color",
    "Kasa adı":
        "Vault name",
    "Not yazı tipi":
        "Note font",
    "Not yazı boyutu":
        "Note font size",
    "Dosya görünümü":
        "File view",
    "Otomatik kilit":
        "Auto-lock",
    "{0} dk hareketsizlikte":
        "After {0} min idle",
    "Kapalı":
        "Off",
    "Kopyalanan parolayı panodan sil":
        "Clear copied passwords from the clipboard",
    "{0} sn sonra":
        "After {0} sec",
    "Silme":
        "Never",
    "Uyku, ekran kilidi ve kullanıcı değişiminde kilitle":
        "Lock on sleep, screen lock, and user switch",
    "Ekran görüntüsü, kayıt ve paylaşımda pencereyi gizle":
        "Hide the window from screenshots, recordings, and screen sharing",
    "Ekledikten sonra orijinalleri Çöp Kutusu'na taşımayı sor":
        "Ask to move originals to the Trash after adding",
    "Parolayı Değiştir…":
        "Change Password…",
    "Aç…":
        "Open…",
    "Güvenlik":
        "Security",
    "SSD çıkarıldığında kasa her zaman kilitlenir.":
        "The vault always locks when the SSD is disconnected.",
    "Yanlış parolada kasayı kalıcı olarak sil":
        "Permanently wipe the vault on wrong passwords",
    "Deneme sayısı":
        "Attempts",
    "{0} yanlış parola":
        "{0} wrong password|{0} wrong passwords",
    "Yanlış parola sınırı":
        "Wrong-password limit",
    "Açıkken art arda bu kadar yanlış parola girilirse kasanın anahtarları yok edilir ve kasadaki her şey kalıcı olarak açılamaz hale gelir; geri alınamaz. Sayaç doğru parolayla açılınca sıfırlanır. Anahtar dosyalı bir kasayı başka bir Mac'te açmaya çalışmak da yanlış deneme sayılır. Yedekler bu ayardan etkilenmez.":
        "When this is on, entering that many wrong passwords in a row destroys the vault's keys, and everything in the vault becomes permanently unreadable; this can't be undone. The counter resets when the vault is opened with the correct password. Trying to open a keyfile-protected vault on another Mac also counts as a wrong attempt. Backups aren't affected by this setting.",
    "Yanlış parola sınırı açılsın mı?":
        "Turn on the wrong-password limit?",
    "{0} yanlış denemede sil":
        "Wipe After {0} Wrong Attempts",
    "Art arda {0} yanlış parola girilirse kasa kalıcı olarak silinir ve hiçbir şekilde geri getirilemez. Deneme sayısını sonra değiştirebilirsiniz. Güncel bir yedeğiniz olduğundan emin olun.":
        "If {0} wrong passwords are entered in a row, the vault is permanently wiped and can't be recovered in any way. You can change the number of attempts later. Make sure you have an up-to-date backup.",
    "Durum":
        "Status",
    "Açık — kasa yalnızca bu Mac'te açılır":
        "On — the vault opens only on this Mac",
    "Kapalı — kasa parolayla her Mac'te açılır":
        "Off — the vault opens on any Mac with the password",
    "Anahtar Dosyasını Yedekle…":
        "Back Up Keyfile…",
    "Bağlantıyı Kaldır…":
        "Remove Binding…",
    "Bu Mac'e Bağla…":
        "Bind to This Mac…",
    "Bu Mac'e bağlama (anahtar dosyası)":
        "Binding to this Mac (keyfile)",
    "Açıkken kasa, parola + bu Mac'te saklanan rastgele bir anahtar dosyasıyla açılır. Başka bir Mac'te doğru parola bile yalnızca \"Parola yanlış\" der; kasada anahtar dosyası kullanıldığına dair iz yoktur.":
        "When this is on, the vault opens with the password plus a random keyfile stored on this Mac. On another Mac, even the correct password just says “Wrong password”; nothing in the vault reveals that a keyfile is in use.",
    "Yedek konumu":
        "Backup location",
    "Finder'da göster":
        "Show in Finder",
    "Seçilmedi":
        "Not set",
    "Son yedek":
        "Last backup",
    "Hiç alınmadı":
        "Never",
    "Hatırlat":
        "Remind me",
    "{0} gün yedek alınmazsa":
        "After {0} day without a backup|After {0} days without a backup",
    "Hatırlatma":
        "Don't remind me",
    "Bütünlük Taraması":
        "Integrity Check",
    "Yedekleme ve bakım":
        "Backup and maintenance",
    "Yedek yalnızca değişen dosyaları kopyalar ve şifreli kalır; aynı parolayla Mahzen'de \"Mevcut kasayı aç\" ile açılır. Bütünlük taraması her dosyayı çözerek doğrular, bozukları yedekten geri yükleyebilir.":
        "A backup copies only the files that changed and stays encrypted; open it in Mahzen with the same password via “Open an existing vault”. The integrity check verifies every file by decrypting it and can restore damaged ones from the backup.",
    "Şifreleme":
        "Encryption",
    "AES-256-GCM (dosya başına ayrı anahtar)":
        "AES-256-GCM (a separate key per file)",
    "Anahtar türetme":
        "Key derivation",
    "İçerik":
        "Contents",
    "{0} klasör":
        "{0} folder|{0} folders",
    "{0} parola":
        "{0} password|{0} passwords",
    "Çöp Kutusu'nu otomatik boşalt":
        "Empty the Trash automatically",
    "{0} gün sonra":
        "After {0} day|After {0} days",
    "Hiçbir zaman":
        "Never",
    "Ana parolayı değiştir":
        "Change the master password",
    "Dosyaların yeniden şifrelenmesi gerekmez; yalnızca ana anahtar yeni parolayla yeniden sarılır.":
        "Your files don't need to be re-encrypted; only the master key is rewrapped with the new password.",
    "Mevcut parola":
        "Current password",
    "Yeni parola (en az {0} karakter)":
        "New password (at least {0} characters)",
    "Yeni parolayı tekrarla":
        "Repeat new password",
    "Değiştir":
        "Change",
    "Kasa bu Mac'e bağlandı":
        "The vault is now bound to this Mac",
    "Şimdi anahtar dosyasının bir yedeğini al. Bu Mac bozulur, çalınır ya da sıfırlanırsa kasayı açmanın tek yolu o yedektir. Yedeği SSD'de değil, ayrı ve güvendiğin bir yerde tut (ör. başka bir USB bellek).":
        "Back up the keyfile now. If this Mac breaks, is stolen, or is erased, that backup is the only way to open the vault. Keep it somewhere separate that you trust (e.g. another USB stick), not on the SSD.",
    "Kasanın mevcut yedeği, bir sonraki \"Şimdi Yedekle\" ile güncellenince o da anahtar dosyası ister.":
        "Once the vault's existing backup is updated by the next “Back Up Now”, it will require the keyfile too.",
    "Kasayı bu Mac'e bağla":
        "Bind the vault to this Mac",
    "Bu Mac'e bağlantıyı kaldır":
        "Remove the binding to this Mac",
    "Kasa bundan sonra parola + bu Mac'teki anahtar dosyasıyla açılır.":
        "From now on, the vault opens with the password plus the keyfile on this Mac.",
    "SSD başka bir Mac'e takılırsa doğru parola da \"Parola yanlış\" der; anahtar dosyası istendiği belli olmaz.":
        "If the SSD is plugged into another Mac, even the correct password says “Wrong password”; nothing shows that a keyfile is required.",
    "Bu Mac bozulur, sıfırlanır ya da anahtar dosyası silinirse, yedeği yoksa kasa bir daha açılamaz.":
        "If this Mac breaks or is erased, or the keyfile is deleted, the vault can never be opened again without a backup of the keyfile.",
    "Anahtar dosyasının yedeğini almazsam verilerimi kaybedebileceğimi anlıyorum.":
        "I understand that I may lose my data if I don't back up the keyfile.",
    "Kasa yeniden yalnızca parolayla açılır hale gelir ve bu Mac'teki anahtar dosyası silinir. Dışa aktardığın yedek kopyaları kendin silmelisin.":
        "The vault goes back to opening with the password alone, and the keyfile on this Mac is deleted. You'll need to delete any backup copies you exported yourself.",
    "Kasa parolası":
        "Vault password",
    "Bağla":
        "Bind",
    "Kaldır":
        "Remove",
    "Dil":
        "Language",
    "Dil değişikliği Mahzen yeniden açılınca uygulanır.":
        "The language change takes effect the next time Mahzen opens.",
    "Yeniden Aç":
        "Relaunch",
    "Not":
        "Note",
    "Parola kaydı":
        "Password entry",
    "Çöp Kutusu boş":
        "Trash Is Empty",
    "Boşalt":
        "Empty",
    "Çöp Kutusu'nu boşalt":
        "Empty the Trash",
    "Çöp Kutusu boşaltılsın mı?":
        "Empty the Trash?",
    "{0} Öğeyi Kalıcı Olarak Sil":
        "Permanently Delete {0} Item|Permanently Delete {0} Items",
    "Bu işlem geri alınamaz.":
        "This can't be undone.",
    "\"{0}\" kalıcı olarak silinsin mi?":
        "Permanently delete “{0}”?",
    "Kalıcı Olarak Sil":
        "Delete Permanently",
    "Silinen dosya, not ve parolalar {0} gün burada kalır, sonra kalıcı olarak silinir.":
        "Deleted files, notes, and passwords stay here for {0} day, then are permanently deleted.|Deleted files, notes, and passwords stay here for {0} days, then are permanently deleted.",
    "Otomatik silme kapalı; öğeler sen boşaltana kadar burada kalır.":
        "Automatic deletion is off; items stay here until you empty the Trash.",
    "{0} · {1} silindi":
        "{0} · deleted {1}",
    "Geri Al":
        "Put Back",
    "Kalıcı olarak sil":
        "Delete permanently",
    "Kalıcı Olarak Sil…":
        "Delete Permanently…",
    "{0} gün sonra kalıcı silinecek":
        "permanently deleted in {0} day|permanently deleted in {0} days",
    "\"{0}\" geri alındı":
        "“{0}” put back",
    "Dışa aktarılamadı":
        "Couldn't export",
    "“{0}” dışa aktarıldı":
        "“{0}” exported",
    "{0} öğe dışa aktarıldı":
        "{0} item exported|{0} items exported",
    "{0} Öğeyi Dışa Aktar…":
        "Export {0} Items…",
    "{0} Klasörü Dışa Aktar…":
        "Export {0} Folders…",
    "Favorilere Ekle (F)":
        "Add to Favorites (F)",
    "Favorilerden Çıkar (F)":
        "Remove from Favorites (F)",
    "Çöp Kutusu'na Taşı (⌘⌫)":
        "Move to Trash (⌘⌫)",
]
