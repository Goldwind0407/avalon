import { strict as assert } from 'node:assert';
import { describe, test } from 'node:test';
import * as l from '../src/limits';

describe('limits', () => {
  const limit = { max: 3, windowMs: 1000 };
  test('only what falls inside the window counts', () => {
    assert.deepEqual(l.recent([100, 900, 1500, 2100, 'x', null], 2000, limit), [1500]);
    assert.deepEqual(l.recent(undefined, 2000, limit), []);
    // a time from the future (a skewed clock) does not count either
    assert.deepEqual(l.recent([1500, 5000], 2000, limit), [1500]);
  });
  test('one more is allowed until the window is full, then after it clears', () => {
    assert.equal(l.allowed([1100, 1200], 2000, limit), true);
    assert.equal(l.allowed([1100, 1200, 1300], 2000, limit), false);
    assert.equal(l.waitMs([1100, 1200, 1300], 2000, limit), 100);
    assert.equal(l.waitMs([1100, 1200], 2000, limit), 0);
    assert.equal(l.allowed([1100, 1200, 1300], 2101, limit), true);
  });
  test('the limits are generous for friends and tight for guessing', () => {
    assert.ok(l.LIMITS.create.max >= 10);
    assert.ok(l.LIMITS.miss.max <= 20);
  });
});
