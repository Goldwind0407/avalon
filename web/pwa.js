// Errors the game itself cannot see (the drawing thread's, the browser's),
// kept short for the frame-rate reports (lib/core/web_perf_web.dart reads
// and empties the list); and a way out when the screen stops being drawn.
(() => {
  const errors = window.avalonErrors = [];
  const keep = (text) => {
    if (errors.length < 20) errors.push([performance.now(), String(text).slice(0, 80)]);
  };
  const consoleError = console.error;
  console.error = function (...args) {
    keep(args.map(String).join(' '));
    return consoleError.apply(this, args);
  };
  addEventListener('error', (e) => keep(e.message || 'error'));
  addEventListener('unhandledrejection', (e) => keep((e.reason && e.reason.message) || e.reason || 'rejection'));

  let notice = null;
  window.avalonFrozen = (frozen) => {
    if (!notice) {
      notice = document.createElement('button');
      notice.type = 'button';
      notice.className = 'avalon-update avalon-frozen';
      notice.textContent = '畫面停止更新了，點此重新載入（這局會中斷）';
      notice.addEventListener('click', () => location.reload());
      document.body.append(notice);
    }
    notice.hidden = !frozen;
  };
})();

(() => {
  if (!('serviceWorker' in navigator)) return;

  const style = document.createElement('link');
  style.rel = 'stylesheet';
  style.href = 'pwa.css';
  document.head.append(style);

  const dialog = document.createElement('dialog');
  dialog.className = 'avalon-offline';
  dialog.setAttribute('aria-labelledby', 'avalon-offline-title');
  dialog.innerHTML = `
    <h2 id="avalon-offline-title">離線遊玩</h2>
    <p data-core role="status">正在啟用離線功能…</p>
    <button type="button" data-retry hidden>重試啟用</button>
    <p data-media role="status">遊玩時會儲存用到的卡圖和音效。想離線開新局，請先下載完整遊戲素材。</p>
    <progress data-media-progress aria-label="遊戲素材下載進度" hidden></progress>
    <button type="button" data-download-media disabled>下載遊戲素材</button>
    <p data-voice role="status">可以先看字幕遊玩。下載語音後，離線也能聽電腦玩家發言。</p>
    <progress data-voice-progress aria-label="電腦語音下載進度" hidden></progress>
    <button type="button" data-download disabled>下載電腦語音</button>
    <p>多機遊玩需要網路。iPhone 可用 Safari 的「加入主畫面」開啟網頁 App。</p>
    <form method="dialog"><button autofocus>關閉</button></form>
  `;
  document.body.append(dialog);

  const coreText = dialog.querySelector('[data-core]');
  const retry = dialog.querySelector('[data-retry]');
  const service = navigator.serviceWorker;
  const workerUrl = new URL('sw.js', document.baseURI);
  const packs = {
    media: { name: '遊戲素材', button: '[data-download-media]', message: 'avalon-download-media',
      ready: '離線準備完成。一機遊玩、跟電腦遊玩已可離線開局。' },
    voice: { name: '電腦語音', button: '[data-download]', message: 'avalon-download-voices',
      ready: '電腦語音已下載，離線也能播放。' },
  };
  for (const [kind, pack] of Object.entries(packs)) {
    pack.text = dialog.querySelector(`[data-${kind}]`);
    pack.progress = dialog.querySelector(`[data-${kind}-progress]`);
    pack.download = dialog.querySelector(pack.button);
    pack.download.onclick = () => {
      pack.download.disabled = true;
      pack.text.textContent = `正在準備下載${pack.name}…`;
      service.controller?.postMessage(pack.message);
    };
  }

  function updateConnectivity() {
    if (!navigator.onLine && !service.controller) {
      coreText.textContent = '需要先連網下載遊戲，才能離線開啟。';
    }
    requestStatus();
  }

  function requestStatus() {
    if (service.controller?.scriptURL !== workerUrl.href) return;
    coreText.hidden = true;
    retry.hidden = true;
    service.controller.postMessage('avalon-status');
  }

  function showProgress(bar, done, total) {
    bar.hidden = false;
    bar.max = Math.max(1, total);
    bar.value = done;
    return total ? Math.floor(done * 100 / total) : 0;
  }

  function coreError() {
    if (service.controller?.scriptURL === workerUrl.href) return;
    coreText.textContent = '無法啟用離線功能，請確認網路後重試。';
    retry.hidden = false;
  }

  service.addEventListener('message', ({ data }) => {
    if (data?.kind === 'status' && Object.hasOwn(packs, data.pack)) {
      const pack = packs[data.pack];
      pack.download.textContent = `下載${pack.name}（約 ${Math.ceil(data.bytes / 1048576)} MiB）`;
      pack.download.disabled = data.ready || data.busy || !navigator.onLine;
      if (data.ready) {
        pack.progress.hidden = true;
        pack.text.textContent = pack.ready;
      } else if (data.busy && pack.progress.hidden) {
        pack.text.textContent = `正在下載${pack.name}，請保持 App 開啟。`;
        pack.progress.hidden = false;
        pack.progress.removeAttribute('value');
      }
    }
    if (Object.hasOwn(packs, data?.kind)) {
      const pack = packs[data.kind];
      if (data.state === 'downloading') {
        pack.download.disabled = true;
        const percent = showProgress(pack.progress, data.done, data.total);
        pack.text.textContent = `正在下載${pack.name}（${percent}%），請保持 App 開啟。`;
      } else {
        pack.progress.hidden = true;
        if (data.state === 'ready') {
          pack.text.textContent = pack.ready;
        } else {
          pack.text.textContent = `${pack.name}下載中斷，重試時會接續已存好的檔案。` +
            (data.reason ? `（${data.reason}）` : '');
        }
        pack.download.disabled = data.state === 'ready' || !navigator.onLine;
      }
    }
  });

  // A new version takes over as soon as it is downloaded (sw.js). The game
  // on screen is the old one until the page reloads: at once when it has
  // only just been opened, and otherwise by the player's tap whenever off
  // the table (window.avalonStage, set by the game), never in a game.
  const openedAt = Date.now();
  let controlled = Boolean(service.controller), newVersion = false;
  const update = document.createElement('button');
  update.type = 'button';
  update.className = 'avalon-update';
  update.textContent = '有新版本，點此更新';
  update.hidden = true;
  document.body.append(update);
  const offTable = () => (window.avalonStage ?? 'menu') === 'menu';
  update.onclick = () => {
    update.textContent = '更新中…';
    location.reload();
  };
  service.addEventListener('controllerchange', () => {
    // the very first version taking control replaces nothing
    if (controlled) {
      newVersion = true;
      if (Date.now() - openedAt < 12000 && offTable()) location.reload();
    }
    controlled = true;
  });
  // which release this is (tool/prepare_pwa.py), on the menu only: the
  // folder uploaded starts with the same eight characters
  const release = document.createElement('div');
  release.className = 'avalon-release';
  release.textContent = `版本 ${String(window.avalonRelease ?? '開發中').slice(0, 8)}`;
  document.body.append(release);
  setInterval(() => {
    update.hidden = !newVersion || !offTable();
    release.hidden = !offTable();
  }, 1000);

  async function register() {
    try {
      const registration = await service.register(workerUrl, { updateViaCache: 'none' });
      function watchInstall() {
        const worker = registration.installing;
        worker?.addEventListener('statechange', () => {
          if (worker.state === 'redundant') coreError();
        });
      }
      registration.addEventListener('updatefound', watchInstall);
      watchInstall();
      // back from the background, an installed app looks for a new version
      document.addEventListener('visibilitychange', () => {
        if (!document.hidden) registration.update().catch(() => {});
      });
      requestStatus();
    } catch {
      coreError();
    }
  }

  retry.onclick = () => {
    retry.hidden = true;
    coreText.textContent = '正在啟用離線功能…';
    register();
  };
  service.addEventListener('controllerchange', requestStatus);
  window.addEventListener('online', updateConnectivity);
  window.addEventListener('offline', updateConnectivity);
  window.openAvalonOffline = () => {
    if (!dialog.open) dialog.showModal();
    updateConnectivity();
  };

  const rotate = document.createElement('div');
  rotate.className = 'avalon-rotate';
  rotate.textContent = '請將手機轉為橫向遊玩';
  document.body.append(rotate);
  updateConnectivity();
  register();
})();

