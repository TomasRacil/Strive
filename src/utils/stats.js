/**
 * Pure stats helpers. Kept free of React so they can be unit tested in Node.
 */

export const DAY_MS = 24 * 60 * 60 * 1000;

export const startOfDay = (value) => {
  const d = new Date(value);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
};

/**
 * Consecutive-day training streak.
 *
 * A streak is allowed to end yesterday: if you trained Mon+Tue and today is
 * Wednesday, the streak is still 2 until the day is over. The previous
 * implementation only counted a run that included today, and skipped over a
 * workout logged exactly one day before the cursor, so a normal
 * train-today-and-yesterday pattern produced 1 instead of 2.
 */
export const calculateStreak = (history, now = new Date()) => {
  if (!Array.isArray(history) || history.length === 0) return 0;

  const days = new Set(history.map(session => startOfDay(session.timestamp)));
  const today = startOfDay(now);

  let cursor;
  if (days.has(today)) cursor = today;
  else if (days.has(today - DAY_MS)) cursor = today - DAY_MS;
  else return 0;

  let streak = 0;
  while (days.has(cursor)) {
    streak += 1;
    cursor -= DAY_MS;
  }
  return streak;
};

export const sessionVolume = (sets = []) =>
  sets.reduce((total, set) => total + Number(set.weight || 0) * Number(set.reps || 0), 0);

export const sessionSetCount = (sets = []) => sets.length;

export const sessionsInLastDays = (history, days = 7, now = new Date()) => {
  const cutoff = now.getTime() - days * DAY_MS;
  return history.filter(session => new Date(session.timestamp).getTime() >= cutoff).length;
};

/**
 * Estimated 1RM per session for one exercise, oldest first.
 * The estimator is passed in so this module stays free of engine imports and
 * the two can be tested independently.
 */
export const exerciseProgress = (history, exerciseId, estimate) => {
  return (history || [])
    .map(session => {
      const sets = (session.sets || []).filter(set => set.exerciseId === exerciseId);
      if (sets.length === 0) return null;

      const best = sets.reduce((a, b) => (estimate(b) > estimate(a) ? b : a));
      return {
        date: session.timestamp,
        value: Math.round(estimate(best)),
        weight: best.weight,
        reps: best.reps
      };
    })
    .filter(Boolean)
    .sort((a, b) => new Date(a.date) - new Date(b.date));
};

/**
 * Weekly tonnage per muscle group, using the engagement split stored on each
 * exercise. Returns [{ muscle, volume }] sorted descending.
 */
export const volumeByMuscle = (history, exercises, sinceDays = 7, now = new Date()) => {
  const cutoff = new Date(now).getTime() - sinceDays * DAY_MS;
  const byMuscle = new Map();

  for (const session of history) {
    if (new Date(session.timestamp).getTime() < cutoff) continue;
    for (const set of session.sets || []) {
      const exercise = exercises.find(e => e.id === set.exerciseId);
      if (!exercise) continue;
      const setVolume = Number(set.weight || 0) * Number(set.reps || 0);
      for (const muscle of exercise.muscles || []) {
        const share = (muscle.engagement || 0) / 100;
        byMuscle.set(muscle.name, (byMuscle.get(muscle.name) || 0) + setVolume * share);
      }
    }
  }

  return [...byMuscle.entries()]
    .map(([muscle, volume]) => ({ muscle, volume: Math.round(volume) }))
    .sort((a, b) => b.volume - a.volume);
};
