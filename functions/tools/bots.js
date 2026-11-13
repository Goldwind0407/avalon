// Virtual players for testing online play on a real phone.
//
//   cd functions && node tools/bots.js [count=4] [--lady] [--excalibur] [--lancelot=1|2]
//
// The first bot creates a room on the deployed project and prints the code;
// the others join. When a person joins and the table has at least 5 players,
// the host bot deals. Bots then play on their own: look at their card, pick
// teams when leading (always including the people), vote, play quest cards
// and assassinate when they are the Assassin. When a person leads, the bots
// wait for them. Bots speak in turn (and pass) when the room uses turn-based
// discussion, use the Lady of the Lake and Excalibur, and follow the
// Lancelot quest-card rules. Stop with Ctrl+C.
const { initializeApp } = require('firebase/app');
const { getAuth, signInAnonymously } = require('firebase/auth');
const { getFirestore, doc, onSnapshot, getDoc } = require('firebase/firestore');
const { getFunctions, httpsCallable } = require('firebase/functions');

const CONFIG = {
  apiKey: 'AIzaSyBX59ZuswRIrIvmhqdvd__44xl5MPyLR8A',
  appId: '1:1041864366616:web:01906d9135bce53515416d',
  projectId: 'avalon-shadow-council',
  authDomain: 'avalon-shadow-council.firebaseapp.com',
};
const NAMES = ['亞瑟', '蘭斯洛特', '高文', '崔斯坦', '貝德維爾', '加拉哈德', '凱伊', '帕西法爾', '莫德雷德'];
const EVIL = new Set(['assassin', 'morgana', 'mordred', 'oberon', 'minion', 'lancelotEvil']);
const LANCELOT = new Set(['lancelotGood', 'lancelotEvil']);
const SIZES = { 5: [2, 3, 2, 3, 3], 6: [2, 3, 4, 3, 4], 7: [2, 3, 3, 4, 4] };
const teamSize = (n, q) => (SIZES[n] ?? [3, 4, 4, 5, 5])[Math.min(q, 4)];

const args = process.argv.slice(2);
const count = Math.max(1, Math.min(9, Number(args.find((a) => /^\d+$/.test(a)) ?? 4)));
const lancelotArg = args.find((a) => a.startsWith('--lancelot'));
const expansions = {
  lady: args.includes('--lady'),
  excalibur: args.includes('--excalibur'),
  lancelot: lancelotArg ? Number(lancelotArg.split('=')[1] ?? 1) : 0,
};
const log = (...a) => console.log(new Date().toTimeString().slice(0, 8), ...a);
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const between = (a, b) => a + Math.random() * (b - a);
const shuffle = (a) => a.map((v) => [Math.random(), v]).sort((x, y) => x[0] - y[0]).map((p) => p[1]);

async function makeBot(i) {
  const app = initializeApp(CONFIG, `bot${i}`);
  const cred = await signInAnonymously(getAuth(app));
  const fns = getFunctions(app, 'asia-east1');
  return {
    name: NAMES[i],
    uid: cred.user.uid,
    db: getFirestore(app),
    // protocol 3: turn-based discussion and expansions, like the current app
    call: async (fn, data) => (await httpsCallable(fns, fn)({ protocolVersion: 3, ...data })).data,
    card: null, // { gen, role, visible }
    done: new Set(),
  };
}

async function main() {
  const bots = [];
  for (let i = 0; i < count; i++) bots.push(await makeBot(i));
  const host = bots[0];
  const { code } = await host.call('createRoom', { name: host.name });
  for (const b of bots.slice(1)) await b.call('joinRoom', { code, name: b.name });
  if (expansions.lady || expansions.excalibur || expansions.lancelot) {
    await host.call('setExpansions', { code, expansions });
  }
  log(`ROOM CODE: ${code}   (${count} bots seated, waiting for people to join)`);
  log(`expansions: ${JSON.stringify(expansions)}`);

  let room = null;
  let startTimer = null;
  const botUids = new Set(bots.map((b) => b.uid));

  const act = (bot, key, delay, fn) => {
    if (bot.done.has(key)) return;
    bot.done.add(key);
    setTimeout(async () => {
      try {
        await fn();
      } catch (e) {
        log(`${bot.name}: ${e.message}`);
      }
    }, delay);
  };

  const myCard = async (bot) => {
    if (bot.card && bot.card.gen === room.gen) return bot.card;
    const snap = await getDoc(doc(bot.db, 'rooms', code, 'private', bot.uid));
    bot.card = snap.data() ?? null;
    if (bot.card) log(`${bot.name} (${bot.seat + 1} 號) is ${bot.card.role}`);
    return bot.card;
  };

  const step = () => {
    if (!room) return;
    const people = room.players.filter((p) => !botUids.has(p.uid));
    if (room.status === 'lobby') {
      if (room.players.length >= 5 && people.length > 0 && !startTimer) {
        log(`${people.map((p) => p.name).join('、')} joined — dealing in 4 s`);
        startTimer = setTimeout(async () => {
          try {
            await host.call('startGame', { code });
            log('cards dealt');
          } catch (e) {
            log(`start failed: ${e.message}`);
          }
        }, 4000);
      }
      return;
    }
    const g = room.game;
    if (!g) return;
    const n = room.players.length;
    const turn = `${room.gen}|${g.phase}|${g.history.length}|${g.rejections}|${g.speechVersion ?? 0}`;
    const speaker = g.phase === 'discussion' ? (g.leader + 1 + (g.speechIndex ?? 0)) % n : null;
    const peopleSeats = room.playerUids
      .map((uid, seat) => (botUids.has(uid) ? -1 : seat))
      .filter((s) => s >= 0);

    for (const bot of bots) {
      const seat = room.playerUids.indexOf(bot.uid);
      bot.seat = seat;
      const move = (m, extra = {}) => bot.call('move', { code, move: m, ...extra });
      const pass = () => move('endSpeech', { expectedVersion: g.speechVersion, generation: room.gen });
      const untilDeadline = () => Math.max(0, (g.speechDeadline ?? Date.now()) - Date.now());
      switch (g.phase) {
        case 'discussion':
          if (speaker === seat) {
            act(bot, turn, between(4000, 7000), async () => {
              log(`${bot.name} passes the floor`);
              await pass();
            });
          } else if (bot === host && !botUids.has(room.playerUids[speaker])) {
            // a person's time ran out and their phone did not move on
            act(bot, `${turn}|late`, untilDeadline() + 6000, pass);
          }
          break;
        case 'freeDiscussion':
          if (bot === host) act(bot, turn, untilDeadline() + 1500, pass);
          break;
        case 'lady':
          if (g.ladyHolder === seat) {
            act(bot, turn, between(3000, 6000), async () => {
              const target = [...Array(n).keys()].find((s) => !g.ladyPast.includes(s));
              log(`${bot.name} examines ${target + 1} 號 with the Lady`);
              await move('useLady', { target });
            });
          }
          break;
        case 'ladyResult':
          if (g.ladyHolder === seat) act(bot, turn, 3000, () => move('continueLady'));
          break;
        case 'excalibur':
          if (g.excaliburHolder === seat) {
            act(bot, turn, between(2500, 5000), () => move('useExcalibur', { target: null }));
          }
          break;
        case 'excaliburResult':
          if (g.excaliburHolder === seat) act(bot, turn, 2500, () => move('continueExcalibur'));
          break;
        case 'identity':
          if (!g.confirmed.includes(seat)) {
            act(bot, turn, between(2500, 6000), async () => {
              await myCard(bot);
              await move('confirmIdentity');
            });
          }
          break;
        case 'team':
          if (g.leader === seat) {
            act(bot, turn, between(5000, 8000), async () => {
              const size = teamSize(n, g.history.length);
              const others = shuffle([...Array(n).keys()].filter((s) => s !== seat && !peopleSeats.includes(s)));
              const team = [seat, ...peopleSeats, ...others].slice(0, size).sort((a, b) => a - b);
              const excalibur = g.expansions?.excalibur ? team.find((s) => s !== seat) : null;
              log(`${bot.name} proposes ${team.map((s) => s + 1).join(', ')}` +
                (excalibur == null ? '' : `, Excalibur to ${excalibur + 1} 號`));
              await move('proposeTeam', { team, excalibur });
            });
          }
          break;
        case 'vote':
          if (!g.voted.includes(seat)) {
            act(bot, turn, between(3000, 9000), async () => {
              const card = await myCard(bot);
              const evil = card && EVIL.has(card.role);
              const teamHasEvilFriend = card && g.team.some((s) => (card.visible ?? []).includes(s));
              const approve = evil ? teamHasEvilFriend || Math.random() < 0.5 : Math.random() < 0.75;
              await move('vote', { approve });
            });
          }
          break;
        case 'voteResult':
          if (g.leader === seat) {
            act(bot, turn, 9000, () => move('continueVote'));
          } else if (bot === host && !botUids.has(room.playerUids[g.leader])) {
            act(bot, turn, 30000, () => move('continueVote')); // person's turn; host steps in late
          }
          break;
        case 'quest':
          if (g.team.includes(seat) && !g.played.includes(seat)) {
            act(bot, turn, between(3000, 7000), async () => {
              const card = await myCard(bot);
              const lancelot = card && LANCELOT.has(card.role);
              // the Lancelots play for the other side after an odd number of switches
              const evil = card && EVIL.has(card.role) !== (lancelot && g.lancelotSwitched === true);
              const mustFail = lancelot && evil && g.expansions?.lancelot === 2;
              const success = !evil || (!mustFail && Math.random() < 0.4);
              await move('playQuest', { success });
            });
          }
          break;
        case 'questResult':
          if (g.leader === seat) {
            act(bot, turn, 14000, () => move('continueQuest'));
          } else if (bot === host && !botUids.has(room.playerUids[g.leader])) {
            act(bot, turn, 35000, () => move('continueQuest'));
          }
          break;
        case 'assassination':
          act(bot, turn, 1000, async () => {
            const card = await myCard(bot);
            if (!card || card.role !== 'assassin') return;
            await wait(8000);
            const known = new Set(card.visible ?? []);
            const choices = [...Array(n).keys()].filter((s) => s !== seat && !known.has(s));
            const target = choices[Math.floor(Math.random() * choices.length)];
            log(`${bot.name} (assassin) strikes ${target + 1} 號`);
            await move('assassinate', { target });
          });
          break;
        case 'finished':
          if (bot === host) act(bot, turn, 0, async () => log(`GAME OVER: ${g.winner} — ${g.result}`));
          break;
      }
    }
  };

  onSnapshot(doc(host.db, 'rooms', code), (snap) => {
    if (!snap.exists()) {
      log('room closed');
      process.exit(0);
    }
    const prev = room;
    room = snap.data();
    if (prev && room.players.length !== prev.players.length) {
      log(`players: ${room.players.map((p, i) => `${i + 1}.${p.name}`).join(' ')}`);
    }
    if (room.status === 'lobby' && room.players.length < 5 && startTimer) {
      clearTimeout(startTimer);
      startTimer = null;
    }
    if (room.game && (!prev?.game || prev.game.phase !== room.game.phase)) {
      log(`phase: ${room.game.phase}  quest ${room.game.history.length + 1}  leader ${room.game.leader + 1} 號`);
    }
    step();
  });
}

main().catch((e) => {
  console.error('bots failed:', e);
  process.exit(1);
});
