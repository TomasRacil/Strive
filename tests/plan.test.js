import test from 'node:test';
import assert from 'node:assert/strict';
import { buildSessionPlan, planToGarminRoutine, planVolume } from '../src/utils/plan.js';

const routine = {
  name: 'Push Day A',
  exercises: [
    { id: 'bench_press', name: 'Bench Press', targetSets: 4, targetReps: 8, restSeconds: 150 },
    { id: 'overhead_press', name: 'Overhead Press', targetSets: 3, targetReps: 10 }
  ]
};

const history = [
  {
    timestamp: '2026-10-28T10:00:00Z',
    sets: [{ exerciseId: 'bench_press', weight: 80, reps: 8, rir: 2 }]
  }
];

test('plan uses routine targets when there is no history', () => {
  const plan = buildSessionPlan(routine, [], 'build_muscle');
  assert.equal(plan.length, 2);
  assert.equal(plan[0].sets, 4);
  assert.equal(plan[0].reps, 8);
  assert.equal(plan[0].weight, null, 'no history means no invented weight');
  assert.equal(plan[0].restSeconds, 150);
  assert.match(plan[0].reason, /No history/);
});

test('plan recommends a heavier load when the last set had reps in reserve', () => {
  const plan = buildSessionPlan(routine, history, 'build_muscle');
  assert.equal(plan[0].weight, 82.5, '80 kg at 2 RIR progresses by 2.5 kg');
  assert.equal(plan[0].last.weight, 80);
  assert.equal(plan[0].last.rir, 2);
});

test('plan holds the load when the last set was near failure', () => {
  const hard = [{ timestamp: '2026-10-28T10:00:00Z', sets: [{ exerciseId: 'bench_press', weight: 80, reps: 8, rir: 0 }] }];
  const plan = buildSessionPlan(routine, hard, 'build_muscle');
  assert.equal(plan[0].weight, 80);
});

test('plan respects the strength goal', () => {
  const hard = [{ timestamp: '2026-10-28T10:00:00Z', sets: [{ exerciseId: 'bench_press', weight: 100, reps: 3, rir: 1 }] }];
  const plan = buildSessionPlan(routine, hard, 'build_strength');
  assert.equal(plan[0].weight, 102.5);
});

test('plan falls back to the routine weight only when there is no history', () => {
  const withWeight = {
    name: 'R',
    exercises: [{ id: 'deadlift', name: 'Deadlift', targetSets: 3, targetReps: 5, weight: 120 }]
  };
  const plan = buildSessionPlan(withWeight, [], 'build_muscle');
  assert.equal(plan[0].weight, 120);
});

test('plan prefers history over a routine weight', () => {
  const withWeight = {
    name: 'R',
    exercises: [{ id: 'bench_press', name: 'Bench Press', targetSets: 3, targetReps: 8, weight: 60 }]
  };
  const plan = buildSessionPlan(withWeight, history, 'build_muscle');
  assert.equal(plan[0].weight, 82.5);
});

test('plan applies sane defaults for missing targets', () => {
  const bare = { name: 'Bare', exercises: [{ id: 'squats', name: 'Squats' }] };
  const plan = buildSessionPlan(bare, [], 'build_muscle');
  assert.equal(plan[0].sets, 3);
  assert.equal(plan[0].reps, 8);
  assert.equal(plan[0].restSeconds, 90);
});

test('plan handles an empty routine', () => {
  assert.deepEqual(buildSessionPlan(null, [], 'build_muscle'), []);
  assert.deepEqual(buildSessionPlan({ exercises: [] }, [], 'build_muscle'), []);
});

test('planToGarminRoutine carries weights and omits them when unknown', () => {
  const plan = buildSessionPlan(routine, history, 'build_muscle');
  const out = planToGarminRoutine('Push Day A', plan);

  assert.equal(out.name, 'Push Day A');
  assert.equal(out.exercises[0].weight, 82.5);
  assert.equal(out.exercises[0].targetSets, 4);
  assert.equal(out.exercises[0].targetReps, 8);
  assert.equal(out.exercises[1].weight, undefined, 'no history means no weight key');
});

test('planVolume sums tonnage of the planned work', () => {
  const plan = buildSessionPlan(routine, history, 'build_muscle');
  // bench: 82.5 * 8 * 4 = 2640, overhead has no weight
  assert.equal(planVolume(plan), 2640);
});
