// Mirrors test/game_model_test.dart so the server and the pass-and-play
// rules stay identical.
import { strict as assert } from 'node:assert';
import { describe, test } from 'node:test';
import * as r from '../src/rules';
import { GameError, GameState, RoleKey } from '../src/rules';

/** Deterministic random numbers (mulberry32). */
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

/** A game with a fixed seating, skipping straight past the identity phase. */
function game(roles: RoleKey[], leader = 0): GameState {
  const s = r.newGame(roles.length, [], seeded(1));
  s.roles = [...roles];
  s.leader = leader;
  for (let i = 0; i < roles.length; i++) r.confirmIdentity(s, i);
  return s;
}

function voteAll(s: GameState, approve: (seat: number) => boolean) {
  for (let i = 0; i < s.roles.length; i++) r.vote(s, i, approve(i));
}

/** Leader proposes the first seats, everyone approves, team plays [cards]. */
function runQuest(s: GameState, cards: (seat: number) => boolean) {
  const team = Array.from({ length: r.requiredTeam(s) }, (_, i) => i);
  r.proposeTeam(s, s.leader, team);
  voteAll(s, () => true);
  r.continueVote(s);
  for (const seat of team) r.playQuest(s, seat, cards(seat), seeded(2));
}

const five: RoleKey[] = ['merlin', 'assassin', 'loyal', 'minion', 'loyal'];
const seven: RoleKey[] = ['merlin', 'assassin', 'loyal', 'minion', 'loyal', 'morgana', 'loyal'];

const throwsGame = (fn: () => void) => assert.throws(fn, GameError);

describe('rules mirror game_model.dart', () => {
  test('all supported player counts receive correct alignment and quest sizes', () => {
    const sizes: Record<number, number[]> = {
      5: [2, 3, 2, 3, 3],
      6: [2, 3, 4, 3, 4],
      7: [2, 3, 3, 4, 4],
      8: [3, 4, 4, 5, 5],
      9: [3, 4, 4, 5, 5],
      10: [3, 4, 4, 5, 5],
    };
    for (let n = 5; n <= 10; n++) {
      const roles = r.dealRoles(n, [], seeded(n));
      assert.equal(roles.length, n);
      assert.equal(roles.filter(r.isEvil).length, r.evilCount(n));
      assert.ok(roles.includes('merlin') && roles.includes('assassin'));
      assert.deepEqual([0, 1, 2, 3, 4].map((q) => r.questSize(n, q)), sizes[n]);
    }
  });

  test('invalid role configuration cannot start', () => {
    assert.equal(r.configIssue(4, []), '需要 5～10 位玩家');
    assert.equal(r.configIssue(11, []), '需要 5～10 位玩家');
    assert.equal(r.configIssue(5, ['morgana', 'mordred']), '邪惡角色超過本局邪惡陣營名額');
    assert.equal(r.configIssue(5, ['percival', 'morgana']), null);
    assert.equal(r.configIssue(10, ['percival', 'morgana', 'mordred', 'oberon']), null);
    throwsGame(() => r.dealRoles(5, ['morgana', 'mordred', 'oberon'], seeded(1)));
  });

  test('Merlin, Percival and evil have the correct private knowledge', () => {
    const roles: RoleKey[] = ['merlin', 'percival', 'assassin', 'morgana', 'mordred', 'oberon', 'loyal', 'loyal', 'minion', 'loyal'];
    // Merlin sees evil except Mordred (Oberon is seen)
    assert.deepEqual(r.visibleSeats(roles, 0), [2, 3, 5, 8]);
    // Percival sees Merlin and Morgana
    assert.deepEqual(r.visibleSeats(roles, 1), [0, 3]);
    // evil see each other except Oberon
    assert.deepEqual(r.visibleSeats(roles, 2), [3, 4, 8]);
    // Oberon sees nobody
    assert.deepEqual(r.visibleSeats(roles, 5), []);
    // loyal servants see nobody
    assert.deepEqual(r.visibleSeats(roles, 6), []);
  });

  test('tie rejects the team; fifth rejection ends the game', () => {
    const s = game([...five, 'loyal']); // 6 players: 3 : 3 is a tie
    for (let k = 0; k < 5; k++) {
      r.proposeTeam(s, s.leader, [0, 1]);
      voteAll(s, (seat) => seat < 3);
      assert.equal(r.teamApproved(s), false);
      r.continueVote(s);
    }
    assert.equal(s.phase, 'finished');
    assert.equal(s.winner, '邪惡');
    assert.equal(s.result, '連續五次組隊遭否決，邪惡陣營獲勝。');
    assert.deepEqual(s.revealedRoles, s.roles);
  });

  test('a rejection passes leadership to the next seat', () => {
    const s = game(five, 4);
    r.proposeTeam(s, 4, [0, 1]);
    voteAll(s, () => false);
    r.continueVote(s);
    assert.equal(s.leader, 0);
    assert.equal(s.rejections, 1);
    assert.equal(s.phase, 'team');
  });

  test('approval on the fifth proposal resets rejections for the next quest', () => {
    const s = game(five);
    for (let k = 0; k < 4; k++) {
      r.proposeTeam(s, s.leader, [0, 1]);
      voteAll(s, () => false);
      r.continueVote(s);
    }
    assert.equal(s.rejections, 4);
    r.proposeTeam(s, s.leader, [0, 1]);
    voteAll(s, () => true);
    r.continueVote(s);
    assert.equal(s.rejections, 0);
    assert.equal(s.phase, 'quest');
  });

  test('good players cannot sabotage; three failed quests end the game', () => {
    const s = game(five);
    r.proposeTeam(s, s.leader, [0, 3]);
    voteAll(s, () => true);
    r.continueVote(s);
    throwsGame(() => r.playQuest(s, 0, false, seeded(3)));
    assert.equal(s.played.length, 0);
    for (let q = 0; q < 3; q++) {
      if (q > 0) {
        const size = r.requiredTeam(s);
        const team = [3, ...[0, 2, 4].slice(0, size - 1)];
        r.proposeTeam(s, s.leader, team);
        voteAll(s, () => true);
        r.continueVote(s);
      }
      for (const seat of s.team) r.playQuest(s, seat, seat !== 3, seeded(q));
      assert.equal(s.history.at(-1)!.succeeded, false);
      r.continueQuest(s);
    }
    assert.equal(s.phase, 'finished');
    assert.equal(s.winner, '邪惡');
    assert.equal(s.result, '三次任務失敗，邪惡陣營獲勝。');
  });

  test('fourth quest needs two fails for seven or more players', () => {
    assert.equal(r.failsRequired(7, 4), 2);
    assert.equal(r.failsRequired(6, 4), 1);
    assert.equal(r.failsRequired(10, 3), 1);
    const s = game(seven);
    // quests 1-3: one success, two... keep the game alive: S, F, S
    runQuest(s, () => true);
    r.continueQuest(s);
    runQuest(s, (seat) => seat !== 1);
    r.continueQuest(s);
    runQuest(s, () => true);
    r.continueQuest(s);
    // quest 4 with a single fail card still succeeds
    runQuest(s, (seat) => seat !== 1);
    const q4 = s.history.at(-1)!;
    assert.equal(q4.fails, 1);
    assert.equal(q4.succeeded, true);
  });

  test('quest result keeps a shuffled order of the same cards', () => {
    const s = game(seven);
    runQuest(s, (seat) => seat !== 1);
    const q = s.history[0];
    assert.equal(q.order.length, q.team.length);
    assert.equal(q.order.filter((c) => !c).length, q.fails);
    assert.deepEqual(s.pendingCards, {});
  });

  test('three successes lead to assassination, with either ending', () => {
    for (const target of [0, 2]) {
      const s = game(five);
      for (let q = 0; q < 3; q++) {
        runQuest(s, () => true);
        r.continueQuest(s);
      }
      assert.equal(s.phase, 'assassination');
      const names = ['A', 'B', 'C', 'D', 'E'];
      r.assassinate(s, 1, target, names);
      assert.equal(s.phase, 'finished');
      assert.equal(s.assassinTarget, target);
      if (target === 0) {
        assert.equal(s.winner, '邪惡');
        assert.equal(s.result, '刺客選擇 1 號 A，成功刺殺梅林。');
      } else {
        assert.equal(s.winner, '正義');
        assert.equal(s.result, '刺客選擇 3 號 C，未能找到梅林，正義陣營獲勝！');
      }
    }
  });

  test('invalid teams cannot advance the game', () => {
    const s = game(five);
    throwsGame(() => r.proposeTeam(s, 0, [0]));
    throwsGame(() => r.proposeTeam(s, 0, [0, 0]));
    throwsGame(() => r.proposeTeam(s, 0, [0, 9]));
    throwsGame(() => r.proposeTeam(s, 1, [0, 1])); // not the leader
    assert.equal(s.phase, 'team');
  });

  test('assassination accepts every other seat without revealing alignment', () => {
    for (let target = 0; target < 5; target++) {
      if (target === 1) continue;
      const s = game(five);
      for (let q = 0; q < 3; q++) {
        runQuest(s, () => true);
        r.continueQuest(s);
      }
      r.assassinate(s, 1, target, ['A', 'B', 'C', 'D', 'E']);
      assert.equal(s.phase, 'finished');
    }
  });

  test('invalid assassination targets do not consume the choice', () => {
    const s = game(five);
    for (let q = 0; q < 3; q++) {
      runQuest(s, () => true);
      r.continueQuest(s);
    }
    throwsGame(() => r.assassinate(s, 1, 1, [])); // own seat
    throwsGame(() => r.assassinate(s, 1, 7, [])); // no such seat
    throwsGame(() => r.assassinate(s, 0, 2, [])); // not the assassin
    assert.equal(s.phase, 'assassination');
  });

  test('every move checks the phase and the player', () => {
    const s = r.newGame(5, [], seeded(9));
    throwsGame(() => r.proposeTeam(s, s.leader, [0, 1]));
    throwsGame(() => r.vote(s, 0, true));
    for (let i = 0; i < 5; i++) r.confirmIdentity(s, i);
    r.proposeTeam(s, s.leader, [0, 1]);
    r.vote(s, 0, true);
    throwsGame(() => r.vote(s, 0, false)); // cannot vote twice
    // a vote stays secret until everyone has voted
    assert.equal(s.votes, null);
    const { open } = r.split(s);
    assert.equal(JSON.stringify(open).includes('pendingVotes'), false);
  });
});
