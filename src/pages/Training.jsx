import React, { useState, useEffect } from 'react';
import { Play, Plus, Search, ChevronRight, Check, List, Trash2, Zap, X, Info } from 'lucide-react';
import { useExercises } from '../hooks/useExercises';
import { useHistory } from '../hooks/useHistory';
import CustomSelect from '../components/CustomSelect';
import { useRoutines } from '../hooks/useRoutines';
import RoutineForm from '../components/RoutineForm';
import FinishExerciseModal from '../components/FinishExerciseModal';
import ExerciseModal from '../components/ExerciseModal';
import RestTimer from '../components/RestTimer';
import TrainingGoalModal from '../components/TrainingGoalModal';
import TutorialModal from '../components/TutorialModal';
import { suggestNextWeight, suggestNextReps, calculateStartingLoad, calculateNextBenchmarkTarget, calculateTargetLoadFrom1RM, estimate1RM, getCalibratedLoad } from '../utils/engine';
import { useDialog } from '../context/DialogContext';

const BENCHMARK_EXERCISES = [
  { id: 'squat', name: 'Squat', type: 'legs', startRatio: 0.5 },
  { id: 'bench_press', name: 'Bench Press', type: 'chest', startRatio: 0.4 },
  { id: 'deadlift', name: 'Deadlift', type: 'hips/back', startRatio: 0.6 },
  { id: 'overhead_press', name: 'Overhead Press', type: 'shoulders', startRatio: 0.3 },
  { id: 'barbell_row', name: 'Barbell Row', type: 'back', startRatio: 0.4 }
];

const HOME_BENCHMARK_CATEGORIES = [
  { 
    id: 'legs', 
    label: 'Legs', 
    options: [
      { id: 'bw_squat', name: 'Bodyweight Squat', difficulty: 'Standard', desc: 'A fundamental movement for leg power.' },
      { id: 'pistol_squat', name: 'Pistol Squat', difficulty: 'Advanced', desc: 'Single-leg strength test for high-level stability.' }
    ]
  },
  { 
    id: 'chest', 
    label: 'Chest', 
    options: [
      { id: 'knee_pushups', name: 'Knee Pushups', difficulty: 'Beginner', desc: 'A great starting point for chest strength.' },
      { id: 'pushups', name: 'Pushups', difficulty: 'Standard', desc: 'The classic upper body power test.' },
      { id: 'diamond_pushups', name: 'Diamond Pushups', difficulty: 'Advanced', desc: 'Higher tricep and chest focus.' }
    ]
  },
  { 
    id: 'shoulders', 
    label: 'Shoulders', 
    options: [
      { id: 'pike_pushups', name: 'Pike Pushups', difficulty: 'Standard', desc: 'Building vertical pressing power.' },
      { id: 'pike_pushups_elevated', name: 'Elevated Pike Pushups', difficulty: 'Advanced', desc: 'Maximum overhead challenge.' }
    ]
  },
  { 
    id: 'back', 
    label: 'Back', 
    options: [
      { id: 'doorway_row', name: 'Doorway Row', difficulty: 'Beginner', desc: 'Scalable horizontal pull for home.' },
      { id: 'inverted_row', name: 'Inverted Row', difficulty: 'Standard', desc: 'Effective test for pulling strength.' }
    ]
  },
  { 
    id: 'hips', 
    label: 'Hips & Posterior', 
    options: [
      { id: 'glute_bridge', name: 'Glute Bridge', difficulty: 'Standard', desc: 'Posterior chain stability test.' },
      { id: 'single_leg_glute_bridge', name: 'Single-Leg Glute Bridge', difficulty: 'Advanced', desc: 'Isolating glute power.' }
    ]
  }
];

const Training = ({ apiKey, activeSession, setActiveSession }) => {
  const { exercises, updateExercise, addExercise } = useExercises();
  const { history, saveSession } = useHistory();
  const { routines, addRoutine, deleteRoutine } = useRoutines();
  const { showAlert } = useDialog();

  const [currentExerciseId, setCurrentExerciseId] = useState(null);
  const [showSelector, setShowSelector] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');
  const [showRoutineForm, setShowRoutineForm] = useState(false);
  const [editingRoutine, setEditingRoutine] = useState(null);
  const [activeRoutine, setActiveRoutine] = useState(null);
  const [routineStep, setRoutineStep] = useState(0);
  const [showAddExercise, setShowAddExercise] = useState(false);
  const [showFinishModal, setShowFinishModal] = useState(false);
  const [isBenchmarkMode, setIsBenchmarkMode] = useState(false);
  const [benchmarkLocation, setBenchmarkLocation] = useState('gym'); // 'gym' or 'home'
  const [showBenchmarkSelector, setShowBenchmarkSelector] = useState(false);
  const [benchmarkCategoryIndex, setBenchmarkCategoryIndex] = useState(0);
  const [lastActionTime, setLastActionTime] = useState(null);
  const [sessionStartTime, setSessionStartTime] = useState(null);
  const userSex = localStorage.getItem('strive_sex') || 'male';
  const userBirthDate = localStorage.getItem('strive_birth_date');
  const [trainingGoal, setTrainingGoal] = useState('build_muscle');
  const [showGoalModal, setShowGoalModal] = useState(false);
  const [pendingAction, setPendingAction] = useState(null);
  const [showTutorial, setShowTutorial] = useState(false);

  const [weight, setWeight] = useState('');
  const [reps, setReps] = useState('');
  const [rir, setRir] = useState(null);
  const [selectedForm, setSelectedForm] = useState('');
  const [sets, setSets] = useState([]);
  const [plannedSets, setPlannedSets] = useState(null);

  const currentExercise = exercises.find(e => e.id === currentExerciseId);
  const currentExerciseSets = sets.filter(s => s.exerciseId === currentExerciseId);
  const currentSetNumber = currentExerciseSets.length + 1;

  useEffect(() => {
    if (currentExercise) {
      if (currentExercise.forms && currentExercise.forms.length > 0 && !selectedForm) {
        setSelectedForm(currentExercise.forms[0].name || currentExercise.forms[0]);
      }

      let lastSet = null;
      
      // 1. Check current session sets first (Dynamic Intra-session adaptation)
      if (currentExerciseSets.length > 0) {
        lastSet = currentExerciseSets[currentExerciseSets.length - 1];
      } 
      // 2. Check exercise template
      else if (currentExercise.template) {
        lastSet = {
          weight: currentExercise.template.weight,
          reps: currentExercise.template.reps,
          rir: currentExercise.template.rir || 0
        };
      } 
      // 3. Check history (Past sessions)
      else {
        if (Array.isArray(history)) {
          for (let i = 0; i < history.length; i++) {
            const session = history[i];
            if (session.sets && Array.isArray(session.sets)) {
              const exerciseSets = session.sets.filter(s =>
                s.exerciseId === currentExerciseId ||
                (s.exerciseName && currentExercise && s.exerciseName === currentExercise.name)
              );
              if (exerciseSets.length > 0) {
                // Find Best Set from this session (highest 1RM equivalent)
                // This ensures we start the next session based on peak performance, not fatigue.
                lastSet = exerciseSets.reduce((best, curr) => {
                  const weightB = parseFloat(best.weight || 0);
                  const repsB = parseInt(best.reps || 0);
                  const rirB = parseInt(best.rir || 0);
                  const e1rmB = weightB * (1 + (repsB + rirB) / 30);
                  
                  const weightC = parseFloat(curr.weight || 0);
                  const repsC = parseInt(curr.reps || 0);
                  const rirC = parseInt(curr.rir || 0);
                  const e1rmC = weightC * (1 + (repsC + rirC) / 30);
                  
                  return e1rmC > e1rmB ? curr : best;
                }, exerciseSets[0]);
                break;
              }
            }
          }
        }

        // 4. Warmup Set logic
        if (!lastSet && currentExercise.requiresWarmup && !isBenchmarkMode && currentExerciseSets.length === 0) {
          const calibrated = getCalibratedLoad(currentExercise, history, trainingGoal, userSex, userBirthDate);
          if (calibrated) {
            setWeight((Math.round((calibrated.weight * 0.6) / 2.5) * 2.5).toString());
            setReps("5");
            showAlert("Warmup Recommended", `This is a heavy compound exercise. Let's start with a warmup set at 60% load.`, "info");
            return;
          }
        }
      }

      let finalWeight = '';
      let finalReps = '';

      if (lastSet) {
        const isLowRepSet = lastSet.reps <= 3;
        const isHighRepGoal = trainingGoal === 'build_muscle' || trainingGoal === 'maintain';

        if (isLowRepSet && isHighRepGoal) {
          const e1RM = estimate1RM(parseFloat(lastSet.weight), parseInt(lastSet.reps), parseInt(lastSet.rir || 0), userSex, currentExerciseId);
          const target = calculateTargetLoadFrom1RM(e1RM, trainingGoal, userSex, userBirthDate);
          finalWeight = target.weight.toString();
          finalReps = target.reps.toString();
        } else {
          let suggestedWeight = suggestNextWeight(lastSet, trainingGoal, userSex, userBirthDate);
          let suggestedReps = suggestNextReps(lastSet, trainingGoal, userSex, userBirthDate);

          if (lastSet.rir >= 3) {
            const calibrated = getCalibratedLoad(currentExercise, history, trainingGoal, userSex, userBirthDate);
            if (calibrated && calibrated.weight > (suggestedWeight || 0)) {
              // Warmup Transition: If jumping from a warmup-level weight to a working potential,
              // be much more aggressive or jump straight to the target.
              if (currentExercise.requiresWarmup && currentExerciseSets.length === 1) {
                suggestedWeight = calibrated.weight;
                suggestedReps = calibrated.reps;
              } else {
                const diff = calibrated.weight - parseFloat(lastSet.weight);
                const jump = Math.max(5, Math.round((diff * 0.4) / 2.5) * 2.5); 
                suggestedWeight = parseFloat(lastSet.weight) + jump;
                suggestedReps = calibrated.reps;
              }
            }
          }
          finalWeight = suggestedWeight?.toString() || '';
          finalReps = suggestedReps?.toString() || '';
        }
      } else {
        const calibrated = getCalibratedLoad(currentExercise, history, trainingGoal, userSex, userBirthDate);
        if (calibrated) {
          finalWeight = calibrated.weight.toString();
          finalReps = calibrated.reps.toString();
        } else {
          const userWeight = localStorage.getItem('strive_weight') || '75';
          const userHeight = localStorage.getItem('strive_height');
          const userBodyFat = localStorage.getItem('strive_body_fat');
          const startRatio = currentExercise?.startRatio || 0.4;
          const guessedWeight = calculateStartingLoad(startRatio, userWeight, userHeight, userBodyFat, userSex);
          finalWeight = guessedWeight.toString();
          finalReps = suggestNextReps(null, trainingGoal, userSex, userBirthDate).toString();
        }
      }

      // Apply Warmup Logic: If first set of a heavy exercise, suggest 60% load
      if (currentExerciseSets.length === 0 && currentExercise.requiresWarmup && !isBenchmarkMode) {
        setWeight((Math.round((parseFloat(finalWeight) * 0.6) / 2.5) * 2.5).toString());
        setReps("5");
        showAlert("Warmup Recommended", `This is a heavy compound exercise. Let's start with a warmup set at 60% load.`, "info");
      } else {
        setWeight(finalWeight);
        setReps(finalReps);
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentExerciseId, trainingGoal, currentExerciseSets.length]);

  const startBenchmark = (location = 'gym') => {
    setIsBenchmarkMode(true);
    setBenchmarkLocation(location);
    setBenchmarkCategoryIndex(0);
    setTrainingGoal('build_strength');
    setActiveSession(true);

    if (location === 'home') {
      setShowBenchmarkSelector(true);
    } else {
      const firstEx = BENCHMARK_EXERCISES[0];
      const exercise = exercises.find(e => e.id === firstEx.id);

      setCurrentExerciseId(firstEx.id);
      const userWeight = localStorage.getItem('strive_weight') || '75';
      const userHeight = localStorage.getItem('strive_height');
      const userBodyFat = localStorage.getItem('strive_body_fat');

      if (exercise?.template) {
        setWeight((Math.floor(exercise.template.weight * 0.5 / 2.5) * 2.5).toString());
        setReps('10');
      } else {
        const guessedWeight = calculateStartingLoad(firstEx.startRatio, userWeight, userHeight, userBodyFat, userSex);
        setWeight(guessedWeight.toString());
        setReps('10');
      }
      setSelectedForm('Strict');
    }
  };

  const selectHomeExercise = (exerciseId) => {
    setCurrentExerciseId(exerciseId);
    setWeight('0');
    setReps('10');
    setSelectedForm('Strict');
    setShowBenchmarkSelector(false);
    notify(`AMRAP: Do as many reps as possible until failure.`, 'info');
  };

  const [notification, setNotification] = useState(null);

  const notify = (message, type = 'info') => {
    setNotification({ message, type });
    setTimeout(() => setNotification(null), 5000);
  };

  const nextBenchmarkStep = (rir, setNumber) => {
    const isHomeDone = benchmarkLocation === 'home';
    
    if (rir === 0 || isHomeDone) {
      if (benchmarkLocation === 'home') {
        if (benchmarkCategoryIndex < HOME_BENCHMARK_CATEGORIES.length - 1) {
          const nextIdx = benchmarkCategoryIndex + 1;
          setBenchmarkCategoryIndex(nextIdx);
          setShowBenchmarkSelector(true);
          notify(`Power limit reached! Calibrating ${HOME_BENCHMARK_CATEGORIES[nextIdx].label}...`, 'success');
        } else {
          notify("Strength Test complete! Your profile is now fully calibrated.", 'success');
          setTimeout(() => endTraining(), 2000);
        }
      } else {
        const currentIndex = BENCHMARK_EXERCISES.findIndex(ex => ex.id === currentExerciseId);
        if (currentIndex < BENCHMARK_EXERCISES.length - 1) {
          const nextExData = BENCHMARK_EXERCISES[currentIndex + 1];
          const nextEx = exercises.find(e => e.id === nextExData.id);

          setCurrentExerciseId(nextExData.id);

          if (nextEx?.template) {
            setWeight((Math.floor(nextEx.template.weight * 0.5 / 2.5) * 2.5).toString());
            setReps('10');
          } else {
            const userWeight = localStorage.getItem('strive_weight') || '75';
            const userHeight = localStorage.getItem('strive_height');
            const userBodyFat = localStorage.getItem('strive_body_fat');
            const guessedWeight = calculateStartingLoad(nextExData.startRatio, userWeight, userHeight, userBodyFat, userSex);
            setWeight(guessedWeight.toString());
            setReps('10');
          }

          setSelectedForm('Strict');
          notify(`Power limit reached! Calibrating ${nextExData.type}...`, 'success');
        } else {
          notify("Strength Test complete! Your profile is now fully calibrated.", 'success');
          setTimeout(() => endTraining(), 2000);
        }
      }
    } else {
      // Keep pushing - Dynamic 1RM Protocol
      const target = calculateNextBenchmarkTarget(setNumber, parseFloat(weight), parseInt(reps), rir, userSex, userBirthDate);

      setWeight(target.weight.toString());
      setReps(target.reps.toString());
      notify(target.message, target.type);
    }
  };

  const filteredExercises = exercises.filter(e =>
    e.name.toLowerCase().includes(searchTerm.toLowerCase())
  );

  const startFreeSession = () => {
    setPendingAction({ type: 'free' });
    setShowGoalModal(true);
  };

  const confirmStart = (goal) => {
    setTrainingGoal(goal);
    setShowGoalModal(false);

    if (pendingAction.type === 'free') {
      setShowSelector(true);
      setActiveSession(true);
    } else if (pendingAction.type === 'routine') {
      const { routine } = pendingAction;
      setActiveRoutine(routine);
      setRoutineStep(0);
      const firstEx = routine.exercises[0];
      setCurrentExerciseId(firstEx.id);
      setPlannedSets(firstEx.targetSets);
      setActiveSession(true);
      const now = new Date().toISOString();
      setSessionStartTime(now);
      setLastActionTime(now);
    }
    setPendingAction(null);
  };

  const startSession = (exerciseId) => {
    setCurrentExerciseId(exerciseId);
    setActiveSession(true);
    setShowSelector(false);
    setIsBenchmarkMode(false);
    setBenchmarkLocation('gym');
  };

  const startRoutine = (routine) => {
    setPendingAction({ type: 'routine', routine });
    setShowGoalModal(true);
  };

  const finishExercise = () => {
    if (activeRoutine) {
      const nextStep = routineStep + 1;
      if (nextStep < activeRoutine.exercises.length) {
        setRoutineStep(nextStep);
        const nextEx = activeRoutine.exercises[nextStep];
        setCurrentExerciseId(nextEx.id);
        setPlannedSets(nextEx.targetSets);
        return;
      } else {
        // Routine complete!
        setShowFinishModal(true);
        return;
      }
    }
    setShowSelector(true);
  };

  const handleFinishExercise = (action) => {
    let sessionName = 'Free Training';
    if (isBenchmarkMode) {
      sessionName = 'Benchmark Test';
    } else if (activeRoutine) {
      sessionName = activeRoutine.name;
    }

    if (action === 'template' || action === 'save') {
      const exerciseSets = sets.filter(s => s.exerciseId === currentExerciseId);
      if (action === 'template' && exerciseSets.length > 0) {
        const lastSet = exerciseSets[exerciseSets.length - 1];
        updateExercise(currentExerciseId, {
          template: {
            weight: lastSet.weight,
            reps: lastSet.reps,
            sets: exerciseSets.length
          }
        });
      }
      saveSession(sets, {
        name: sessionName,
        goal: trainingGoal,
        duration: sessionStartTime ? Math.floor((new Date() - new Date(sessionStartTime)) / 1000) : 0
      });
    } else if (action === 'discard') {
      const filteredSets = sets.filter(s => s.exerciseId !== currentExerciseId);
      saveSession(filteredSets, {
        name: sessionName,
        goal: trainingGoal,
        duration: sessionStartTime ? Math.floor((new Date() - new Date(sessionStartTime)) / 1000) : 0
      });
    } else {
      // Basic save
      saveSession(sets, {
        name: sessionName,
        goal: trainingGoal,
        duration: sessionStartTime ? Math.floor((new Date() - new Date(sessionStartTime)) / 1000) : 0
      });
    }

    resetTrainingState();
  };

  const resetTrainingState = () => {
    setShowFinishModal(false);
    setActiveSession(false);
    setSets([]);
    setPlannedSets(null);
    setShowSelector(false);
    setCurrentExerciseId(null);
    setActiveRoutine(null);
    setRoutineStep(0);
    setIsBenchmarkMode(false);
    setBenchmarkLocation('gym');
  };

  const endTraining = () => {
    if (sets.length === 0) {
      resetTrainingState();
      return;
    }
    setShowFinishModal(true);
  };

  const logSet = (goToNextExercise = false) => {
    if (!weight || !reps || rir === null) {
      showAlert('Missing Data', 'Please enter weight, reps and select RIR.', 'warning');
      return;
    }

    const newSet = {
      exerciseId: currentExerciseId,
      exerciseName: currentExercise?.name,
      weight: weight === 'BW' ? 0 : parseFloat(weight),
      reps: parseInt(reps),
      rir,
      form: selectedForm,
      timestamp: new Date().toISOString()
    };

    // Start session timer only after first set
    if (sets.length === 0 && !sessionStartTime) {
      setSessionStartTime(new Date().toISOString());
    }

    setSets([...sets, newSet]);
    setLastActionTime(new Date().toISOString());
    const currentExerciseSets = sets.filter(s => s.exerciseId === currentExerciseId);
    const updatedSetNumber = currentExerciseSets.length + 1;

    if (isBenchmarkMode) {
      nextBenchmarkStep(rir, updatedSetNumber);
    } else {
      setReps('');
      setRir(null);

      if (goToNextExercise) {
        finishExercise();
      }
    }
  };

  // Phase: Main Training Dashboard (Not in active session/selector)
  if (!activeSession && !showSelector) {
    return (
      <div className="page-container" style={{ height: '100vh', display: 'flex', flexDirection: 'column', paddingBottom: '0' }}>
        <div style={{ flex: 1, overflowY: 'auto', paddingBottom: '120px' }}>
          <header className="sticky-header">
            <h1 className="premium-gradient-text" style={{ fontSize: '32px' }}>Training</h1>
            <p style={{ color: 'var(--text-secondary)' }}>Ready to push your limits?</p>
          </header>

          <div className="glass" style={{ padding: '25px', textAlign: 'center', marginBottom: '20px', border: '1px solid var(--primary-color)', background: 'linear-gradient(rgba(59, 130, 246, 0.05), transparent)' }}>
            <div style={{ marginBottom: '20px' }}>
              <h2 className="premium-gradient-text" style={{ fontSize: '20px', marginBottom: '10px' }}>Strength Test</h2>
              <p style={{ color: 'var(--text-secondary)', fontSize: '14px' }}>
                Challenge your limits. Choose your environment.
              </p>
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
              <button className="btn-primary" onClick={() => startBenchmark('gym')} style={{ width: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '10px' }}>
                <Zap size={18} /> Gym Strength Test
              </button>
              <button className="btn-secondary" onClick={() => startBenchmark('home')} style={{ width: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '10px' }}>
                <Play size={18} /> Home Strength Test
              </button>
            </div>
          </div>

          <div className="glass" style={{ padding: '25px', textAlign: 'center' }}>
            <div style={{ marginBottom: '20px' }}>
              <h3 style={{ marginBottom: '10px' }}>Free Training</h3>
              <p style={{ color: 'var(--text-secondary)', fontSize: '14px' }}>
                Select any exercise from your library and start training.
              </p>
            </div>
            <button className="btn-primary" onClick={startFreeSession} style={{ width: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '10px' }}>
              <Play size={18} /> Start Free Session
            </button>
          </div>

          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '30px', marginBottom: '15px' }}>
            <h2 style={{ fontSize: '20px' }}>My Routines</h2>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
            {routines.map(routine => (
              <div key={routine.id} className="glass" style={{ padding: '20px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <div style={{ cursor: 'pointer', flex: 1 }} onClick={() => startRoutine(routine)}>
                  <div style={{ fontWeight: '700', marginBottom: '4px' }}>{routine.name}</div>
                  <div style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>
                    {routine.exercises.length} Exercises • {routine.exercises.map(e => e.name).slice(0, 2).join(', ')}{routine.exercises.length > 2 ? '...' : ''}
                  </div>
                </div>
                <div style={{ display: 'flex', gap: '8px' }}>
                  <button
                    className="btn-secondary"
                    style={{ padding: '8px', minWidth: '36px', height: '36px' }}
                    onClick={() => {
                      setEditingRoutine(routine);
                      setShowRoutineForm(true);
                    }}
                  >
                    <List size={16} />
                  </button>
                  <button
                    style={{ background: 'none', border: 'none', color: '#ef4444', padding: '10px', cursor: 'pointer' }}
                    onClick={() => deleteRoutine(routine.id)}
                  >
                    <Trash2 size={18} />
                  </button>
                </div>
              </div>
            ))}

            <div className="glass clickable-card" style={{ padding: '30px', borderStyle: 'dashed' }} onClick={() => {
              setEditingRoutine(null);
              setShowRoutineForm(true);
            }}>
              <Plus size={32} style={{ marginBottom: '10px', color: 'var(--text-secondary)' }} />
              <span style={{ color: 'var(--text-secondary)' }}>Create New Routine</span>
            </div>
          </div>

          {showRoutineForm && (
            <RoutineForm
              initialData={editingRoutine}
              onSave={(r) => {
                if (editingRoutine) {
                  deleteRoutine(editingRoutine.id);
                }
                addRoutine(r);
                setShowRoutineForm(false);
                setEditingRoutine(null);
              }}
              onCancel={() => {
                setShowRoutineForm(false);
                setEditingRoutine(null);
              }}
            />
          )}

          {showGoalModal && (
            <TrainingGoalModal
              onSelect={confirmStart}
              onCancel={() => {
                setShowGoalModal(false);
                setPendingAction(null);
              }}
            />
          )}

          {showTutorial && (
            <TutorialModal
              exercise={currentExercise}
              onClose={() => setShowTutorial(false)}
            />
          )}
        </div>
      </div>
    );
  }

  // Phase: Selecting Exercise (Mid-workout or Start of Free session)
  if (showSelector) {
    return (
      <div className="page-container" style={{ height: '100vh', display: 'flex', flexDirection: 'column', paddingBottom: '0' }}>
        <div style={{ flex: 1, overflowY: 'auto', paddingBottom: '120px' }}>
          <header className="sticky-header" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div>
              <h1 className="premium-gradient-text" style={{ fontSize: '32px' }}>Add Exercise</h1>
              <p style={{ color: 'var(--text-secondary)', fontSize: '14px' }}>Choose what is next.</p>
            </div>
            <div style={{ display: 'flex', gap: '10px' }}>
              <button className="btn-secondary" style={{ padding: '8px' }} onClick={() => setShowAddExercise(true)}>
                <Plus size={20} />
              </button>
              <button className="btn-secondary" style={{ padding: '8px' }} onClick={() => setShowSelector(false)}>
                <X size={20} />
              </button>
            </div>
          </header>

          <div className="glass" style={{ display: 'flex', alignItems: 'center', padding: '0 15px', marginBottom: '20px' }}>
            <Search size={18} color="var(--text-secondary)" />
            <input
              type="text"
              placeholder="Filter exercises..."
              style={{ background: 'none', border: 'none', width: '100%', padding: '15px' }}
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
            />
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '12px', padding: '10px' }}>
            {filteredExercises.map(ex => (
              <div
                key={ex.id}
                className="glass"
                style={{ padding: '15px 20px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: 'pointer' }}
                onClick={() => startSession(ex.id)}
              >
                <div>
                  <div style={{ fontWeight: '600' }}>{ex.name}</div>
                  <div style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>{ex.muscles[0]?.name}</div>
                </div>
                <ChevronRight size={18} color="var(--text-secondary)" />
              </div>
            ))}
          </div>
        </div>

        <div style={{ marginTop: '20px', flexShrink: 0, paddingBottom: '20px' }}>
          {sets.length === 0 ? (
            <button className="btn-secondary" style={{ width: '100%' }} onClick={() => { setShowSelector(false); setActiveSession(false); }}>
              Cancel Training
            </button>
          ) : (
            <button className="btn-primary" style={{ width: '100%', background: 'linear-gradient(135deg, #ef4444, #b91c1c)', boxShadow: '0 4px 15px rgba(239, 68, 68, 0.3)' }} onClick={endTraining}>
              Finish & Save Session <Check size={18} />
            </button>
          )}
        </div>

        {showAddExercise && (
          <ExerciseModal
            onSave={(data) => {
              addExercise(data);
              setShowAddExercise(false);
            }}
            onClose={() => setShowAddExercise(false)}
          />
        )}

        {showFinishModal && (
          <FinishExerciseModal
            exerciseName={currentExercise?.name}
            onSaveWithTemplate={() => handleFinishExercise('template')}
            onSaveOnly={() => handleFinishExercise('save')}
            onDiscard={() => handleFinishExercise('discard')}
            onCancel={() => setShowFinishModal(false)}
          />
        )}
      </div>
    );
  }

  // Phase: Benchmark Exercise Selector (Home Mode)
  if (showBenchmarkSelector) {
    const currentCategory = HOME_BENCHMARK_CATEGORIES[benchmarkCategoryIndex];
    return (
      <div className="page-container" style={{ height: '100vh', display: 'flex', flexDirection: 'column', paddingBottom: '0' }}>
        <div style={{ flex: 1, overflowY: 'auto', paddingBottom: '40px' }}>
          <header className="sticky-header">
            <h1 className="premium-gradient-text" style={{ fontSize: '32px' }}>{currentCategory.label} Test</h1>
            <p style={{ color: 'var(--text-secondary)' }}>Select your challenge level.</p>
          </header>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '15px', padding: '10px' }}>
            {currentCategory.options.map(option => (
              <div 
                key={option.id}
                className="glass clickable-card"
                style={{ padding: '25px', textAlign: 'left', border: '1px solid rgba(255,255,255,0.1)' }}
                onClick={() => selectHomeExercise(option.id)}
              >
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '10px' }}>
                  <h3 style={{ fontSize: '20px' }}>{option.name}</h3>
                  <span style={{ 
                    fontSize: '12px', 
                    padding: '4px 10px', 
                    borderRadius: '20px', 
                    background: option.difficulty === 'Advanced' ? 'rgba(239, 68, 68, 0.2)' : 
                               option.difficulty === 'Standard' ? 'rgba(59, 130, 246, 0.2)' : 
                               'rgba(16, 185, 129, 0.2)',
                    color: option.difficulty === 'Advanced' ? '#ef4444' : 
                           option.difficulty === 'Standard' ? '#3b82f6' : 
                           '#10b981',
                    fontWeight: '700'
                  }}>
                    {option.difficulty}
                  </span>
                </div>
                <p style={{ color: 'var(--text-secondary)', fontSize: '14px', lineHeight: '1.5' }}>
                  {option.desc}
                </p>
              </div>
            ))}
          </div>
        </div>
        <div style={{ padding: '20px' }}>
           <button className="btn-secondary" style={{ width: '100%' }} onClick={() => { setShowBenchmarkSelector(false); setActiveSession(false); }}>
              Abort Test
            </button>
        </div>
      </div>
    );
  }

  // Phase: Active Exercise Logging
  return (
    <div className="page-container" style={{ height: '100vh', display: 'flex', flexDirection: 'column', paddingBottom: '0' }}>
      <div style={{ flex: 1, overflowY: 'auto', paddingBottom: '120px' }}>
        <header className="sticky-header">
          {notification && (
            <div
              className="glass fade-in"
              style={{
                position: 'fixed',
                top: '20px',
                left: '50%',
                transform: 'translateX(-50%)',
                zIndex: 15000,
                padding: '12px 25px',
                background: notification.type === 'success' ? 'rgba(16, 185, 129, 0.2)' :
                  notification.type === 'warning' ? 'rgba(245, 158, 11, 0.2)' :
                    'rgba(59, 130, 246, 0.2)',
                border: `1px solid ${notification.type === 'success' ? '#10b981' :
                  notification.type === 'warning' ? '#f59e0b' :
                    '#3b82f6'}`,
                color: 'white',
                borderRadius: '12px',
                fontSize: '13px',
                fontWeight: '600',
                boxShadow: '0 10px 30px rgba(0,0,0,0.5)',
                display: 'flex',
                alignItems: 'center',
                gap: '10px',
                backdropFilter: 'blur(12px)',
                width: 'calc(100% - 40px)',
                maxWidth: '400px'
              }}
            >
              <Zap size={16} color={notification.type === 'success' ? '#10b981' :
                notification.type === 'warning' ? '#f59e0b' :
                  '#3b82f6'} />
              {notification.message}
            </div>
          )}
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div>
              <span className="premium-gradient-text" style={{ fontWeight: '700', display: 'block' }}>Active Session</span>
              <span style={{ fontSize: '10px', color: 'var(--text-secondary)', textTransform: 'uppercase', letterSpacing: '1px' }}>
                Goal: {trainingGoal.replace('_', ' ')}
              </span>
            </div>
            <div style={{ display: 'flex', gap: '8px' }}>
              {!isBenchmarkMode && (
                <button
                  className="btn-secondary"
                  style={{ padding: '8px', minWidth: '36px', height: '36px' }}
                  onClick={() => setShowSelector(true)}
                >
                  <List size={16} />
                </button>
              )}
              <button className="btn-secondary" style={{ padding: '8px 16px', fontSize: '12px', color: '#ef4444' }} onClick={endTraining}>End & Save</button>
            </div>
          </div>
        </header>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '10px', marginBottom: '15px' }}>
          <RestTimer startTime={lastActionTime} label="Resting" />
          <RestTimer startTime={sessionStartTime} label="Session" />
        </div>

        <div className="glass" style={{ padding: '25px', marginBottom: '20px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '20px', flexWrap: 'wrap', gap: '10px' }}>
            <div style={{ flex: '1 1 200px' }}>
              <h2 style={{ fontSize: '24px', marginBottom: '4px' }}>{currentExercise?.name}</h2>
              <p style={{ color: 'var(--text-secondary)', fontSize: '14px', marginBottom: '12px' }}>
                {currentExercise?.muscles.map(m => m.name).join(', ')}
              </p>
              <button
                onClick={() => setShowTutorial(true)}
                style={{ background: 'rgba(59, 130, 246, 0.1)', border: '1px solid rgba(59, 130, 246, 0.3)', color: 'var(--primary-color)', display: 'inline-flex', alignItems: 'center', gap: '6px', cursor: 'pointer', fontSize: '12px', fontWeight: '600', padding: '6px 12px', borderRadius: '8px' }}
              >
                <Info size={14} /> View Technical Guide
              </button>
            </div>
            <div className="glass" style={{ padding: '8px 12px', fontSize: '12px', fontWeight: '700', color: 'var(--primary-color)', borderRadius: '12px' }}>
              Set {currentSetNumber}{plannedSets ? ` / ${plannedSets}` : ''}
            </div>
          </div>

          <div style={{ marginBottom: '20px' }}>
            <CustomSelect
              label={isBenchmarkMode ? "Execution Form (Locked for Test)" : "Execution Form"}
              value={selectedForm}
              onChange={setSelectedForm}
              options={currentExercise?.forms.map(f => ({ value: f.name, label: f.name })) || []}
              disabled={isBenchmarkMode}
            />
          </div>

          <div className="responsive-grid" style={{ marginBottom: '20px' }}>
            <div className="input-group">
              <label style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>
                {(isBenchmarkMode && benchmarkLocation === 'home')
                  ? 'Weight' 
                  : (currentExercise?.type === 'bodyweight_plus_weight' || currentExercise?.type === 'bodyweight_only'
                    ? 'Added Weight (+kg)'
                    : 'Weight (kg)')}
              </label>
              <input
                type={(isBenchmarkMode && benchmarkLocation === 'home') ? "text" : "number"}
                placeholder="0"
                value={(isBenchmarkMode && benchmarkLocation === 'home') ? "Bodyweight" : weight}
                onChange={(e) => !(isBenchmarkMode && benchmarkLocation === 'home') && setWeight(e.target.value)}
                disabled={isBenchmarkMode && benchmarkLocation === 'home'}
                style={{ opacity: (isBenchmarkMode && benchmarkLocation === 'home') ? 0.6 : 1 }}
              />
            </div>
            <div className="input-group">
              <label style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>Reps</label>
              <input
                type="number"
                placeholder="0"
                value={reps}
                onChange={(e) => setReps(e.target.value)}
              />
            </div>
          </div>

          <div className="input-group" style={{ marginBottom: '25px' }}>
            <label style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>Reps in Reserve (RIR)</label>
            <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap' }}>
              {[0, 1, 2, 3].map(val => (
                <button
                  key={val}
                  className="glass"
                  onClick={() => setRir(val)}
                  style={{
                    flex: '1 1 60px',
                    padding: '12px',
                    fontSize: '14px',
                    borderRadius: '12px',
                    background: rir === val ? 'var(--primary-color)' : 'var(--glass-bg)',
                    borderColor: rir === val ? 'var(--primary-color)' : 'var(--glass-border)',
                    color: rir === val ? 'white' : 'var(--text-primary)',
                    transition: 'all 0.2s ease'
                  }}
                >
                  {val === 3 ? '3+' : val}
                </button>
              ))}
            </div>
          </div>

          <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
            <button
              className="btn-primary"
              onClick={() => logSet(false)}
              style={{ width: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '10px' }}
            >
              {isBenchmarkMode ? 'Record Progress' : 'Log & Next Set'} <ChevronRight size={18} />
            </button>
            {!isBenchmarkMode && (
              <button
                className="btn-secondary"
                onClick={() => logSet(true)}
                style={{ width: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '10px' }}
              >
                Log & Finish Exercise <Check size={18} />
              </button>
            )}
          </div>
        </div>

        {sets.length > 0 && (
          <div className="fade-in" style={{ marginTop: '10px' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '15px' }}>
              <h3 style={{ fontSize: '18px' }}>Session Log</h3>
              <span style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>{sets.length} Sets Total</span>
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
              {(() => {
                // Group sets by exerciseId
                const groups = sets.reduce((acc, set) => {
                  if (!acc[set.exerciseId]) acc[set.exerciseId] = [];
                  acc[set.exerciseId].push(set);
                  return acc;
                }, {});

                // Sort groups by the timestamp of their latest set (newest first)
                const sortedGroups = Object.entries(groups).sort((a, b) => {
                  const latestA = Math.max(...a[1].map(s => new Date(s.timestamp).getTime()));
                  const latestB = Math.max(...b[1].map(s => new Date(s.timestamp).getTime()));
                  return latestB - latestA;
                });

                return sortedGroups.map(([exId, exSets]) => {
                  const ex = exercises.find(e => e.id === exId);
                  return (
                    <div key={exId} className="glass" style={{ padding: '20px', borderRadius: '20px' }}>
                      <div style={{ fontWeight: '700', fontSize: '16px', marginBottom: '12px', color: 'var(--primary-color)' }}>
                        {ex?.name}
                      </div>
                      <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
                        {[...exSets].reverse().map((set, i) => (
                          <div key={i} style={{
                            display: 'flex',
                            justifyContent: 'space-between',
                            alignItems: 'center',
                            padding: '10px',
                            background: 'rgba(255,255,255,0.03)',
                            borderRadius: '10px'
                          }}>
                            <div style={{ fontSize: '14px' }}>
                              <span style={{ color: 'var(--text-secondary)', marginRight: '10px' }}>Set {exSets.length - i}</span>
                              <strong>{set.weight}kg</strong> × {set.reps} • <span style={{ fontSize: '12px' }}>{set.rir} RIR</span>
                            </div>
                            <div style={{ fontSize: '11px', color: 'var(--text-secondary)' }}>
                              {set.form}
                            </div>
                          </div>
                        ))}
                      </div>
                    </div>
                  );
                });
              })()}
            </div>
          </div>
        )}

        {showFinishModal && (
          <FinishExerciseModal
            exerciseName={currentExercise?.name}
            isBenchmarkMode={isBenchmarkMode}
            onSaveWithTemplate={() => handleFinishExercise('template')}
            onSaveOnly={() => handleFinishExercise('save')}
            onDiscard={() => handleFinishExercise('discard')}
            onCancel={() => setShowFinishModal(false)}
          />
        )}

        {showTutorial && currentExercise && (
          <TutorialModal
            exercise={currentExercise}
            onClose={() => setShowTutorial(false)}
          />
        )}
      </div>
    </div>
  );
};

export default Training;
