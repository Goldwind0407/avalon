// The table of a game against the computers, drawn by the browser itself
// over the app (lib/features/html_table/html_table_screen.dart). The game
// and its computers stay in the app: it sends the table what the player may
// see (update), and the table asks it for moves, sounds and the app's own
// pages (host). This file only stages the game, as lib/features/game/
// game_screen.dart does with the app's own drawing: the same pieces, the
// same steps, the same timings.
(() => {
  'use strict';
  const IMG = 'assets/assets/images/';
  const ART = {
    roleBack: IMG + 'cards/card_back_role.webp',
    questBack: IMG + 'cards/card_back_quest.webp',
    voteBack: IMG + 'cards/card_back_vote.webp',
    seatBack: IMG + 'cards/card_back_vote_seat.webp',
    seatYes: IMG + 'cards/vote_approve_seat.webp',
    seatNo: IMG + 'cards/vote_reject_seat.webp',
    approve: IMG + 'cards/vote_approve.webp',
    reject: IMG + 'cards/vote_reject.webp',
    success: IMG + 'cards/quest_success.webp',
    fail: IMG + 'cards/quest_fail.webp',
    loyaltyGood: IMG + 'cards/loyalty_good.webp',
    loyaltyEvil: IMG + 'cards/loyalty_evil.webp',
    loyaltyBack: IMG + 'cards/lancelot_switch_back.webp',
    loyaltySwitch: IMG + 'cards/lancelot_switch.webp',
    loyaltyStay: IMG + 'cards/lancelot_no_switch.webp',
    lady: IMG + 'roles/lady_of_the_lake.webp',
    sword: IMG + 'tokens/excalibur.webp',
    crown: IMG + 'tokens/leader_token.webp',
    shield: IMG + 'tokens/team_token.webp',
    round: IMG + 'tokens/round_marker.webp',
    track: IMG + 'tokens/vote_track_marker.webp',
    scoreGood: IMG + 'tokens/score_good.webp',
    scoreEvil: IMG + 'tokens/score_evil.webp',
  };
  const boardArt = n => `${IMG}boards/board_${Math.min(10, Math.max(5, n))}p.webp`;
  const GOOD = '#6fc3ff', EVIL = '#ff6b5e', GOLD = '#e7c47b';
  const NUMERALS = ['一', '二', '三', '四', '五'];
  const ASPECT = 2 / 3;

  // where the pieces lie on each board (lib/features/table/board_layout.dart),
  // in the pictures' 1440 × 1080 pixels: quests, score slots, vote track
  const LAYOUT = {
    5: [[[161, 505], [439, 496], [707, 503], [984, 499], [1263, 499]],
      [[264, 623], [548, 628], [819, 627], [1082, 630], [1354, 625]],
      [[153, 899], [352, 898], [553, 894], [745, 902], [936, 890]]],
    6: [[[162, 527], [440, 523], [710, 532], [983, 524], [1259, 532]],
      [[246, 637], [524, 641], [798, 642], [1071, 654], [1341, 654]],
      [[162, 908], [364, 907], [559, 901], [750, 909], [934, 900]]],
    7: [[[184, 502], [451, 498], [714, 498], [970, 508], [1251, 505]],
      [[274, 612], [537, 604], [804, 618], [1080, 610], [1323, 601]],
      [[161, 881], [361, 883], [553, 882], [742, 886], [933, 881]]],
    8: [[[185, 472], [455, 479], [720, 478], [988, 469], [1260, 469]],
      [[275, 584], [541, 599], [810, 592], [1076, 599], [1346, 603]],
      [[150, 900], [345, 900], [538, 897], [728, 902], [918, 898]]],
    9: [[[186, 491], [448, 506], [720, 506], [993, 493], [1257, 492]],
      [[272, 611], [540, 612], [810, 612], [1075, 617], [1339, 618]],
      [[160, 905], [352, 894], [549, 901], [734, 906], [924, 897]]],
    10: [[[184, 487], [454, 496], [718, 495], [989, 483], [1262, 484]],
      [[282, 609], [532, 618], [804, 611], [1071, 615], [1344, 610]],
      [[157, 892], [346, 892], [534, 889], [722, 897], [912, 890]]],
  };

  const ICON = {
    back: 'M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z',
    sound: 'M3 9v6h4l5 5V4L7 9H3zm13.5 3A4.5 4.5 0 0 0 14 7.97v8.05A4.47 4.47 0 0 0 16.5 12zM14 3.23v2.06a7 7 0 0 1 0 13.42v2.06A9 9 0 0 0 14 3.23z',
    rules: 'M11.07 12.85c.77-1.39 2.25-2.21 3.11-3.44.91-1.29.4-3.7-2.18-3.7-1.69 0-2.52 1.28-2.87 2.34L6.54 6.96C7.25 4.83 9.18 3 11.99 3c2.35 0 3.96 1.07 4.78 2.41.7 1.15 1.11 3.3.03 4.9-1.2 1.77-2.35 2.31-2.97 3.45-.25.46-.35.76-.35 2.24h-2.89c-.01-.78-.13-2.05.48-3.15zM14 20c0 1.1-.9 2-2 2s-2-.9-2-2 .9-2 2-2 2 .9 2 2z',
    log: 'M15 4v7H5.17L4 12.17V4h11m1-2H3a1 1 0 0 0-1 1v14l4-4h10a1 1 0 0 0 1-1V3a1 1 0 0 0-1-1zm5 4h-2v9H6v2a1 1 0 0 0 1 1h11l4 4V7a1 1 0 0 0-1-1z',
    book: 'M21 5c-1.11-.35-2.33-.5-3.5-.5-1.95 0-4.05.4-5.5 1.5-1.45-1.1-3.55-1.5-5.5-1.5S2.45 4.9 1 6v14.65c0 .25.25.5.5.5.1 0 .15-.05.25-.05C3.1 20.45 5.05 20 6.5 20c1.95 0 4.05.4 5.5 1.5 1.35-.85 3.8-1.5 5.5-1.5 1.65 0 3.35.3 4.75 1.05.1.05.15.05.25.05.25 0 .5-.25.5-.5V6c-.6-.45-1.25-.75-2-1zm0 13.5c-1.1-.35-2.3-.5-3.5-.5-1.7 0-4.15.65-5.5 1.5V8c1.35-.85 3.8-1.5 5.5-1.5 1.2 0 2.4.15 3.5.5v11.5z',
    talk: 'M9 13c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4zm6.76-9.64-1.68 1.69c.84 1.18.84 2.71 0 3.89l1.68 1.69c2.02-2.02 2.02-5.07 0-7.27zM20.07 2l-1.63 1.63c2.77 3.02 2.77 7.56 0 10.74L20.07 16c3.9-3.89 3.91-9.95 0-14z',
    lock: 'M18 8h-1V6c0-2.76-2.24-5-5-5S7 3.24 7 6v2H6c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2zM9 6c0-1.66 1.34-3 3-3s3 1.34 3 3v2H9V6zm9 14H6V10h12v10zm-6-3c1.1 0 2-.9 2-2s-.9-2-2-2-2 .9-2 2 .9 2 2 2z',
    close: 'M19 6.41 17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z',
  };
  const svg = name => `<svg viewBox="0 0 24 24"><path d="${ICON[name]}"/></svg>`;

  // ───────────── little tools ─────────────
  const esc = t => String(t ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  function el(tag, cls, html) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (html != null) e.innerHTML = html;
    return e;
  }
  const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
  const seg = (t, a, b) => b <= a ? (t >= b ? 1 : 0) : clamp((t - a) / (b - a), 0, 1);
  const easeOut = t => 1 - (1 - t) * (1 - t);
  const easeOutCubic = t => 1 - Math.pow(1 - t, 3);
  const easeInCubic = t => t * t * t;
  const easeInOutCubic = t => t < .5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
  const easeOutBack = t => { const c1 = 1.70158, c3 = c1 + 1; return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2); };
  const shuffled = list => {
    const a = [...list];
    for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; }
    return a;
  };

  // ───────────── the table's own state ─────────────
  let host = null, S = null, root = null, built = null, s = 1;
  let ui = null;
  function freshUi() {
    return {
      selected: new Set(), choice: null, committing: false, hiding: false, interlude: false,
      dealing: false, waiting: null, voteLanding: new Set(), shieldLanding: new Set(), pileLanding: 0,
      crownFlying: false, revealed: new Set(), verdict: false, assassinShown: false, order: [],
      epoch: 0, timers: [], secretKey: null, secret: null, questKey: null, endKey: null,
      talkKey: null, talk: null, modal: null, scored: 0, ticker: null, lastSecond: null,
    };
  }
  const call = (type, arg) => { try { return host ? String(host(type, typeof arg === 'string' ? arg : JSON.stringify(arg ?? '')) ?? '') : ''; } catch (e) { console.error(e); return ''; } };
  const sound = name => call('sound', name);
  const player = i => `${i + 1} 號 【${S.names[i]}】`;
  const me = () => S.me;

  function after(ms, fn) {
    const epoch = ui.epoch;
    const t = setTimeout(() => {
      ui.timers = ui.timers.filter(x => x !== t);
      if (ui && epoch === ui.epoch && root) fn();
    }, ms);
    ui.timers.push(t);
  }
  function invalidate() {
    ui.epoch++;
    ui.timers.forEach(clearTimeout);
    ui.timers = [];
    if (built) built.flights.innerHTML = '';
  }

  // a two-sided card; `up` shows its face
  function card(back, front, w, h, { up = false, flip = 420 } = {}) {
    const c = el('div', 'at-card' + (up ? ' up now' : ''));
    c.style.width = w + 'px';
    c.style.height = h + 'px';
    c.style.setProperty('--flip', flip + 'ms');
    c.innerHTML = `<div class="in"><div class="at-face back"><img src="${back}" alt=""></div>` +
      `<div class="at-face front"><img src="${front}" alt=""></div></div>`;
    if (up) requestAnimationFrame(() => requestAnimationFrame(() => c.classList.remove('now')));
    return c;
  }
  function turnCard(c, up, onDone) {
    const inner = c.querySelector('.in');
    let done = false;
    const finish = () => { if (!done) { done = true; onDone?.(); } };
    inner.addEventListener('transitionend', finish, { once: true });
    setTimeout(finish, parseFloat(c.style.getPropertyValue('--flip') || 420) + 120);
    c.classList.toggle('up', up);
  }
  function face(src, w, h, cls = '') {
    const f = el('div', 'at-face ' + cls, `<img src="${src}" alt="">`);
    f.style.position = 'relative';
    f.style.width = w + 'px';
    f.style.height = h + 'px';
    return f;
  }
  function button(label, onClick, { plain = false, cls = '' } = {}) {
    const b = el('button', `at-btn ${plain ? 'plain ' : ''}${cls}`);
    b.textContent = label;
    b.addEventListener('click', e => { e.stopPropagation(); if (!b.disabled) onClick(); });
    return b;
  }
  function appear(e, { delay = 0, x = 0, y = 0, scale = 1, ms = 400 } = {}) {
    e.classList.add('at-appear');
    e.style.setProperty('--ax', x + 'px');
    e.style.setProperty('--ay', y + 'px');
    e.style.setProperty('--as', scale);
    e.style.animationDelay = delay + 'ms';
    e.style.animationDuration = ms + 'ms';
    return e;
  }
  function sparks(kind, count, { seed = 0 } = {}) {
    const box = el('div', 'at-sparks');
    for (let i = 0; i < count; i++) {
      const p = el('i', 'at-spark ' + kind);
      const r = (k) => { const x = Math.sin((i + 1) * 12.9898 * (k + 1) + seed * 78.233) * 43758.5453; return x - Math.floor(x); };
      p.style.left = (r(0) * 100) + '%';
      p.style.top = (40 + r(1) * 60) + '%';
      p.style.setProperty('--dx', ((r(2) - .5) * 80) + 'px');
      p.style.setProperty('--dy', (-(60 + r(3) * 160)) + 'px');
      p.style.setProperty('--d', (2.2 + r(4) * 2.4) + 's');
      p.style.animationDelay = (-r(5) * 3) + 's';
      box.append(p);
    }
    return box;
  }
  function glow(color, size, delay) {
    const g = el('div', 'at-glow');
    g.style.setProperty('--c', color);
    g.style.width = g.style.height = size + 'px';
    g.style.animationDelay = delay + 'ms';
    return g;
  }
  function rel(e) {
    if (!e || !built) return null;
    const r = e.getBoundingClientRect(), t = built.shake.getBoundingClientRect();
    if (!r.width && !r.height) return null;
    return { x: r.left - t.left, y: r.top - t.top, w: r.width, h: r.height };
  }
  function shake(amount) {
    const e = built?.shake;
    if (!e) return;
    e.style.setProperty('--amp', amount * s);
    e.classList.remove('shake');
    void e.offsetWidth;
    e.classList.add('shake');
  }
  function bump(i) {
    const p = built?.seats[i]?.plate;
    if (!p) return;
    p.classList.remove('at-bump');
    void p.offsetWidth;
    p.classList.add('at-bump');
  }

  // a piece carried across the table, in an arc
  function flight({ from, to, make, delay = 0, duration = 480, arc = 0, turns = 0, onDone }) {
    if (!from || !to || !built) { onDone?.(); return; }
    const piece = make(to.w, to.h);
    piece.style.position = 'absolute';
    piece.style.left = to.x + 'px';
    piece.style.top = to.y + 'px';
    piece.style.width = to.w + 'px';
    piece.style.height = to.h + 'px';
    built.flights.append(piece);
    const fx = from.x + from.w / 2, fy = from.y + from.h / 2;
    const tx = to.x + to.w / 2, ty = to.y + to.h / 2;
    const k = from.w / to.w;
    const frames = [];
    for (let i = 0; i <= 12; i++) {
      const t = i / 12, e = easeInOutCubic(t);
      const x = (fx - tx) * (1 - e), y = (fy - ty) * (1 - e) + arc * 4 * e * (1 - e);
      const sc = k + (1 - k) * e;
      frames.push({ transform: `translate(${x}px, ${y}px) rotate(${turns * 360 * e}deg) scale(${sc})` });
    }
    piece.style.visibility = 'hidden';
    const epoch = ui.epoch;
    const go = setTimeout(() => {
      piece.style.visibility = '';
      const a = piece.animate(frames, { duration, easing: 'linear', fill: 'both' });
      a.onfinish = () => { piece.remove(); if (ui && epoch === ui.epoch) onDone?.(); };
    }, delay);
    ui.timers.push(go);
  }

  // ───────────── building the table ─────────────
  function build() {
    if (root) root.remove();
    root = el('div');
    root.id = 'at';
    root.innerHTML = `
      <div id="at-wood"></div>
      <div id="at-safe"><div id="at-shake">
        <div id="at-left" class="at-col"></div>
        <div id="at-mid"><div id="at-mat">
          <div id="at-banner"></div>
          <div id="at-center"><div id="at-board"><div id="at-board-tilt"><img id="at-board-img" alt=""></div></div><div id="at-talk"></div></div>
          <div id="at-bar"></div>
        </div></div>
        <div id="at-right" class="at-col"></div>
        <div id="at-props"><div id="at-pile"></div><div id="at-deck"></div><div id="at-stamp"></div></div>
        <div id="at-announce"><b></b><span></span></div>
        <div id="at-quest" class="at-scrim"></div>
        <div id="at-end" class="at-scrim"></div>
        <div id="at-secret" class="at-scrim"></div>
        <div id="at-flights"></div>
      </div></div>
      <div id="at-toasts"></div>`;
    document.body.append(root);
    const $ = id => root.querySelector('#' + id);
    built = {
      shake: $('at-shake'), left: $('at-left'), right: $('at-right'), mat: $('at-mat'), banner: $('at-banner'),
      center: $('at-center'), board: $('at-board'), tilt: $('at-board-tilt'), talk: $('at-talk'), bar: $('at-bar'),
      pile: $('at-pile'), deck: $('at-deck'), stamp: $('at-stamp'), announce: $('at-announce'),
      quest: $('at-quest'), end: $('at-end'), secret: $('at-secret'), flights: $('at-flights'), toasts: $('at-toasts'),
      seats: [], tokens: {}, n: S.names.length, gen: S.gen,
    };
    built.tilt.querySelector('img').src = boardArt(built.n);
    for (let j = 0; j < 3; j++) {
      const f = el('div', 'at-face', `<img src="${ART.roleBack}" alt="">`);
      f.style.left = f.style.top = (-j * 1.6) + 'px';
      built.deck.append(f);
    }
    // seats: up the left side from seat 1, down the right
    const n = built.n, half = Math.ceil(n / 2);
    const left = [], right = [];
    for (let i = half - 1; i >= 0; i--) left.push(i);
    for (let i = half; i < n; i++) right.push(i);
    const seatOf = (i, row, onLeft) => {
      const seat = el('div', 'at-seat ' + (onLeft ? 'at-in-left' : 'at-in-right'));
      seat.style.animationDelay = (120 + 70 * row) + 'ms';
      seat.innerHTML = `<div class="at-seat-row"><button class="at-plate"><span class="at-no">${i + 1}</span>` +
        `<span class="at-name">${esc(S.names[i])}</span></button>` +
        `<div class="at-pieces"><div class="at-shield"></div><div class="at-vote"></div></div></div>` +
        `<div class="at-crown"></div><div class="at-badges"></div>`;
      const q = c => seat.querySelector(c);
      const parts = { root: seat, plate: q('.at-plate'), shield: q('.at-shield'), vote: q('.at-vote'),
        crown: q('.at-crown'), badges: q('.at-badges'), state: {} };
      parts.plate.addEventListener('click', () => onSeat(i));
      built.seats[i] = parts;
      return seat;
    };
    left.forEach((i, row) => built.left.append(seatOf(i, row, true)));
    right.forEach((i, row) => built.right.append(seatOf(i, row, false)));
    // dust in the light
    for (let i = 0; i < 26; i++) {
      const d = el('i', 'at-dust');
      d.style.left = Math.random() * 100 + '%';
      d.style.top = Math.random() * 100 + '%';
      d.style.setProperty('--dx', (Math.random() * 80 - 40) + 'px');
      d.style.setProperty('--dy', (Math.random() * -90 - 20) + 'px');
      d.style.animationDuration = (5 + Math.random() * 6) + 's';
      d.style.animationDelay = (-Math.random() * 8) + 's';
      built.shake.append(d);
    }
    // the banner: leave, sound | what is going on | rules, record, notebook
    const round = (icon, tip, fn) => {
      const b = el('button', 'at-round', svg(icon));
      b.setAttribute('aria-label', tip);
      b.addEventListener('click', fn);
      return b;
    };
    built.title = el('div');
    built.title.id = 'at-title';
    built.banner.append(round('back', '返回設定', leave), round('sound', '音效設定', () => call('open', 'sound')),
      built.title, round('rules', '遊戲規則', () => call('open', 'rules')),
      round('log', '討論紀錄', openLog), round('book', '玩家筆記', openNotebook));
    built.quest.addEventListener('click', () => built.questReveal?.skip());
    built.end.addEventListener('click', () => built.endReveal?.skip());
    layout();
  }

  function layout() {
    if (!root || !built) return;
    const safe = root.querySelector('#at-safe').getBoundingClientRect();
    s = clamp(Math.min(safe.height / 390, safe.width / 800), .72, 2.2);
    root.style.setProperty('--s', s);
    // the board: 4:3, as large as the middle of the mat allows
    const c = built.center.getBoundingClientRect();
    const w = Math.min(c.width, c.height * 4 / 3);
    built.board.style.width = w + 'px';
    built.board.style.height = (w * .75) + 'px';
    built.boardK = w / 1440;
    if (S) renderBoard(true);
  }

  // ───────────── the moves ─────────────
  function act(move, { interlude = false } = {}) {
    ui.selected.clear();
    ui.choice = null;
    ui.committing = ui.hiding = false;
    ui.shieldLanding.clear();
    if (interlude) {
      ui.interlude = true;
      after(1000, () => { ui.interlude = false; render(); });
    }
    ui.waiting = S.turn;
    call('act', move);
    render();
  }

  const pendingMove = () => S.pending && ui.waiting !== S.turn;
  const secretVisible = () => !ui.dealing && !ui.interlude && pendingMove();
  const iPickTeam = () => S.phase === 'team' && S.leader === me();
  const discussing = () => S.phase === 'discussion' || S.phase === 'freeDiscussion';
  const expansionActor = () => ['lady', 'ladyResult'].includes(S.phase) ? S.ladyHolder
    : ['excalibur', 'excaliburResult'].includes(S.phase) ? S.swordHolder : null;

  function onSeat(i) {
    if (!iPickTeam() || !(ui.selected.has(i) || ui.selected.size < S.need)) return;
    toggleSeat(i);
  }

  /// The leader hands a shield to (or takes it back from) a seat.
  function toggleSeat(i) {
    sound('tap');
    if (ui.selected.has(i)) {
      ui.selected.delete(i);
      ui.shieldLanding.delete(i);
      render();
      return;
    }
    ui.selected.add(i);
    ui.shieldLanding.add(i);
    render();
    const land = () => {
      if (!ui.shieldLanding.has(i)) return;
      sound('token');
      ui.shieldLanding.delete(i);
      bump(i);
      render();
    };
    const from = rel(built.seats[S.leader].plate), to = rel(built.seats[i].shield);
    if (!from || !to) return land();
    flight({
      from: { x: from.x + from.w / 2 - to.w / 2, y: from.y + from.h / 2 - to.h / 2, w: to.w, h: to.h }, to,
      duration: 420, arc: -22 * s, make: () => el('div', 'at-shield', `<img src="${ART.shield}" alt="">`),
      onDone: land,
    });
  }

  /// Turns the chosen card face down, then plays it onto the table.
  function commit(kind) {
    if (ui.committing || ui.choice === null) return;
    sound('flip');
    const picked = ui.choice, turn = S.turn;
    const pick = ui.secret?.cards?.[String(picked)];
    ui.committing = true;
    ui.secret?.update();
    after(430, () => {
      if (turn !== S.turn) { ui.committing = false; ui.secret?.update(); return; }
      const from = rel(pick?.querySelector('.at-card'));
      const mine = me();
      if (kind === 'vote') ui.voteLanding.add(mine); else ui.pileLanding++;
      act(kind === 'vote' ? { move: 'vote', approve: picked } : { move: 'quest', success: picked }, { interlude: true });
      requestAnimationFrame(() => {
        const to = rel(kind === 'vote' ? built.seats[mine].vote : built.pile);
        const back = kind === 'vote' ? ART.voteBack : ART.questBack;
        flight({
          from, to, duration: 640, arc: -34 * s, turns: .5,
          make: (w, h) => face(back, w, h),
          onDone: () => {
            sound('seal');
            if (kind === 'vote') { ui.voteLanding.delete(mine); bump(mine); } else ui.pileLanding = Math.max(0, ui.pileLanding - 1);
            render();
          },
        });
      });
    });
  }

  function leave() {
    if (S.phase === 'finished') return call('leave');
    dialog('結束這場對局？', '<p>目前進度不會保存，返回後可以重新發牌。</p>', [
      ['繼續遊戲', null],
      ['返回設定', () => call('leave')],
    ]);
  }
  function openNotebook() {
    if (ui.dealing || ui.interlude) return;
    call('open', 'notebook');
  }

  // ───────────── reacting to the game ─────────────
  let prev = null;
  function changed(old, now) {
    if (!old || now.gen !== old.gen || (now.phase === old.phase &&
        (now.history.length !== old.history.length || now.rejections !== old.rejections))) {
      startTable();
      return;
    }
    if (now.phase !== old.phase) {
      ui.choice = null;
      ui.selected.clear();
      ui.hiding = ui.committing = false;
      if (now.phase === 'discussion') hideAnnouncement();
    }
    if (now.phase !== 'voteResult') resetVotes();
    if (now.phase === 'questResult' && old.phase !== 'questResult') ui.order = orderOf(now.history.at(-1));
    if (now.phase === 'team' && old.phase !== 'team') {
      if (now.leader !== old.leader) passCrown(old.leader, now.leader);
      if (old.phase !== 'voteResult') announceQuest(old.phase);
    }
  }

  function startTable() {
    if (ui?.modal) closeModal();
    invalidate();
    const keep = ui ? { scored: ui.scored } : null;
    ui = freshUi();
    if (keep && built && built.gen === S.gen) ui.scored = keep.scored;
    if (!built || built.gen !== S.gen || built.n !== S.names.length) {
      build();
      ui.scored = S.history.length - (S.phase === 'questResult' ? 1 : 0);
    }
    if (S.phase === 'identity' && S.confirmed.length === 0) deal();
    if (S.phase === 'questResult') ui.order = orderOf(S.history.at(-1));
  }

  const orderOf = q => shuffled([...Array(q.team.length - q.fails).fill(true), ...Array(q.fails).fill(false)]);

  /// Deals one face-down role card from the deck to every seat.
  function deal() {
    ui.dealing = true;
    const n = S.names.length;
    after(900, () => {
      const deck = rel(built.deck);
      for (let i = 0; i < n; i++) {
        const plate = rel(built.seats[i].plate);
        if (!deck || !plate) continue;
        const w = deck.w * .5, h = deck.h * .5;
        flight({
          from: deck, to: { x: plate.x + plate.w / 2 - w / 2, y: plate.y + plate.h / 2 - h / 2, w, h },
          delay: 120 * i, duration: 480, arc: -28 * s, turns: i % 2 ? -.5 : .5,
          make: (w2, h2) => face(ART.roleBack, w2, h2),
          onDone: () => { sound('deal'); bump(i); },
        });
      }
      after(120 * (n - 1) + 480 + 280, () => {
        ui.dealing = false;
        render();
        if (S.phase === 'identity' && !S.confirmed.includes(me())) sound('flip');
      });
    });
    render();
  }

  /// The crown is carried from the old leader to the new one.
  function passCrown(from, to) {
    ui.crownFlying = true;
    const land = () => { sound('token'); ui.crownFlying = false; bump(to); render(); };
    requestAnimationFrame(() => {
      const a = rel(built.seats[from].crown), b = rel(built.seats[to].crown);
      if (!a || !b) return land();
      flight({ from: a, to: b, delay: 350, duration: 850, arc: -46 * s,
        make: () => el('div', 'at-crown', `<img src="${ART.crown}" alt="">`), onDone: land });
    });
  }

  function announceQuest(oldPhase) {
    const card = S.lancelot > 0 && S.quest <= 5 ? S.loyalty[S.quest - 1] : null;
    if (card === true) sound('magic');
    const delay = ['questResult', 'ladyResult'].includes(oldPhase) ? 1500 : 350;
    if (card === true) {
      after(delay + 2000, () => toast({ title: '轉換陣營卡翻開', text: '兩位蘭斯洛特暗中交換了陣營，出牌限制與勝負都依新的陣營計算。', image: ART.loyaltySwitch }));
    }
    const a = built.announce;
    a.querySelector('b').textContent = `第${NUMERALS[S.quest - 1]}次遠征`;
    a.querySelector('span').textContent = `隊長 ${player(S.leader)}　·　派出 ${S.need} 人` +
      (S.failsNeeded === 2 ? '　·　需兩張失敗' : '') + (card === true ? '　·　陣營轉換！' : '') +
      (card === false && S.lancelot === 1 ? '　·　轉換陣營卡：不變' : '');
    a.classList.remove('go');
    void a.offsetWidth;
    a.style.animationDelay = delay + 'ms';
    a.classList.add('go');
  }
  function hideAnnouncement() { built?.announce.classList.remove('go'); }

  function resetVotes() {
    ui.revealed.clear();
    ui.verdict = false;
  }

  // ───────────── drawing it ─────────────
  function render() {
    if (!root || !S || !built) return;
    renderSeats();
    renderBanner();
    renderCenter();
    renderBar();
    renderProps();
    renderLayers();
  }

  function highlight(i) {
    if (discussing()) return S.speaker === i;
    if (S.phase === 'team') return ui.selected.has(i);
    const actor = expansionActor();
    if (actor != null) return i === actor;
    switch (S.phase) {
      case 'identity': return !S.confirmed.includes(i);
      case 'vote': return !S.voted.includes(i);
      case 'quest': return S.team.includes(i) && !S.played.includes(i);
      default: return false;
    }
  }

  function renderSeats() {
    const phase = S.phase;
    const picking = iPickTeam();
    S.names.forEach((_, i) => {
      const seat = built.seats[i], st = seat.state;
      const onTeam = phase === 'team' ? ui.selected.has(i) && !ui.shieldLanding.has(i)
        : ['discussion', 'freeDiscussion', 'vote', 'voteResult', 'quest', 'questResult'].includes(phase) && S.team.includes(i);
      if (st.onTeam !== onTeam) {
        st.onTeam = onTeam;
        seat.shield.innerHTML = onTeam ? `<img src="${ART.shield}" alt="">` : '';
      }
      const leader = i === S.leader && phase !== 'finished' && !ui.crownFlying;
      if (st.leader !== leader) {
        st.leader = leader;
        seat.crown.innerHTML = leader ? `<img src="${ART.crown}" alt="">` : '';
      }
      seat.plate.classList.toggle('hl', highlight(i));
      seat.plate.classList.toggle('pick', picking && (ui.selected.has(i) || ui.selected.size < S.need));
      const lady = S.ladyHolder === i && phase !== 'finished';
      const sword = S.swordHolder === i && ['discussion', 'freeDiscussion', 'vote', 'voteResult', 'quest', 'excalibur', 'excaliburResult'].includes(phase);
      const badges = `${lady ? 1 : 0}${sword ? 1 : 0}`;
      if (st.badges !== badges) {
        st.badges = badges;
        seat.badges.innerHTML = (lady ? `<span class="lady"><img src="${ART.lady}" alt=""></span>` : '') +
          (sword ? `<span><img src="${ART.sword}" alt=""></span>` : '');
        seat.root.classList.toggle('badged', lady || sword);
      }
      // the vote card lying by the seat
      const vote = ui.voteLanding.has(i) ? 'none'
        : phase === 'vote' ? (S.voted.includes(i) ? 'hidden' : 'none')
          : phase === 'voteResult' ? (ui.voteLanding.size ? 'hidden' : S.votes[i] ? 'yes' : 'no') : 'none';
      if (st.vote !== vote) {
        const was = st.vote;
        st.vote = vote;
        if (vote === 'none') { seat.vote.innerHTML = ''; st.card = null; return; }
        if (!st.card) {
          const w = 26 * s, h = 39 * s;
          st.card = card(ART.seatBack, vote === 'no' ? ART.seatNo : ART.seatYes, w, h);
          st.card.style.width = st.card.style.height = '';
          st.card.style.position = 'absolute';
          st.card.style.inset = '0';
          seat.vote.innerHTML = '';
          seat.vote.append(st.card);
          if (was !== 'none' || vote === 'hidden') appear(st.card, { y: -10 * s, scale: 1.3, ms: 260 });
        } else {
          st.card.querySelector('.front img').src = vote === 'no' ? ART.seatNo : ART.seatYes;
        }
        if (vote === 'yes' || vote === 'no') {
          const epoch = ui.epoch;
          setTimeout(() => {
            if (!ui || epoch !== ui.epoch || st.vote !== vote) return;
            turnCard(st.card, true, () => voteRevealed(i));
          }, 180 + 55 * i);
        }
      }
    });
  }

  function voteRevealed(i) {
    if (S.phase !== 'voteResult' || ui.revealed.has(i)) return;
    ui.revealed.add(i);
    sound('flip');
    if (ui.revealed.size === S.names.length) {
      ui.verdict = true;
      stampVerdict();
      renderBar();
    }
  }

  function stampVerdict() {
    const st = built.stamp;
    st.textContent = S.approved ? '通過' : '否決';
    st.style.color = S.approved ? '#ffe3a3' : EVIL;
    st.classList.remove('in');
    void st.offsetWidth;
    st.classList.add('in');
    const approved = S.approved, epoch = ui.epoch;
    setTimeout(() => {
      if (!ui || epoch !== ui.epoch) return;
      sound(approved ? 'approve' : 'reject');
      shake(approved ? 3 : 6);
    }, 420);
  }

  function renderBanner() {
    const p = S.phase;
    const [title, sub] =
      p === 'identity' ? ['身分確認', '你坐在 1 號位，電腦只知道各自的身分情報']
        : p === 'assassination' ? ['刺殺梅林', '正義已完成三次任務，刺客的最後機會']
          : p === 'finished' ? ['遊戲結束', '']
            : p === 'questResult' ? [`第 ${S.history.length} 次遠征`, '結果揭曉']
              : p === 'lady' || p === 'ladyResult' ? ['湖中女神', `持有者 ${player(S.ladyHolder)} 查驗一名玩家的陣營`]
                : p === 'excalibur' || p === 'excaliburResult' ? ['王者之劍', `持劍者 ${player(S.swordHolder)} 可以翻轉一張任務牌`]
                  : [`第 ${S.quest} 次遠征`, `隊長 ${player(S.leader)}　·　派出 ${S.need} 人${S.failsNeeded === 2 ? '　·　需兩張失敗' : ''}`];
    const key = title + '|' + sub;
    if (built.titleKey === key) return;
    built.titleKey = key;
    const old = built.title.querySelector('.at-title:not(.out)');
    if (old) { old.classList.add('out'); setTimeout(() => old.remove(), 400); }
    const t = el('div', 'at-title pre', `<b>${esc(title)}</b>${sub ? `<span>${esc(sub)}</span>` : ''}`);
    built.title.append(t);
    requestAnimationFrame(() => requestAnimationFrame(() => t.classList.remove('pre')));
  }

  // ── the quest board, or what is being said ──
  function renderCenter() {
    const talking = discussing();
    built.board.style.display = talking ? 'none' : '';
    built.talk.style.display = talking ? '' : 'none';
    if (talking) renderTalk(); else { stopTicker(); ui.talkKey = null; renderBoard(false); }
  }

  function token(key, src, size) {
    let t = built.tokens[key];
    if (!t) {
      t = el('div', 'at-token', `<img src="${src}" alt="">`);
      built.tilt.append(t);
      built.tokens[key] = t;
    }
    t.style.width = t.style.height = size + 'px';
    return t;
  }
  function place(t, x, y, size, { hop = 0, now = false, delay = 0 } = {}) {
    const to = `translate(${x - size / 2}px, ${y - size / 2}px)`;
    if (t.dataset.at === to) return;
    const first = !t.dataset.at;
    t.dataset.at = to;
    if (first || now) {
      t.style.transition = 'none';
      t.style.transform = to;
      void t.offsetWidth;
      t.style.transition = '';
      return;
    }
    t.style.transitionDelay = delay + 'ms';
    t.style.transform = to;
    if (hop) {
      t.querySelector('img').animate([{ transform: 'translateY(0)' }, { transform: `translateY(${-hop}px)`, offset: .45 },
        { transform: 'translateY(0)' }], { duration: 700, delay, easing: 'ease-in-out' });
    }
  }
  function ripple(x, y, size, color) {
    const r = el('div', 'at-ripple');
    r.style.left = (x - size / 2) + 'px';
    r.style.top = (y - size / 2) + 'px';
    r.style.width = r.style.height = size + 'px';
    r.style.setProperty('--ring', color);
    built.tilt.append(r);
    setTimeout(() => r.remove(), 700);
  }

  function renderBoard(relayout) {
    const k = built.boardK || .3, L = LAYOUT[clamp(S.names.length, 5, 10)];
    const scored = S.history.length - (S.phase === 'questResult' ? 1 : 0);
    const playing = S.phase !== 'finished' && S.phase !== 'assassination' && scored < 5;
    const current = clamp(scored, 0, 4);
    // glow around the quest being played
    const ring = 122 * 2.08 * k;
    let pulse = built.tokens.pulse;
    if (!pulse) { pulse = el('div', 'at-ring'); built.tilt.append(pulse); built.tokens.pulse = pulse; }
    pulse.style.width = pulse.style.height = ring + 'px';
    pulse.style.opacity = playing ? 1 : 0;
    const [qx, qy] = L[0][current];
    const pAt = `translate(${qx * k - ring / 2}px, ${qy * k - ring / 2}px)`;
    if (relayout) { pulse.style.transition = 'none'; pulse.style.transform = pAt; void pulse.offsetWidth; pulse.style.transition = ''; }
    else pulse.style.transform = pAt;
    // the fifth proposal: last chance
    const vote = 88 * 2 * k * .78;
    const lastChance = S.rejections >= 4 && playing;
    let warn = built.tokens.warn;
    if (lastChance && !warn) { warn = el('div', 'at-ring'); warn.style.setProperty('--ring', '#ff4a3a'); built.tilt.append(warn); built.tokens.warn = warn; }
    if (warn) {
      warn.style.display = lastChance ? '' : 'none';
      const d = vote * 1.28, [vx, vy] = L[2][4];
      warn.style.width = warn.style.height = d + 'px';
      warn.style.transform = `translate(${vx * k - d / 2}px, ${vy * k - d / 2}px)`;
    }
    // score markers: a new one is dropped onto its slot
    const slot = 54 * 2.15 * k;
    for (let i = 0; i < 5; i++) {
      const key = 'score' + i;
      if (i >= scored) { if (built.tokens[key]) { built.tokens[key].remove(); delete built.tokens[key]; } continue; }
      const fresh = !built.tokens[key];
      const ok = S.history[i].ok;
      const t = token(key, ok ? ART.scoreGood : ART.scoreEvil, slot);
      const [x, y] = L[1][i];
      place(t, x * k, y * k, slot, { now: true });
      if (fresh && i >= ui.scored) {
        t.querySelector('img').animate([{ transform: `translateY(${-90 * k}px) scale(1.5)`, opacity: 0 },
          { transform: 'translateY(0) scale(1)', opacity: 1 }], { duration: 420, easing: 'cubic-bezier(.5, 0, .75, 0)' })
          .onfinish = () => {
            ripple(x * k, y * k, slot, ok ? '#8fd3ff' : '#ff7a66');
            sound('token');
            shake(4);
          };
      }
    }
    ui.scored = Math.max(ui.scored, scored);
    // the round marker, at the top left of the quest being played
    if (playing) {
      const t = token('round', ART.round, 80 * k);
      const [x, y] = L[0][current];
      place(t, (x - 98) * k, (y - 90) * k, 80 * k, { hop: 46 * k, delay: 450, now: relayout });
      t.style.display = '';
    } else if (built.tokens.round) built.tokens.round.style.display = 'none';
    // the vote track
    const tt = token('track', ART.track, vote);
    const [vx, vy] = L[2][clamp(S.rejections, 0, 4)];
    place(tt, vx * k, vy * k, vote, { hop: 40 * k, now: relayout });
    renderLoyalty();
  }

  function renderLoyalty() {
    if (!(S.lancelot > 0)) return;
    let strip = built.loyalty;
    const w = 34 * s, h = w / 1.5;
    if (!strip || strip.dataset.s !== String(s)) {
      strip?.remove();
      strip = el('div');
      strip.id = 'at-loyalty';
      strip.dataset.s = String(s);
      strip.innerHTML = '<div class="t"></div><div class="row"></div>';
      built.board.append(strip);
      built.loyalty = strip;
      strip.cards = [];
      for (let i = 0; i < 5; i++) {
        const slot = el('div', 'slot');
        const c = card(ART.loyaltyBack, ART.loyaltyBack, w, h, { flip: 500 });
        slot.append(c);
        strip.querySelector('.row').append(slot);
        strip.cards.push({ slot, c, shown: undefined });
      }
    }
    strip.classList.toggle('moved', !!S.switched);
    strip.querySelector('.t').textContent = S.switched ? '蘭斯洛特・已轉換' : '蘭斯洛特';
    const current = S.phase === 'finished' || S.phase === 'assassination' ? -1 : Math.min(S.history.length, 4);
    strip.cards.forEach((x, i) => {
      x.slot.classList.toggle('now', i === current);
      x.slot.classList.toggle('off', S.lancelot === 1 && i < 2);
      const v = S.loyalty[i];
      if (x.shown === v) return;
      const first = x.shown === undefined;
      x.shown = v;
      x.c.querySelector('.front img').src = v === true ? ART.loyaltySwitch : v === false ? ART.loyaltyStay : ART.loyaltyBack;
      if (v == null) { x.c.classList.remove('up'); return; }
      if (first && S.lancelot === 2) { x.c.classList.add('up', 'now'); requestAnimationFrame(() => x.c.classList.remove('now')); return; }
      setTimeout(() => turnCard(x.c, true), 600);
    });
  }

  // ── a turn to speak ──
  function stopTicker() { if (ui.ticker) { clearInterval(ui.ticker); ui.ticker = null; } }
  function renderTalk() {
    const key = `${S.gen}/${S.speechVersion}`;
    if (ui.talkKey !== key) {
      ui.talkKey = key;
      stopTicker();
      ui.lastSecond = null;
      const t = el('div', 'at-talk');
      t.innerHTML = `${svg('talk')}<div class="name"></div><div class="left"></div><div class="track"><i></i></div>` +
        `<div class="team"></div><div class="line"></div><div class="mine"></div><div class="say"></div><div class="note"></div>`;
      built.talk.innerHTML = '';
      built.talk.append(t);
      ui.talk = t;
      if (S.speaker === me()) sound('turn');
      ui.ticker = setInterval(tick, 1000);
      const say = t.querySelector('.say');
      const speak = el('button', 'at-btn plain', '我要發言');
      speak.style.fontSize = 'calc(14 * var(--u))';
      speak.addEventListener('click', openSpeech);
      const yes = el('button', 'at-chip', '支持並過麥');
      yes.addEventListener('click', () => act({ move: 'express', approve: true }));
      const no = el('button', 'at-chip', '想換人並過麥');
      no.addEventListener('click', () => act({ move: 'express', approve: false }));
      say.append(speak, yes, no);
    }
    const t = ui.talk, mine = S.speaker === me();
    const bot = S.speaker !== me();
    t.querySelector('.name').textContent = player(S.speaker);
    t.querySelector('.team').textContent = S.team.length ? `提案隊伍：${S.team.map(player).join('、')}` : '';
    const line = t.querySelector('.line');
    if (line.dataset.text !== (S.line ?? '')) {
      line.dataset.text = S.line ?? '';
      line.textContent = S.line ?? '';
      line.style.display = S.line ? '' : 'none';
      line.style.animation = 'none'; void line.offsetWidth; line.style.animation = '';
    }
    const m = t.querySelector('.mine');
    m.textContent = mine && S.mine.length ? `你說：${S.mine.join('　')}` : '';
    m.style.display = m.textContent ? '' : 'none';
    t.querySelector('.say').style.display = mine ? '' : 'none';
    t.querySelector('.note').textContent = S.speaker === S.leader ? '隊長最後總結' : '依座位順序發言，隊長最後總結';
    t.querySelector('.track').style.display = bot ? 'none' : '';
    tick(true);
    // a long line is shrunk to fit, never cut off
    t.style.transform = '';
    const room = built.talk.clientHeight;
    if (room && t.scrollHeight > room) t.style.transform = `scale(${room / t.scrollHeight})`;
  }
  function tick(quiet) {
    if (!ui.talk || !S || !discussing()) return;
    const t = ui.talk, bot = S.speaker !== me();
    // held (a page of the app open, typing a line): the clock stands still
    const left = S.paused && ui.lastSecond != null ? ui.lastSecond
      : Math.max(0, Math.ceil(((S.deadline ?? Date.now()) - Date.now()) / 1000));
    const total = S.speechSeconds || 0;
    const late = left <= 5;
    if (quiet !== true && !bot && !S.paused && left > 0 && left <= 5 && left !== ui.lastSecond) sound('tick');
    ui.lastSecond = left;
    const l = t.querySelector('.left');
    l.textContent = bot ? '稍後自動過麥' : `${left} 秒`;
    l.className = 'left' + (bot ? ' auto' : '') + (late ? ' late' : '');
    const tr = t.querySelector('.track');
    tr.classList.toggle('late', late);
    tr.querySelector('i').style.transform = `scaleX(${total ? clamp(left / total, 0, 1) : 0})`;
  }

  // ── the bar under the board ──
  function renderBar() {
    const bar = built.bar, p = S.phase, n = S.names.length;
    let key, hint = '', btn = null, rise = false;
    const id = S.identity;
    if (p === 'identity') hint = `等待所有人確認身分（${S.confirmed.length}/${n}）`;
    else if (p === 'team' && S.leader !== me()) hint = `等待隊長 ${player(S.leader)} 挑選 ${S.need} 名隊員`;
    else if (p === 'vote') hint = `等待投票（${S.voted.length}/${n}）`;
    else if (p === 'quest') hint = `任務進行中：已出牌 ${S.played.length}/${S.team.length}`;
    else if (p === 'assassination' && !id?.assassin) hint = '刺客正在選擇刺殺目標…';
    else if (p === 'lady' && S.ladyHolder !== me()) hint = `湖中女神持有者 ${player(S.ladyHolder)} 正在選擇查驗對象…`;
    else if (p === 'ladyResult' && S.ladyHolder !== me() && S.ladyCheck) hint = `${player(S.ladyCheck.holder)} 查驗了 ${player(S.ladyCheck.target)} 的陣營，湖中女神將交給對方`;
    else if ((p === 'excalibur' || p === 'excaliburResult') && S.swordHolder !== me()) hint = `持劍者 ${player(S.swordHolder)} 正在決定是否使用王者之劍…`;
    else if (p === 'discussion') {
      const mine = S.speaker === me(), version = S.speechVersion;
      hint = mine ? '輪到你發言，講完可提前過麥' : '請聆聽當前玩家發言';
      btn = [mine ? '結束發言 / 下一位' : '下一位電腦', ui.waiting !== S.turn ? () => act({ move: 'endSpeech', version }) : null];
    } else if (p === 'team') {
      hint = `隊長點選座位，挑選 ${S.need} 名隊員`;
      btn = [`${S.talk ? '確認隊伍並開始發言' : '提案並開始投票'}（${ui.selected.size}/${S.need}）`,
        ui.selected.size === S.need ? proposeTeam : null];
    } else if (p === 'voteResult') {
      if (ui.verdict) {
        const yes = S.votes.filter(Boolean).length;
        const final = !S.approved && S.rejections === 4;
        hint = `贊成 ${yes} · 反對 ${n - yes}　—　${final ? '連續五次組隊遭否決，邪惡陣營獲勝' : S.approved ? '組隊通過' : '組隊遭否決（需超過半數贊成）'}`;
        btn = [final ? '邪惡獲勝・查看結算' : S.approved ? '開始秘密執行任務' : '繼續', () => act({ move: 'continueVote' })];
        rise = true;
      }
    }
    key = `${hint}|${btn?.[0] ?? ''}|${!!btn?.[1]}`;
    if (bar.dataset.key === key) return;
    const wasKey = bar.dataset.key ?? '';
    bar.dataset.key = key;
    bar.innerHTML = '';
    bar.classList.remove('rise');
    if (rise && !wasKey.startsWith(hint)) { void bar.offsetWidth; bar.classList.add('rise'); }
    const h = el('div', 'hint');
    h.textContent = hint;
    bar.append(h);
    if (btn) {
      const b = button(btn[0], () => btn[1]?.());
      b.disabled = !btn[1];
      bar.append(b);
    }
  }

  function proposeTeam() {
    const picked = [...ui.selected];
    if (!S.excalibur) return act({ move: 'propose', team: picked });
    // the leader hands Excalibur to one of the team (not themselves)
    dialog('把王者之劍交給哪位隊員？', '<p class="at-muted" style="font-size:13px">任務牌收走前，持劍者可以翻轉另一名隊員的任務牌。隊長不能拿劍。</p>',
      [['取消', null]], picked.filter(i => i !== S.leader).map(i => [player(i), () => act({ move: 'propose', team: picked, sword: i })]));
  }

  // ── pieces lying on the board ──
  function renderProps() {
    const played = S.phase === 'quest' ? S.played.length
      : S.phase === 'excalibur' || S.phase === 'excaliburResult' ? S.team.length
        : S.phase === 'questResult' && ui.interlude ? S.team.length : 0;
    const pile = Math.max(0, played - ui.pileLanding);
    const have = built.pile.children.length;
    if (have !== pile) {
      if (pile < have) built.pile.innerHTML = '';
      for (let j = built.pile.children.length; j < pile; j++) {
        const f = face(ART.questBack, 34 * s, 51 * s);
        f.style.position = 'absolute';
        f.style.transform = `rotate(${((j * 37) % 11 - 5) * .045}rad)`;
        if (j >= have && have > 0) appear(f, { y: -8 * s, scale: 1.2, ms: 220 });
        built.pile.append(f);
      }
    }
    built.deck.classList.toggle('on', ui.dealing);
    if (S.phase !== 'voteResult' || !ui.verdict) built.stamp.classList.remove('in');
  }

  // ── layers over the table ──
  function renderLayers() {
    const secret = secretVisible();
    const questShow = S.phase === 'questResult' && !ui.interlude;
    const endShow = S.phase === 'finished' && !ui.interlude;
    root.classList.toggle('still', secret || questShow || endShow);
    // a quest's cards
    const qKey = questShow ? `${S.gen}/${S.history.length}` : null;
    if (qKey !== ui.questKey) {
      ui.questKey = qKey;
      built.questReveal?.stop();
      built.questReveal = null;
      if (qKey) {
        built.quest.innerHTML = '';
        built.questReveal = questReveal();
        built.quest.append(built.questReveal.el);
      }
    }
    built.quest.classList.toggle('on', questShow);
    // the end
    const eKey = endShow ? `${S.gen}/${ui.assassinShown || S.assassinTarget == null}` : null;
    if (eKey !== ui.endKey) {
      ui.endKey = eKey;
      built.endReveal?.stop();
      built.endReveal = null;
      if (eKey) {
        built.end.innerHTML = '';
        const strike = S.assassinTarget != null && !ui.assassinShown;
        const x = strike ? assassinReveal() : finalReveal();
        built.endReveal = x;
        x.el.classList.add('at-swap');
        built.end.append(x.el);
      }
    }
    built.end.classList.toggle('on', endShow);
    // a secret move
    const key = secret ? `${S.gen}|${S.phase}|${S.turn}` : null;
    if (key !== ui.secretKey) {
      ui.secretKey = key;
      if (key) {
        built.secret.innerHTML = '';
        ui.secret = secretContent();
        if (ui.secret) {
          ui.secret.el.classList.add('at-swap');
          built.secret.append(ui.secret.el);
        }
      } else ui.secret = null;
    } else ui.secret?.update?.();
    built.secret.classList.toggle('on', secret && !!ui.secret);
  }

  function box() {
    const r = built.secret.getBoundingClientRect();
    return { w: Math.max(1, r.width - 32 * s), h: Math.max(1, r.height - 32 * s) };
  }

  function secretContent() {
    switch (S.phase) {
      case 'identity': return identity();
      case 'vote': return voteChoice();
      case 'quest': return questChoice();
      case 'lady': return ladyPick();
      case 'excalibur': return swordPick();
      case 'ladyResult': case 'excaliburResult': return expansionResult();
      case 'assassination': return assassinate();
      default: return null;
    }
  }

  // ── your card ──
  function identity() {
    const id = S.identity, c = box();
    const cardW = Math.min((c.h - 40 * s) * ASPECT, c.w * .32), cardH = cardW / ASPECT;
    const infoW = Math.min(380 * s, Math.max(1, c.w - cardW - 64 * s));
    const color = id.evil ? EVIL : GOOD;
    const flipAt = 350, flipMs = 900, shown = flipAt + flipMs;
    const wrap = el('div', 'at-ident');
    wrap.append(sparks(id.evil ? 'ember' : 'spark', 22, { seed: 3 }));
    const cardBox = el('div');
    cardBox.style.position = 'relative';
    cardBox.append(glow(color, cardW * 3.4, flipAt + flipMs / 2 - 60));
    const floaty = el('div', 'at-floaty');
    const c1 = card(ART.roleBack, id.art, cardW, cardH, { flip: flipMs });
    const shine = el('div', 'at-shine');
    shine.style.animationDelay = (flipAt + flipMs / 2 - 80) + 'ms';
    c1.querySelector('.front').append(shine);
    floaty.append(c1);
    cardBox.append(floaty);
    setTimeout(() => c1.classList.add('up'), flipAt);
    const info = el('div', 'at-info');
    info.style.width = infoW + 'px';
    const line = (i, e) => { appear(e, { delay: shown - 250 + 110 * i, x: 20 * s }); info.append(e); return e; };
    line(0, el('div', 'who')).textContent = player(me());
    const role = line(1, el('div', 'role'));
    role.textContent = id.label;
    role.style.color = color;
    role.style.textShadow = `0 0 ${18 * s}px ${color}b3`;
    const side = line(2, el('div', 'side'));
    side.style.color = color + 'd9';
    side.innerHTML = `<span>${id.evil ? '邪惡陣營' : '正義陣營'}</span><span>${id.evil ? '讓任務失敗或找出梅林' : '完成三次任務並保護梅林'}</span>` +
      (id.lancelot && S.switched ? `<span style="color:${id.evil ? GOOD : EVIL};font-weight:700">目前已轉換為${id.evil ? '正義' : '邪惡'}陣營</span>` : '');
    const know = line(3, el('div', 'at-know'));
    know.innerHTML = `<div>${esc(id.heading)}${id.lists ? '：' : ''}</div>` +
      (id.lists ? `<div class="seen">${id.seen.length ? id.seen.map(x => `<span>${esc(x)}</span>`).join('') : '<span>無</span>'}</div>` : '') +
      (id.reminder ? `<div class="rem">${esc(id.reminder)}</div>` : '');
    const ok = button('記住了', () => {
      if (ui.hiding) return;
      sound('flip');
      ui.hiding = true;
      c1.classList.remove('up');
      info.style.opacity = 0;
      const turn = S.turn;
      after(400, () => { if (turn === S.turn) act({ move: 'confirm' }); });
    });
    line(4, el('div')).append(ok);
    wrap.append(cardBox, info);
    return { el: wrap };
  }

  // ── a card to play face down ──
  function choiceRow(title, sub, options, confirm, deck, onConfirm, note) {
    const c = box();
    const cardW = Math.min((c.h - 200 * s) * ASPECT, 150 * s), cardH = cardW / ASPECT;
    const wrap = el('div', 'at-choice');
    const head = appear(el('div'), { y: -10 * s });
    head.innerHTML = `<div class="at-h"></div><div class="at-sub"></div>`;
    head.querySelector('.at-h').textContent = title;
    head.querySelector('.at-sub').textContent = sub;
    if (note) head.append(note);
    const row = el('div', 'cards');
    const cards = {};
    options.forEach(([value, art, label, enabled], i) => {
      const pick = el('div', 'at-pick' + (enabled ? '' : ' locked'));
      appear(pick, { delay: 120 + 130 * i, ms: 520, y: 80 * s, scale: .85 });
      const lift = el('div', 'lift');
      lift.style.position = 'relative';
      const cc = card(deck, art, cardW, cardH, { up: true, flip: 420 });
      lift.append(cc);
      if (!enabled) lift.append(el('div', 'lock', svg('lock')));
      const lab = el('div', 'label');
      lab.textContent = label;
      pick.append(lift, lab);
      pick.addEventListener('click', () => {
        if (!enabled || ui.committing) return;
        sound('tap');
        ui.choice = value;
        update();
      });
      cards[String(value)] = pick;
      row.append(pick);
    });
    const ok = button(confirm, () => onConfirm());
    const okBox = appear(el('div', 'at-fade'), { delay: 380 });
    okBox.append(ok);
    wrap.append(head, row, okBox);
    function update() {
      for (const [v, pick] of Object.entries(cards)) {
        const sel = String(ui.choice) === v;
        pick.classList.toggle('sel', sel);
        pick.classList.toggle('dim', ui.choice !== null && !sel && !ui.committing);
        pick.classList.toggle('gone', ui.committing && !sel);
        pick.classList.toggle('going', ui.committing && sel);
        const cc = pick.querySelector('.at-card');
        const down = ui.committing && sel;
        if (cc.classList.contains('up') === down) cc.classList.toggle('up', !down);
      }
      ok.disabled = ui.choice === null || ui.committing;
      okBox.classList.toggle('gone', ui.committing);
    }
    update();
    return { el: wrap, update, cards };
  }

  function voteChoice() {
    const note = S.revised ? (() => {
      const b = el('button', 'at-link', `${svg('log').replace('<svg', '<svg style="width:16px;fill:currentColor"')}${S.revised} 位電腦玩家改口了，點這裡看原因`);
      b.addEventListener('click', openLog);
      return b;
    })() : null;
    return choiceRow(`${player(me())}　投下組隊票`, `提案隊伍：${S.team.map(player).join('、')}`,
      [[true, ART.approve, '贊成', true], [false, ART.reject, '反對', true]],
      '蓋牌投出', ART.voteBack, () => commit('vote'), note);
  }

  function questChoice() {
    const evil = S.evilNow === true, mustFail = S.mustFail, lancelot = S.identity?.lancelot;
    return choiceRow(`${player(me())}　執行任務`,
      mustFail ? '你是邪惡方的蘭斯洛特，必須打出「任務失敗」。'
        : evil ? `${lancelot ? '你目前屬於邪惡陣營。' : ''}邪惡玩家可以自由選擇。結果只會公布總失敗張數。`
          : `${lancelot ? '你目前屬於正義陣營。' : ''}正義玩家只能打出「任務成功」。`,
      [[true, ART.success, '任務成功', !mustFail], [false, ART.fail, '破壞任務', evil]],
      '蓋牌打出', ART.questBack, () => commit('quest'));
  }

  // ── seats to pick from ──
  function seatPicker(seats, color) {
    const wrap = el('div', 'at-seats');
    const rows = Math.max(1, Math.ceil(seats.length / 6)), per = Math.ceil(seats.length / rows);
    const plaques = [];
    for (let r = 0; r < rows; r++) {
      const row = el('div', 'row');
      seats.slice(r * per, (r + 1) * per).forEach((i, k) => {
        const b = el('button', 'at-plaque');
        b.textContent = player(i);
        b.style.setProperty('--c', color);
        appear(b, { delay: 150 + 70 * (r * per + k), scale: .9 });
        b.addEventListener('click', () => {
          sound('tap');
          ui.selected.clear();
          ui.selected.add(i);
          plaques.forEach(([j, p]) => p.classList.toggle('sel', ui.selected.has(j)));
          onPick?.();
        });
        plaques.push([i, b]);
        row.append(b);
      });
      wrap.append(row);
    }
    let onPick = null;
    return { el: wrap, set onPick(f) { onPick = f; } };
  }
  function pickPage(top, title, sub, seats, color, buttons) {
    const wrap = el('div');
    wrap.style.cssText = 'display:flex;flex-direction:column;align-items:center;gap:calc(6*var(--u));max-height:100%;overflow:auto';
    if (top) wrap.append(top);
    const h = el('div', 'at-h');
    h.textContent = title;
    h.style.color = color === EVIL ? EVIL : GOLD;
    const p = el('div', 'at-sub');
    p.textContent = sub;
    const head = appear(el('div'), { y: -10 * s });
    head.append(h, p);
    const picker = seatPicker(seats, color);
    picker.el.style.margin = `${8 * s}px 0`;
    const acts = appear(el('div', 'at-btns'), { delay: 450 });
    const made = buttons.map(([label, fn, needsPick, plain]) => {
      const b = button(label, fn, { plain });
      acts.append(b);
      return [b, needsPick];
    });
    const update = () => made.forEach(([b, needs]) => { if (needs) b.disabled = ui.selected.size !== 1; });
    picker.onPick = update;
    update();
    wrap.append(head, picker.el, acts);
    return { el: wrap, update };
  }

  function ladyPick() {
    const top = appear(face(ART.lady, 54 * s, 81 * s), { scale: .6 });
    const targets = S.names.map((_, i) => i).filter(i => !S.ladyPast.includes(i));
    return pickPage(top, `${player(me())}　使用湖中女神`, '選擇一名玩家查驗陣營（只看陣營，不看角色）。持有過湖中女神的人不能被查驗。',
      targets, GOOD, [['查驗陣營', () => act({ move: 'lady', target: [...ui.selected][0] }), true]]);
  }
  function swordPick() {
    const top = appear(el('div', '', `<img src="${ART.sword}" alt="" style="width:${90 * s}px;height:${90 * s}px;object-fit:contain">`), { scale: .6 });
    const targets = S.team.filter(i => i !== me());
    return pickPage(top, `${player(me())}　使用王者之劍`, '可以指定另一名隊員，把他打出的任務牌翻轉（成功 ↔ 失敗），你會看到那張牌原本是什麼。也可以不使用。',
      targets, GOLD, [
        ['不使用', () => act({ move: 'excalibur', target: null }, { interlude: true }), false, true],
        ['翻轉這張牌', () => act({ move: 'excalibur', target: [...ui.selected][0] }), true],
      ]);
  }
  function assassinate() {
    const wrap = pickPage(null, `${player(me())}　選擇刺殺目標`, '回想誰一直知道得太多：總是反對有壞人的隊、帶的隊特別乾淨。請選出你認為的梅林。',
      S.names.map((_, i) => i).filter(i => i !== me()), EVIL,
      [['確認刺殺', () => act({ move: 'assassinate', target: [...ui.selected][0] }), true]]);
    wrap.el.prepend(sparks('ember', 18, { seed: 21 }));
    return wrap;
  }

  /// What the Lady (a loyalty) or Excalibur (the original card) showed.
  function expansionResult() {
    const r = S.reveal;
    if (!r) return null;
    const lady = r.kind === 'lady';
    const bad = lady ? r.evil === true : r.card === false;
    const color = bad ? EVIL : GOOD;
    const c = box();
    const cardW = Math.min((c.h - 60 * s) * ASPECT, 150 * s), cardH = cardW / ASPECT;
    const art = lady ? (bad ? ART.loyaltyEvil : ART.loyaltyGood) : (bad ? ART.fail : ART.success);
    const wrap = el('div', 'at-ident');
    wrap.style.gap = 28 * s + 'px';
    const cardBox = el('div');
    cardBox.style.position = 'relative';
    cardBox.append(glow(color, cardW * 3, 700));
    const cc = card(lady ? ART.roleBack : ART.questBack, art, cardW, cardH, { flip: 800 });
    cardBox.append(cc);
    setTimeout(() => cc.classList.add('up'), 300);
    const info = el('div', 'at-info');
    info.style.maxWidth = 330 * s + 'px';
    const a = appear(el('div', 'who'), { delay: 900 });
    a.textContent = lady ? `${player(r.target)} 的陣營是` : `${player(r.target)} 原本打出的是`;
    a.style.fontSize = 14 * s + 'px';
    const v = appear(el('div', 'role'), { delay: 1050 });
    v.textContent = lady ? `${bad ? '邪惡' : '正義'}陣營` : `「${bad ? '任務失敗' : '任務成功'}」`;
    v.style.color = color;
    v.style.fontSize = 30 * s + 'px';
    v.style.textShadow = `0 0 ${16 * s}px ${color}b3`;
    const t = appear(el('div'), { delay: 1200 });
    t.style.cssText += `font-size:${13 * s}px;white-space:pre-line;margin:${8 * s}px 0 ${16 * s}px`;
    t.textContent = lady ? `好人只能照實公布，壞人可以說謊；也可以先不公布，之後發言時再說。\n湖中女神將交給 ${player(r.target)}。`
      : `這張牌已翻轉為「${bad ? '任務成功' : '任務失敗'}」，接著所有任務牌會洗勻後公開。`;
    const acts = appear(el('div', 'at-btns'), { delay: 1350 });
    acts.style.justifyContent = 'flex-start';
    if (lady) {
      acts.append(
        button('公布：他是好人', () => act({ move: 'announceLady', evil: false }, { interlude: true })),
        button('公布：他是壞人', () => act({ move: 'announceLady', evil: true }, { interlude: true })),
        button('先不公布', () => act({ move: 'continueLady' }, { interlude: true }), { plain: true }));
    } else {
      acts.append(button('記住了，繼續', () => act({ move: 'continueExcalibur' }, { interlude: true })));
    }
    info.append(a, v, t, acts);
    wrap.append(cardBox, info);
    return { el: wrap };
  }

  // ── the public reveal: gathered, shuffled, laid out, turned one by one ──
  // (lib/features/table/card_reveal.dart, frame by frame)
  function cardReveal({ items, cardW, caption, verdict, verdictColor, particles, detail, label, onContinue,
    shuffle = true, onReveal, onVerdict, onShuffle }) {
    const n = items.length, w = cardW, h = w / ASPECT, gap = 18 * s;
    const rowW = Math.max(n * (w + gap), w * 2.8);
    const gatherEnd = 380, flipMs = 540;
    const doShuffle = shuffle && n > 1;
    const shuffleEnd = gatherEnd + (doShuffle ? 950 : 0);
    const spreadEnd = shuffleEnd + (n > 1 ? 480 : 0);
    let t = spreadEnd + 320;
    const anticStart = [], flipStart = [], reveal = [];
    for (let i = 0; i < n; i++) {
      const last = i === n - 1;
      const antic = last ? (n === 1 ? 1300 : 950) : 320;
      anticStart.push(t);
      flipStart.push(t + antic);
      reveal.push(t + antic + flipMs / 2);
      t += antic + flipMs + (last ? 0 : 240);
    }
    const verdictAt = t + 380, controlsAt = verdictAt + 650, total = controlsAt + 500;
    const wrap = el('div', 'at-reveal');
    const sp = sparks(particles, 36);
    sp.style.opacity = 0;
    sp.style.transition = 'opacity .8s ease-out';
    const cap = el('div', 'cap');
    cap.textContent = caption;
    cap.style.opacity = 0;
    cap.style.transition = 'opacity .32s';
    const rowBox = el('div', 'rowbox');
    rowBox.style.width = rowW + 'px';
    rowBox.style.height = (h * 1.2) + 'px';
    rowBox.style.marginTop = 10 * s + 'px';
    const cards = items.map(item => {
      const c = el('div', 'rc');
      c.style.width = w + 'px';
      c.style.height = h + 'px';
      const burst = el('div', 'burst');
      c.style.setProperty('--c', item.glow);
      burst.style.width = burst.style.height = (w * 3.6) + 'px';
      const inner = el('div', 'in2');
      inner.innerHTML = `<div class="at-face back"><img src="${item.back}" alt=""></div><div class="at-face front"><img src="${item.front}" alt=""></div>`;
      c.append(burst, inner);
      rowBox.append(c);
      return { c, inner, burst, front: inner.querySelector('.front') };
    });
    const v = el('div', 'at-verdict');
    v.textContent = verdict;
    v.style.color = verdictColor;
    v.style.marginTop = 6 * s + 'px';
    const controls = el('div', 'at-controls');
    const d = el('div', 'at-detail');
    d.textContent = detail;
    controls.append(d);
    if (label) controls.append(button(label, () => onContinue?.(), { cls: '' }));
    wrap.append(sp, cap, rowBox, v, controls);
    const fired = Array(n).fill(false);
    let shuffled = false, verdictFired = false, verdictShown = false, controlsShown = false;
    const start = performance.now();
    let raf = 0, skipped = false, stopped = false;
    function frame(now) {
      if (stopped) return;
      const tt = skipped ? total : now - start;
      cap.style.opacity = seg(tt, 0, 320);
      const gather = easeOutBack(seg(tt, 0, gatherEnd));
      const u = seg(tt, gatherEnd, shuffleEnd);
      const spread = easeInOutCubic(seg(tt, shuffleEnd, spreadEnd));
      if (!shuffled && doShuffle && tt >= gatherEnd) { shuffled = true; if (!skipped) onShuffle?.(); }
      cards.forEach((x, i) => {
        const last = i === n - 1;
        const a = seg(tt, anticStart[i], flipStart[i]);
        const f = seg(tt, flipStart[i], flipStart[i] + flipMs);
        const post = seg(tt, reveal[i], reveal[i] + 800);
        const down = easeOut(seg(tt, flipStart[i] + flipMs, flipStart[i] + flipMs + 320));
        const lift = a <= 0 ? 0 : easeOut(a) * (1 - down);
        const wave = 2 * Math.PI * (u * 2 + i / n), env = Math.sin(Math.PI * u);
        const mid = i - (n - 1) / 2;
        const x0 = mid * (w + gap) * spread + w * .62 * Math.sin(wave) * env;
        const y0 = h * .13 - 5 * s * i * (1 - spread) - 12 * s * lift;
        let turn = .07 * Math.sin(wave) * env + mid * .045 * (1 - spread);
        if (a > 0 && a < 1) turn += .03 * Math.sin(a * Math.PI * (last ? 10 : 6)) * (1 - a);
        let scale = gather * (1 + .08 * lift);
        if (last && a > 0 && f <= 0) scale *= 1 + .035 * Math.abs(Math.sin(a * Math.PI * 5));
        x.c.style.transform = `translate(${rowW / 2 + x0 - w / 2}px, ${y0}px) rotate(${turn}rad) scale(${Math.max(0, scale)})`;
        x.inner.style.transform = `rotateY(${180 * easeInOutCubic(f)}deg)`;
        if (!fired[i] && tt >= reveal[i]) {
          fired[i] = true;
          // the light around the card fades in on its own (set once)
          x.c.classList.add('lit');
          if (!skipped) { x.burst.classList.add('go'); onReveal?.(items[i]); }
        }
      });
      if (!verdictShown && tt >= verdictAt) { verdictShown = true; v.classList.add('go'); sp.style.opacity = 1; }
      if (!verdictFired && tt >= verdictAt + 260) { verdictFired = true; onVerdict?.(); }
      if (!controlsShown && tt >= controlsAt) { controlsShown = true; controls.classList.add('on'); }
      if (tt < total) raf = requestAnimationFrame(frame);
    }
    // the first frame waits for the layer to be on screen
    requestAnimationFrame(() => { raf = requestAnimationFrame(frame); });
    return {
      el: wrap,
      skip() { if (skipped || controlsShown) return; skipped = true; cancelAnimationFrame(raf); frame(performance.now()); },
      stop() { stopped = true; cancelAnimationFrame(raf); },
    };
  }

  function onRevealItem(item) {
    sound('flip');
    if (item.shock) shake(9);
  }

  function questReveal() {
    const q = S.history.at(-1), n = ui.order.length;
    const r = built.quest.getBoundingClientRect();
    const W = r.width - 20 * s, H = r.height - 20 * s;
    const cardW = Math.min((H - 190 * s) * ASPECT / 1.2, (W - 80 * s) / n - 18 * s);
    const sword = q.swordHolder == null ? '' : q.swordTarget == null
      ? `\n王者之劍：${player(q.swordHolder)} 沒有翻轉任何牌`
      : `\n王者之劍：${player(q.swordHolder)} 翻轉了 ${player(q.swordTarget)} 的任務牌`;
    return cardReveal({
      cardW, caption: `第 ${S.history.length} 次任務　·　洗勻後逐張翻開`,
      items: ui.order.map(ok => ({ glow: ok ? '#ffd98a' : EVIL, shock: !ok, back: ART.questBack, front: ok ? ART.success : ART.fail })),
      verdict: q.ok ? '任務成功' : '任務失敗', verdictColor: q.ok ? GOOD : EVIL, particles: q.ok ? 'spark' : 'ember',
      detail: `收到 ${q.team.length - q.fails} 張成功、${q.fails} 張失敗${sword}`,
      label: '繼續議會',
      onReveal: onRevealItem,
      onShuffle: () => sound('shuffle'),
      onVerdict: () => { sound(q.ok ? 'success' : 'failure'); if (!q.ok) shake(7); },
      onContinue: () => act({ move: 'continueQuest' }, { interlude: true }),
    });
  }

  /// The assassin's target turns their card over: Merlin, or not?
  function assassinReveal() {
    const target = S.assassinTarget, role = S.roles?.[target];
    const hit = !!role?.merlin;
    const r = built.end.getBoundingClientRect();
    const cardW = Math.min((r.height - 20 * s - 210 * s) * ASPECT / 1.2, 170 * s);
    return cardReveal({
      cardW, shuffle: false, caption: `刺客出手　·　目標是 ${player(target)}`,
      items: [{ glow: hit ? EVIL : GOOD, shock: hit, back: ART.roleBack, front: role?.art ?? ART.roleBack }],
      verdict: hit ? '梅林遇刺' : '刺殺失敗', verdictColor: hit ? EVIL : GOOD, particles: hit ? 'ember' : 'spark',
      detail: hit ? '邪惡陣營逆轉獲勝' : '梅林安然無恙，正義陣營獲勝',
      label: '揭曉全員身分',
      onReveal: item => { onRevealItem(item); sound('token'); },
      onVerdict: () => { sound(hit ? 'failure' : 'success'); if (hit) shake(8); },
      onContinue: () => { ui.assassinShown = true; render(); },
    });
  }

  function finalReveal() {
    const n = S.names.length;
    const perRow = n <= 5 ? n : Math.ceil(n / 2), rows = Math.ceil(n / perRow);
    const r = built.end.getBoundingClientRect();
    const W = r.width - 20 * s, H = r.height - 20 * s;
    const cardW = Math.min(((H - 150 * s) / rows - 20 * s) * ASPECT, (W - 60 * s) / perRow - 14 * s);
    const evilWon = S.winner === '邪惡', color = evilWon ? EVIL : GOOD;
    const firstFlip = 950, step = 220;
    const wrap = el('div', 'at-final');
    wrap.append(sparks(evilWon ? 'ember' : 'spark', 46));
    const win = el('div', 'win');
    win.textContent = `${S.winner}陣營獲勝`;
    win.style.color = color;
    const res = appear(el('div'), { delay: 650 });
    res.textContent = S.result;
    res.style.fontSize = 12.5 * s + 'px';
    const rowsEl = el('div', 'rows');
    for (let rr = 0; rr < rows; rr++) {
      const row = el('div', 'row');
      for (let i = rr * perRow; i < Math.min(n, (rr + 1) * perRow); i++) {
        const role = S.roles[i];
        const seat = el('div', 'seat');
        seat.style.width = cardW + 'px';
        const cc = card(ART.roleBack, role.art, cardW, cardW / ASPECT, { flip: 600 });
        const shine = el('div', 'at-shine');
        shine.style.animationDelay = (firstFlip + step * i + 300) + 'ms';
        cc.querySelector('.front').append(shine);
        appear(cc, { delay: 250 + 60 * i, y: 30 * s, scale: .8 });
        setTimeout(() => turnCard(cc, true, () => sound('flip')), firstFlip + step * i);
        // the name, and under it how that computer liked to play
        const name = appear(el('span'), { delay: firstFlip + step * i + 350, y: 6 * s });
        name.textContent = `${i + 1}. ${S.names[i]}${role.moved ? '（已換邊）' : ''}`;
        const style = appear(el('span', 'style'), { delay: firstFlip + step * i + 420, y: 6 * s });
        style.textContent = role.style ?? '';
        seat.append(cc, name, style);
        row.append(seat);
      }
      rowsEl.append(row);
    }
    const acts = appear(el('div', 'at-btns'), { delay: firstFlip + step * n + 500 });
    acts.append(button('相同配置，再玩一局', () => act({ move: 'restart' })));
    if (S.review) acts.append(button('複盤', () => call('open', 'review'), { plain: true }));
    acts.append(button('返回設定', () => call('leave'), { plain: true }));
    wrap.append(win, res, rowsEl, acts);
    const epoch = ui.epoch;
    setTimeout(() => {
      if (!ui || epoch !== ui.epoch) return;
      sound(evilWon ? 'evilWin' : 'goodWin');
      shake(5);
    }, 650);
    return { el: wrap, skip() {}, stop() {} };
  }

  // ───────────── dialogs, the record, typing a line ─────────────
  function hold(on) { call('hold', on ? '1' : '0'); }
  function closeModal() {
    if (!ui?.modal) return;
    ui.modal.remove();
    ui.modal = null;
    hold(false);
  }
  function modal(content) {
    closeModal();
    const m = el('div', 'at-modal');
    m.append(content);
    m.addEventListener('click', e => { if (e.target === m) closeModal(); });
    root.append(m);
    ui.modal = m;
    hold(true);
    return m;
  }
  function dialog(title, html, actions, options = []) {
    const d = el('div', 'at-dialog');
    d.innerHTML = `<h2>${esc(title)}</h2><div class="body">${html}</div><div class="acts"></div>`;
    const body = d.querySelector('.body');
    for (const [label, fn] of options) {
      const o = el('button', 'opt');
      o.textContent = label;
      o.addEventListener('click', () => { closeModal(); fn(); });
      body.append(o);
    }
    for (const [label, fn] of actions) {
      const b = el('button');
      b.textContent = label;
      b.addEventListener('click', () => { closeModal(); fn?.(); });
      d.querySelector('.acts').append(b);
    }
    modal(d);
  }
  function openLog() {
    let lines = [];
    try { lines = JSON.parse(call('log') || '[]'); } catch (_) {}
    const html = lines.length ? lines.map(l => `<p style="color:${l.now ? '#fff' : 'var(--muted)'}">${esc(l.heading)}\n${esc(l.text)}</p>`).join('')
      : '<p>尚無發言紀錄。</p>';
    dialog('討論紀錄', html, [['返回對局', null]]);
  }

  /// A line of the player's own (a page of its own: the keyboard takes the
  /// lower half of a phone held sideways).
  function openSpeech() {
    const page = el('div', 'at-page');
    page.innerHTML = `<div class="top"><button class="x" aria-label="取消">${svg('close')}</button>` +
      `<input maxlength="60" enterkeyhint="send" placeholder="想說什麼都可以，例如：3號上一輪投了失敗的隊，我不信他">` +
      `<button class="send" disabled>說出來</button></div><div class="read"></div><div class="count"></div>`;
    const input = page.querySelector('input'), send = page.querySelector('.send'), read = page.querySelector('.read');
    const count = page.querySelector('.count');
    const hint = '計時已暫停。提到座位號碼或暱稱，再說懷疑、相信、為什麼或支持／反對，電腦就會回應。';
    const refresh = () => {
      const text = input.value.trim();
      send.disabled = !text;
      const r = text ? call('read', text) : '';
      read.textContent = r ? `電腦會理解成：${r}` : hint;
      read.classList.toggle('on', !!r);
      count.textContent = `${input.value.length}/60`;
    };
    const close = () => { page.remove(); ui.modal = null; hold(false); };
    const go = () => {
      const text = input.value.trim();
      if (!text) return;
      close();
      call('act', { move: 'say', text });
    };
    page.querySelector('.x').addEventListener('click', close);
    send.addEventListener('click', go);
    input.addEventListener('input', refresh);
    input.addEventListener('keydown', e => { if (e.key === 'Enter' && !e.isComposing) go(); });
    closeModal();
    root.append(page);
    ui.modal = page;
    hold(true);
    refresh();
    input.focus();
  }

  function toast({ title, text, image }) {
    if (!built) return;
    const t = el('div', 'at-toast');
    t.innerHTML = (image ? `<img src="${esc(image)}" alt="">` : '') + `<div>${title ? `<b>${esc(title)}</b>` : ''}${esc(text)}</div>`;
    built.toasts.append(t);
    while (built.toasts.children.length > 3) built.toasts.firstChild.remove();
    const bye = () => { t.classList.add('bye'); setTimeout(() => t.remove(), 300); };
    t.addEventListener('click', bye);
    setTimeout(bye, Math.min(9000, 3500 + String(text).length * 60));
  }

  // ───────────── what the app calls ─────────────
  let resizeTimer = 0;
  const onResize = () => { clearTimeout(resizeTimer); resizeTimer = setTimeout(() => { layout(); render(); }, 120); };

  window.avalonTable = {
    open(h) {
      host = h;
      S = null;
      prev = null;
      ui = freshUi();
      addEventListener('resize', onResize);
      // the pieces' pictures, ready before they are needed
      for (const src of Object.values(ART)) { const i = new Image(); i.src = src; }
    },
    update(json) {
      let next;
      try { next = JSON.parse(json); } catch (e) { console.error(e); return; }
      const old = S;
      S = next;
      if (!root || !built) {
        startTable();
        prev = S;
        render();
        return;
      }
      changed(old, S);
      prev = S;
      render();
    },
    event(json) {
      let e;
      try { e = JSON.parse(json); } catch (_) { return; }
      if (e.type === 'toast') toast(e);
      else if (e.type === 'refused') {
        ui.waiting = null;
        ui.voteLanding.clear();
        ui.pileLanding = 0;
        toast({ text: e.text });
        render();
      } else if (e.type === 'back') {
        if (ui.modal) closeModal(); else leave();
      }
    },
    cover(on) { if (root) root.hidden = !!on; },
    close() {
      removeEventListener('resize', onResize);
      if (ui) { invalidate(); stopTicker(); built?.questReveal?.stop(); }
      root?.remove();
      root = built = S = prev = host = null;
    },
  };
})();
