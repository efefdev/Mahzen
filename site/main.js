// Mahzen tanıtım sitesi: kaydırma, gösterimler, sekmeler.
(() => {
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const HEX = "0123456789abcdef";
  const randHex = (n) => Array.from({ length: n }, () => HEX[(Math.random() * 16) | 0]).join("");
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  // Üst çubuk ve giriş bölümü: kaydırdıkça kapıya yaklaş.
  const nav = $("#nav");
  const hero = $("#hero");
  let ticking = false;
  const onScroll = () => {
    ticking = false;
    nav.classList.toggle("scrolled", window.scrollY > 20);
    if (reduce || !hero) return;
    const range = hero.offsetHeight - window.innerHeight;
    const p = Math.min(Math.max(window.scrollY / Math.max(range, 1), 0), 1);
    document.documentElement.style.setProperty("--p", p.toFixed(4));
  };
  window.addEventListener("scroll", () => { if (!ticking) { ticking = true; requestAnimationFrame(onScroll); } }, { passive: true });
  window.addEventListener("resize", onScroll);
  onScroll();

  // Görünürken belirme.
  const revealTargets = $$(".section-head, .cipher, .steps li, .tile, .wipe-demo, .drive, .device, .honest-card, .term, .tabs");
  revealTargets.forEach((el) => el.classList.add("reveal"));
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) {
      if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
    }
  }, { rootMargin: "0px 0px -8% 0px" });
  revealTargets.forEach((el, i) => { el.style.transitionDelay = `${(i % 3) * 70}ms`; io.observe(el); });

  // Bir bölüm ekrandayken döngü çalıştıran yardımcı.
  const whileVisible = (el, loop) => {
    if (!el) return;
    let running = false;
    const state = { visible: false };
    new IntersectionObserver(([e]) => {
      state.visible = e.isIntersecting;
      if (state.visible && !running) {
        running = true;
        loop(state).finally(() => { running = false; });
      }
    }, { threshold: 0.25 }).observe(el);
  };

  // 01 — Şifreleme: adlar rastgele baytlara dönüşüp geri gelir.
  const diskHex = $$("#disk .hex");
  const fillDisk = () => diskHex.forEach((h) => { h.textContent = randHex(+h.dataset.len); });
  fillDisk();

  const scramble = async (el, toCipher) => {
    const plain = el.dataset.plain;
    const target = toCipher ? randHex(plain.length) : plain;
    const frames = 14;
    for (let f = 1; f <= frames; f++) {
      const cut = Math.floor((plain.length * f) / frames);
      el.textContent = target.slice(0, cut) + randHex(Math.max(plain.length - cut, 0));
      await sleep(38);
    }
    el.textContent = target;
    el.classList.toggle("scrambled", toCipher);
  };

  whileVisible($("#cipher"), async (state) => {
    const names = $$("#cipher .file-name");
    if (reduce) return;
    while (state.visible) {
      for (const n of names) { scramble(n, true); await sleep(160); }
      for (let i = 0; i < 10 && state.visible; i++) { fillDisk(); await sleep(120); }
      await sleep(1600);
      for (const n of names) { scramble(n, false); await sleep(160); }
      await sleep(2600);
    }
  });

  // Parola üretici gösterimi.
  const pw = $("#pwgen");
  const CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#$%^&*-_=+";
  whileVisible(pw, async (state) => {
    if (reduce) return;
    while (state.visible) {
      await sleep(2600);
      const next = Array.from({ length: 18 }, () => CHARS[(Math.random() * CHARS.length) | 0]).join("");
      for (let f = 0; f <= 10; f++) {
        pw.textContent = next.slice(0, (next.length * f) / 10 | 0) + Array.from({ length: 18 - ((18 * f) / 10 | 0) }, () => CHARS[(Math.random() * CHARS.length) | 0]).join("");
        await sleep(40);
      }
    }
  });

  // 03 — Kendini silme: beş yanlış denemede vault.json yok olur.
  const demo = $("#wipeDemo");
  const dots = $("#wdDots"), msg = $("#wdMsg"), field = $(".wd-field", demo || document);
  const pips = $$("#wdPips i"), file = $("#wdFile"), bytes = $("#wdBytes");
  const resetDemo = () => {
    pips.forEach((p) => p.classList.remove("used"));
    file.classList.remove("gone");
    demo.classList.remove("alarm");
    msg.innerHTML = "&nbsp;";
    dots.textContent = "";
  };
  whileVisible(demo, async (state) => {
    if (!demo) return;
    bytes.textContent = randHex(28);
    if (reduce) { msg.textContent = "Parola yanlış. Kalan deneme: 4"; pips[0].classList.add("used"); return; }
    while (state.visible) {
      resetDemo();
      bytes.textContent = randHex(28);
      await sleep(900);
      for (let attempt = 1; attempt <= 5 && state.visible; attempt++) {
        dots.textContent = "";
        for (let c = 0; c < 9 + (attempt % 3); c++) { dots.textContent += "•"; await sleep(55); }
        await sleep(350);
        field.classList.add("bad");
        pips[attempt - 1].classList.add("used");
        const left = 5 - attempt;
        if (left === 0) {
          msg.textContent = "Kasa kalıcı olarak silindi.";
          demo.classList.add("alarm");
          for (let i = 0; i < 16; i++) { bytes.textContent = randHex(28); await sleep(60); }
          file.classList.add("gone");
        } else {
          msg.textContent = left === 1 ? "Son deneme hakkı: bir yanlış daha kasayı siler." : `Parola yanlış. Kalan deneme: ${left}`;
          if (left === 1) demo.classList.add("alarm");
        }
        await sleep(450);
        field.classList.remove("bad");
        dots.textContent = "";
        await sleep(left === 0 ? 3200 : 900);
      }
    }
  });

  // 06 — Kurulum sekmeleri.
  const tabs = $$('.tabs [role="tab"]');
  tabs.forEach((tab) => tab.addEventListener("click", () => {
    tabs.forEach((t) => {
      const on = t === tab;
      t.setAttribute("aria-selected", String(on));
      $("#" + t.getAttribute("aria-controls")).hidden = !on;
    });
  }));
  // Varsayılan sekme: Linux ziyaretçisine Linux.
  if (/Linux/.test(navigator.userAgent) && !/Android/.test(navigator.userAgent)) $("#tab-linux")?.click();

  // Kopyala.
  $$(".copy").forEach((b) => b.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(b.dataset.copy);
      b.textContent = "Kopyalandı"; b.classList.add("ok");
      setTimeout(() => { b.textContent = "Kopyala"; b.classList.remove("ok"); }, 1600);
    } catch { /* pano izni yoksa sessiz geç */ }
  }));
})();
