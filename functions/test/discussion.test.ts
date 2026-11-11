import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import * as r from '../src/rules';

function game(freeSeconds = 0) {
  const s = r.newGame(5, [], () => .25, {
    enabled: true, speechSeconds: 45, freeSeconds, selectionFree: true,
  });
  for (let i = 0; i < 5; i++) r.confirmIdentity(s, i);
  r.proposeTeam(s, s.leader, [0, 1], 1000);
  return s;
}

test('leader speaks last; early pass requires speaker; stale concurrent passes are no-ops', () => {
  const s = game();
  for (let i = 1; i <= 5; i++) {
    const seat = (s.leader + i) % 5, version = s.speechVersion;
    assert.equal(r.currentSpeaker(s), seat);
    assert.throws(() => r.vote(s, seat, true), r.GameError);
    assert.throws(() => r.endSpeech(s, (seat + 1) % 5, version, 1001), r.GameError);
    assert.equal(r.endSpeech(s, seat, version, 1001), true);
    assert.equal(r.endSpeech(s, seat, version, 1001), false);
    assert.equal(s.speechVersion, version + 1);
  }
  assert.equal(s.phase, 'vote');
  assert.equal(s.speechDeadline, null);
});

test('any member may advance expired speech; free discussion cannot end early', () => {
  const s = game(60);
  r.endSpeech(s, s.leader, s.speechVersion, 46000);
  while (s.phase === 'discussion') r.endSpeech(s, r.currentSpeaker(s)!, s.speechVersion, 46000);
  assert.equal(s.phase, 'freeDiscussion');
  assert.equal(s.speechDeadline, 106000);
  assert.throws(() => r.endSpeech(s, 0, s.speechVersion, 105999), r.GameError);
  r.endSpeech(s, 0, s.speechVersion, 106000);
  assert.equal(s.phase, 'vote');
});

test('rejected proposals persist and incomplete ballots are never published', () => {
  const s = game();
  for (let attempt = 1; attempt <= 5; attempt++) {
    if (attempt > 1) r.proposeTeam(s, s.leader, [1, 2], 1000);
    while (s.phase === 'discussion') r.endSpeech(s, r.currentSpeaker(s)!, s.speechVersion, 1000);
    for (let i = 0; i < 4; i++) r.vote(s, i, false);
    assert.equal(s.proposals.length, attempt - 1);
    const open = r.split(s).open;
    assert.equal(open.votes, null);
    assert.equal('pendingVotes' in open, false);
    r.vote(s, 4, true);
    const record = s.proposals.at(-1)!;
    assert.equal(record.attempt, attempt);
    assert.equal(record.leader, s.leader);
    assert.equal(record.approved, false);
    assert.deepEqual(record.votes, [false, false, false, false, true]);
    r.continueVote(s);
  }
  assert.equal(s.phase, 'finished');
  assert.equal(s.proposals.length, 5);
  assert.deepEqual(s.proposals[0].team, [0, 1]);
  assert.equal(s.winner, '邪惡');
});

test('settings reject invalid durations and legacy games use classic discussion', () => {
  for (const value of [false, { ...r.FREE_DISCUSSION, speechSeconds: 0 },
    { ...r.FREE_DISCUSSION, speechSeconds: 91 }, { ...r.FREE_DISCUSSION, freeSeconds: 1 }]) {
    assert.throws(() => r.discussionSettings(value), r.GameError);
  }
  const s = game();
  const { open, secret } = r.split(s);
  const legacy = { ...open } as any;
  delete legacy.discussion;
  delete legacy.proposals;
  const restored = r.join(legacy, secret);
  assert.equal(restored.discussion.enabled, false);
  assert.deepEqual(restored.proposals, []);
});
