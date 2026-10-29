import test from 'node:test';
import assert from 'node:assert/strict';
import { estimate1RM, suggestNextWeight, suggestNextReps, getBenchmarkProgression, findLastSet, findBest1RM } from '../src/utils/engine.js';

test('estimate1RM uses Brzycki and matches a known value', () => {
  // 100kg x 5 @ RIR 0 -> 100 / (1.0278 - 0.0278*5) = 112.51
  assert.equal(Math.round(estimate1RM(100, 5, 0) * 100) / 100, 112.51);
});

test('estimate1RM treats RIR as reps in hand', () => {
  assert.ok(estimate1RM(100, 5, 2) > estimate1RM(100, 5, 0));
});

test('estimate1RM returns 0 for missing or zero input', () => {
  assert.equal(estimate1RM(0, 5), 0);
  assert.equal(estimate1RM(100, 0, 0), 0);
  assert.equal(estimate1RM(undefined, undefined), 0);
});

test('estimate1RM stays finite at absurd rep counts', () => {
  const value = estimate1RM(100, 40, 0);
  assert.ok(Number.isFinite(value));
  assert.ok(value > 0);
});

test('suggestNextWeight adds load when RIR is high enough for the goal', () => {
  assert.equal(suggestNextWeight({ weight: 100, reps: 8, rir: 2 }, 'build_muscle'), 102.5);
  assert.equal(suggestNextWeight({ weight: 100, reps: 5, rir: 1 }, 'build_strength'), 102.5);
});

test('suggestNextWeight holds load when the set was near failure', () => {
  assert.equal(suggestNextWeight({ weight: 100, reps: 8, rir: 0 }, 'build_muscle'), 100);
  assert.equal(suggestNextWeight({ weight: 100, reps: 8, rir: 2 }, 'maintain'), 100);
});

test('suggestNextWeight returns null without a baseline', () => {
  assert.equal(suggestNextWeight(null), null);
  assert.equal(suggestNextWeight({ weight: 0 }), null);
});

test('suggestNextReps progresses hypertrophy reps and caps at 12', () => {
  assert.equal(suggestNextReps({ reps: 8, rir: 2 }, 'build_muscle'), 9);
  assert.equal(suggestNextReps({ reps: 12, rir: 2 }, 'build_muscle'), 12);
});

test('suggestNextReps defaults sensibly with no history', () => {
  assert.equal(suggestNextReps(null, 'build_strength'), 5);
  assert.equal(suggestNextReps(null, 'build_muscle'), 10);
});

test('getBenchmarkProgression scales with RIR', () => {
  assert.equal(getBenchmarkProgression(100, 3), 120);
  assert.equal(getBenchmarkProgression(100, 2), 110);
  assert.equal(getBenchmarkProgression(100, 1), 102.5);
  assert.equal(getBenchmarkProgression(100, 0), 100);
});

test('findLastSet returns the best set from the most recent session', () => {
  const history = [
    { timestamp: '2026-10-28', sets: [{ exerciseId: 'bench', weight: 90, reps: 8, rir: 1 }, { exerciseId: 'bench', weight: 100, reps: 5, rir: 1 }] },
    { timestamp: '2026-10-20', sets: [{ exerciseId: 'bench', weight: 120, reps: 5, rir: 0 }] }
  ];
  const best = findLastSet(history, 'bench');
  assert.equal(best.weight, 100);
  assert.equal(best.reps, 5);
});

test('findLastSet skips sessions that do not contain the exercise', () => {
  const history = [
    { timestamp: '2026-10-28', sets: [{ exerciseId: 'squats', weight: 150, reps: 5 }] },
    { timestamp: '2026-10-20', sets: [{ exerciseId: 'bench', weight: 80, reps: 8 }] }
  ];
  assert.equal(findLastSet(history, 'bench').weight, 80);
});

test('findLastSet returns null when the exercise was never logged', () => {
  assert.equal(findLastSet([], 'bench'), null);
  assert.equal(findLastSet([{ sets: [] }], 'bench'), null);
  assert.equal(findLastSet(null, 'bench'), null);
});

test('findBest1RM returns 0 with no history', () => {
  assert.equal(findBest1RM([], 'bench'), 0);
  assert.equal(findBest1RM(null, 'bench'), 0);
});

test('findBest1RM picks the best estimated set across all sessions', () => {
  const history = [
    { sets: [{ exerciseId: 'bench', weight: 90, reps: 10, rir: 0 }] },
    { sets: [{ exerciseId: 'bench', weight: 100, reps: 5, rir: 0 }] }
  ];
  // 90x10 -> ~119.7 beats 100x5 -> ~112.5
  assert.ok(Math.abs(findBest1RM(history, 'bench') - 119.7) < 0.5);
});

test('findBest1RM ignores other exercises', () => {
  const history = [{ sets: [{ exerciseId: 'squats', weight: 200, reps: 5, rir: 0 }] }];
  assert.equal(findBest1RM(history, 'bench'), 0);
});

test('findBest1RM includes sets from the session in progress', () => {
  const history = [{ sets: [{ exerciseId: 'bench', weight: 100, reps: 5, rir: 0 }] }];
  const current = [{ exerciseId: 'bench', weight: 105, reps: 5, rir: 0 }];
  assert.ok(findBest1RM(history, 'bench', current) > findBest1RM(history, 'bench'));
});
