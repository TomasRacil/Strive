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
      if (currentExercise.forms && currentExercise.forms.length > 0) {
        setSelectedForm(currentExercise.forms[0].name || currentExercise.forms[0]);
      }
      
      // Load template OR suggest based on engine
      if (currentExercise.template) {
        const lastSet = { 
          weight: currentExercise.template.weight, 
          reps: currentExercise.template.reps, 
          rir: currentExercise.template.rir || 0 
        };
        setWeight(suggestNextWeight(lastSet, trainingGoal, userSex, userBirthDate)?.toString() || '');
        setReps(suggestNextReps(lastSet, trainingGoal, userSex, userBirthDate)?.toString() || '');
      } else if (!isBenchmarkMode) {
        let lastHistorySet = null;
        if (Array.isArray(history)) {
          for (let i = 0; i < history.length; i++) {
            const session = history[i];
            if (session.sets && Array.isArray(session.sets)) {
              // Resilient search: check both ID and Name to handle potential data mismatches
              const exerciseSets = session.sets.filter(s => 
                s.exerciseId === currentExerciseId || 
                (s.exerciseName && currentExercise && s.exerciseName === currentExercise.name)
              );
              if (exerciseSets.length > 0) {
                lastHistorySet = exerciseSets[exerciseSets.length - 1];
                break;
              }
            }
          }
        }
        
        if (lastHistorySet) {
          // Phase Shift Intelligence: 
          // If we are moving from a very low-rep set (like a Benchmark) to a higher-rep goal,
          // calculate the target based on 1RM rather than simple linear progression.
          const isLowRepSet = lastHistorySet.reps <= 3;
          const isHighRepGoal = trainingGoal === 'build_muscle' || trainingGoal === 'maintain';
          
          if (isLowRepSet && isHighRepGoal) {
            const e1RM = estimate1RM(parseFloat(lastHistorySet.weight), parseInt(lastHistorySet.reps), parseInt(lastHistorySet.rir || 0), userSex);
            const target = calculateTargetLoadFrom1RM(e1RM, trainingGoal, userSex, userBirthDate);
            
            if (target.weight > 0) {
              setWeight(target.weight.toString());
              setReps(target.reps.toString());
              return; // Exit early if we found a valid recommendation
            }
          } else {
            setWeight(suggestNextWeight(lastHistorySet, trainingGoal, userSex, userBirthDate)?.toString() || '');
            setReps(suggestNextReps(lastHistorySet, trainingGoal, userSex, userBirthDate)?.toString() || '');
            return; // Exit early
          }
        }
        
        // Final Fallback: Calibration via Benchmarks
        const calibrated = getCalibratedLoad(currentExercise, history, trainingGoal, userSex, userBirthDate);
        if (calibrated) {
          setWeight(calibrated.weight.toString());
          setReps(calibrated.reps.toString());
        } else {
          // Absolute fallback: Biometric Guess
          const userWeight = localStorage.getItem('strive_weight') || '75';
          const userHeight = localStorage.getItem('strive_height');
          const userBodyFat = localStorage.getItem('strive_body_fat');
          const startRatio = currentExercise?.startRatio || 0.4;
          const guessedWeight = calculateStartingLoad(startRatio, userWeight, userHeight, userBodyFat, userSex);
          setWeight(guessedWeight.toString());
          setReps(suggestNextReps(null, trainingGoal, userSex, userBirthDate).toString());
        }
      }
    }
  }, [currentExerciseId, currentExercise, isBenchmarkMode, trainingGoal, userSex, history]);

  const startBenchmark = () => {
    setIsBenchmarkMode(true);
    setTrainingGoal('build_strength');
    setActiveSession(true);
    
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
      // Guess based on lean body mass for a safe first-ever start
      const guessedWeight = calculateStartingLoad(firstEx.startRatio, userWeight, userHeight, userBodyFat, userSex);
      setWeight(guessedWeight.toString());
      setReps('10');
    }
    setSelectedForm('Strict');
  };

  const [notification, setNotification] = useState(null);

  const notify = (message, type = 'info') => {
    setNotification({ message, type });
    setTimeout(() => setNotification(null), 5000);
  };

  const nextBenchmarkStep = (rir, setNumber) => {
    if (rir === 0) {
      // Limit found! Move to next muscle group
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
      weight: parseFloat(weight),
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
      <div className="page-container fade-in">
        <header style={{ marginBottom: '30px' }}>
          <h1 className="premium-gradient-text" style={{ fontSize: '32px' }}>Training</h1>
          <p style={{ color: 'var(--text-secondary)' }}>Ready to push your limits?</p>
        </header>

        <div className="glass" style={{ padding: '25px', textAlign: 'center', marginBottom: '20px', border: '1px solid var(--primary-color)', background: 'linear-gradient(rgba(59, 130, 246, 0.05), transparent)' }}>
          <div style={{ marginBottom: '20px' }}>
            <h2 className="premium-gradient-text" style={{ fontSize: '20px', marginBottom: '10px' }}>Strength Test</h2>
            <p style={{ color: 'var(--text-secondary)', fontSize: '14px' }}>
              Challenge your limits. Loads evolve based on your current power level.
            </p>
          </div>
          <button className="btn-primary" onClick={startBenchmark} style={{ width: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '10px' }}>
            <Zap size={18} /> Test My Strength
          </button>
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
    );
  }

  // Phase: Selecting Exercise (Mid-workout or Start of Free session)
  if (showSelector) {
    return (
      <div className="page-container fade-in" style={{ height: 'calc(100vh - 40px)', display: 'flex', flexDirection: 'column' }}>
        <header style={{ marginBottom: '20px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div>
            <h2 className="premium-gradient-text">Choose Exercise</h2>
            <p style={{ color: 'var(--text-secondary)', fontSize: '14px' }}>What are we working on next?</p>
          </div>
          <button className="btn-secondary" style={{ padding: '10px', borderRadius: '12px' }} onClick={() => setShowAddExercise(true)}>
            <Plus size={20} />
          </button>
        </header>

        <div className="glass" style={{ display: 'flex', alignItems: 'center', padding: '0 15px', marginBottom: '20px' }}>
          <Search size={18} color="var(--text-secondary)" />
          <input 
            type="text" 
            placeholder="Search library..." 
            style={{ background: 'none', border: 'none', width: '100%', padding: '15px' }}
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
          />
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: '12px', flex: 1, overflowY: 'auto', padding: '10px' }}>
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

        <div style={{ marginTop: '20px' }}>
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

  // Phase: Active Exercise Logging
  return (
    <div className="page-container fade-in" style={{ position: 'relative' }}>
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
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
        <div>
          <span className="premium-gradient-text" style={{ fontWeight: '700', display: 'block' }}>Active Session</span>
          <span style={{ fontSize: '10px', color: 'var(--text-secondary)', textTransform: 'uppercase', letterSpacing: '1px' }}>
            Goal: {trainingGoal.replace('_', ' ')}
          </span>
        </div>
        <div style={{ display: 'flex', gap: '10px', alignItems: 'center' }}>
          {isBenchmarkMode ? (
            <div className="glass" style={{ padding: '6px 12px', fontSize: '10px', fontWeight: '800', color: 'var(--primary-color)', textTransform: 'uppercase', letterSpacing: '1px' }}>
              Test in Progress
            </div>
          ) : (
            <button className="btn-secondary" style={{ padding: '8px 12px' }} onClick={() => setShowSelector(true)}>
              <List size={16} />
            </button>
          )}
          <button className="btn-secondary" style={{ padding: '8px 16px', fontSize: '12px', color: '#ef4444' }} onClick={endTraining}>End & Save</button>
        </div>
      </div>
      
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
              {currentExercise?.type === 'bodyweight_plus_weight' || currentExercise?.type === 'bodyweight_only' 
                ? 'Added Weight (+kg)' 
                : 'Weight (kg)'}
            </label>
            <input 
              type="number" 
              placeholder="0" 
              value={weight}
              onChange={(e) => setWeight(e.target.value)}
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
                {val}
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
  );
};

export default Training;
