{{flutter_js}}
{{flutter_build_config}}

// Flutter runs its WebAssembly build only in Chromium browsers unless told
// otherwise, and every browser on an iPhone is WebKit (Safari's engine).
// Measured, the WebAssembly build draws every effect more smoothly than the
// JavaScript one draws the light table, so WebKit is let in too, guarded
// twice, since a WebAssembly build that fails to start shows nothing at all:
//  * only where it can draw from a worker (OffscreenCanvas with WebGL 2,
//    which its multi-threaded renderer uses; iOS 17 and later);
//  * and if it has drawn no frame within 15 seconds, this device is marked
//    and the page loads again with the JavaScript build (light effects).
(() => {
  const mark = 'avalon.noWasm';
  let refused = false;
  try {
    // ?retrywasm gives the WebAssembly build another chance on this device
    if (new URLSearchParams(location.search).has('retrywasm')) localStorage.removeItem(mark);
    refused = localStorage.getItem(mark) === '1';
  } catch (_) {}
  let offscreen = false;
  try {
    const probe = !refused && typeof OffscreenCanvas !== 'undefined' &&
      new OffscreenCanvas(1, 1).getContext('webgl2');
    offscreen = Boolean(probe);
    if (probe) probe.getExtension('WEBGL_lose_context')?.loseContext();
  } catch (_) {}
  const webkit = !refused && offscreen;

  let drawn = false;
  window.addEventListener('flutter-first-frame', () => { drawn = true; }, { once: true });
  if (webkit) {
    setTimeout(() => {
      const wasm = performance.getEntriesByType('resource')
        .some(e => e.name.includes('main.dart.wasm'));
      if (drawn || !wasm) return;
      try { localStorage.setItem(mark, '1'); } catch (_) { return; }
      location.reload();
    }, 15000);
  }

  // A phone screen of three pixels to the point (every iPhone) is drawn at
  // two and scaled up by the browser: 56% fewer pixels to draw each frame,
  // and as much less drawing memory. Measured on an iPhone, changing screens
  // took the drawing up to 1.5 s at three, and in long games its memory ran
  // out and the screen stopped. (?fullres draws at the screen's own.)
  try {
    const real = window.devicePixelRatio;
    if (real > 2 && !new URLSearchParams(location.search).has('fullres')) {
      window.avalonScreenDpr = real;
      Object.defineProperty(window, 'devicePixelRatio', { get: () => 2, configurable: true });
    }
  } catch (_) {}

  _flutter.loader.load({
    config: { wasmAllowList: { webkit } },
  });
})();
