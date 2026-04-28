/**
 * Strive Intelligence Engine
 * Handles weight suggestions and strength estimation.
 */

export const estimate1RM = (weight, reps, rir = 0) => {
  const actualReps = reps + rir;
  if (actualReps === 0) return 0;
  // Brzycki Formula
  return weight / (1.0278 - (0.0278 * actualReps));
};

export const suggestNextWeight = (lastSet, goal = 'build_muscle') => {
  if (!lastSet) return null;
  
  const { weight, reps, rir } = lastSet;
  
  // Progressive Overload Logic based on Goals
  if (goal === 'build_strength') {
    if (rir >= 1) return weight + 2.5; // Aggressive for strength
    return weight;
  }
  
  if (goal === 'build_muscle') {
    if (rir >= 2) return weight + 2.5; // Moderate for hypertrophy
    return weight;
  }
  
  // Maintenance: only increase if RIR is very high (safety)
  if (goal === 'maintain') {
    if (rir >= 3) return weight + 2.5;
    return weight;
  }
  
  return weight;
};

export const suggestNextReps = (lastSet, goal = 'build_muscle') => {
  if (!lastSet) return goal === 'build_strength' ? 5 : 10;
  
  const { reps, rir } = lastSet;

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
  if (rir >= 3) return currentWeight * 1.2; // 20% jump
  if (rir === 2) return currentWeight * 1.1; // 10% jump
  if (rir === 1) return currentWeight + 2.5; // Small jump
  return currentWeight; // Limit found
};
