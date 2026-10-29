/**
 * Strive Intelligence Engine
 * Handles weight suggestions and strength estimation.
 */

export const estimate1RM = (weight, reps, rir = 0) => {
  const actualReps = Number(reps || 0) + Number(rir || 0);
  if (!weight || actualReps <= 0) return 0;
  // Brzycki formula is only valid for reps < 37; clamp to avoid negative/absurd output.
  const clamped = Math.min(actualReps, 36);
  return Number(weight) / (1.0278 - 0.0278 * clamped);
};

const roundToPlate = (weight) => Math.round(weight * 2) / 2;

export const suggestNextWeight = (lastSet, goal = 'build_muscle') => {
  if (!lastSet || !lastSet.weight) return null;

  const weight = Number(lastSet.weight);
  const rir = Number(lastSet.rir ?? 0);

  // Progressive overload based on goals.
  if (goal === 'build_strength') {
    return rir >= 1 ? roundToPlate(weight + 2.5) : weight;
  }

  if (goal === 'build_muscle') {
    return rir >= 2 ? roundToPlate(weight + 2.5) : weight;
  }

  // Maintenance: only increase if RIR is very high (safety).
  if (goal === 'maintain') {
    return rir >= 3 ? roundToPlate(weight + 2.5) : weight;
  }

  return weight;
};

export const suggestNextReps = (lastSet, goal = 'build_muscle') => {
  if (!lastSet) return goal === 'build_strength' ? 5 : 10;

  const { reps = 0, rir = 0 } = lastSet;

  if (goal === 'build_muscle') {
    if (rir >= 2 && reps < 12) return reps + 1; // Increase reps until 12
    return reps;
  }

  if (goal === 'build_strength') {
    if (reps > 6) return 5; // Pull back to strength range
    return reps;
  }

  return reps;
};

export const getBenchmarkProgression = (currentWeight, rir) => {
  if (rir >= 3) return roundToPlate(currentWeight * 1.2); // 20% jump
  if (rir === 2) return roundToPlate(currentWeight * 1.1); // 10% jump
  if (rir === 1) return roundToPlate(currentWeight + 2.5); // Small jump
  return currentWeight; // Limit found
};

/**
 * Best estimated 1RM ever recorded for an exercise, optionally including sets
 * from the session currently in progress (which are not in history yet).
 */
export const findBest1RM = (history, exerciseId, extraSets = []) => {
  let best = 0;

  const consider = (set) => {
    if (!set || set.exerciseId !== exerciseId) return;
    best = Math.max(best, estimate1RM(set.weight, set.reps, set.rir));
  };

  for (const session of history || []) {
    for (const set of session.sets || []) consider(set);
  }
  for (const set of extraSets || []) consider(set);

  return best;
};

/**
 * Find the best set logged for an exercise in the most recent session that
 * contains it. History is expected newest-first, which is how useHistory stores it.
 * Used to auto-fill the next workout from what you actually lifted last time,
 * instead of only from a manually saved template.
 */
export const findLastSet = (history, exerciseId) => {
  if (!Array.isArray(history) || !exerciseId) return null;

  for (const session of history) {
    const sets = (session.sets || []).filter(s => s.exerciseId === exerciseId);
    if (sets.length > 0) {
      return sets.reduce((best, set) => (
        estimate1RM(set.weight, set.reps, set.rir) > estimate1RM(best.weight, best.reps, best.rir)
          ? set
          : best
      ));
    }
  }
  return null;
};
