import { useState, useEffect } from 'react';

const HISTORY_KEY = 'strive_workout_history';

export const useHistory = () => {
  const [history, setHistory] = useState([]);

  useEffect(() => {
    const savedHistory = JSON.parse(localStorage.getItem(HISTORY_KEY) || '[]');
    setHistory(savedHistory);

    // Migration: Populate persistent benchmarks from history if not already present
    if (savedHistory.length > 0 && !localStorage.getItem('strive_benchmarks')) {
      const benchmarks = {};
      const EQUIVALENTS = {
        'bench_press': ['bench_press', 'pushups', 'knee_pushups', 'diamond_pushups'],
        'squat': ['squat', 'bw_squat', 'pistol_squat'],
        'deadlift': ['deadlift', 'glute_bridge', 'single_leg_glute_bridge'],
        'overhead_press': ['overhead_press', 'pike_pushups', 'pike_pushups_elevated'],
        'barbell_row': ['barbell_row', 'inverted_row', 'doorway_row']
      };

      savedHistory.forEach(session => {
        if (session.sets) {
          session.sets.forEach(set => {
            Object.entries(EQUIVALENTS).forEach(([benchId, eqList]) => {
              if (eqList.includes(set.exerciseId)) {
                // Simplified 1RM for migration
                const weight = parseFloat(set.weight || 0);
                const reps = parseInt(set.reps || 0);
                const rir = parseInt(set.rir || 0);
                const isBW = weight === 0;
                
                // Approximate BW factor for migration
                let factor = 1.0;
                if (isBW) {
                  const factors = { 'pushups': 0.65, 'knee_pushups': 0.45, 'diamond_pushups': 0.70, 'pike_pushups': 0.50, 'glute_bridge': 0.30, 'pistol_squat': 1.0, 'inverted_row': 0.50 };
                  factor = factors[set.exerciseId] || 1.0;
                }

                const userWeight = session.userWeight || parseFloat(localStorage.getItem('strive_weight') || '75');
                const effectiveWeight = isBW ? (userWeight * factor) : weight;
                const e1rm = effectiveWeight * (1 + (reps + rir) / 30);
                
                if (e1rm > (benchmarks[benchId] || 0)) benchmarks[benchId] = e1rm;
              }
            });
          });
        }
      });
      localStorage.setItem('strive_benchmarks', JSON.stringify(benchmarks));
    }
  }, []);

  const saveSession = (sets, metadata = {}) => {
    if (sets.length === 0) return;
    const currentHistory = JSON.parse(localStorage.getItem(HISTORY_KEY) || '[]');
    const userWeight = parseFloat(localStorage.getItem('strive_weight') || '0');
    const userSex = localStorage.getItem('strive_sex') || 'male';

    const newSession = {
      id: Date.now().toString(),
      name: metadata.name || 'Workout',
      timestamp: new Date().toISOString(),
      sets,
      goal: metadata.goal || 'build_muscle',
      duration: metadata.duration || 0,
      userWeight,
      userSex,
      version: '1.1'
    };

    const updatedHistory = [newSession, ...currentHistory];
    localStorage.setItem(HISTORY_KEY, JSON.stringify(updatedHistory));
    setHistory(updatedHistory);

    // Update Benchmark 1RMs for faster calibration lookup
    try {
      const benchmarks = JSON.parse(localStorage.getItem('strive_benchmarks') || '{}');
      const EQUIVALENTS = {
        'bench_press': ['bench_press', 'pushups', 'knee_pushups', 'diamond_pushups'],
        'squat': ['squat', 'bw_squat', 'pistol_squat'],
        'deadlift': ['deadlift', 'glute_bridge', 'single_leg_glute_bridge'],
        'overhead_press': ['overhead_press', 'pike_pushups', 'pike_pushups_elevated'],
        'barbell_row': ['barbell_row', 'inverted_row', 'doorway_row']
      };

      sets.forEach(set => {
        Object.entries(EQUIVALENTS).forEach(([benchId, eqList]) => {
          if (eqList.includes(set.exerciseId)) {
            const e1rm = (set.weight * (1 + (set.reps + (set.rir || 0)) / 30)) * (set.weight === 0 ? 0.65 : 1); // Simplified check for bodyweight
            // Note: better to use the imported estimate1RM but avoid circular dependencies if possible
            // For now, let's keep it simple or import it if safe.
            if (e1rm > (benchmarks[benchId] || 0)) benchmarks[benchId] = e1rm;
          }
        });
      });
      localStorage.setItem('strive_benchmarks', JSON.stringify(benchmarks));
    } catch (e) {
      console.error("Failed to update benchmarks", e);
    }
  };

  const getStreak = () => {
    if (history.length === 0) return 0;
    
    let streak = 0;
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    
    let checkDate = new Date(today);
    
    // Sort history by date descending
    const sortedHistory = [...history].sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
    
    for (let i = 0; i < sortedHistory.length; i++) {
      const workoutDate = new Date(sortedHistory[i].timestamp);
      workoutDate.setHours(0, 0, 0, 0);
      
      const diffDays = Math.floor((checkDate - workoutDate) / (1000 * 60 * 60 * 24));
      
      if (diffDays === 0) {
        streak++;
        checkDate.setDate(checkDate.getDate() - 1);
      } else if (diffDays > 1) {
        break;
      }
    }
    return streak;
  };

  const deleteSession = (id) => {
    const updatedHistory = history.filter(s => s.id !== id);
    localStorage.setItem(HISTORY_KEY, JSON.stringify(updatedHistory));
    setHistory(updatedHistory);
  };

  const updateSession = (id, updatedSession) => {
    const updatedHistory = history.map(s => s.id === id ? updatedSession : s);
    localStorage.setItem(HISTORY_KEY, JSON.stringify(updatedHistory));
    setHistory(updatedHistory);
  };

  return { history, saveSession, getStreak, deleteSession, updateSession };
};
