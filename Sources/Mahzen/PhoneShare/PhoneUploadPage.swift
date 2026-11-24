import CryptoKit
import Foundation

// "Telefondan Ekle" sayfası: telefonda açılır, seçilen dosyaları tarayıcıda şifreleyip bilgisayara yükler
// (HTML + CSS + JS, dış bağımlılık yok). Şifreleme kodu "Telefonda Göster" sayfasıyla ortaktır.
// Metinler "bilgisayar" der; macOS ve Linux sürümlerinde sayfa birebir aynıdır.
enum PhoneUploadPage {
    static let html: String = """
    <!doctype html>
    <html lang="tr"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <meta name="referrer" content="no-referrer">
    <meta name="robots" content="noindex">
    <meta name="theme-color" content="#0b0b0d">
    <title>Mahzen</title>
    <style>\(css)</style>
    </head><body>
    \(body)
    <script>\(script)</script>
    </body></html>
    """

    /// Sayfa yalnızca kendi gömülü betiğini çalıştırabilir, yalnızca kendi sunucusuna bağlanabilir.
    static let securityHeaders: [String: String] = [
        "Content-Security-Policy": [
            "default-src 'none'",
            "script-src 'sha256-\(scriptHash)'",
            "style-src 'unsafe-inline'",
            "img-src data:",
            "connect-src 'self'",
            "base-uri 'none'",
            "form-action 'none'",
            "frame-ancestors 'none'",
        ].joined(separator: "; "),
        "X-Frame-Options": "DENY",
        "Cross-Origin-Opener-Policy": "same-origin",
        "Cross-Origin-Resource-Policy": "same-origin",
        "Permissions-Policy": "microphone=(), geolocation=()",
    ]

    static let script = PhoneShareViewer.cryptoScript + "\n" + uploadScript

    private static let scriptHash = Data(SHA256.hash(data: Data(script.utf8))).base64EncodedString()

    private static let css = #"""
:root {
  --bg: #0b0b0d; --panel: rgba(22,22,26,.78); --card: #17171b; --line: rgba(255,255,255,.08);
  --text: #f5f5f7; --dim: #9a9aa3; --accent: #ff9f0a; --accent-dim: rgba(255,159,10,.16); --danger: #ff453a; --ok: #32d74b;
  --top: env(safe-area-inset-top); --bottom: env(safe-area-inset-bottom);
  color-scheme: dark;
}
* { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
html, body { margin: 0; background: var(--bg); color: var(--text); }
body {
  font: 15px/1.4 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
  -webkit-font-smoothing: antialiased; min-height: 100vh;
}
button { font: inherit; color: inherit; background: none; border: 0; padding: 0; cursor: pointer; }
svg { display: block; }
[hidden] { display: none !important; }

.screen {
  position: fixed; inset: 0; display: flex; flex-direction: column; align-items: center; justify-content: center;
  gap: 14px; padding: 32px; text-align: center; background: var(--bg); z-index: 50;
}
.mark {
  width: 68px; height: 68px; border-radius: 20px; display: grid; place-items: center;
  background: linear-gradient(145deg, #ffb340, #ff7a00); box-shadow: 0 10px 40px rgba(255,140,0,.35);
}
.mark svg { width: 34px; height: 34px; color: #1a1000; }
.screen.error .mark { background: #2a2a30; box-shadow: none; }
.screen.error .mark svg { color: var(--dim); }
.screen h1 { margin: 6px 0 0; font-size: 21px; font-weight: 650; letter-spacing: -.01em; }
.screen p { margin: 0; color: var(--dim); max-width: 320px; }
.spinner {
  width: 22px; height: 22px; border-radius: 50%; border: 2.5px solid var(--accent-dim); border-top-color: var(--accent);
  animation: spin .8s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }

header {
  position: sticky; top: 0; z-index: 10; padding: calc(var(--top) + 12px) 16px 12px;
  background: var(--panel); -webkit-backdrop-filter: saturate(180%) blur(20px); backdrop-filter: saturate(180%) blur(20px);
  border-bottom: 1px solid var(--line); display: flex; align-items: center; gap: 12px;
}
header .titles { flex: 1; min-width: 0; }
header h1 { margin: 0; font-size: 20px; font-weight: 700; letter-spacing: -.02em; }
header .sub { color: var(--dim); font-size: 13px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
header .sub b { color: var(--text); font-weight: 600; }
.pill {
  flex: none; display: inline-flex; align-items: center; gap: 6px; padding: 6px 11px; border-radius: 999px;
  background: var(--accent-dim); color: var(--accent); font-size: 13px; font-weight: 600; font-variant-numeric: tabular-nums;
}
.pill svg { width: 14px; height: 14px; }
.pill.low { background: rgba(255,69,58,.16); color: var(--danger); }

main { max-width: 560px; margin: 0 auto; padding: 18px 16px calc(var(--bottom) + 28px); }
.pick {
  position: relative; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 10px;
  min-height: 150px; padding: 22px; border-radius: 20px; text-align: center; cursor: pointer;
  background: linear-gradient(160deg, rgba(255,159,10,.20), rgba(255,122,0,.08)); border: 1.5px dashed rgba(255,159,10,.55);
}
.pick:active { filter: brightness(.85); }
.pick input { position: absolute; width: 1px; height: 1px; opacity: 0; pointer-events: none; }
.pick .plus {
  width: 52px; height: 52px; border-radius: 50%; display: grid; place-items: center;
  background: linear-gradient(145deg, #ffb340, #ff7a00); color: #1a1000;
}
.pick .plus svg { width: 26px; height: 26px; }
.pick strong { font-size: 17px; font-weight: 650; }
.pick span { color: var(--dim); font-size: 13px; }
.ended { display: flex; flex-direction: column; gap: 4px; padding: 16px 18px; border-radius: 16px; background: var(--card); }
.ended span { color: var(--dim); font-size: 13px; }
.hint { display: flex; gap: 10px; margin: 14px 2px 0; color: var(--dim); font-size: 13px; }
.hint svg { flex: none; width: 16px; height: 16px; margin-top: 1px; color: var(--accent); }

.list-head { display: flex; align-items: center; justify-content: space-between; margin: 24px 2px 8px; font-size: 13px; color: var(--dim); }
.list-head button { color: var(--accent); font-weight: 600; }
ul { list-style: none; margin: 0; padding: 0; border-radius: 16px; background: var(--card); overflow: hidden; }
li { display: flex; align-items: center; gap: 12px; padding: 12px 12px 12px 14px; border-top: 1px solid var(--line); }
li:first-child { border-top: 0; }
li .ic { flex: none; width: 34px; height: 34px; border-radius: 10px; display: grid; place-items: center; background: rgba(255,255,255,.06); color: var(--dim); }
li .ic svg { width: 18px; height: 18px; }
li.done .ic { background: rgba(50,215,75,.14); color: var(--ok); }
li.error .ic { background: rgba(255,69,58,.14); color: var(--danger); }
li .info { flex: 1; min-width: 0; }
li .name { font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
li .meta { color: var(--dim); font-size: 12px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
li.error .meta { color: var(--danger); }
li .track { height: 4px; margin-top: 7px; border-radius: 2px; background: rgba(255,255,255,.09); overflow: hidden; }
li .track i { display: block; height: 100%; width: 0; background: var(--accent); border-radius: 2px; transition: width .2s; }
li .act { flex: none; width: 32px; height: 32px; border-radius: 50%; display: grid; place-items: center; background: rgba(255,255,255,.07); color: var(--dim); }
li .act svg { width: 15px; height: 15px; }
"""#

    private static let body = #"""
<div id="splash" class="screen">
  <div class="mark"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><rect x="4.5" y="10.5" width="15" height="10" rx="2.5"/><path d="M8 10.5V7.5a4 4 0 0 1 8 0v3"/></svg></div>
  <h1>Mahzen</h1>
  <p data-t>Bağlanılıyor…</p>
  <div class="spinner"></div>
</div>
<div id="error" class="screen error" hidden>
  <div class="mark"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><rect x="4.5" y="10.5" width="15" height="10" rx="2.5"/><path d="M8 10.5V7.5a4 4 0 0 1 8 0v3"/></svg></div>
  <h1 id="error-title"></h1>
  <p id="error-text"></p>
</div>
<div id="app" hidden>
  <header>
    <div class="titles"><h1 data-t>Kasaya ekle</h1><div class="sub"><span data-t>Klasör:</span> <b id="folder"></b></div></div>
    <div class="pill" id="timer" title="Oturumun bitmesine kalan süre"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><circle cx="12" cy="13" r="8"/><path d="M12 9v4l2.5 2M10 2h4"/></svg><span id="timer-text"></span></div>
  </header>
  <main>
    <label class="pick" id="pick">
      <input type="file" id="input" multiple>
      <div class="plus"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg></div>
      <strong data-t>Fotoğraf, video ya da dosya seç</strong>
      <span id="limit"></span>
    </label>
    <div class="ended" id="ended" hidden><strong id="ended-title"></strong><span id="ended-text"></span></div>
    <p class="hint"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><rect x="4.5" y="10.5" width="15" height="10" rx="2.5"/><path d="M8 10.5V7.5a4 4 0 0 1 8 0v3"/></svg><span data-t>Dosyalar bu telefonda şifrelenir ve bilgisayardaki kasaya şifreli olarak yazılır. Yükleme bitene kadar bu sayfayı açık tutun.</span></p>
    <section id="list-wrap" hidden>
      <div class="list-head"><span id="summary"></span><button id="stop-all" data-t hidden>Tümünü durdur</button></div>
      <ul id="list"></ul>
    </section>
  </main>
</div>
"""#

    private static let uploadScript = #"""
// Mahzen yükleme akışı: telefondaki dosya parça parça okunur, her parça çerçeve olarak şifrelenir
// (MahzenStream ile aynı biçim) ve birkaç çerçevelik isteklerle bilgisayara gönderilir.
const MahzenUpload = (() => {
  const C = MahzenCrypto;
  const enc = new TextEncoder();
  const AAD0 = enc.encode("mahzen.phone.v1|0"), AAD1 = enc.encode("mahzen.phone.v1|1");
  const CHUNK = 1 << 20;
  function nonce(stream, chunk) {
    const n = new Uint8Array(12), dv = new DataView(n.buffer);
    dv.setUint32(0, stream); dv.setUint32(4, Math.floor(chunk / 2 ** 32)); dv.setUint32(8, chunk >>> 0);
    return n;
  }
  // Tek çerçeve: uzunluk (UInt32 BE) + şifreli metin + etiket.
  function frame(key, stream, chunk, final, plain) {
    const sealed = C.seal(key, nonce(stream, chunk), final ? AAD1 : AAD0, plain);
    const out = new Uint8Array(4 + sealed.length);
    new DataView(out.buffer).setUint32(0, sealed.length);
    out.set(sealed, 4);
    return out;
  }
  function concat(parts) {
    const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
    let o = 0;
    for (const p of parts) { out.set(p, o); o += p.length; }
    return out;
  }
  const chunkCount = (size) => Math.max(1, Math.ceil(size / CHUNK));
  // Bellekteki küçük bir içeriği tek akış olarak şifreler.
  function seal(key, stream, bytes) {
    const n = chunkCount(bytes.length), parts = [];
    for (let i = 0; i < n; i++) parts.push(frame(key, stream, i, i === n - 1, bytes.subarray(i * CHUNK, (i + 1) * CHUNK)));
    return concat(parts);
  }
  // Bir dosyanın `first` sırasından başlayan en fazla `count` çerçevesi (Blob/File'dan okunarak).
  async function fileFrames(key, stream, file, first, count) {
    const n = chunkCount(file.size), parts = [];
    for (let i = first; i < Math.min(n, first + count); i++) {
      const plain = new Uint8Array(await file.slice(i * CHUNK, Math.min(file.size, (i + 1) * CHUNK)).arrayBuffer());
      parts.push(frame(key, stream, i, i === n - 1, plain));
    }
    return concat(parts);
  }
  return { CHUNK, frame, seal, fileFrames, chunkCount };
})();

(() => {
  "use strict";

  // Arayüz dili telefonun dil tercihine göre: Türkçe tercih ediliyorsa Türkçe, değilse İngilizce.
  const EN = {
    "Bağlanılıyor…": "Connecting…",
    "Kasaya ekle": "Add to vault",
    "Klasör:": "Folder:",
    "Oturumun bitmesine kalan süre": "Time left until the session ends",
    "Fotoğraf, video ya da dosya seç": "Choose photos, videos or files",
    "Dosya başına en fazla {0}": "Up to {0} per file",
    "Dosyalar bu telefonda şifrelenir ve bilgisayardaki kasaya şifreli olarak yazılır. Yükleme bitene kadar bu sayfayı açık tutun.":
      "Files are encrypted on this phone and written to the vault on the computer encrypted. Keep this page open until the upload finishes.",
    "Tümünü durdur": "Stop all",
    "İptal": "Cancel",
    "Yeniden dene": "Try again",
    "Kaldır": "Remove",
    "Sırada": "Waiting",
    "Şifreleniyor ve gönderiliyor": "Encrypting and sending",
    "Kasaya eklendi": "Added to the vault",
    "Kasada zaten vardı": "Already in the vault",
    "Durduruldu": "Stopped",
    "{0} dosya eklendi": "{0} file added|{0} files added",
    "{0} dosya gönderiliyor": "Sending {0} file|Sending {0} files",
    "Dosya çok büyük (en fazla {0})": "File is too large (up to {0})",
    "Bilgisayarda yeterli boş alan yok": "Not enough free space on the computer",
    "Dosya doğrulanamadı": "The file failed verification",
    "Bilgisayara ulaşılamadı": "Couldn't reach the computer",
    "Aynı anda çok fazla yükleme var": "Too many uploads at once",
    "Dosya okunamadı": "The file couldn't be read",
    "Sunucu hatası": "Server error",
    "Oturum sona erdi": "Session ended",
    "Yeniden eklemek için bilgisayardaki Mahzen'de yeni bir QR kod oluşturun.": "To add more, create a new QR code in Mahzen on the computer.",
    "Oturum durduruldu": "Session stopped",
    "Bilgisayardaki Mahzen oturumu kapattı.": "Mahzen on the computer ended the session.",
    "Bağlantı kesildi": "Connection lost",
    "Bilgisayardaki oturum kapandı ya da telefon aynı Wi-Fi ağında değil.": "The session ended on the computer, or the phone isn't on the same Wi-Fi network.",
    "Anahtar bulunamadı": "Key not found",
    "QR kodu bilgisayardaki Mahzen'den yeniden okutun. Bağlantıyı kopyalamak yerine kamerayla açın.": "Scan the QR code from Mahzen on the computer again. Open it with the camera rather than copying the link.",
    "Anahtar uyuşmuyor": "Key doesn't match",
    "Bu bağlantı eski bir oturuma ait olabilir. QR kodu yeniden okutun.": "This link may belong to an earlier session. Scan the QR code again.",
    "Oturum bulunamadı": "Session not found",
    "Oturumun süresi dolmuş ya da bilgisayarda durdurulmuş.": "The session has expired or was stopped on the computer.",
    "Telefon ile bilgisayar aynı Wi-Fi ağında olmalı ve Mahzen'de oturum açık kalmalı.": "The phone and the computer must be on the same Wi-Fi network, and the session must stay open in Mahzen.",
  };
  const english = (() => {
    for (const l of navigator.languages || [navigator.language || ""]) {
      if (/^tr\b/i.test(l)) return false;
      if (/^en\b/i.test(l)) return true;
    }
    return true;
  })();
  const t = (s, a) => { const x = (english && EN[s]) || s; return a === undefined ? x : x.replace("{0}", a); };
  const tn = (s, n) => { const f = t(s).split("|"); return (f.length === 2 ? f[n === 1 ? 0 : 1] : f[0]).replace("{0}", n); };
  if (english) {
    document.documentElement.lang = "en";
    for (const n of document.querySelectorAll("[data-t]")) n.textContent = t(n.textContent);
    for (const n of document.querySelectorAll("[title]")) n.setAttribute("title", t(n.getAttribute("title")));
  }
  const $ = (id) => document.getElementById(id);
  const el = (tag, cls, text) => {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  };
  const ICONS = {
    file: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linejoin="round"><path d="M6 3.5h8l4 4v13H6z"/><path d="M14 3.5v4h4"/></svg>',
    image: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4.5" width="18" height="15" rx="3"/><circle cx="9" cy="10" r="1.8"/><path d="M21 16l-5-5-8 8.5"/></svg>',
    video: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linejoin="round"><rect x="3" y="5.5" width="13" height="13" rx="3"/><path d="M16 10l5-3v10l-5-3z"/></svg>',
    done: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>',
    error: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"><path d="M12 7v6M12 17h.01"/></svg>',
    x: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>',
    retry: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M4 12a8 8 0 1 0 2.5-5.8M4 4v5h5"/></svg>',
  };

  // ---------- Anahtar: adresin # kısmından alınır, sonra adresten silinir ----------
  const KEY_SLOT = "mahzen.u" + location.pathname;
  function fromB64url(s) {
    s = s.replace(/-/g, "+").replace(/_/g, "/");
    while (s.length % 4) s += "=";
    const bin = atob(s), out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }
  let key = null;
  try {
    const frag = location.hash.slice(1);
    if (frag) {
      key = fromB64url(frag);
      history.replaceState(null, "", location.pathname + location.search);
      try { sessionStorage.setItem(KEY_SLOT, frag); } catch (_) {}
    } else {
      const saved = sessionStorage.getItem(KEY_SLOT);
      if (saved) key = fromB64url(saved);
    }
  } catch (_) { key = null; }

  const nf = new Intl.NumberFormat(english ? "en" : "tr-TR", { maximumFractionDigits: 1 });
  function fmtSize(n) {
    if (n < 1000) return n + " B";
    const units = ["KB", "MB", "GB", "TB"];
    let v = n, u = -1;
    do { v /= 1000; u++; } while (v >= 1000 && u < units.length - 1);
    return nf.format(v) + " " + units[u];
  }

  // ---------- Ağ ----------
  class UploadError extends Error {
    constructor(kind) { super(kind); this.kind = kind; }
  }
  async function post(path, body, signal) {
    let res;
    try {
      res = await fetch(path, { method: "POST", body, cache: "no-store", credentials: "omit", signal,
                                headers: { "Content-Type": "application/octet-stream" } });
    } catch (e) {
      throw new UploadError(signal && signal.aborted ? "abort" : "net");
    }
    let data = null;
    try { data = await res.json(); } catch (_) {}
    if (res.status === 404) throw new UploadError("gone");
    if (!res.ok) throw new UploadError((data && data.error) || "http");
    return data || {};
  }
  function errorText(kind) {
    switch (kind) {
      case "too-large": return t("Dosya çok büyük (en fazla {0})", fmtSize(status.maxFileSize));
      case "no-space": return t("Bilgisayarda yeterli boş alan yok");
      case "crypto": return t("Dosya doğrulanamadı");
      case "net": return t("Bilgisayara ulaşılamadı");
      case "busy": return t("Aynı anda çok fazla yükleme var");
      case "read": return t("Dosya okunamadı");
      default: return t("Sunucu hatası");
    }
  }

  // ---------- Durum ----------
  let status = null, ended = false, timerHandle = 0, heartbeatHandle = 0, netStrikes = 0, running = false;
  const entries = [];   // { file, state: queued|up|done|dup|error|stopped, sent, n, ctrl, row, error }

  function kindOf(file) {
    const ty = file.type || "";
    return ty.startsWith("image/") ? "image" : ty.startsWith("video/") ? "video" : "file";
  }

  function render(entry) {
    const r = entry.row;
    r.li.className = entry.state === "done" || entry.state === "dup" ? "done" : entry.state === "error" ? "error" : "";
    r.ic.innerHTML = entry.state === "done" || entry.state === "dup" ? ICONS.done : entry.state === "error" ? ICONS.error : ICONS[kindOf(entry.file)];
    const size = fmtSize(entry.file.size);
    let meta;
    switch (entry.state) {
      case "queued": meta = size + " · " + t("Sırada"); break;
      case "up": meta = fmtSize(entry.sent) + " / " + size + " · " + t("Şifreleniyor ve gönderiliyor"); break;
      case "done": meta = size + " · " + t("Kasaya eklendi"); break;
      case "dup": meta = size + " · " + t("Kasada zaten vardı"); break;
      case "stopped": meta = size + " · " + t("Durduruldu"); break;
      default: meta = entry.error || t("Sunucu hatası");
    }
    r.meta.textContent = meta;
    r.track.hidden = entry.state !== "up";
    r.bar.style.width = (entry.file.size ? Math.min(100, (100 * entry.sent) / entry.file.size) : 0) + "%";
    const canRetry = (entry.state === "error" || entry.state === "stopped") && !ended;
    const canStop = entry.state === "queued" || entry.state === "up";
    r.act.hidden = !(canRetry || canStop);
    r.act.innerHTML = canRetry ? ICONS.retry : ICONS.x;
    r.act.setAttribute("aria-label", canRetry ? t("Yeniden dene") : t("İptal"));
  }

  function renderSummary() {
    const done = entries.filter((e) => e.state === "done").length;
    const busy = entries.filter((e) => e.state === "queued" || e.state === "up").length;
    $("summary").textContent = busy ? tn("{0} dosya gönderiliyor", busy) : tn("{0} dosya eklendi", done);
    $("stop-all").hidden = !busy;
    $("list-wrap").hidden = entries.length === 0;
  }

  function addFiles(files) {
    for (const file of files) {
      const entry = { file, state: "queued", sent: 0, n: null, ctrl: null, error: null };
      const li = el("li"), ic = el("div", "ic"), info = el("div", "info");
      const name = el("div", "name", file.name || "?"), meta = el("div", "meta");
      const track = el("div", "track"), bar = el("i");
      track.appendChild(bar);
      info.append(name, meta, track);
      const act = el("button", "act");
      act.onclick = () => (entry.state === "error" || entry.state === "stopped") ? retry(entry) : stop(entry);
      li.append(ic, info, act);
      entry.row = { li, ic, meta, track, bar, act };
      entries.push(entry);
      $("list").appendChild(li);
      render(entry);
    }
    renderSummary();
    pump();
  }

  function stop(entry) {
    if (entry.state === "queued") { entry.state = "stopped"; render(entry); renderSummary(); return; }
    if (entry.state === "up" && entry.ctrl) entry.ctrl.abort();
  }
  function retry(entry) {
    if (ended) return;
    Object.assign(entry, { state: "queued", sent: 0, n: null, ctrl: null, error: null });
    render(entry); renderSummary(); pump();
  }
  function cancelOnServer(entry) {
    if (entry.n == null) return;
    fetch("x/" + entry.n, { method: "POST", cache: "no-store", credentials: "omit" }).catch(() => {});
  }

  async function upload(entry) {
    const file = entry.file, ctrl = new AbortController();
    entry.ctrl = ctrl;
    if (file.size > status.maxFileSize) throw new UploadError("too-large");
    const { n } = await post("n", null, ctrl.signal);
    if (!Number.isInteger(n) || n < 1) throw new UploadError("http");
    entry.n = n;
    const meta = { name: file.name || "dosya", size: file.size, type: file.type || null, modified: file.lastModified || null };
    await post("u/" + n + "/0", MahzenUpload.seal(key, 2 * n, new TextEncoder().encode(JSON.stringify(meta))), ctrl.signal);
    const chunks = MahzenUpload.chunkCount(file.size), per = status.framesPerPart || 4;
    let result = {};
    for (let first = 0, part = 1; first < chunks; first += per, part++) {
      let body;
      try { body = await MahzenUpload.fileFrames(key, 2 * n + 1, file, first, per); }
      catch (_) { throw new UploadError("read"); }
      if (ctrl.signal.aborted) throw new UploadError("abort");
      const last = first + per >= chunks;
      result = await post("u/" + n + "/" + part + (last ? "?end=1" : ""), body, ctrl.signal);
      entry.sent = Math.min(file.size, (first + per) * MahzenUpload.CHUNK);
      render(entry);
    }
    return result;
  }

  async function pump() {
    if (running || ended) return;
    const entry = entries.find((e) => e.state === "queued");
    if (!entry) return;
    running = true;
    entry.state = "up";
    render(entry); renderSummary();
    try {
      const result = await upload(entry);
      entry.state = result.result === "duplicate" ? "dup" : "done";
      entry.sent = entry.file.size;
    } catch (e) {
      cancelOnServer(entry);
      if (e.kind === "abort") entry.state = "stopped";
      else { entry.state = "error"; entry.error = errorText(e.kind); }
      if (e.kind === "gone") {
        running = false;
        return end(t("Oturum durduruldu"), t("Bilgisayardaki Mahzen oturumu kapattı."));
      }
    }
    entry.ctrl = null;
    running = false;
    render(entry); renderSummary();
    pump();
  }

  // ---------- Bitiş, süre ve bağlantı denetimi ----------
  function showError(title, text) {
    $("splash").hidden = true;
    $("app").hidden = true;
    $("error-title").textContent = title;
    $("error-text").textContent = text;
    $("error").hidden = false;
  }
  function end(title, text) {
    if (ended) return;
    ended = true;
    clearInterval(timerHandle); clearInterval(heartbeatHandle);
    for (const e of entries) {
      if (e.state === "up" && e.ctrl) e.ctrl.abort();
      if (e.state === "queued") e.state = "stopped";
    }
    try { sessionStorage.removeItem(KEY_SLOT); } catch (_) {}
    key = null;
    // Biten oturumda liste görünür kalsın (neyin eklendiği belli olsun); seçim kapanır.
    if (entries.length) {
      $("pick").hidden = true;
      $("input").disabled = true;
      $("timer").hidden = true;
      $("ended-title").textContent = title;
      $("ended-text").textContent = text;
      $("ended").hidden = false;
      for (const e of entries) render(e);
      renderSummary();
    } else {
      showError(title, text);
    }
  }
  function tick() {
    const left = Math.round(status.expiresAt - Date.now() / 1000);
    if (left <= 0) return end(t("Oturum sona erdi"), t("Yeniden eklemek için bilgisayardaki Mahzen'de yeni bir QR kod oluşturun."));
    $("timer-text").textContent = Math.floor(left / 60) + ":" + String(left % 60).padStart(2, "0");
    $("timer").classList.toggle("low", left < 60);
  }
  async function checkAlive() {
    if (ended) return;
    try {
      const res = await fetch("s", { cache: "no-store", credentials: "omit" });
      if (res.status === 404) return end(t("Oturum durduruldu"), t("Bilgisayardaki Mahzen oturumu kapattı."));
      netStrikes = 0;
    } catch (_) {
      if (++netStrikes >= 2 && !running) end(t("Bağlantı kesildi"), t("Bilgisayardaki oturum kapandı ya da telefon aynı Wi-Fi ağında değil."));
    }
  }
  window.addEventListener("beforeunload", (e) => {
    if (!ended && entries.some((x) => x.state === "queued" || x.state === "up")) { e.preventDefault(); e.returnValue = ""; }
  });

  // ---------- Başlangıç ----------
  async function start() {
    if (!key || key.length !== 32) {
      return showError(t("Anahtar bulunamadı"), t("QR kodu bilgisayardaki Mahzen'den yeniden okutun. Bağlantıyı kopyalamak yerine kamerayla açın."));
    }
    let res;
    try { res = await fetch("s", { cache: "no-store", credentials: "omit" }); } catch (_) {
      return showError(t("Bilgisayara ulaşılamadı"), t("Telefon ile bilgisayar aynı Wi-Fi ağında olmalı ve Mahzen'de oturum açık kalmalı."));
    }
    if (!res.ok) return showError(t("Oturum bulunamadı"), t("Oturumun süresi dolmuş ya da bilgisayarda durdurulmuş."));
    try {
      const dec = MahzenStream.decoder(key, 0), parts = dec.push(new Uint8Array(await res.arrayBuffer()));
      parts.push(dec.finish());
      const bytes = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
      let o = 0;
      for (const p of parts) { bytes.set(p, o); o += p.length; }
      status = JSON.parse(new TextDecoder().decode(bytes));
    } catch (_) {
      return showError(t("Anahtar uyuşmuyor"), t("Bu bağlantı eski bir oturuma ait olabilir. QR kodu yeniden okutun."));
    }
    $("folder").textContent = status.folder;
    $("limit").textContent = t("Dosya başına en fazla {0}", fmtSize(status.maxFileSize));
    $("input").addEventListener("change", (e) => {
      const files = Array.from(e.target.files || []);
      e.target.value = "";
      if (files.length && !ended) addFiles(files);
    });
    $("stop-all").onclick = () => { for (const e of entries.slice().reverse()) stop(e); };
    $("splash").hidden = true;
    $("app").hidden = false;
    tick();
    timerHandle = setInterval(tick, 1000);
    heartbeatHandle = setInterval(checkAlive, 15000);
  }
  start();
})();
"""#
}
