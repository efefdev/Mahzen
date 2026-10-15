// Mahzen tanıtım sitesi: kaydırma efektleri, özellik turu, küçük gösterimler.
(() => {
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const HEX = "0123456789abcdef";
  const randHex = (n) => Array.from({ length: n }, () => HEX[(Math.random() * 16) | 0]).join("");

  // Üst çubuk çizgisi ve giriş görselinin düzleşmesi.
  const nav = $("#nav");
  const stage = $("#heroStage");
  let queued = false;
  const onScroll = () => {
    queued = false;
    nav.classList.toggle("scrolled", window.scrollY > 8);
    if (reduce || !stage) return;
    const top = stage.getBoundingClientRect().top;
    const vh = window.innerHeight;
    // Görselin üstü ekranın %90'ından %25'ine gelirken 0 → 1.
    const h = Math.min(Math.max((vh * 0.9 - top) / (vh * 0.65), 0), 1);
    document.documentElement.style.setProperty("--h", h.toFixed(4));
  };
  addEventListener("scroll", () => { if (!queued) { queued = true; requestAnimationFrame(onScroll); } }, { passive: true });
  addEventListener("resize", onScroll);
  onScroll();

  // Görünürken belirme.
  const reveals = $$(".statement > *, .numbers > div, .tour-head, .wipe-copy, .wipe-stage, .facts li, .systems > *, .install > *, .cmd");
  reveals.forEach((el) => el.classList.add("reveal"));
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
  }, { rootMargin: "0px 0px -10% 0px" });
  reveals.forEach((el, i) => { el.style.transitionDelay = `${(i % 3) * 90}ms`; io.observe(el); });

  // Sayılar: görününce sayarak gelir.
  const counts = $$(".count");
  const countIO = new IntersectionObserver((entries) => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      countIO.unobserve(e.target);
      const to = +e.target.dataset.to;
      if (reduce || to === 0) continue;
      const start = performance.now(), dur = 1400;
      const tick = (t) => {
        const k = Math.min((t - start) / dur, 1), ease = 1 - Math.pow(1 - k, 4);
        e.target.textContent = Math.round(to * ease);
        if (k < 1) requestAnimationFrame(tick);
      };
      e.target.textContent = "0";
      requestAnimationFrame(tick);
    }
  }, { threshold: 0.6 });
  counts.forEach((c) => countIO.observe(c));

  // Dosya adı → şifreli bayt dönüşümü.
  const clText = $("#clText"), clHex = $("#clHex");
  const names = ["pasaport-taramasi.pdf", "kurtarma-ifadesi.txt", "banka@ornek.com", "Tatil/2026/plan.md"];
  let cipherRunning = false;
  const cipherIO = new IntersectionObserver(async ([e]) => {
    if (!e.isIntersecting || cipherRunning || reduce) {
      if (reduce && clHex) clHex.textContent = randHex(32);
      return;
    }
    cipherRunning = true;
    let i = 0;
    while (true) {
      const name = names[i++ % names.length];
      clText.textContent = name;
      for (let f = 0; f <= 16; f++) { clHex.textContent = randHex(8 + f * 2); await sleep(45); }
      await sleep(2200);
      if (!e.target.isConnected) break;
    }
  }, { threshold: 0.5 });
  if (clText) cipherIO.observe(clText.parentElement);

  // Özellik turu: hangi adım ekranın ortasındaysa onun görüntüsü.
  const steps = $$(".step");
  const shots = $$(".tour-shot");
  const setStep = (n) => {
    steps.forEach((s) => s.classList.toggle("is-on", +s.dataset.shot === n));
    shots.forEach((img, i) => img.classList.toggle("is-on", i === n));
  };
  const stepIO = new IntersectionObserver((entries) => {
    for (const e of entries) if (e.isIntersecting) setStep(+e.target.dataset.shot);
  }, { rootMargin: "-45% 0px -45% 0px" });
  steps.forEach((s) => stepIO.observe(s));
  setStep(0);

  // Kopyala.
  $$(".copy").forEach((b) => b.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(b.dataset.copy);
      b.textContent = "Kopyalandı"; b.classList.add("ok");
      setTimeout(() => { b.textContent = "Kopyala"; b.classList.remove("ok"); }, 1600);
    } catch { /* pano izni yoksa sessiz geç */ }
  }));
})();
