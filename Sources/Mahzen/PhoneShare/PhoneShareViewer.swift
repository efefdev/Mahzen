import CryptoKit
import Foundation

// Bu dosya telefonda açılan görüntüleyici sayfasıdır (HTML + CSS + JS, dış bağımlılık yok).
// Şifre çözme tarayıcıda yapılır: ChaCha20-Poly1305 (RFC 8439) saf JavaScript ile.
enum PhoneShareViewer {
    static let html: String = """
    <!doctype html>
    <html lang="tr"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover, user-scalable=no">
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
            "img-src blob: data:",
            "media-src blob:",
            "connect-src 'self'",
            "base-uri 'none'",
            "form-action 'none'",
            "frame-ancestors 'none'",
        ].joined(separator: "; "),
        "X-Frame-Options": "DENY",
        "Cross-Origin-Opener-Policy": "same-origin",
        "Cross-Origin-Resource-Policy": "same-origin",
        "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
    ]

    private static let scriptHash = Data(SHA256.hash(data: Data(script.utf8))).base64EncodedString()

    private static let css = #"""
:root {
  --bg: #0b0b0d; --panel: rgba(22,22,26,.78); --tile: #1b1b20; --line: rgba(255,255,255,.08);
  --text: #f5f5f7; --dim: #9a9aa3; --accent: #ff9f0a; --accent-dim: rgba(255,159,10,.16); --danger: #ff453a;
  --top: env(safe-area-inset-top); --bottom: env(safe-area-inset-bottom);
  color-scheme: dark;
}
* { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
html, body { margin: 0; background: var(--bg); color: var(--text); }
body {
  font: 15px/1.4 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
  -webkit-font-smoothing: antialiased; min-height: 100vh; overscroll-behavior-y: none;
}
button, a.btn { font: inherit; color: inherit; background: none; border: 0; padding: 0; cursor: pointer; text-decoration: none; }
svg { display: block; }
[hidden] { display: none !important; }

/* Açılış ve hata ekranları */
.screen {
  position: fixed; inset: 0; display: flex; flex-direction: column; align-items: center; justify-content: center;
  gap: 14px; padding: 32px; text-align: center; background: var(--bg); z-index: 50;
}
.screen .mark {
  width: 68px; height: 68px; border-radius: 20px; display: grid; place-items: center;
  background: linear-gradient(145deg, #ffb340, #ff7a00); box-shadow: 0 10px 40px rgba(255,140,0,.35);
}
.screen .mark svg { width: 34px; height: 34px; color: #1a1000; }
.screen.error .mark { background: #2a2a30; box-shadow: none; }
.screen.error .mark svg { color: var(--dim); }
.screen h1 { margin: 6px 0 0; font-size: 21px; font-weight: 650; letter-spacing: -.01em; }
.screen p { margin: 0; color: var(--dim); max-width: 320px; }
.spinner {
  width: 22px; height: 22px; border-radius: 50%; border: 2.5px solid var(--accent-dim); border-top-color: var(--accent);
  animation: spin .8s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }

/* Üst çubuk */
header {
  position: sticky; top: 0; z-index: 10; padding: calc(var(--top) + 10px) 16px 10px;
  background: var(--panel); -webkit-backdrop-filter: saturate(180%) blur(20px); backdrop-filter: saturate(180%) blur(20px);
  border-bottom: 1px solid var(--line);
}
.bar { display: flex; align-items: center; gap: 12px; }
.bar .titles { flex: 1; min-width: 0; }
.bar h1 { margin: 0; font-size: 20px; font-weight: 700; letter-spacing: -.02em; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.bar .sub { color: var(--dim); font-size: 13px; }
.pill {
  display: inline-flex; align-items: center; gap: 6px; padding: 6px 11px; border-radius: 999px;
  background: var(--accent-dim); color: var(--accent); font-size: 13px; font-weight: 600; font-variant-numeric: tabular-nums;
}
.pill svg { width: 14px; height: 14px; }
.pill.low { background: rgba(255,69,58,.16); color: var(--danger); }
.filters { display: flex; gap: 6px; margin-top: 10px; }
.filters button {
  padding: 6px 13px; border-radius: 999px; background: rgba(255,255,255,.07); color: var(--dim); font-size: 13px; font-weight: 600;
}
.filters button[aria-pressed="true"] { background: var(--text); color: #000; }

/* Izgara */
main { padding: 0 0 calc(var(--bottom) + 24px); }
section h2 {
  position: sticky; top: var(--header-h, 0px); z-index: 5; margin: 0; padding: 14px 16px 8px; font-size: 13px; font-weight: 600;
  color: var(--dim); display: flex; align-items: baseline; gap: 8px; background: linear-gradient(var(--bg) 70%, transparent);
}
section h2 .path { color: var(--text); font-size: 15px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
section h2 .path span { color: var(--dim); }
.grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 2px; }
@media (min-width: 600px) { .grid { grid-template-columns: repeat(5, 1fr); } }
@media (min-width: 1000px) { .grid { grid-template-columns: repeat(7, 1fr); } }
.tile { position: relative; aspect-ratio: 1; background: var(--tile); overflow: hidden; }
.tile img { width: 100%; height: 100%; object-fit: cover; opacity: 0; transition: opacity .25s; }
.tile img.ready { opacity: 1; }
.tile .glyph { position: absolute; inset: 0; display: grid; place-items: center; color: #3a3a42; }
.tile .glyph svg { width: 30%; height: 30%; }
.tile .badge {
  position: absolute; right: 5px; bottom: 5px; display: flex; align-items: center; gap: 3px; padding: 2px 6px 2px 4px;
  border-radius: 6px; background: rgba(0,0,0,.55); font-size: 11px; font-weight: 600; color: #fff;
}
.tile .badge svg { width: 11px; height: 11px; }
.tile:active { filter: brightness(.75); }
.empty { padding: 60px 24px; text-align: center; color: var(--dim); }

/* Tam ekran görüntüleyici */
#viewer { position: fixed; inset: 0; z-index: 30; background: #000; touch-action: none; overflow: hidden; }
#viewer .backdrop { position: absolute; inset: 0; background: #000; }
#track { position: absolute; inset: 0; display: flex; will-change: transform; }
.slide { position: relative; flex: 0 0 100%; height: 100%; display: grid; place-items: center; overflow: hidden; }
.slide .media { max-width: 100%; max-height: 100%; width: 100%; height: 100%; object-fit: contain; transform-origin: 0 0; user-select: none; -webkit-user-select: none; -webkit-touch-callout: none; }
.slide img.ph { filter: blur(14px) brightness(.7); transform: scale(1.04); }
.slide video.media {
  /* Videonun kendi kontrolleri (tam ekran, süre çubuğu) üst ve alt çubukların altında kalmasın. */
  position: absolute; left: 0; width: 100%; top: calc(var(--top) + 58px);
  height: calc(100% - var(--top) - var(--bottom) - 124px); max-height: none;
  background: #000;
}
.ring { position: absolute; width: 64px; height: 64px; display: grid; place-items: center; }
.ring svg { position: absolute; inset: 0; width: 64px; height: 64px; transform: rotate(-90deg); }
.ring circle { fill: none; stroke-width: 4; }
.ring .track { stroke: rgba(255,255,255,.18); }
.ring .bar { stroke: var(--accent); stroke-linecap: round; transition: stroke-dashoffset .15s; }
.ring span { font-size: 12px; font-weight: 700; font-variant-numeric: tabular-nums; }
.slide .note {
  position: absolute; left: 50%; bottom: calc(var(--bottom) + 90px); transform: translateX(-50%); padding: 8px 14px;
  border-radius: 12px; background: rgba(40,40,46,.85); color: var(--text); font-size: 13px; text-align: center; max-width: 86%;
}
.chrome { position: absolute; left: 0; right: 0; z-index: 2; transition: opacity .2s; pointer-events: none; display: flex; align-items: center; gap: 10px; padding: 0 12px; }
#viewer.bare .chrome { opacity: 0; pointer-events: none; }
.chrome.top { top: 0; padding-top: calc(var(--top) + 8px); padding-bottom: 24px; background: linear-gradient(rgba(0,0,0,.6), transparent); }
.chrome.bottom { bottom: 0; padding-bottom: calc(var(--bottom) + 12px); padding-top: 28px; background: linear-gradient(transparent, rgba(0,0,0,.6)); justify-content: center; }
.chrome .titles { flex: 1; min-width: 0; text-align: center; }
.chrome .name { font-weight: 600; font-size: 15px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.chrome .meta { color: rgba(255,255,255,.65); font-size: 12px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.chrome .round, .chrome .counter { pointer-events: auto; }
.round {
  flex: none; width: 38px; height: 38px; border-radius: 50%; display: grid; place-items: center;
  background: rgba(60,60,66,.55); -webkit-backdrop-filter: blur(12px); backdrop-filter: blur(12px);
}
.round svg { width: 18px; height: 18px; }
.round.off { opacity: .3; pointer-events: none; }
.counter { font-size: 13px; font-weight: 600; color: rgba(255,255,255,.8); font-variant-numeric: tabular-nums; min-width: 70px; text-align: center; }
"""#

    private static let body = #"""
<div id="splash" class="screen">
  <div class="mark"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><rect x="4.5" y="10.5" width="15" height="10" rx="2.5"/><path d="M8 10.5V7.5a4 4 0 0 1 8 0v3"/></svg></div>
  <h1>Mahzen</h1>
  <p id="splash-text" data-t>Şifre çözülüyor…</p>
  <div class="spinner"></div>
</div>
<div id="error" class="screen error" hidden>
  <div class="mark"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><rect x="4.5" y="10.5" width="15" height="10" rx="2.5"/><path d="M8 10.5V7.5a4 4 0 0 1 8 0v3"/></svg></div>
  <h1 id="error-title"></h1>
  <p id="error-text"></p>
</div>
<div id="app" hidden>
  <header id="header">
    <div class="bar">
      <div class="titles"><h1 id="title"></h1><div class="sub" id="subtitle"></div></div>
      <div class="pill" id="timer" title="Paylaşımın bitmesine kalan süre"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><circle cx="12" cy="13" r="8"/><path d="M12 9v4l2.5 2M10 2h4"/></svg><span id="timer-text"></span></div>
    </div>
    <div class="filters" id="filters" hidden>
      <button data-filter="all" aria-pressed="true" data-t>Tümü</button>
      <button data-filter="image" aria-pressed="false" data-t>Fotoğraflar</button>
      <button data-filter="video" aria-pressed="false" data-t>Videolar</button>
    </div>
  </header>
  <main id="sections"></main>
</div>
<div id="viewer" hidden>
  <div class="backdrop" id="backdrop"></div>
  <div id="track"><div class="slide"></div><div class="slide"></div><div class="slide"></div></div>
  <div class="chrome top">
    <button class="round" id="v-close" aria-label="Kapat"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg></button>
    <div class="titles"><div class="name" id="v-name"></div><div class="meta" id="v-meta"></div></div>
    <a class="round btn off" id="v-save" aria-label="İndir"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4v11M7 10.5l5 5 5-5M5 20h14"/></svg></a>
  </div>
  <div class="chrome bottom">
    <button class="round" id="v-prev" aria-label="Önceki"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M15 5l-7 7 7 7"/></svg></button>
    <div class="counter" id="v-counter"></div>
    <button class="round" id="v-next" aria-label="Sonraki"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M9 5l7 7-7 7"/></svg></button>
  </div>
</div>
"""#

    private static let script = #"""
// ChaCha20-Poly1305 (RFC 8439) — telefondaki tarayıcıda çözme için. Web Crypto, yerel ağdaki HTTP
// sayfalarında kullanılamadığından saf JavaScript. Yalnızca 32 bit tamsayı ve kesin (2^53 altı) kayan nokta
// aritmetiği kullanır; Poly1305 birikimcisi 13 bitlik 10 parça hâlinde tutulur.
const MahzenCrypto = (() => {
  function le32(b, i) { return (b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)) >>> 0; }

  // ChaCha20: `data` üzerine anahtar akışını XOR'lar (yeni dizi döner). Durum yerel değişkenlerde tutulur;
  // tam bloklar 32 bitlik kelimeler hâlinde işlenir (iPhone ve Mac küçük-sonludur).
  function chacha20(key, nonce, counter, data) {
    const k0 = le32(key, 0), k1 = le32(key, 4), k2 = le32(key, 8), k3 = le32(key, 12);
    const k4 = le32(key, 16), k5 = le32(key, 20), k6 = le32(key, 24), k7 = le32(key, 28);
    const n0 = le32(nonce, 0), n1 = le32(nonce, 4), n2 = le32(nonce, 8);
    const out = new Uint8Array(data.length);
    const fullBlocks = Math.floor(data.length / 64);
    const aligned = (data.byteOffset % 4) === 0;
    const in32 = aligned ? new Uint32Array(data.buffer, data.byteOffset, fullBlocks * 16) : null;
    const out32 = new Uint32Array(out.buffer, 0, fullBlocks * 16);
    const ks = new Uint32Array(16), ks8 = new Uint8Array(ks.buffer);
    for (let blockIndex = 0, pos = 0; pos < data.length; blockIndex++, pos += 64, counter++) {
      let x0 = 0x61707865, x1 = 0x3320646e, x2 = 0x79622d32, x3 = 0x6b206574;
      let x4 = k0, x5 = k1, x6 = k2, x7 = k3, x8 = k4, x9 = k5, x10 = k6, x11 = k7;
      let x12 = counter >>> 0, x13 = n0, x14 = n1, x15 = n2;
      for (let r = 0; r < 10; r++) {
        x0 = (x0 + x4) | 0; x12 ^= x0; x12 = (x12 << 16) | (x12 >>> 16);
        x8 = (x8 + x12) | 0; x4 ^= x8; x4 = (x4 << 12) | (x4 >>> 20);
        x0 = (x0 + x4) | 0; x12 ^= x0; x12 = (x12 << 8) | (x12 >>> 24);
        x8 = (x8 + x12) | 0; x4 ^= x8; x4 = (x4 << 7) | (x4 >>> 25);
        x1 = (x1 + x5) | 0; x13 ^= x1; x13 = (x13 << 16) | (x13 >>> 16);
        x9 = (x9 + x13) | 0; x5 ^= x9; x5 = (x5 << 12) | (x5 >>> 20);
        x1 = (x1 + x5) | 0; x13 ^= x1; x13 = (x13 << 8) | (x13 >>> 24);
        x9 = (x9 + x13) | 0; x5 ^= x9; x5 = (x5 << 7) | (x5 >>> 25);
        x2 = (x2 + x6) | 0; x14 ^= x2; x14 = (x14 << 16) | (x14 >>> 16);
        x10 = (x10 + x14) | 0; x6 ^= x10; x6 = (x6 << 12) | (x6 >>> 20);
        x2 = (x2 + x6) | 0; x14 ^= x2; x14 = (x14 << 8) | (x14 >>> 24);
        x10 = (x10 + x14) | 0; x6 ^= x10; x6 = (x6 << 7) | (x6 >>> 25);
        x3 = (x3 + x7) | 0; x15 ^= x3; x15 = (x15 << 16) | (x15 >>> 16);
        x11 = (x11 + x15) | 0; x7 ^= x11; x7 = (x7 << 12) | (x7 >>> 20);
        x3 = (x3 + x7) | 0; x15 ^= x3; x15 = (x15 << 8) | (x15 >>> 24);
        x11 = (x11 + x15) | 0; x7 ^= x11; x7 = (x7 << 7) | (x7 >>> 25);
        x0 = (x0 + x5) | 0; x15 ^= x0; x15 = (x15 << 16) | (x15 >>> 16);
        x10 = (x10 + x15) | 0; x5 ^= x10; x5 = (x5 << 12) | (x5 >>> 20);
        x0 = (x0 + x5) | 0; x15 ^= x0; x15 = (x15 << 8) | (x15 >>> 24);
        x10 = (x10 + x15) | 0; x5 ^= x10; x5 = (x5 << 7) | (x5 >>> 25);
        x1 = (x1 + x6) | 0; x12 ^= x1; x12 = (x12 << 16) | (x12 >>> 16);
        x11 = (x11 + x12) | 0; x6 ^= x11; x6 = (x6 << 12) | (x6 >>> 20);
        x1 = (x1 + x6) | 0; x12 ^= x1; x12 = (x12 << 8) | (x12 >>> 24);
        x11 = (x11 + x12) | 0; x6 ^= x11; x6 = (x6 << 7) | (x6 >>> 25);
        x2 = (x2 + x7) | 0; x13 ^= x2; x13 = (x13 << 16) | (x13 >>> 16);
        x8 = (x8 + x13) | 0; x7 ^= x8; x7 = (x7 << 12) | (x7 >>> 20);
        x2 = (x2 + x7) | 0; x13 ^= x2; x13 = (x13 << 8) | (x13 >>> 24);
        x8 = (x8 + x13) | 0; x7 ^= x8; x7 = (x7 << 7) | (x7 >>> 25);
        x3 = (x3 + x4) | 0; x14 ^= x3; x14 = (x14 << 16) | (x14 >>> 16);
        x9 = (x9 + x14) | 0; x4 ^= x9; x4 = (x4 << 12) | (x4 >>> 20);
        x3 = (x3 + x4) | 0; x14 ^= x3; x14 = (x14 << 8) | (x14 >>> 24);
        x9 = (x9 + x14) | 0; x4 ^= x9; x4 = (x4 << 7) | (x4 >>> 25);
      }
      ks[0] = x0 + 0x61707865; ks[1] = x1 + 0x3320646e; ks[2] = x2 + 0x79622d32; ks[3] = x3 + 0x6b206574;
      ks[4] = x4 + k0; ks[5] = x5 + k1; ks[6] = x6 + k2; ks[7] = x7 + k3;
      ks[8] = x8 + k4; ks[9] = x9 + k5; ks[10] = x10 + k6; ks[11] = x11 + k7;
      ks[12] = x12 + (counter >>> 0); ks[13] = x13 + n0; ks[14] = x14 + n1; ks[15] = x15 + n2;
      if (blockIndex < fullBlocks && in32) {
        const w = blockIndex * 16;
        for (let i = 0; i < 16; i++) out32[w + i] = in32[w + i] ^ ks[i];
      } else {
        const end = Math.min(64, data.length - pos);
        for (let i = 0; i < end; i++) out[pos + i] = data[pos + i] ^ ks8[i];
      }
    }
    return out;
  }

  // Poly1305: 130 bitlik sayılar 13 bitlik 10 parçada. 2^130 ≡ 5 (mod p) olduğundan taşan parçalar 5 ile çarpılır.
  const M13 = 0x1fff;

  // 16 baytlık bloğu (ya da son kısa bloğu) 13 bitlik 10 parçaya böler; `hibit` 2^(8·len) bitini ekler.
  const blk = new Uint8Array(20);
  function bytesToLimbs(b, off, len, hibit, out) {
    blk.fill(0);
    for (let i = 0; i < len; i++) blk[i] = b[off + i];
    if (hibit) blk[len] = 1;
    for (let i = 0, bit = 0; i < 10; i++, bit += 13) {
      const by = bit >>> 3;
      out[i] = ((blk[by] | (blk[by + 1] << 8) | (blk[by + 2] << 16)) >>> (bit & 7)) & M13;
    }
  }

  function poly1305(key, msg) {
    const rb = key.slice(0, 16);
    rb[3] &= 15; rb[7] &= 15; rb[11] &= 15; rb[15] &= 15;
    rb[4] &= 252; rb[8] &= 252; rb[12] &= 252;
    const r = new Float64Array(10), r5 = new Float64Array(10), h = new Float64Array(10), m = new Float64Array(10);
    bytesToLimbs(rb, 0, 16, false, r);
    for (let i = 0; i < 10; i++) r5[i] = 5 * r[i];
    let h0 = 0, h1 = 0, h2 = 0, h3 = 0, h4 = 0, h5 = 0, h6 = 0, h7 = 0, h8 = 0, h9 = 0;
    const r0 = r[0], r1 = r[1], r2 = r[2], r3 = r[3], r4 = r[4], r5_ = r[5], r6 = r[6], r7 = r[7], r8 = r[8], r9 = r[9];
    const s1 = r5[1], s2 = r5[2], s3 = r5[3], s4 = r5[4], s5 = r5[5], s6 = r5[6], s7 = r5[7], s8 = r5[8], s9 = r5[9];
    for (let off = 0; off < msg.length; off += 16) {
      bytesToLimbs(msg, off, Math.min(16, msg.length - off), true, m);
      h0 += m[0]; h1 += m[1]; h2 += m[2]; h3 += m[3]; h4 += m[4]; h5 += m[5]; h6 += m[6]; h7 += m[7]; h8 += m[8]; h9 += m[9];
      const d0 = h0 * r0 + h1 * s9 + h2 * s8 + h3 * s7 + h4 * s6 + h5 * s5 + h6 * s4 + h7 * s3 + h8 * s2 + h9 * s1;
      const d1 = h0 * r1 + h1 * r0 + h2 * s9 + h3 * s8 + h4 * s7 + h5 * s6 + h6 * s5 + h7 * s4 + h8 * s3 + h9 * s2;
      const d2 = h0 * r2 + h1 * r1 + h2 * r0 + h3 * s9 + h4 * s8 + h5 * s7 + h6 * s6 + h7 * s5 + h8 * s4 + h9 * s3;
      const d3 = h0 * r3 + h1 * r2 + h2 * r1 + h3 * r0 + h4 * s9 + h5 * s8 + h6 * s7 + h7 * s6 + h8 * s5 + h9 * s4;
      const d4 = h0 * r4 + h1 * r3 + h2 * r2 + h3 * r1 + h4 * r0 + h5 * s9 + h6 * s8 + h7 * s7 + h8 * s6 + h9 * s5;
      const d5 = h0 * r5_ + h1 * r4 + h2 * r3 + h3 * r2 + h4 * r1 + h5 * r0 + h6 * s9 + h7 * s8 + h8 * s7 + h9 * s6;
      const d6 = h0 * r6 + h1 * r5_ + h2 * r4 + h3 * r3 + h4 * r2 + h5 * r1 + h6 * r0 + h7 * s9 + h8 * s8 + h9 * s7;
      const d7 = h0 * r7 + h1 * r6 + h2 * r5_ + h3 * r4 + h4 * r3 + h5 * r2 + h6 * r1 + h7 * r0 + h8 * s9 + h9 * s8;
      const d8 = h0 * r8 + h1 * r7 + h2 * r6 + h3 * r5_ + h4 * r4 + h5 * r3 + h6 * r2 + h7 * r1 + h8 * r0 + h9 * s9;
      const d9 = h0 * r9 + h1 * r8 + h2 * r7 + h3 * r6 + h4 * r5_ + h5 * r4 + h6 * r3 + h7 * r2 + h8 * r1 + h9 * r0;
      // Taşıma: her parçayı 13 bite indir; en üstten taşanı 5 ile çarpıp en alta ekle.
      let c, v;
      v = d0; c = Math.floor(v / 8192); h0 = v - c * 8192;
      v = d1 + c; c = Math.floor(v / 8192); h1 = v - c * 8192;
      v = d2 + c; c = Math.floor(v / 8192); h2 = v - c * 8192;
      v = d3 + c; c = Math.floor(v / 8192); h3 = v - c * 8192;
      v = d4 + c; c = Math.floor(v / 8192); h4 = v - c * 8192;
      v = d5 + c; c = Math.floor(v / 8192); h5 = v - c * 8192;
      v = d6 + c; c = Math.floor(v / 8192); h6 = v - c * 8192;
      v = d7 + c; c = Math.floor(v / 8192); h7 = v - c * 8192;
      v = d8 + c; c = Math.floor(v / 8192); h8 = v - c * 8192;
      v = d9 + c; c = Math.floor(v / 8192); h9 = v - c * 8192;
      h0 += c * 5; c = Math.floor(h0 / 8192); h0 -= c * 8192; h1 += c;
    }
    h[0] = h0; h[1] = h1; h[2] = h2; h[3] = h3; h[4] = h4; h[5] = h5; h[6] = h6; h[7] = h7; h[8] = h8; h[9] = h9;
    // Son indirgeme ve s eklemesi BigInt ile (blok başına değil, bir kez).
    let acc = 0n;
    for (let i = 9; i >= 0; i--) acc = (acc << 13n) + BigInt(h[i]);
    const p = (1n << 130n) - 5n;
    acc %= p;
    let s = 0n;
    for (let i = 31; i >= 16; i--) s = (s << 8n) + BigInt(key[i]);
    let tag = (acc + s) & ((1n << 128n) - 1n);
    const out = new Uint8Array(16);
    for (let i = 0; i < 16; i++) { out[i] = Number(tag & 0xffn); tag >>= 8n; }
    return out;
  }

  function pad16(n) { return (16 - (n % 16)) % 16; }

  function macData(aad, ct) {
    const len = aad.length + pad16(aad.length) + ct.length + pad16(ct.length) + 16;
    const buf = new Uint8Array(len);
    let o = 0;
    buf.set(aad, o); o += aad.length + pad16(aad.length);
    buf.set(ct, o); o += ct.length + pad16(ct.length);
    const dv = new DataView(buf.buffer);
    dv.setUint32(o, aad.length, true); dv.setUint32(o + 4, Math.floor(aad.length / 2 ** 32), true);
    dv.setUint32(o + 8, ct.length >>> 0, true); dv.setUint32(o + 12, Math.floor(ct.length / 2 ** 32), true);
    return buf;
  }

  // AEAD açma: doğrulanamazsa hata fırlatır.
  function open(key, nonce, aad, sealed) {
    if (sealed.length < 16) throw new Error("kısa");
    const ct = sealed.subarray(0, sealed.length - 16), tag = sealed.subarray(sealed.length - 16);
    const otk = chacha20(key, nonce, 0, new Uint8Array(32));
    const expect = poly1305(otk, macData(aad, ct));
    let diff = 0;
    for (let i = 0; i < 16; i++) diff |= expect[i] ^ tag[i];
    if (diff !== 0) throw new Error("doğrulanamadı");
    return chacha20(key, nonce, 1, ct);
  }

  // Testler için: mühürleme.
  function seal(key, nonce, aad, plain) {
    const ct = chacha20(key, nonce, 1, plain);
    const otk = chacha20(key, nonce, 0, new Uint8Array(32));
    const tag = poly1305(otk, macData(aad, ct));
    const out = new Uint8Array(ct.length + 16);
    out.set(ct); out.set(tag, ct.length);
    return out;
  }

  return { chacha20, poly1305, open, seal };
})();

// Mahzen telefon akışı: [uzunluk (UInt32 BE)][şifreli metin + etiket]...; nonce = akış (UInt32 BE) + parça (UInt64 BE);
// AAD = "mahzen.phone.v1|" + son parça bayrağı ("1"/"0").
const MahzenStream = (() => {
  const C = MahzenCrypto;
  const enc = new TextEncoder();
  const AAD0 = enc.encode("mahzen.phone.v1|0"), AAD1 = enc.encode("mahzen.phone.v1|1");
  const MAX_FRAME = (1 << 20) + 16;
  function nonce(stream, chunk) {
    const n = new Uint8Array(12), dv = new DataView(n.buffer);
    dv.setUint32(0, stream); dv.setUint32(4, Math.floor(chunk / 2 ** 32)); dv.setUint32(8, chunk >>> 0);
    return n;
  }
  // Parça parça gelen baytları çözer. push(bytes) çözülmüş parçaları döndürür; finish() akışın bütün olduğunu doğrular.
  // Gelen parçalar bir listede biriktirilir; her çerçeve yalnızca bir kez kopyalanır.
  function decoder(key, stream) {
    let parts = [], total = 0, chunk = 0, pending = null;
    function take(n) {
      const out = new Uint8Array(n);
      let filled = 0;
      while (filled < n) {
        const p = parts[0], need = n - filled;
        if (p.length <= need) { out.set(p, filled); filled += p.length; parts.shift(); }
        else { out.set(p.subarray(0, need), filled); parts[0] = p.subarray(need); filled += need; }
      }
      total -= n;
      return out;
    }
    function peekLength() {
      const b = new Uint8Array(4);
      let filled = 0;
      for (const p of parts) {
        const n = Math.min(4 - filled, p.length);
        b.set(p.subarray(0, n), filled); filled += n;
        if (filled === 4) break;
      }
      return new DataView(b.buffer).getUint32(0);
    }
    function decrypt(frame, final) {
      const plain = C.open(key, nonce(stream, chunk), final ? AAD1 : AAD0, frame);
      chunk++;
      return plain;
    }
    return {
      push(bytes) {
        if (bytes.length) { parts.push(bytes); total += bytes.length; }
        const produced = [];
        while (total >= 4) {
          const len = peekLength();
          if (len < 16 || len > MAX_FRAME) throw new Error("akış bozuk");
          if (total < 4 + len) break;
          take(4);
          const frame = take(len);
          // Bir önceki çerçeve "son değil" demekti; ancak arkasından yeni çerçeve gelince çözebiliriz.
          if (pending) produced.push(decrypt(pending, false));
          pending = frame;
        }
        return produced;
      },
      finish() {
        if (total || !pending) throw new Error("akış kesik");
        const last = decrypt(pending, true);
        pending = null;
        return last;
      },
    };
  }
  return { decoder };
})();

(() => {
  "use strict";

  // Arayüz dili telefonun dil tercihine göre: Türkçe tercih ediliyorsa Türkçe, değilse İngilizce.
  const EN = {
    "Şifre çözülüyor…": "Decrypting…",
    "Paylaşımın bitmesine kalan süre": "Time left until sharing ends",
    "Tümü": "All",
    "Fotoğraflar": "Photos",
    "Videolar": "Videos",
    "Kapat": "Close",
    "İndir": "Download",
    "Önceki": "Previous",
    "Sonraki": "Next",
    "iptal": "cancelled",
    "Mac'e ulaşılamadı": "Couldn't reach the Mac",
    "Sunucu hatası": "Server error",
    "Aktarım yarıda kesildi": "The transfer was interrupted",
    "Dosya doğrulanamadı": "The file failed verification",
    "Burada gösterilecek bir şey yok.": "Nothing to show here.",
    "Bu video büyük ({0}); telefonun belleği yetmeyebilir.": "This video is large ({0}); your phone may run out of memory.",
    "Tekrar dene": "Try again",
    "Paylaşım sona erdi": "Sharing ended",
    "Yeniden görmek için Mac'teki Mahzen'de yeni bir QR kod oluşturun.": "To view again, create a new QR code in Mahzen on the Mac.",
    "Paylaşım durduruldu": "Sharing stopped",
    "Mac'teki Mahzen paylaşımı kapattı.": "Mahzen on the Mac ended the sharing.",
    "Bağlantı kesildi": "Connection lost",
    "Mac'teki paylaşım kapandı ya da telefon aynı Wi-Fi ağında değil.": "Sharing ended on the Mac, or the phone isn't on the same Wi-Fi network.",
    "Anahtar bulunamadı": "Key not found",
    "QR kodu Mac'teki Mahzen'den yeniden okutun. Bağlantıyı kopyalamak yerine kamerayla açın.": "Scan the QR code from Mahzen on the Mac again. Open it with the camera rather than copying the link.",
    "Anahtar uyuşmuyor": "Key doesn't match",
    "Bu bağlantı eski bir paylaşıma ait olabilir. QR kodu yeniden okutun.": "This link may belong to an earlier share. Scan the QR code again.",
    "Paylaşım bulunamadı": "Share not found",
    "Paylaşımın süresi dolmuş ya da Mac'te durdurulmuş.": "The share has expired or was stopped on the Mac.",
    "Telefon ile Mac aynı Wi-Fi ağında olmalı ve Mahzen'de paylaşım açık kalmalı.": "The phone and the Mac must be on the same Wi-Fi network, and sharing must stay open in Mahzen.",
    "{0} fotoğraf": "{0} photo|{0} photos",
    "{0} video": "{0} video|{0} videos",
    "Boş": "Empty",
  };
  const english = (() => {
    for (const l of navigator.languages || [navigator.language || ""]) {
      if (/^tr\b/i.test(l)) return false;
      if (/^en\b/i.test(l)) return true;
    }
    return true;
  })();
  const t = (s) => (english && EN[s]) || s;
  const tn = (s, n) => { const f = t(s).split("|"); return (f.length === 2 ? f[n === 1 ? 0 : 1] : f[0]).replace("{0}", n); };
  if (english) {
    document.documentElement.lang = "en";
    for (const n of document.querySelectorAll("[data-t]")) n.textContent = t(n.textContent);
    for (const a of ["aria-label", "title"]) for (const n of document.querySelectorAll("[" + a + "]")) n.setAttribute(a, t(n.getAttribute(a)));
  }
  const $ = (id) => document.getElementById(id);
  const el = (tag, cls, text) => {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  };
  const ICON_PLAY = '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M7 4.5v15l13-7.5z"/></svg>';
  const ICON_PHOTO = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4.5" width="18" height="15" rx="3"/><circle cx="9" cy="10" r="1.8"/><path d="M21 16l-5-5-8 8.5"/></svg>';
  const ICON_VIDEO = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"><rect x="3" y="5.5" width="13" height="13" rx="3"/><path d="M16 10l5-3v10l-5-3z"/></svg>';

  // ---------- Anahtar: adresin # kısmından alınır, sonra adresten silinir ----------
  const KEY_SLOT = "mahzen.k" + location.pathname;
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
      // Sayfa yenilenirse anahtar bu sekmenin oturum belleğinden gelir; sekme kapanınca silinir.
      const saved = sessionStorage.getItem(KEY_SLOT);
      if (saved) key = fromB64url(saved);
    }
  } catch (_) { key = null; }

  // ---------- Biçimlendirme ----------
  const nf = new Intl.NumberFormat(english ? "en" : "tr-TR", { maximumFractionDigits: 1 });
  function fmtSize(n) {
    if (n < 1000) return n + " B";
    const units = ["KB", "MB", "GB", "TB"];
    let v = n, u = -1;
    do { v /= 1000; u++; } while (v >= 1000 && u < units.length - 1);
    return nf.format(v) + " " + units[u];
  }
  const streamLength = (size) => size + Math.max(1, Math.ceil(size / 1048576)) * 20;

  // ---------- Ağ + şifre çözme ----------
  class LoadError extends Error {
    constructor(kind, message) { super(message); this.kind = kind; }
  }
  async function fetchStream(path, stream, signal, onProgress) {
    let res;
    try {
      res = await fetch(path, { cache: "no-store", credentials: "omit", signal });
    } catch (e) {
      if (signal && signal.aborted) throw new LoadError("abort", t("iptal"));
      throw new LoadError("net", t("Mac'e ulaşılamadı"));
    }
    if (!res.ok) throw new LoadError(res.status === 404 ? "gone" : "http", t("Sunucu hatası") + " (" + res.status + ")");
    const decoder = MahzenStream.decoder(key, stream), parts = [];
    const reader = res.body.getReader();
    let received = 0;
    for (;;) {
      let r;
      try { r = await reader.read(); } catch (e) {
        if (signal && signal.aborted) throw new LoadError("abort", t("iptal"));
        throw new LoadError("net", t("Aktarım yarıda kesildi"));
      }
      if (r.done) break;
      received += r.value.length;
      try { for (const p of decoder.push(r.value)) parts.push(p); } catch (e) {
        throw new LoadError("crypto", t("Dosya doğrulanamadı"));
      }
      if (onProgress) onProgress(received);
    }
    try { parts.push(decoder.finish()); } catch (e) { throw new LoadError("crypto", t("Dosya doğrulanamadı")); }
    return parts;
  }

  // ---------- Durum ----------
  let manifest = null, items = [], visible = [], filter = "all";
  let ended = false, timerHandle = 0, heartbeatHandle = 0, netStrikes = 0;
  const thumbs = new Map();   // sıra -> blob adresi (küçük, hepsi tutulur)
  const files = new Map();    // sıra -> { url, ctrl, received, total, error, listeners }

  function end(title, text) {
    if (ended) return;
    ended = true;
    clearInterval(timerHandle); clearInterval(heartbeatHandle);
    for (const e of files.values()) { e.ctrl.abort(); if (e.url) URL.revokeObjectURL(e.url); }
    files.clear();
    for (const u of thumbs.values()) URL.revokeObjectURL(u);
    thumbs.clear();
    try { sessionStorage.removeItem(KEY_SLOT); } catch (_) {}
    key = null;
    for (const v of document.querySelectorAll("video")) { v.pause(); v.removeAttribute("src"); v.load(); }
    $("app").remove(); $("viewer").remove(); $("splash").hidden = true;
    showError(title, text);
  }
  function showError(title, text) {
    $("splash").hidden = true;
    $("error-title").textContent = title;
    $("error-text").textContent = text;
    $("error").hidden = false;
  }

  // ---------- Küçük resimler: görünür olunca, en fazla 4'ü aynı anda ----------
  const thumbQueue = [];
  let thumbActive = 0;
  function wantThumb(idx, cb) {
    if (thumbs.has(idx)) return cb(thumbs.get(idx));
    thumbQueue.push({ idx, cb });
    pumpThumbs();
  }
  function pumpThumbs() {
    while (thumbActive < 4 && thumbQueue.length && !ended) {
      const { idx, cb } = thumbQueue.shift();
      if (thumbs.has(idx)) { cb(thumbs.get(idx)); continue; }
      thumbActive++;
      fetchStream("t/" + idx, 2 * idx + 2)
        .then((parts) => {
          if (ended) return;
          const url = URL.createObjectURL(new Blob(parts));
          thumbs.set(idx, url);
          cb(url);
        })
        .catch(() => {})
        .finally(() => { thumbActive--; pumpThumbs(); });
    }
  }

  // ---------- Dosyalar ----------
  function loadFile(idx) {
    let e = files.get(idx);
    if (e) return e;
    const item = items[idx];
    e = { url: null, ctrl: new AbortController(), received: 0, total: streamLength(item.size), error: null, listeners: new Set() };
    const notify = () => e.listeners.forEach((f) => f());
    files.set(idx, e);
    fetchStream("f/" + idx, 2 * idx + 1, e.ctrl.signal, (n) => { e.received = n; notify(); })
      .then((parts) => {
        if (files.get(idx) !== e) return;
        e.url = URL.createObjectURL(new Blob(parts, { type: item.mime }));
        notify();
      })
      .catch((err) => {
        if (err.kind === "abort") return;
        if (files.get(idx) === e) files.delete(idx);
        e.error = err;
        notify();
        if (err.kind === "gone") checkAlive();
      });
    return e;
  }
  // Görüntüleyicide yalnızca açık olan ve iki yanındaki dosyalar bellekte tutulur.
  function pruneFiles(keep) {
    for (const [idx, e] of files) {
      if (keep.has(idx)) continue;
      e.ctrl.abort();
      if (e.url) URL.revokeObjectURL(e.url);
      files.delete(idx);
    }
  }

  // ---------- Ana ekran ----------
  function render() {
    visible = items.filter((it) => filter === "all" || it.kind === filter).map((it) => it.index);
    const root = $("sections");
    root.textContent = "";
    if (!visible.length) { root.append(el("div", "empty", t("Burada gösterilecek bir şey yok."))); return; }
    const groups = new Map();
    for (let pos = 0; pos < visible.length; pos++) {
      const it = items[visible[pos]];
      const k = it.path.join("/");
      if (!groups.has(k)) groups.set(k, { path: it.path, list: [] });
      groups.get(k).list.push(pos);
    }
    const showHeaders = groups.size > 1 || [...groups.values()][0].path.length > 0;
    for (const g of groups.values()) {
      const sec = el("section");
      if (showHeaders) {
        const h = el("h2"), p = el("div", "path");
        const segs = g.path.length ? g.path : [manifest.title];
        segs.forEach((s, i) => {
          if (i) p.append(el("span", null, " › "));
          p.append(document.createTextNode(s));
        });
        h.append(p, el("span", null, String(g.list.length)));
        sec.append(h);
      }
      const grid = el("div", "grid");
      for (const pos of g.list) grid.append(tile(pos));
      sec.append(grid);
      root.append(sec);
    }
  }
  const observer = new IntersectionObserver((entries) => {
    for (const en of entries) {
      if (!en.isIntersecting) continue;
      observer.unobserve(en.target);
      const idx = Number(en.target.dataset.idx), img = en.target.querySelector("img");
      if (items[idx].hasThumbnail) wantThumb(idx, (url) => { img.src = url; });
    }
  }, { rootMargin: "800px 0px" });
  function tile(pos) {
    const idx = visible[pos], it = items[idx];
    const t = el("button", "tile");
    t.dataset.idx = idx;
    t.setAttribute("aria-label", it.name);
    const glyph = el("div", "glyph");
    glyph.innerHTML = it.kind === "video" ? ICON_VIDEO : ICON_PHOTO;
    const img = el("img");
    img.alt = "";
    img.decoding = "async";
    img.onload = () => { img.classList.add("ready"); glyph.remove(); };
    t.append(glyph, img);
    if (it.kind === "video") {
      const b = el("div", "badge");
      b.innerHTML = ICON_PLAY;
      b.append(document.createTextNode(fmtSize(it.size)));
      t.append(b);
    }
    t.onclick = () => openViewer(pos);
    observer.observe(t);
    return t;
  }

  // ---------- Tam ekran görüntüleyici ----------
  const viewer = $("viewer"), track = $("track");
  let slides = [...track.children];
  let cur = 0, zoom = { s: 1, x: 0, y: 0 }, open = false;

  function openViewer(pos) {
    cur = pos; open = true;
    viewer.hidden = false; viewer.classList.remove("bare");
    $("backdrop").style.opacity = 1;
    document.body.style.overflow = "hidden";
    slides.forEach((s) => { s._key = null; });
    setTrack(0, false);
    renderSlides();
    history.pushState({ viewer: 1 }, "");
  }
  function closeViewer(fromHistory) {
    if (!open) return;
    open = false;
    for (const v of viewer.querySelectorAll("video")) v.pause();
    viewer.hidden = true;
    document.body.style.overflow = "";
    slides.forEach((s) => { s.textContent = ""; s._key = null; s.style.transform = ""; });
    pruneFiles(new Set());
    if (!fromHistory && history.state && history.state.viewer) history.back();
  }
  window.addEventListener("popstate", () => closeViewer(true));

  function setTrack(px, animate) {
    track.style.transition = animate ? "transform .3s cubic-bezier(.2,.85,.25,1)" : "none";
    track.style.transform = "translate3d(calc(-100% + " + px + "px),0,0)";
  }
  function media(slide) { return slide.querySelector(".media"); }
  function applyZoom() {
    const m = media(slides[1]);
    if (m) m.style.transform = zoom.s === 1 ? "" : "translate(" + zoom.x + "px," + zoom.y + "px) scale(" + zoom.s + ")";
  }
  function resetZoom() { zoom = { s: 1, x: 0, y: 0 }; applyZoom(); }
  function clampZoom() {
    const w = viewer.clientWidth, h = viewer.clientHeight;
    zoom.s = Math.min(5, Math.max(1, zoom.s));
    zoom.x = Math.min(0, Math.max(w - w * zoom.s, zoom.x));
    zoom.y = Math.min(0, Math.max(h - h * zoom.s, zoom.y));
  }

  function renderSlides() {
    for (let i = 0; i < 3; i++) renderSlide(slides[i], cur - 1 + i);
    const keep = new Set();
    for (let p = cur - 1; p <= cur + 1; p++) if (p >= 0 && p < visible.length) keep.add(visible[p]);
    pruneFiles(new Set([...keep].filter((idx) => files.has(idx))));
    updateChrome();
  }
  function renderSlide(slide, pos) {
    if (pos < 0 || pos >= visible.length) { if (slide._key !== "none") { slide.textContent = ""; slide._key = "none"; } return; }
    const idx = visible[pos], it = items[idx], isCur = pos === cur;
    const isVideo = it.kind === "video";
    // Videolar yalnızca açıkken indirilir; fotoğraflar iki yandakiler için önceden çözülür.
    const entry = !isVideo || isCur ? loadFile(idx) : null;
    const state = entry ? (entry.url ? "ready" : entry.error ? "error" : "loading") : "idle";
    const key = idx + ":" + state + ":" + (isVideo && isCur ? "c" : "");
    if (entry) {
      entry.listeners.clear();
      entry.listeners.add(() => {
        if (slide._pos !== pos || !open) return;
        const st = entry.url ? "ready" : entry.error ? "error" : "loading";
        if (st !== slide._state) renderSlide(slide, pos);
        else if (st === "loading") updateRing(slide, entry);
        if (pos === cur) updateChrome();
      });
    }
    slide._pos = pos;
    if (slide._key === key) return;
    slide._key = key; slide._state = state;
    slide.textContent = "";
    slide.style.transform = "";
    if (state === "ready") {
      let m;
      if (isVideo) {
        m = el("video", "media");
        m.controls = true; m.playsInline = true; m.preload = "metadata";
        m.setAttribute("playsinline", "");
        m.src = entry.url;
      } else {
        m = el("img", "media");
        m.alt = it.name; m.draggable = false;
        m.src = entry.url;
      }
      slide.append(m);
      return;
    }
    if (it.hasThumbnail) {
      const ph = el("img", "media ph");
      ph.alt = ""; ph.draggable = false;
      wantThumb(idx, (url) => { ph.src = url; });
      slide.append(ph);
    }
    if (state === "loading") {
      const ring = el("div", "ring");
      ring.innerHTML = '<svg viewBox="0 0 64 64"><circle class="track" cx="32" cy="32" r="28"/><circle class="bar" cx="32" cy="32" r="28" stroke-dasharray="175.9" stroke-dashoffset="175.9"/></svg><span></span>';
      slide.append(ring);
      updateRing(slide, entry);
      if (isVideo && it.size > 1.5e9) slide.append(el("div", "note", t("Bu video büyük ({0}); telefonun belleği yetmeyebilir.").replace("{0}", fmtSize(it.size))));
    } else if (state === "error") {
      const n = el("div", "note", entry.error.message + " · ");
      const retry = el("button", null, t("Tekrar dene"));
      retry.style.color = "var(--accent)"; retry.style.fontWeight = "600";
      retry.onclick = (ev) => { ev.stopPropagation(); slide._key = null; renderSlide(slide, pos); };
      n.append(retry);
      slide.append(n);
    } else if (isVideo) {
      const ring = el("div", "ring");
      ring.innerHTML = ICON_PLAY;
      ring.firstChild.style.cssText = "width:34px;height:34px;opacity:.85";
      slide.append(ring);
    }
  }
  function updateRing(slide, entry) {
    const bar = slide.querySelector(".ring .bar"), label = slide.querySelector(".ring span");
    if (!bar) return;
    const f = Math.min(1, entry.received / entry.total);
    bar.setAttribute("stroke-dashoffset", String(175.9 * (1 - f)));
    label.textContent = Math.floor(f * 100) + "%";
  }
  function updateChrome() {
    if (!visible.length) return;
    const idx = visible[cur], it = items[idx];
    $("v-name").textContent = it.name;
    $("v-meta").textContent = fmtSize(it.size) + (it.path.length ? " · " + it.path.join(" › ") : "");
    $("v-counter").textContent = (cur + 1) + " / " + visible.length;
    $("v-prev").classList.toggle("off", cur === 0);
    $("v-next").classList.toggle("off", cur === visible.length - 1);
    const e = files.get(idx), save = $("v-save");
    if (e && e.url) { save.href = e.url; save.download = it.name; save.classList.remove("off"); }
    else { save.removeAttribute("href"); save.classList.add("off"); }
  }

  let animating = false;
  function go(dir) {
    const next = cur + dir;
    if (animating) return;
    if (next < 0 || next >= visible.length) { setTrack(0, true); return; }
    animating = true;
    for (const v of slides[1].querySelectorAll("video")) v.pause();
    setTrack(-dir * viewer.clientWidth, true);
    let done = false;
    const finish = () => {
      if (done) return;
      done = true;
      track.removeEventListener("transitionend", finish);
      cur = next;
      if (dir > 0) { track.append(slides[0]); slides = [slides[1], slides[2], slides[0]]; }
      else { track.prepend(slides[2]); slides = [slides[2], slides[0], slides[1]]; }
      setTrack(0, false);
      resetZoomQuiet();
      renderSlides();
      animating = false;
    };
    track.addEventListener("transitionend", finish);
    setTimeout(finish, 380);
  }
  function resetZoomQuiet() {
    zoom = { s: 1, x: 0, y: 0 };
    for (const s of slides) { const m = media(s); if (m) m.style.transform = ""; }
  }

  // ---------- Dokunma: kaydır, aşağı çekip kapat, iki parmakla ya da çift dokunarak yakınlaştır ----------
  const pointers = new Map();
  let g = null, lastTap = 0, lastTapX = 0, lastTapY = 0, tapTimer = 0;
  function isImageCurrent() { const m = media(slides[1]); return m && m.tagName === "IMG" && !m.classList.contains("ph"); }
  function startGesture() {
    const pts = [...pointers.values()];
    if (pts.length >= 2 && isImageCurrent()) {
      const [a, b] = pts;
      g = { mode: "pinch", d: Math.hypot(a.x - b.x, a.y - b.y) || 1, mx: (a.x + b.x) / 2, my: (a.y + b.y) / 2, z: { ...zoom } };
    } else if (pts.length === 1) {
      const p = pts[0];
      g = { mode: null, x: p.x, y: p.y, t: performance.now(), z: { ...zoom } };
    }
  }
  viewer.addEventListener("pointerdown", (e) => {
    if (e.target.closest(".chrome") || animating) return;
    pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    startGesture();
  });
  viewer.addEventListener("pointermove", (e) => {
    if (!pointers.has(e.pointerId) || !g) return;
    pointers.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (g.mode === "pinch") {
      const [a, b] = [...pointers.values()];
      if (!b) return;
      const d = Math.hypot(a.x - b.x, a.y - b.y), mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2;
      const s = Math.min(6, Math.max(0.8, g.z.s * d / g.d));
      // Parmakların ortasındaki nokta yerinde kalsın.
      const cx = (g.mx - g.z.x) / g.z.s, cy = (g.my - g.z.y) / g.z.s;
      zoom = { s, x: mx - cx * s, y: my - cy * s };
      applyZoom();
      return;
    }
    const dx = e.clientX - g.x, dy = e.clientY - g.y;
    if (!g.mode) {
      if (Math.abs(dx) + Math.abs(dy) < 8) return;
      if (zoom.s > 1.01) g.mode = "pan";
      else if (Math.abs(dx) > Math.abs(dy)) g.mode = "swipe";
      else g.mode = dy > 0 ? "dismiss" : "none";
    }
    if (g.mode === "pan") {
      zoom.x = g.z.x + dx; zoom.y = g.z.y + dy;
      applyZoom();
    } else if (g.mode === "swipe") {
      const edge = (dx > 0 && cur === 0) || (dx < 0 && cur === visible.length - 1);
      setTrack(edge ? dx * 0.3 : dx, false);
    } else if (g.mode === "dismiss") {
      const y = Math.max(0, dy);
      slides[1].style.transform = "translate3d(" + dx * 0.4 + "px," + y + "px,0) scale(" + Math.max(0.75, 1 - y / 1200) + ")";
      $("backdrop").style.opacity = Math.max(0, 1 - y / 350);
      viewer.classList.add("bare");
    }
  });
  function endPointer(e) {
    if (!pointers.has(e.pointerId)) return;
    const p = pointers.get(e.pointerId);
    pointers.delete(e.pointerId);
    if (!g) return;
    if (g.mode === "pinch") {
      if (zoom.s < 1.05) { zoom = { s: 1, x: 0, y: 0 }; }
      clampZoom();
      const m = media(slides[1]);
      if (m) { m.style.transition = "transform .2s"; applyZoom(); setTimeout(() => { m.style.transition = ""; }, 220); }
      g = null;
      if (pointers.size === 1) startGesture();
      return;
    }
    const dx = p.x - g.x, dy = p.y - g.y, dt = Math.max(1, performance.now() - g.t);
    if (g.mode === "swipe") {
      const v = dx / dt;
      if ((dx < -viewer.clientWidth * 0.2 || v < -0.45) && cur < visible.length - 1) go(1);
      else if ((dx > viewer.clientWidth * 0.2 || v > 0.45) && cur > 0) go(-1);
      else setTrack(0, true);
    } else if (g.mode === "dismiss") {
      if (dy > 120 || dy / dt > 0.6) closeViewer(false);
      else {
        slides[1].style.transition = "transform .25s"; slides[1].style.transform = "";
        $("backdrop").style.opacity = 1;
        setTimeout(() => { slides[1].style.transition = ""; }, 260);
        viewer.classList.remove("bare");
      }
    } else if (g.mode === "pan") {
      clampZoom();
      const m = media(slides[1]);
      if (m) { m.style.transition = "transform .2s"; applyZoom(); setTimeout(() => { m.style.transition = ""; }, 220); }
    } else if (!g.mode && dt < 350 && e.type === "pointerup" && e.target.tagName !== "VIDEO") {
      onTap(p.x, p.y);
    }
    g = null;
  }
  viewer.addEventListener("pointerup", endPointer);
  viewer.addEventListener("pointercancel", endPointer);
  function onTap(x, y) {
    const now = performance.now();
    if (now - lastTap < 300 && Math.hypot(x - lastTapX, y - lastTapY) < 30) {
      clearTimeout(tapTimer); lastTap = 0;
      if (!isImageCurrent()) return;
      const m = media(slides[1]);
      if (zoom.s > 1.01) zoom = { s: 1, x: 0, y: 0 };
      else zoom = { s: 2.5, x: x - x * 2.5, y: y - y * 2.5 };
      clampZoom();
      m.style.transition = "transform .25s"; applyZoom();
      setTimeout(() => { m.style.transition = ""; }, 260);
      return;
    }
    lastTap = now; lastTapX = x; lastTapY = y;
    tapTimer = setTimeout(() => viewer.classList.toggle("bare"), 280);
  }

  $("v-close").onclick = () => closeViewer(false);
  $("v-prev").onclick = () => go(-1);
  $("v-next").onclick = () => go(1);
  document.addEventListener("keydown", (e) => {
    if (!open) return;
    if (e.key === "ArrowRight") go(1);
    else if (e.key === "ArrowLeft") go(-1);
    else if (e.key === "Escape") closeViewer(false);
  });
  window.addEventListener("resize", () => {
    $("app").style.setProperty("--header-h", $("header").offsetHeight + "px");
    if (open) { resetZoom(); setTrack(0, false); }
  });

  // ---------- Süre ve bağlantı denetimi ----------
  function tick() {
    const left = Math.round(manifest.expiresAt - Date.now() / 1000);
    if (left <= 0) return end(t("Paylaşım sona erdi"), t("Yeniden görmek için Mac'teki Mahzen'de yeni bir QR kod oluşturun."));
    const m = Math.floor(left / 60), s = left % 60;
    $("timer-text").textContent = m + ":" + String(s).padStart(2, "0");
    $("timer").classList.toggle("low", left < 60);
  }
  async function checkAlive() {
    if (ended) return;
    try {
      const res = await fetch("m", { cache: "no-store", credentials: "omit" });
      if (res.status === 404) return end(t("Paylaşım durduruldu"), t("Mac'teki Mahzen paylaşımı kapattı."));
      netStrikes = 0;
    } catch (_) {
      if (++netStrikes >= 2) end(t("Bağlantı kesildi"), t("Mac'teki paylaşım kapandı ya da telefon aynı Wi-Fi ağında değil."));
    }
  }

  // ---------- Başlangıç ----------
  async function start() {
    if (!key || key.length !== 32) {
      return showError(t("Anahtar bulunamadı"), t("QR kodu Mac'teki Mahzen'den yeniden okutun. Bağlantıyı kopyalamak yerine kamerayla açın."));
    }
    let parts;
    try {
      parts = await fetchStream("m", 0);
    } catch (e) {
      if (e.kind === "crypto") return showError(t("Anahtar uyuşmuyor"), t("Bu bağlantı eski bir paylaşıma ait olabilir. QR kodu yeniden okutun."));
      if (e.kind === "gone") return showError(t("Paylaşım bulunamadı"), t("Paylaşımın süresi dolmuş ya da Mac'te durdurulmuş."));
      return showError(t("Mac'e ulaşılamadı"), t("Telefon ile Mac aynı Wi-Fi ağında olmalı ve Mahzen'de paylaşım açık kalmalı."));
    }
    const bytes = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
    let o = 0;
    for (const p of parts) { bytes.set(p, o); o += p.length; }
    manifest = JSON.parse(new TextDecoder().decode(bytes));
    items = manifest.items;
    document.title = manifest.title + " · Mahzen";
    $("title").textContent = manifest.title;
    const photos = items.filter((i) => i.kind === "image").length, videos = items.length - photos;
    $("subtitle").textContent = [photos && tn("{0} fotoğraf", photos), videos && tn("{0} video", videos)].filter(Boolean).join(" · ") || t("Boş");
    if (photos && videos) {
      $("filters").hidden = false;
      for (const b of $("filters").children) {
        b.onclick = () => {
          filter = b.dataset.filter;
          for (const x of $("filters").children) x.setAttribute("aria-pressed", String(x === b));
          render();
          window.scrollTo(0, 0);
        };
      }
    }
    $("splash").hidden = true;
    $("app").hidden = false;
    $("app").style.setProperty("--header-h", $("header").offsetHeight + "px");
    render();
    tick();
    timerHandle = setInterval(tick, 1000);
    heartbeatHandle = setInterval(checkAlive, 15000);
  }
  start();
})();
"""#
}
