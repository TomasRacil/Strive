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
    if (sex === 'female' || isMaster) {
      // Prioritize volume (reps) before weight for masters to protect joints
      const targetReps = isMaster ? 12 : 15;
      if (reps >= targetReps && rir >= 2) return weight + 2.5;
      return weight;
    }
    
    // Aggressive progression for juniors
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
    const maxReps = (sex === 'female' || isMaster) ? 15 : 12;
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

const MUSCLE_TO_BENCHMARK = {
  'Chest': ['bench_press', 'pushups'],
  'Triceps': ['bench_press', 'pushups'],
  'Front Delts': ['bench_press', 'pushups', 'pike_pushups'],
  'Quads': ['squat', 'bw_squat'],
  'Glutes': ['squat', 'glute_bridge', 'bw_squat'],
  'Hamstrings': ['deadlift', 'glute_bridge'],
  'Lower Back': ['deadlift'],
  'Upper Back': ['barbell_row', 'doorway_row', 'inverted_row'],
  'Back': ['barbell_row', 'doorway_row', 'inverted_row', 'pullups'],
  'Lats': ['barbell_row', 'pullups'],
  'Shoulders': ['overhead_press', 'pike_pushups'],
  'Biceps': ['barbell_row', 'inverted_row']
};

export const getCalibratedLoad = (exercise, history, goal, sex, birthDate) => {
  if (!exercise || !Array.isArray(history)) return null;
  
  const primaryMuscle = exercise.muscles?.[0]?.name;
  const benchmarkIds = MUSCLE_TO_BENCHMARK[primaryMuscle];
  if (!benchmarkIds) return null;
  
  let bestE1RM = 0;
  
  // Search history for the best 1RM of any relevant benchmark exercise
  history.forEach(session => {
    if (session.sets) {
      session.sets.forEach(set => {
        benchmarkIds.forEach(benchmarkId => {
          const idMatch = set.exerciseId === benchmarkId;
          const nameMatch = set.exerciseName && set.exerciseName.toLowerCase().includes(benchmarkId.replace('_', ' '));
          
          if (idMatch || nameMatch) {
            const e1rm = estimate1RM(parseFloat(set.weight || 0), parseInt(set.reps), parseInt(set.rir || 0), sex, benchmarkId);
            if (!isNaN(e1rm) && e1rm > bestE1RM) bestE1RM = e1rm;
          }
        });
      });
    }
  });
  
  if (bestE1RM <= 0) return null;
  
  const userWeight = parseFloat(localStorage.getItem('strive_weight') || '75');
  // 0.4 is the average benchmark startRatio (Novice level)
  // Clamp strength multiplier between 0.5 and 4.0 to avoid insane suggestions
  let strengthMultiplier = bestE1RM / (userWeight * 0.4);
  strengthMultiplier = Math.min(Math.max(strengthMultiplier, 0.5), 4.0);
  
  const exerciseRatio = exercise.startRatio || 0.2;
  const calibrated1RM = userWeight * exerciseRatio * strengthMultiplier;
  
  return calculateTargetLoadFrom1RM(calibrated1RM, goal, sex, birthDate);
};
