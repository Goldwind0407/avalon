// The stand-in that plays for a player whose phone has gone quiet.
import { strict as assert } from 'node:assert';
import { describe, test } from 'node:test';
import * as proxy from '../src/proxy';
import * as r from '../src/rules';
import { GameState, RoleKey } from '../src/rules';

function seeded(seed: number): r.Rng {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const names = (s: GameState) => s.roles.map((_, i) => `P${i + 1}`);
const everyone = (s: GameState) => s.roles.map((_, i) => i);
const LONG = 60 * 1000;

function game(roles: RoleKey[], leader = 0): GameState {
  const s = r.newGame(roles.length, [], seeded(1));
  s.roles = [...roles];
  s.leader = leader;
  for (let i = 0; i < roles.length; i++) r.confirmIdentity(s, i);
  return s;
}

describe('presence', () => {
  test('a phone is away after a minute of silence, or when never heard from', () => {
    assert.equal(proxy.isAway(1000, 1000 + proxy.AWAY_AFTER_MS), false);
    assert.equal(proxy.isAway(1000, 1001 + proxy.AWAY_AFTER_MS), true);
    assert.equal(proxy.isAway(null, 0), true);
  });
});

describe('stand-in', () => {
  test('a table of stand-ins plays any game through to the end', () => {
    const setups: [number, RoleKey[], r.Expansions][] = [
      [5, [], r.NO_EXPANSIONS],
      [6, ['percival', 'morgana'], { lady: true, lancelot: 0, excalibur: false }],
      [7, ['percival', 'morgana'], { lady: true, lancelot: 1, excalibur: true }],
      [8, ['percival', 'morgana'], { lady: false, lancelot: 2, excalibur: true }],
      [10, ['percival', 'morgana', 'mordred'], { lady: true, lancelot: 2, excalibur: false }],
      [9, ['percival', 'morgana', 'oberon'], { lady: true, lancelot: 0, excalibur: true }],
    ];
    for (const [players, optional, expansions] of setups) {
      for (let seed = 1; seed <= 40; seed++) {
        const rng = seeded(seed * 31 + players);
        const talk = seed % 2 === 0
          ? { enabled: true, speechSeconds: 45, freeSeconds: 0, selectionFree: true }
          : r.FREE_DISCUSSION;
        const s = r.newGame(players, optional, rng, talk, expansions);
        let calls = 0;
        while (s.phase !== 'finished') {
          assert.ok(++calls < 400, `stuck in ${s.phase} (${players} players, seed ${seed})`);
          const moves = proxy.standIn(s, everyone(s), rng, names(s), 0, LONG);
          assert.ok(moves > 0, `nothing to do in ${s.phase} (${players} players, seed ${seed})`);
        }
        assert.ok(s.winner === '正義' || s.winner === '邪惡');
      }
    }
  });

  test('it stops where the game waits for someone who is there', () => {
    const s = game(['merlin', 'assassin', 'loyal', 'loyal', 'minion']);
    r.proposeTeam(s, 0, [0, 1]);
    // only seats 1 and 4 are away: their votes go in, the rest is waited for
    assert.equal(proxy.standIn(s, [1, 4], seeded(3), names(s), 0, LONG), 2);
    assert.equal(s.phase, 'vote');
    assert.deepEqual([...s.voted].sort(), [1, 4]);
    assert.equal(proxy.standIn(s, [1, 4], seeded(3), names(s), 0, LONG), 0);
  });

  test('a result is left on the table long enough to be seen', () => {
    const s = game(['merlin', 'assassin', 'loyal', 'loyal', 'minion']);
    // every seat away: one call runs up to the vote result and stops there
    proxy.standIn(s, everyone(s), seeded(4), names(s), 0, LONG);
    assert.equal(s.phase, 'voteResult');
    // shown a moment ago: not yet
    assert.equal(proxy.standIn(s, everyone(s), seeded(4), names(s), 0, proxy.RESULT_VIEW_MS - 1), 0);
    assert.equal(s.phase, 'voteResult');
    assert.ok(proxy.standIn(s, everyone(s), seeded(4), names(s), 0, proxy.RESULT_VIEW_MS) > 0);
    assert.notEqual(s.phase, 'voteResult');
  });

  test('it plays its side: no ally exposed for nothing, no evil let through knowingly', () => {
    // seven players, fourth quest needs two Fails; the lone minion holds back
    const s = game(['merlin', 'assassin', 'loyal', 'loyal', 'minion', 'loyal', 'mordred']);
    s.history = [0, 1, 2].map((i) => ({ team: [2, 3], fails: i === 0 ? 1 : 0, succeeded: i !== 0, order: [] }));
    r.proposeTeam(s, 0, [0, 2, 3, 4]);
    for (let seat = 0; seat < 7; seat++) r.vote(s, seat, true);
    r.continueVote(s);
    for (const seat of [0, 2, 3, 4]) proxy.act(s, seat, seeded(5), names(s), 0, false);
    assert.equal(s.history[3].fails, 0);

    // Merlin's stand-in turns down a team with an evil player he sees on it
    const t = game(['merlin', 'assassin', 'loyal', 'loyal', 'minion'], 1);
    r.proposeTeam(t, 1, [1, 2]);
    proxy.act(t, 0, seeded(6), names(t), 0, false);
    assert.equal(t.pendingVotes['0'], false);
    // and as leader leaves them off his own
    const u = game(['merlin', 'assassin', 'loyal', 'loyal', 'minion']);
    proxy.act(u, 0, seeded(7), names(u), 0, false);
    assert.ok(!u.team.includes(1) && !u.team.includes(4), `team ${u.team}`);
  });

  test('the fifth proposal is never turned down by a stand-in', () => {
    const s = game(['merlin', 'assassin', 'loyal', 'loyal', 'minion']);
    s.rejections = 4;
    r.proposeTeam(s, 0, [1, 4]);
    proxy.standIn(s, everyone(s), seeded(8), names(s), 0, LONG);
    assert.deepEqual(s.votes, [true, true, true, true, true]);
  });
});

describe('stand-in with the Lancelots', () => {
  const roles: RoleKey[] =
    ['merlin', 'assassin', 'lancelotEvil', 'lancelotGood', 'loyal', 'loyal', 'morgana'];
  function lancelotGame(switched: boolean): GameState {
    const s = r.newGame(7, ['morgana'], seeded(1), r.FREE_DISCUSSION,
      { lady: true, lancelot: 2, excalibur: false });
    s.roles = [...roles];
    s.leader = 4;
    s.loyalty = [switched, false, false, false, false];
    s.lancelotSwitched = switched;
    for (let i = 0; i < 7; i++) r.confirmIdentity(s, i);
    return s;
  }

  test('an evil Lancelot who has switched is no longer counted as an ally', () => {
    assert.deepEqual([...proxy.knownEvil(lancelotGame(false), 1)].sort(), [2, 6]);
    assert.deepEqual([...proxy.knownEvil(lancelotGame(true), 1)], [6]);
    // Merlin cannot tell which of the evil players he sees is Lancelot
    assert.deepEqual([...proxy.knownEvil(lancelotGame(true), 0)].sort(), [1, 2, 6]);
    // the Assassin's stand-in no longer waves a team through for his sake:
    // over many votes on [switched Lancelot, loyal] some are against
    let against = 0;
    for (let seed = 0; seed < 40; seed++) {
      const s = lancelotGame(true);
      r.proposeTeam(s, 4, [2, 4]);
      proxy.act(s, 1, seeded(seed), names(s), 0, false);
      if (s.pendingVotes['1'] === false) against++;
    }
    assert.ok(against > 5, `against ${against} of 40`);
  });

  test('a Lady result from before a switch is not relied on', () => {
    const s = lancelotGame(false);
    s.reveals.push({ seat: 4, kind: 'lady', quest: 2, target: 2, evil: true });
    s.history = [0, 1].map(() => ({ team: [4, 5], fails: 0, succeeded: true, order: [] }));
    assert.ok(proxy.knownEvil(s, 4).has(2));
    s.loyalty[2] = true; // turned over as the third quest begins
    s.lancelotSwitched = true;
    assert.ok(!proxy.knownEvil(s, 4).has(2));
  });
});
