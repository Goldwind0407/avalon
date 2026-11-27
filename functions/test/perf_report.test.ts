import { strict as assert } from 'node:assert';
import { describe, it } from 'node:test';
import { cleanPerfReport } from '../src/perf_report';

const good = {
  renderer: 'wasm', isolated: true, light: false, gaveUp: false, fps: 57.3,
  latePct: 4.2, p95: 19.1, worst: 120, slowSeconds: 0, seconds: 118,
  dpr: 3, width: 844, height: 390, standalone: true,
  ua: 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X)', page: '#/online?x=1',
  stages: {
    voteResult: { fps: 22.4, latePct: 61, seconds: 9.5, stalls: 2 },
    discussion: { fps: 58, latePct: 2, seconds: 80, stalls: 0 },
  },
  stalls: [
    { stage: 'voteResult', ms: 340, before: ['voice@-120', 'net:v32185c79.mp3@-80', 'sfx:flip@3'] },
    { stage: 'deal', ms: 120 },
  ],
  over: { 50: 9, 100: 4, 250: 3, 500: 2, 1000: 0 },
};

describe('perf reports', () => {
  it('keeps a well-formed report, the screen without its query', () => {
    const r = cleanPerfReport(good);
    assert.ok(r);
    assert.equal(r.fps, 57.3);
    assert.equal(r.page, '#/online');
    assert.equal(r.stages.voteResult.fps, 22.4);
    assert.deepEqual(r.stalls[0].before, ['voice@-120', 'net:v32185c79.mp3@-80', 'sfx:flip@3']);
    assert.deepEqual(r.stalls[1].before, []);
    assert.equal(r.over['500'], 2);
    assert.equal(r.release, null);
  });
  it('keeps the release played, when it looks like one', () => {
    assert.equal(cleanPerfReport({ ...good, release: 'c1bda885e689f241' })?.release, 'c1bda885e689f241');
    assert.equal(cleanPerfReport({ ...good, release: 'not-a-release' })?.release, null);
  });
  it('drops anything missing or out of range', () => {
    assert.equal(cleanPerfReport(null), null);
    assert.equal(cleanPerfReport({ ...good, renderer: 'canvaskit' }), null);
    assert.equal(cleanPerfReport({ ...good, fps: Number.NaN }), null);
    assert.equal(cleanPerfReport({ ...good, latePct: 101 }), null);
    assert.equal(cleanPerfReport({ ...good, light: 'yes' }), null);
    assert.equal(cleanPerfReport({ ...good, stages: { 'a b': good.stages.discussion } }), null);
    assert.equal(cleanPerfReport({ ...good, stages: { deal: { fps: 30 } } }), null);
    assert.equal(cleanPerfReport({ ...good, stalls: [{ stage: 'deal' }] }), null);
    assert.equal(cleanPerfReport({ ...good, over: { 60: 1 } }), null);
    assert.equal(cleanPerfReport({ ...good, stalls: [{ stage: 'deal', ms: 1, before: ['<b>@1'] }] }), null);
    assert.equal(cleanPerfReport({ ...good, stalls: Array(9).fill(good.stalls[0]) }), null);
    const { ua: _ua, ...noUa } = good;
    assert.equal(cleanPerfReport(noUa), null);
  });
  it('keeps nothing it was not asked for, and bounds the text', () => {
    const r = cleanPerfReport({ ...good, email: 'x@y.z', ua: 'u'.repeat(900) });
    assert.ok(r);
    assert.equal('email' in r, false);
    assert.equal(r.ua.length, 300);
  });
});
