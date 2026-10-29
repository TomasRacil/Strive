import test from 'node:test';
import assert from 'node:assert/strict';
import { calculateStreak, sessionsInLastDays, volumeByMuscle, sessionVolume, exerciseProgress } from '../src/utils/stats.js';
import { estimate1RM } from '../src/utils/engine.js';

const session = (iso) => ({ timestamp: iso, sets: [] });
const at = (daysAgo, hour = 12) => {
  const d = new Date('2026-10-29T12:00:00Z');
  d.setDate(d.getDate() - daysAgo);
  d.setHours(hour, 0, 0, 0);
  return d;
};
const NOW = at(0);

test('calculateStreak returns 0 for empty history', () => {
  assert.equal(calculateStreak([], NOW), 0);
});

test('calculateStreak counts today', () => {
  assert.equal(calculateStreak([session(at(0))], NOW), 1);
});

test('calculateStreak counts a run that ends today', () => {
  const history = [session(at(0)), session(at(1)), session(at(2))];
  assert.equal(calculateStreak(history, NOW), 3);
});

test('calculateStreak still counts a run that ended yesterday', () => {
  // Training yesterday and the day before is a 2-day streak until today ends.
  const history = [session(at(1)), session(at(2))];
  assert.equal(calculateStreak(history, NOW), 2);
});

test('calculateStreak breaks on a gap', () => {
  const history = [session(at(0)), session(at(1)), session(at(3))];
  assert.equal(calculateStreak(history, NOW), 2);
});

test('calculateStreak ignores a stale streak', () => {
  const history = [session(at(5)), session(at(6))];
  assert.equal(calculateStreak(history, NOW), 0);
});

test('calculateStreak counts a single day once with multiple sessions', () => {
  const history = [session(at(0, 9)), session(at(0, 18))];
  assert.equal(calculateStreak(history, NOW), 1);
});

test('sessionsInLastDays respects the window', () => {
  const history = [session(at(0)), session(at(3)), session(at(6)), session(at(9))];
  assert.equal(sessionsInLastDays(history, 7, NOW), 3);
});

test('sessionVolume sums weight x reps', () => {
  const sets = [{ weight: 100, reps: 5 }, { weight: 80, reps: 10 }];
  assert.equal(sessionVolume(sets), 1300);
});

test('volumeByMuscle splits volume by engagement weighting', () => {
  const exercises = [
    { id: 'bench', muscles: [{ name: 'Chest', engagement: 60 }, { name: 'Triceps', engagement: 40 }] }
  ];
  const history = [{
    timestamp: at(1),
    sets: [{ exerciseId: 'bench', weight: 100, reps: 10 }]
  }];

  const result = volumeByMuscle(history, exercises, 7, NOW);
  const byName = Object.fromEntries(result.map(r => [r.muscle, r.volume]));

  assert.equal(byName.Chest, 600);
  assert.equal(byName.Triceps, 400);
  assert.equal(result[0].muscle, 'Chest');
});

test('volumeByMuscle ignores sessions outside the window', () => {
  const exercises = [{ id: 'bench', muscles: [{ name: 'Chest', engagement: 100 }] }];
  const history = [{ timestamp: at(30), sets: [{ exerciseId: 'bench', weight: 100, reps: 10 }] }];
  assert.deepEqual(volumeByMuscle(history, exercises, 7, NOW), []);
});

test('exerciseProgress returns one point per session, oldest first', () => {
  const history = [
    { timestamp: '2026-10-20T10:00:00Z', sets: [{ exerciseId: 'bench', weight: 100, reps: 5, rir: 0 }] },
    { timestamp: '2026-10-27T10:00:00Z', sets: [{ exerciseId: 'bench', weight: 105, reps: 5, rir: 0 }] }
  ];
  const points = exerciseProgress(history, 'bench', s => estimate1RM(s.weight, s.reps, s.rir));

  assert.equal(points.length, 2);
  assert.equal(points[0].date, '2026-10-20T10:00:00Z');
  assert.ok(points[1].value > points[0].value);
});

test('exerciseProgress uses the best set in a session, not the last', () => {
  const history = [{
    timestamp: '2026-10-27T10:00:00Z',
    sets: [
      { exerciseId: 'bench', weight: 110, reps: 3, rir: 0 },
      { exerciseId: 'bench', weight: 80, reps: 10, rir: 0 }  // back-off set, lower e1RM
    ]
  }];
  const points = exerciseProgress(history, 'bench', s => estimate1RM(s.weight, s.reps, s.rir));

  assert.equal(points.length, 1);
  assert.equal(points[0].weight, 110);
});

test('exerciseProgress skips sessions that do not contain the exercise', () => {
  const history = [
    { timestamp: '2026-10-27T10:00:00Z', sets: [{ exerciseId: 'squats', weight: 150, reps: 5 }] }
  ];
  assert.deepEqual(exerciseProgress(history, 'bench', s => estimate1RM(s.weight, s.reps, s.rir)), []);
});
