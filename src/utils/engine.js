/**
 * Strive Intelligence Engine v1.4
 * Handles biological and age-specific weight suggestions and strength estimation.
 */

const calculateAge = (birthDate) => {
  if (!birthDate) return 30; // Default to 30 if unknown
  const today = new Date();
  const birth = new Date(birthDate);
  let age = today.getFullYear() - birth.getFullYear();
  const m = today.getMonth() - birth.getMonth();
  if (m < 0 || (m === 0 && today.getDate() < birth.getDate())) {
    age--;
  }
  return age;
};

export const calculateStartingLoad = (startRatio, weight, height, bodyFat, sex = 'male') => {
  let lbm = weight * 0.75; // Default rough estimate

  if (bodyFat) {
    lbm = weight * (1 - (parseFloat(bodyFat) / 100));
  } else if (height && weight) {
    // Boer Formula for Lean Body Mass
    const w = parseFloat(weight);
    const h = parseFloat(height);
    if (sex === 'female') {
      lbm = (0.252 * w) + (0.473 * h) - 48.3;
    } else {
      lbm = (0.407 * w) + (0.267 * h) - 19.2;
    }
  }

  // Adjust ratio since startRatio was originally based on total body weight
  // If original ratio was 0.5 (for total weight), new ratio for LBM should be higher (e.g. 0.5 / 0.75 = 0.66)
  const lbmRatio = startRatio / 0.75; 
  
  const guessedWeight = Math.max(20, Math.floor((lbm * lbmRatio) / 2.5) * 2.5);
  return guessedWeight;
};

export const getBodyweightLoadFactor = (exerciseId) => {
  const factors = {
    'pushups': 0.65,
    'knee_pushups': 0.45,
    'diamond_pushups': 0.70,
    'pike_pushups': 0.50,
    'pike_pushups_elevated': 0.75,
    'pullups': 1.0,
    'dips': 0.90,
    'inverted_row': 0.50,
    'bw_squat': 0.0, 
    'pistol_squat': 1.0,
    'lunges': 0.40,
    'glute_bridge': 0.30,
    'single_leg_glute_bridge': 0.50
  };
  return factors[exerciseId] || 0;
};

export const estimate1RM = (weight, reps, rir = 0, sex = 'male', exerciseId = null, userWeightOverride = null) => {
  const actualReps = reps + rir;
  if (actualReps === 0) return 0;

  let effectiveWeight = weight;
  
  // If weight is 0 or explicitly bodyweight-based, calculate based on BW
  if (exerciseId && (weight === 0 || weight === 'BW')) {
    const userWeight = userWeightOverride || parseFloat(localStorage.getItem('strive_weight') || '75');
    const factor = getBodyweightLoadFactor(exerciseId);
    effectiveWeight = userWeight * factor;
  }

  // Use Epley formula for better stability at high rep ranges
  // 1RM = Weight * (1 + (Reps / 30))
  return effectiveWeight * (1 + (actualReps / 30));
};

export const suggestNextWeight = (lastSet, goal = 'build_muscle', sex = 'male', birthDate = null) => {
  if (!lastSet) return null;
  const { weight, reps, rir } = lastSet;
  const age = calculateAge(birthDate);
  
  // Recovery/Progression factor based on Age
  // Master's athletes (>45) benefit from slower weight jumps
  const isMaster = age > 45;
  const isJunior = age < 23;
  
  if (goal === 'build_strength') {
    if (rir >= 1) return weight + 2.5; 
    return weight;
  }
  
  if (goal === 'build_muscle') {
    const targetReps = (sex === 'female' || isMaster) ? 12 : 10;
    
    // Fatigue Management / Rep Range Correction:
    if (reps < targetReps - 2 && rir <= 1) {
      return Math.round((weight * 0.9) / 2.5) * 2.5;
    }

    // Progressive Overload (Step Loading):
    // 1. If you exceeded target reps (e.g. 11-12) even with low RIR
    // 2. If you hit your target reps (10) with at least 1 RIR to spare
    if (reps >= targetReps + 1 || (reps >= targetReps && rir >= 1)) {
      return weight + 2.5;
    }

    if (sex === 'female' || isMaster) {
      if (reps >= 12 && rir >= 2) return weight + 2.5;
      return weight;
    }
    
    if (isJunior && rir >= 3) return weight + 5; 
    if (rir >= 2) return weight + 2.5; 
    return weight;
  }
  
  if (goal === 'maintain') {
    if (rir >= 3) return weight + 2.5;
    return weight;
  }
  
  return weight;
};

export const suggestNextReps = (lastSet, goal = 'build_muscle', sex = 'male', birthDate = null) => {
  if (!lastSet) {
    if (goal === 'build_strength') return 5;
    return sex === 'female' ? 12 : 10;
  }
  
  const { reps, rir } = lastSet;
  const age = calculateAge(birthDate);
  const isMaster = age > 45;

  if (goal === 'build_muscle') {
    const targetReps = (sex === 'female' || isMaster) ? 12 : 10;
    const maxReps = (sex === 'female' || isMaster) ? 15 : 12;

    // If we fell short and hit failure, and we expect a weight drop, reset to target reps
    if (reps < targetReps - 2 && rir <= 1) return targetReps;
    
    // Progressive Overload Reset:
    // If we hit/exceeded target reps and weight is likely increasing, reset reps back to target baseline
    if (reps >= targetReps + 1 || (reps >= targetReps && rir >= 1)) return targetReps;

    // Intra-session adaptation: If it was way too easy (RIR 3+), jump 2 reps
    if (rir >= 3 && reps < maxReps - 1) return reps + 2;
    
    if (rir >= 1 && reps < maxReps) return reps + 1;
    return reps;
  }
  
  if (goal === 'build_strength') {
    if (reps > 6) return 5; 
    return reps;
  }
  
  return reps;
};

export const calculateNextBenchmarkTarget = (currentSetNumber, currentWeight, reps, rir, sex = 'male', birthDate = null) => {
  const e1RM = estimate1RM(currentWeight, reps, rir, sex);
  
  let targetWeight = currentWeight;
  let targetReps = 1;
  let message = "";
  let type = "info";

  // Phase 1: Acclimation (Set 2)
  if (currentSetNumber === 1) {
    targetWeight = Math.max(currentWeight + 2.5, e1RM * 0.70); // Ensure it at least goes up
    targetReps = 5;
    message = `Warmup logged. Acclimating with 5 reps at ~70% capacity.`;
  } 
  // Phase 2: Intensity Build (Set 3)
  else if (currentSetNumber === 2) {
    targetWeight = Math.max(currentWeight + 2.5, e1RM * 0.85);
    targetReps = 3;
    message = `Building intensity. Drop to 3 reps at ~85% capacity.`;
  } 
  // Phase 3: Near Max (Set 4)
  else if (currentSetNumber === 3) {
    targetWeight = Math.max(currentWeight + 2.5, e1RM * 0.95);
    targetReps = 1;
    message = `Near max effort! Single rep at ~95% capacity.`;
    type = "warning";
  } 
  // Phase 4: Max Testing (Set 5+)
  else {
    let jumpPercent = 0.05; // Default 5% jump for 1 RIR
    if (rir >= 3) jumpPercent = 0.20; // 20% jump if it was way too light
    else if (rir === 2) jumpPercent = 0.10; // 10% jump for 2 RIR
    
    // Calculate raw jump, ensure at least a minimum plate jump
    const rawJump = Math.max(currentWeight * jumpPercent, sex === 'female' ? 2.5 : 5);
    targetWeight = currentWeight + rawJump;
    
    targetReps = 1;
    message = `True max attempt! Let's push the limit.`;
    type = "warning";
  }

  // Always round to the nearest 2.5kg (standard plate increments)
  targetWeight = Math.round(targetWeight / 2.5) * 2.5;

  return { weight: targetWeight, reps: targetReps, message, type };
};

export const calculateTargetLoadFrom1RM = (e1RM, goal, sex = 'male', birthDate = null) => {
  if (!e1RM || isNaN(e1RM) || e1RM <= 0) return { weight: 0, reps: 10 };

  const age = calculateAge(birthDate);
  const isMaster = age > 45;
  
  let intensity = 0.75; // Default 75% for Muscle
  let reps = 10;
  
  if (goal === 'build_strength') {
    intensity = 0.85;
    reps = 5;
  } else if (goal === 'build_muscle') {
    intensity = isMaster ? 0.70 : 0.75;
    reps = (sex === 'female' || isMaster) ? 12 : 10;
  } else if (goal === 'maintain') {
    intensity = 0.65;
    reps = 12;
  }
  
  // Calculate weight and ensure it's at least a standard bar (20kg) or a reasonable minimum
  let weight = Math.round((e1RM * intensity) / 2.5) * 2.5;
  weight = Math.max(sex === 'female' ? 15 : 20, weight);
  
  return { weight, reps };
};

const BENCHMARK_EQUIVALENTS = {
  'bench_press': ['bench_press', 'pushups', 'knee_pushups', 'diamond_pushups'],
  'squat': ['squat', 'bw_squat', 'pistol_squat'],
  'deadlift': ['deadlift', 'glute_bridge', 'single_leg_glute_bridge'],
  'overhead_press': ['overhead_press', 'pike_pushups', 'pike_pushups_elevated'],
  'barbell_row': ['barbell_row', 'inverted_row', 'doorway_row']
};

export const getCalibratedLoad = (exercise, history, goal, sex, birthDate) => {
  if (!exercise) return null;
  
  // Find which benchmark matches this exercise's primary muscle
  const primaryMuscle = exercise.muscles?.[0]?.name;
  let benchmarkId = null;
  
  if (['Chest', 'Triceps'].includes(primaryMuscle)) benchmarkId = 'bench_press';
  else if (['Quads', 'Glutes'].includes(primaryMuscle)) benchmarkId = 'squat';
  else if (['Hamstrings', 'Lower Back'].includes(primaryMuscle)) benchmarkId = 'deadlift';
  else if (['Upper Back', 'Back', 'Lats', 'Biceps'].includes(primaryMuscle)) benchmarkId = 'barbell_row';
  else if (['Shoulders', 'Front Delts'].includes(primaryMuscle)) benchmarkId = 'overhead_press';

  if (!benchmarkId) return null;
  
  let bestE1RM = 0;

  // 1. CHECK SPECIFIC HISTORY FIRST (Highest Precedence)
  // If the user has actually done THIS exercise, their real performance is the most accurate calibration.
  if (Array.isArray(history)) {
    history.forEach(session => {
      if (session.sets) {
        session.sets.forEach(set => {
          if (set.exerciseId === exercise.id || (set.exerciseName === exercise.name)) {
            const sessionWeight = session.userWeight || parseFloat(localStorage.getItem('strive_weight') || '75');
            const e1rm = estimate1RM(parseFloat(set.weight || 0), parseInt(set.reps), parseInt(set.rir || 0), sex, set.exerciseId, sessionWeight);
            if (!isNaN(e1rm) && e1rm > bestE1RM) bestE1RM = e1rm;
          }
        });
      }
    });
  }

  // 2. FALLBACK TO BENCHMARK VAULT (If no specific history found)
  if (bestE1RM === 0) {
    try {
      const benchmarks = JSON.parse(localStorage.getItem('strive_benchmarks') || '{}');
      if (benchmarks[benchmarkId]) {
        bestE1RM = benchmarks[benchmarkId];
      }
    } catch (e) {}
  }

  // 3. FALLBACK TO BROAD HISTORY SCAN
  if (bestE1RM === 0 && Array.isArray(history)) {
    const equivalents = BENCHMARK_EQUIVALENTS[benchmarkId] || [benchmarkId];
    history.forEach(session => {
      if (session.sets) {
        session.sets.forEach(set => {
          if (equivalents.includes(set.exerciseId)) {
            const sessionWeight = session.userWeight || parseFloat(localStorage.getItem('strive_weight') || '75');
            const e1rm = estimate1RM(parseFloat(set.weight || 0), parseInt(set.reps), parseInt(set.rir || 0), sex, set.exerciseId, sessionWeight);
            if (!isNaN(e1rm) && e1rm > bestE1RM) bestE1RM = e1rm;
          }
        });
      }
    });
  }
  
  if (bestE1RM === 0) return null;
  return calculateTargetLoadFrom1RM(bestE1RM, goal, sex, birthDate);
};
