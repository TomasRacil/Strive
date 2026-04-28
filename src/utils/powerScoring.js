import { estimate1RM } from './engine';

// Multipliers of Bodyweight for each level
const STANDARDS = {
  male: {
    bench_press: { beginner: 0.75, novice: 1.0, intermediate: 1.25, advanced: 1.5, elite: 1.75 },
    squat: { beginner: 1.0, novice: 1.25, intermediate: 1.5, advanced: 1.75, elite: 2.0 },
    deadlift: { beginner: 1.2, novice: 1.5, intermediate: 1.75, advanced: 2.25, elite: 2.75 },
    overhead_press: { beginner: 0.5, novice: 0.7, intermediate: 0.9, advanced: 1.1, elite: 1.3 },
    barbell_row: { beginner: 0.75, novice: 1.0, intermediate: 1.25, advanced: 1.5, elite: 1.75 }
  },
  female: {
    bench_press: { beginner: 0.4, novice: 0.6, intermediate: 0.8, advanced: 1.0, elite: 1.2 },
    squat: { beginner: 0.6, novice: 0.8, intermediate: 1.1, advanced: 1.4, elite: 1.7 },
    deadlift: { beginner: 0.8, novice: 1.0, intermediate: 1.3, advanced: 1.7, elite: 2.1 },
    overhead_press: { beginner: 0.3, novice: 0.45, intermediate: 0.6, advanced: 0.8, elite: 1.0 },
    barbell_row: { beginner: 0.4, novice: 0.6, intermediate: 0.8, advanced: 1.0, elite: 1.2 }
  }
};

const LEVELS = ['Beginner', 'Novice', 'Intermediate', 'Advanced', 'Elite'];
const LEVEL_COLORS = {
  'Beginner': '#9ca3af', // Gray
  'Novice': '#10b981', // Green
  'Intermediate': '#3b82f6', // Blue
  'Advanced': '#8b5cf6', // Purple
  'Elite': '#f59e0b', // Gold
  'Unranked': '#4b5563' // Dark Gray
};

export const calculateMaxE1RM = (history, exerciseId, sex = 'male') => {
  if (!history || history.length === 0) return 0;
  
  let maxE1RM = 0;
  history.forEach(session => {
    if (session.sets) {
      session.sets.forEach(set => {
        if (set.exerciseId === exerciseId) {
          const e1rm = estimate1RM(parseFloat(set.weight), parseInt(set.reps), parseInt(set.rir || 0), sex);
          if (e1rm > maxE1RM) {
            maxE1RM = e1rm;
          }
        }
      });
    }
  });
  
  return maxE1RM;
};

export const calculatePowerScore = (history, bodyweight, sex = 'male') => {
  const bw = parseFloat(bodyweight);
  if (!bw || isNaN(bw)) return null;

  const targetLifts = ['bench_press', 'squat', 'deadlift', 'overhead_press', 'barbell_row'];
  let totalScore = 0;
  let activeLifts = 0;
  
  const liftDetails = targetLifts.map(liftId => {
    const maxE1RM = calculateMaxE1RM(history, liftId, sex);
    
    if (maxE1RM === 0) return { id: liftId, maxE1RM: 0, level: 'Unranked', multiplier: 0, progressToNext: 0 };
    
    const multiplier = maxE1RM / bw;
    const stds = STANDARDS[sex][liftId];
    
    let levelIndex = -1;
    let currentLevelScore = 0;
    
    if (multiplier >= stds.elite) levelIndex = 4;
    else if (multiplier >= stds.advanced) levelIndex = 3;
    else if (multiplier >= stds.intermediate) levelIndex = 2;
    else if (multiplier >= stds.novice) levelIndex = 1;
    else if (multiplier >= stds.beginner) levelIndex = 0;
    
    // Calculate fractional score for overall Power Level
    // Each level is worth 1.0 points (e.g. Novice = 1.0, Intermediate = 2.0)
    // We interpolate between levels
    const levelsArr = [0, stds.beginner, stds.novice, stds.intermediate, stds.advanced, stds.elite];
    let exactScore = 0;
    let progressToNext = 0;
    
    for (let i = 0; i < levelsArr.length - 1; i++) {
      if (multiplier >= levelsArr[i] && multiplier < levelsArr[i+1]) {
        const range = levelsArr[i+1] - levelsArr[i];
        const progress = (multiplier - levelsArr[i]) / range;
        exactScore = i - 1 + progress; // -1 because < beginner is negative score space
        progressToNext = progress * 100;
        break;
      }
    }
    
    if (multiplier >= stds.elite) {
      exactScore = 4.0;
      progressToNext = 100;
    }
    
    totalScore += Math.max(0, exactScore);
    activeLifts++;

    const levelStr = levelIndex >= 0 ? LEVELS[levelIndex] : 'Beginner';
    
    return {
      id: liftId,
      maxE1RM,
      multiplier,
      level: levelStr,
      color: LEVEL_COLORS[levelStr],
      progressToNext
    };
  });
  
  // If no lifts recorded, return unranked
  if (activeLifts === 0) return { overallLevel: 'Unranked', color: LEVEL_COLORS['Unranked'], details: liftDetails };
  
  // Average score across active lifts
  const avgScore = totalScore / activeLifts;
  let overallLevel = 'Beginner';
  if (avgScore >= 4.0) overallLevel = 'Elite';
  else if (avgScore >= 3.0) overallLevel = 'Advanced';
  else if (avgScore >= 2.0) overallLevel = 'Intermediate';
  else if (avgScore >= 1.0) overallLevel = 'Novice';
  else if (avgScore > 0) overallLevel = 'Beginner';
  
  return {
    overallLevel,
    color: LEVEL_COLORS[overallLevel],
    details: liftDetails,
    score: (avgScore * 25).toFixed(1) // Map 0-4 scale to 0-100 Power Score
  };
};
