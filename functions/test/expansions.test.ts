// Mirrors test/expansion_test.dart so the server and the pass-and-play
// rules stay identical.
import { strict as assert } from 'node:assert';
import { describe, test } from 'node:test';
import * as r from '../src/rules';
import { Expansions, GameError, GameState, RoleKey } from '../src/rules';

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

const seven: RoleKey[] = [
  'merlin', 'assassin', 'loyal', 'minion', 'loyal', 'lancelotGood', 'lancelotEvil',
];
const LANCELOT_GOOD = 5;
const LANCELOT_EVIL = 6;
const ASSASSIN = 1;

/** A game with fixed seats and leader 0, past the identity phase. */
function game(e: Partial<Expansions>, roles: RoleKey[] = seven): GameState {
  const expansions = { ...r.NO_EXPANSIONS, ...e };
  const s = r.newGame(roles.length, [], seeded(1), r.FREE_DISCUSSION, expansions);
  s.roles = [...roles];
  s.leader = 0;
  if (expansions.lady) {
    s.ladyHolder = roles.length - 1;
    s.ladyPast = [roles.length - 1];
  }
  for (let i = 0; i < roles.length; i++) r.confirmIdentity(s, i);
  return s;
}

const throwsGame = (fn: () => void) => assert.throws(fn, GameError);

function approve(s: GameState, team: number[], sword: number | null = null) {
  r.proposeTeam(s, s.leader, team, Date.now(), sword);
  for (let i = 0; i < s.roles.length; i++) r.vote(s, i, true);
  r.continueVote(s);
}

/** The Assassin goes on every quest and fails it when [fail] is set. */
function play(s: GameState, fail = false) {
  const team = [ASSASSIN, 0, 2, 3, 4].slice(0, r.requiredTeam(s));
  approve(s, team, s.expansions.excalibur ? team.find((i) => i !== s.leader)! : null);
  for (const seat of team) {
    r.playQuest(s, seat, !(seat === ASSASSIN && fail) && !r.mustFail(s, seat), seeded(3));
  }
  if (s.phase === 'excalibur') r.useExcalibur(s, s.excaliburHolder!, null, seeded(3));
  r.continueQuest(s);
  if (s.phase === 'lady') {
    const target = s.roles.findIndex((_, i) => !s.ladyPast.includes(i));
    r.useLady(s, s.ladyHolder!, target);
    r.continueLady(s, s.ladyHolder!);
  }
}

describe('expansions mirror expansion_test.dart', () => {
  test('the Lancelots take one good and one evil place', () => {
    const v1: Expansions = { ...r.NO_EXPANSIONS, lancelot: 1 };
    for (const n of [7, 8, 10]) {
      const roles = r.dealRoles(n, [], seeded(n), v1);
      assert.ok(roles.includes('lancelotGood') && roles.includes('lancelotEvil'));
      assert.equal(roles.filter(r.isEvil).length, r.evilCount(n));
    }
    assert.equal(r.configIssue(6, [], v1), '蘭斯洛特擴充需要 7 人以上');
    assert.equal(r.configIssue(7, ['morgana'], v1), null);
    assert.notEqual(r.configIssue(7, ['morgana', 'mordred'], v1), null);
    assert.throws(() => r.expansionSettings({ lady: true, lancelot: 3, excalibur: false }));
  });

  test('evil sees evil Lancelot; Lancelot sees nobody', () => {
    assert.ok(r.visibleSeats(seven, ASSASSIN).includes(LANCELOT_EVIL));
    assert.ok(r.visibleSeats(seven, 0).includes(LANCELOT_EVIL));
    assert.deepEqual(r.visibleSeats(seven, LANCELOT_EVIL), []);
    assert.deepEqual(r.visibleSeats(seven, LANCELOT_GOOD), []);
  });

  test('variant 1: loyalty cards are turned over from the third quest', () => {
    const s = game({ lancelot: 1 });
    s.loyaltyDeck = [true, false, false, false, false, true, false];
    play(s);
    play(s, true);
    assert.deepEqual(s.loyalty, [null, null, true, null, null]);
    assert.equal(s.lancelotSwitched, true);
    assert.equal(r.evilNow(s, LANCELOT_GOOD), true);
    assert.equal(r.evilNow(s, LANCELOT_EVIL), false);
    assert.equal(r.mustFail(s, LANCELOT_GOOD), false);
    approve(s, [LANCELOT_EVIL, LANCELOT_GOOD, 0]);
    throwsGame(() => r.playQuest(s, LANCELOT_EVIL, false, seeded(3)));
    r.playQuest(s, LANCELOT_EVIL, true, seeded(3));
    r.playQuest(s, LANCELOT_GOOD, false, seeded(3));
    r.playQuest(s, 0, true, seeded(3));
    assert.equal(s.history[2].fails, 1);
    r.continueQuest(s);
    play(s, true);
    assert.deepEqual(s.loyalty, [null, null, true, false, false]);
    assert.equal(s.loyaltyDeck.length, 4);
  });

  test('a rejected team does not turn over another loyalty card', () => {
    const s = game({ lancelot: 1 });
    s.loyaltyDeck = [true, true, false, false, false, false, false];
    play(s);
    play(s, true);
    r.proposeTeam(s, s.leader, [0, 1, 2]);
    for (let i = 0; i < 7; i++) r.vote(s, i, false);
    r.continueVote(s);
    assert.deepEqual(s.loyalty, [null, null, true, null, null]);
    assert.equal(s.lancelotSwitched, true);
  });

  test('variant 2: five cards are dealt face up; evil Lancelot must fail', () => {
    const fresh = r.newGame(7, [], seeded(4), r.FREE_DISCUSSION,
      { ...r.NO_EXPANSIONS, lancelot: 2 });
    assert.ok(fresh.loyalty.every((c) => c !== null));
    assert.ok(fresh.loyalty.filter((c) => c).length <= 2);
    assert.equal(fresh.lancelotSwitched, fresh.loyalty[0]);

    const s = game({ lancelot: 2 });
    s.loyalty = [true, false, false, false, true];
    s.lancelotSwitched = true;
    assert.equal(r.mustFail(s, LANCELOT_GOOD), true);
    assert.equal(r.mustFail(s, LANCELOT_EVIL), false);
    approve(s, [LANCELOT_GOOD, LANCELOT_EVIL]);
    throwsGame(() => r.playQuest(s, LANCELOT_GOOD, true, seeded(3)));
    throwsGame(() => r.playQuest(s, LANCELOT_EVIL, false, seeded(3)));
    r.playQuest(s, LANCELOT_GOOD, false, seeded(3));
    r.playQuest(s, LANCELOT_EVIL, true, seeded(3));
    assert.equal(s.history[0].succeeded, false);
  });

  test('Lady of the Lake after quests 2-4, never on a past holder', () => {
    const fresh = r.newGame(7, [], seeded(5), r.FREE_DISCUSSION,
      { ...r.NO_EXPANSIONS, lady: true });
    assert.equal(fresh.ladyHolder, (fresh.leader + 6) % 7);

    const s = game({ lady: true });
    const first = 6;
    play(s);
    assert.equal(s.phase, 'team');
    approve(s, [ASSASSIN, 0, 2]);
    for (const seat of [ASSASSIN, 0, 2]) r.playQuest(s, seat, seat !== ASSASSIN, seeded(3));
    r.continueQuest(s);
    assert.equal(s.phase, 'lady');
    throwsGame(() => r.useLady(s, 0, ASSASSIN)); // not the holder
    throwsGame(() => r.useLady(s, first, first)); // past holder
    r.useLady(s, first, ASSASSIN);
    assert.equal(s.phase, 'ladyResult');
    assert.deepEqual(s.reveals.at(-1), { seat: first, kind: 'lady', quest: 2, target: ASSASSIN, evil: true });
    throwsGame(() => r.continueLady(s, 0));
    const leader = s.leader;
    r.continueLady(s, first);
    assert.equal(s.ladyHolder, ASSASSIN);
    assert.deepEqual(s.ladyPast, [first, ASSASSIN]);
    assert.equal(s.phase, 'team');
    assert.equal(s.leader, (leader + 1) % 7);
    // reveals stay secret
    assert.ok(!('reveals' in r.split(s).open));
  });

  test('Lady sees a switched Lancelot on their current side', () => {
    const s = game({ lady: true, lancelot: 2 });
    s.loyalty = [true, false, false, false, false];
    s.lancelotSwitched = true;
    play(s);
    approve(s, [ASSASSIN, 0, 2]);
    for (const seat of [ASSASSIN, 0, 2]) r.playQuest(s, seat, seat !== ASSASSIN, seeded(3));
    r.continueQuest(s);
    r.useLady(s, 6, LANCELOT_GOOD);
    assert.equal(s.reveals.at(-1)?.evil, true);
  });

  test('three successes go straight to the assassination', () => {
    const s = game({ lady: true });
    play(s);
    play(s);
    play(s);
    assert.equal(s.phase, 'assassination');
  });

  test('Excalibur: handed to a team member, may flip one other card', () => {
    const s = game({ excalibur: true }, ['merlin', 'assassin', 'loyal', 'minion', 'loyal']);
    throwsGame(() => r.proposeTeam(s, 0, [0, 2]));
    throwsGame(() => r.proposeTeam(s, 0, [0, 2], Date.now(), 0));
    throwsGame(() => r.proposeTeam(s, 0, [0, 2], Date.now(), 4));
    approve(s, [0, 2], 2);
    assert.equal(s.excaliburHolder, 2);
    r.playQuest(s, 0, true, seeded(3));
    r.playQuest(s, 2, true, seeded(3));
    assert.equal(s.phase, 'excalibur');
    throwsGame(() => r.useExcalibur(s, 0, 2, seeded(3)));
    throwsGame(() => r.useExcalibur(s, 2, 2, seeded(3)));
    r.useExcalibur(s, 2, 0, seeded(3));
    assert.equal(s.phase, 'excaliburResult');
    assert.equal(s.reveals.at(-1)?.card, true);
    r.continueExcalibur(s, 2, seeded(3));
    assert.equal(s.phase, 'questResult');
    assert.equal(s.history[0].fails, 1);
    assert.deepEqual(s.history[0].excalibur, { holder: 2, target: 0 });
    r.continueQuest(s);
    assert.equal(s.excaliburHolder, null);
  });
});
