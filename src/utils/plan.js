/**
 * Turn a routine into a concrete session plan with recommended loads.
 *
 * This is what makes the watch useful: Garmin's strength app shows the planned
 * weight for each set, but it never decides that weight for you. The plan below
 * derives it from your last performance on the same lift plus the goal, so the
 * number on your wrist is the progression the engine recommends.
 */

import { findLastSet, suggestNextWeight, suggestNextReps, estimate1RM } from './engine.js';

export const DEFAULT_SETS = 3;
export const DEFAULT_REPS = 8;
export const DEFAULT_REST_SECONDS = 90;

const toNumber = (value, fallback) => {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
};

/**
 * @param {object} routine  { name, exercises: [{ id, name, targetSets, targetReps, restSeconds, weight }] }
 * @param {Array}  history  newest-first session list
 * @param {string} goal     'build_muscle' | 'build_strength' | 'maintain'
 */
export const buildSessionPlan = (routine, history, goal = 'build_muscle') => {
  const exercises = routine?.exercises || [];

  return exercises.map((exercise) => {
    const sets = toNumber(exercise.targetSets, DEFAULT_SETS);
    const restSeconds = toNumber(exercise.restSeconds, DEFAULT_REST_SECONDS);

    const last = findLastSet(history, exercise.id);

    // Fall back to a weight written on the routine only when there is no history
    // for the lift at all — history always wins, it is what you actually did.
    const seed = last || (exercise.weight
      ? { weight: exercise.weight, reps: exercise.targetReps ?? DEFAULT_REPS, rir: 0 }
      : null);

    const recommendedWeight = seed ? suggestNextWeight(seed, goal) : null;
    const reps = toNumber(exercise.targetReps, seed ? suggestNextReps(seed, goal) : DEFAULT_REPS);

    return {
      id: exercise.id,
      name: exercise.name || 'Exercise',
      sets,
      reps,
      weight: recommendedWeight,
      restSeconds,
      last: last ? { weight: last.weight, reps: last.reps, rir: last.rir } : null,
      estimated1RM: last ? Math.round(estimate1RM(last.weight, last.reps, last.rir)) : null,
      reason: last
        ? `Last time ${last.weight} kg x ${last.reps} @ ${last.rir ?? 0} RIR`
        : 'No history yet — pick a weight you can do for the target reps'
    };
  });
};

/**
 * Convert a plan back into the routine shape the Garmin bridge consumes.
 * Unweighted exercises omit the weight so Garmin shows no target.
 */
export const planToGarminRoutine = (routineName, plan) => ({
  name: routineName,
  exercises: plan.map(item => ({
    id: item.id,
    name: item.name,
    targetSets: item.sets,
    targetReps: item.reps,
    restSeconds: item.restSeconds,
    ...(item.weight ? { weight: item.weight } : {})
  }))
});

export const planVolume = (plan) => plan.reduce(
  (total, item) => total + (item.weight || 0) * item.reps * item.sets,
  0
);
