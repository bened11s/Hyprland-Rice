// Island — liefert Cover-Bilder als CSS-Variablen und setzt die Schrift:
//   --island-art        (auf <html>)     : Cover des laufenden Titels (immer aktuell)
//   --island-art-a / -b (auf <html>)     : zwei Ebenen fuer den ganzflaechigen
//                                          Backdrop; html.island-b schaltet die
//                                          sichtbare Ebene um -> weicher Crossfade
//   --island-page-art   (auf #main-view) : Cover der gerade geoeffneten Seite
//                                          (Playlist/Album/Artist-Header), sonst entfernt
//   --island-tint       (auf <html>)     : Vibrant-Farbe des Covers als "r, g, b"
//   html.island-playing                  : Wiedergabe laeuft (Vinyl-Drehung)
//   html.island-focus                    : Fokus-Modus, Ctrl+. oder Profilmenue
// user.css zeichnet daraus Backdrop und Glows hinter Hauptansicht, NPV und Player-Pille.
(function island() {
  if (!window.Spicetify || !Spicetify.Player || !Spicetify.Player.data || !Spicetify.Platform) {
    setTimeout(island, 300);
    return;
  }

  const root = document.documentElement;

  // --- Schrift ----------------------------------------------------------------
  // Spotify setzt --encore-*-font-stack in einem @layer mit !important; das
  // schlaegt jede Regel aus user.css. Nur ein Inline-Style mit !important gewinnt.
  const body = '"Inter Variable", "Inter", "Noto Sans", sans-serif';
  const title = '"Inter Display", "Inter Variable", "Inter", sans-serif';
  root.style.setProperty("--encore-body-font-stack", body, "important");
  root.style.setProperty("--encore-title-font-stack", title, "important");
  root.style.setProperty("--encore-variable-font-stack", title, "important");

  function toHttp(raw) {
    if (!raw) return "";
    if (raw.startsWith("spotify:image:")) return "https://i.scdn.co/image/" + raw.slice("spotify:image:".length);
    return raw;
  }

  function coverUrl() {
    const item = Spicetify.Player.data && Spicetify.Player.data.item;
    const meta = (item && item.metadata) || {};
    return toHttp(meta.image_xlarge_url || meta.image_large_url || meta.image_url || "");
  }

  // Erst laden, dann setzen -> kein Flackern beim Wechsel
  function preload(url, cb) {
    const img = new Image();
    img.onload = () => cb(true);
    img.onerror = () => cb(false);
    img.src = url;
  }
  function setVar(el, name, url) {
    if (!url) { el.style.removeProperty(name); return; }
    preload(url, (ok) => ok ? el.style.setProperty(name, `url("${url}")`) : el.style.removeProperty(name));
  }

  // --- Laufender Titel: --island-art + Backdrop-Crossfade --------------------
  let currentTrackArt = null;
  let showingB = false;
  function updateTrackArt() {
    const url = coverUrl();
    if (url === currentTrackArt) return;
    currentTrackArt = url;
    if (!url) {
      root.style.removeProperty("--island-art");
      return;
    }
    preload(url, (ok) => {
      if (!ok || url !== currentTrackArt) return;
      root.style.setProperty("--island-art", `url("${url}")`);
      // in die gerade unsichtbare Ebene laden, dann umschalten
      const next = showingB ? "--island-art-a" : "--island-art-b";
      root.style.setProperty(next, `url("${url}")`);
      showingB = !showingB;
      root.classList.toggle("island-b", showingB);
    });
  }
  Spicetify.Player.addEventListener("songchange", updateTrackArt);
  updateTrackArt();

  // --- Seiten-Cover (Entity-Header) ------------------------------------------
  let currentPageArt = null;
  let tries = 0;
  function findPageArt() {
    const img = document.querySelector(
      "#main-view .main-entityHeader-imageContainer img, #main-view .main-entityHeader-image img, #main-view img.main-entityHeader-image"
    );
    return img && img.src ? img.src : "";
  }
  function updatePageArt() {
    const mainView = document.getElementById("main-view");
    if (!mainView) return;
    const url = findPageArt();
    if (!url && tries < 20) { tries++; setTimeout(updatePageArt, 150); return; }
    tries = 0;
    if (url === currentPageArt) return;
    currentPageArt = url;
    setVar(mainView, "--island-page-art", url);
  }
  function onNavigate() {
    tries = 0;
    currentPageArt = null;
    const mainView = document.getElementById("main-view");
    if (mainView) mainView.style.removeProperty("--island-page-art");
    setTimeout(updatePageArt, 50);
  }
  if (Spicetify.Platform.History && Spicetify.Platform.History.listen) {
    Spicetify.Platform.History.listen(onNavigate);
  }
  onNavigate();

  // Header-Bilder, die nach dem Routing nachgeladen werden, nachziehen
  const mo = new MutationObserver(() => {
    const url = findPageArt();
    if (url !== currentPageArt && (url || currentPageArt)) {
      currentPageArt = url;
      const mainView = document.getElementById("main-view");
      if (mainView) setVar(mainView, "--island-page-art", url);
    }
  });
  const target = document.getElementById("main-view") || document.body;
  mo.observe(target, { childList: true, subtree: true, attributes: true, attributeFilter: ["src"] });

  // --- Coverfarbe: --island-tint (r, g, b) fuer Pillen-Glow und Fortschritt --
  // Spicetify.colorExtractor und die GraphQL-Variante scheitern in Spotify
  // 1.3.4 ("Resolver not found") -> selbst aus dem Cover rechnen: 32x32
  // herunterskalieren, Pixel nach Farbton (15°-Faecher) sammeln, Gewicht =
  // Saettigung; der staerkste Faecher gewinnt. Danach auf Mindesthelligkeit
  // anheben, damit Glow und Haarlinie auf Schwarz sichtbar bleiben.
  function vibrant(img) {
    const n = 32, c = document.createElement("canvas");
    c.width = c.height = n;
    const ctx = c.getContext("2d", { willReadFrequently: true });
    ctx.drawImage(img, 0, 0, n, n);
    const px = ctx.getImageData(0, 0, n, n).data;
    const bins = new Map();
    for (let i = 0; i < px.length; i += 4) {
      const r = px[i] / 255, g = px[i + 1] / 255, b = px[i + 2] / 255;
      const max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2, d = max - min;
      if (d < 0.12 || l < 0.15 || l > 0.92) continue;          // grau, fast schwarz/weiss
      const s = d / (1 - Math.abs(2 * l - 1));
      let h = max === r ? ((g - b) / d) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
      h = (h * 60 + 360) % 360;
      const k = Math.floor(h / 15), e = bins.get(k) || { w: 0, h: 0, s: 0, l: 0 };
      e.w += s; e.h += h * s; e.s += s * s; e.l += l * s;
      bins.set(k, e);
    }
    let best = null;
    for (const e of bins.values()) if (!best || e.w > best.w) best = e;
    if (!best || best.w < 6) return "";                          // kaum Farbe im Cover
    const h = best.h / best.w, s = Math.min(1, best.s / best.w * 1.1), l = Math.min(0.75, Math.max(0.62, best.l / best.w));
    // HSL -> RGB
    const q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q;
    const ch = (t) => {
      t = (t + 1) % 1;
      const v = t < 1 / 6 ? p + (q - p) * 6 * t : t < 1 / 2 ? q : t < 2 / 3 ? p + (q - p) * (2 / 3 - t) * 6 : p;
      return Math.round(v * 255);
    };
    return [ch(h / 360 + 1 / 3), ch(h / 360), ch(h / 360 - 1 / 3)].join(", ");
  }
  let tintFor = null;
  function updateTint() {
    const url = coverUrl();
    if (url === tintFor) return;
    tintFor = url;
    if (!url) { root.style.removeProperty("--island-tint"); return; }
    const img = new Image();
    img.crossOrigin = "anonymous";                               // i.scdn.co sendet CORS
    img.onload = () => {
      if (url !== tintFor) return;
      let rgb = "";
      try { rgb = vibrant(img); } catch (e) { /* lokale Datei ohne CORS */ }
      if (rgb) root.style.setProperty("--island-tint", rgb);
      else root.style.removeProperty("--island-tint");
    };
    img.onerror = () => url === tintFor && root.style.removeProperty("--island-tint");
    img.src = url;
  }
  Spicetify.Player.addEventListener("songchange", updateTint);
  updateTint();

  // --- Abspielstatus: html.island-playing (Vinyl-Drehung des Covers) --------
  function updatePlaying() {
    root.classList.toggle("island-playing", Spicetify.Player.isPlaying());
  }
  Spicetify.Player.addEventListener("onplaypause", updatePlaying);
  updatePlaying();

  // --- Fokus-Modus: html.island-focus blendet beide Seitenleisten aus --------
  const FOCUS_KEY = "island:focus";
  function setFocus(on) {
    root.classList.toggle("island-focus", on);
    Spicetify.LocalStorage.set(FOCUS_KEY, on ? "1" : "0");
    if (focusItem) focusItem.setState(on);
  }
  let focusItem = null;
  if (Spicetify.Menu && Spicetify.Menu.Item) {
    focusItem = new Spicetify.Menu.Item("Fokus-Modus (Ctrl+.)", false, () =>
      setFocus(!root.classList.contains("island-focus")));
    focusItem.register();
  }
  if (Spicetify.Mousetrap) {
    Spicetify.Mousetrap.bind("mod+.", () => {
      setFocus(!root.classList.contains("island-focus"));
      return false;
    });
  }
  setFocus(Spicetify.LocalStorage.get(FOCUS_KEY) === "1");
})();
