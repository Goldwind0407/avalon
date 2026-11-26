// Frame-time probe for the web build, loaded only with `?perf` in the
// address. A small box in the corner shows the frames drawn each second,
// how many came late and how the game runs (WebAssembly or JavaScript,
// isolated or not); every 10 seconds the same is logged as one line of
// JSON (AVALON_PERF) for a measuring script to read.
(() => {
  const late = 1000 / 60 * 1.5;
  let last = 0, started = 0;
  let second = { frames: 0, slow: 0, from: 0 };
  let ten = { frames: 0, slow: 0, worst: 0, total: 0, gaps: [] };
  const box = document.createElement('div');
  box.style.cssText = 'position:fixed;left:calc(env(safe-area-inset-left) + 4px);' +
    'top:calc(env(safe-area-inset-top) + 4px);z-index:2147483647;pointer-events:none;' +
    'font:11px/1.35 ui-monospace,monospace;color:#9f9;background:#000a;' +
    'padding:3px 6px;border-radius:4px;white-space:pre';
  const mount = () => document.body ? document.body.append(box) : setTimeout(mount, 50);
  mount();
  const how = () => {
    const wasm = performance.getEntriesByType('resource')
      .some(e => e.name.includes('main.dart.wasm'));
    return `${wasm ? 'Wasm' : 'JS'}・${crossOriginIsolated ? '多執行緒' : '單執行緒'}・${devicePixelRatio}x`;
  };
  function frame(now) {
    if (last) {
      const gap = now - last;
      second.frames++; ten.frames++; ten.total += gap; ten.gaps.push(gap);
      if (gap > late) { second.slow++; ten.slow++; }
      if (gap > ten.worst) ten.worst = gap;
    } else {
      started = second.from = now;
    }
    last = now;
    if (now - second.from >= 1000) {
      const fps = second.frames * 1000 / (now - second.from);
      box.textContent = `${fps.toFixed(0)} fps・延遲 ${second.slow}\n${how()}`;
      box.style.color = fps >= 50 ? '#9f9' : fps >= 35 ? '#fd6' : '#f88';
      second = { frames: 0, slow: 0, from: now };
    }
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
  setInterval(() => {
    if (!ten.frames) return;
    ten.gaps.sort((a, b) => a - b);
    console.log('AVALON_PERF ' + JSON.stringify({
      seconds: Math.round((last - started) / 1000),
      fps: +(1000 * ten.frames / ten.total).toFixed(1),
      late: ten.slow, frames: ten.frames,
      p95: +ten.gaps[Math.floor(ten.gaps.length * .95)].toFixed(1),
      worst: +ten.worst.toFixed(1), dpr: devicePixelRatio,
    }));
    ten = { frames: 0, slow: 0, worst: 0, total: 0, gaps: [] };
  }, 10000);
})();
