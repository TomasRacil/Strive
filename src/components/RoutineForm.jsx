import React, { useState } from 'react';
import { X, Plus, Trash2, Check, Search } from 'lucide-react';
import { useExercises } from '../hooks/useExercises';
import { useDialog } from '../context/DialogContext';

const RoutineForm = ({ onSave, onCancel, initialData }) => {
  const { exercises } = useExercises();
  const { showAlert } = useDialog();
  const [name, setName] = useState(initialData?.name || '');
  const [selectedExercises, setSelectedExercises] = useState(initialData?.exercises || []);
  const [showExercisePicker, setShowExercisePicker] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');

  const filteredExercises = exercises.filter(e => 
    e.name.toLowerCase().includes(searchTerm.toLowerCase())
  );

  const addExerciseToRoutine = (ex) => {
    setSelectedExercises([...selectedExercises, { ...ex, targetSets: 3 }]);
    setShowExercisePicker(false);
    setSearchTerm('');
  };

  const removeExerciseFromRoutine = (index) => {
    setSelectedExercises(selectedExercises.filter((_, i) => i !== index));
  };

  const updateTargetSets = (index, val) => {
    const updated = [...selectedExercises];
    updated[index].targetSets = parseInt(val) || 1;
    setSelectedExercises(updated);
  };

  const handleSave = () => {
    if (!name.trim()) {
      showAlert('Missing Information', 'Please enter a routine name.', 'warning');
      return;
    }
    if (selectedExercises.length === 0) {
      showAlert('Missing Information', 'Please add at least one exercise.', 'warning');
      return;
    }
    onSave({
      name,
      exercises: selectedExercises.map(ex => ({
        id: ex.id,
        name: ex.name,
        targetSets: ex.targetSets
      }))
    });
  };

  if (showExercisePicker) {
    return (
      <div className="modal-overlay">
        <div className="glass modal-content fade-in">
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <h3>Add Exercise</h3>
            <button className="btn-secondary" style={{ padding: '10px', borderRadius: '50%', minWidth: '40px', height: '40px' }} onClick={() => setShowExercisePicker(false)}>
              <X size={20} />
            </button>
          </div>

          <div className="glass" style={{ display: 'flex', alignItems: 'center', padding: '0 15px' }}>
            <Search size={18} color="var(--text-secondary)" />
            <input 
              type="text" 
              placeholder="Search library..." 
              style={{ background: 'none', border: 'none', width: '100%', padding: '15px' }}
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
            />
          </div>

          <div style={{ overflowY: 'auto', overflowX: 'hidden', display: 'flex', flexDirection: 'column', gap: '12px', padding: '10px' }}>
            {filteredExercises.map(ex => (
              <div 
                key={ex.id} 
                className="glass clickable-card" 
                style={{ padding: '15px', flexDirection: 'row', justifyContent: 'space-between', textAlign: 'left' }}
                onClick={() => addExerciseToRoutine(ex)}
              >
                <div>
                  <div style={{ fontWeight: '600' }}>{ex.name}</div>
                  <div style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>{ex.muscles[0]?.name}</div>
                </div>
                <Plus size={18} color="var(--primary-color)" />
              </div>
            ))}
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="modal-overlay">
      <div className="glass modal-content fade-in">
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <h2 className="premium-gradient-text">Create Routine</h2>
          <button className="btn-secondary" style={{ padding: '10px', borderRadius: '50%', minWidth: '40px', height: '40px' }} onClick={onCancel}>
            <X size={20} />
          </button>
        </div>

        <div className="input-group">
          <label>Routine Name</label>
          <input 
            type="text" 
            placeholder="e.g. Push Day A" 
            value={name}
            onChange={(e) => setName(e.target.value)}
          />
        </div>

        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '10px' }}>
          <h3 style={{ fontSize: '16px' }}>Exercises</h3>
          <button className="btn-secondary" style={{ padding: '10px', width: '40px', height: '40px', borderRadius: '12px' }} onClick={() => setShowExercisePicker(true)}>
            <Plus size={20} />
          </button>
        </div>

        <div style={{ overflowY: 'auto', overflowX: 'hidden', display: 'flex', flexDirection: 'column', gap: '15px', minHeight: '100px', padding: '10px' }}>
          {selectedExercises.length === 0 ? (
            <p style={{ textAlign: 'center', color: 'var(--text-secondary)', padding: '20px' }}>No exercises added yet.</p>
          ) : (
            selectedExercises.map((ex, i) => (
              <div key={i} className="glass" style={{ padding: '15px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <div style={{ flex: 1 }}>
                  <div style={{ fontWeight: '600', fontSize: '14px' }}>{ex.name}</div>
                  <div style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>{ex.muscles?.[0]?.name || 'Exercise'}</div>
                </div>
                <div style={{ display: 'flex', alignItems: 'center', gap: '15px' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <input 
                      type="number" 
                      style={{ width: '45px', padding: '5px', textAlign: 'center', fontSize: '12px' }} 
                      value={ex.targetSets}
                      onChange={(e) => updateTargetSets(i, e.target.value)}
                    />
                    <span style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>Sets</span>
                  </div>
                  <button style={{ background: 'none', border: 'none', color: '#ef4444', cursor: 'pointer' }} onClick={() => removeExerciseFromRoutine(i)}>
                    <Trash2 size={16} />
                  </button>
                </div>
              </div>
            ))
          )}
        </div>

        <div style={{ display: 'flex', gap: '12px', marginTop: '10px' }}>
          <button className="btn-secondary" style={{ flex: 1 }} onClick={onCancel}>Cancel</button>
          <button className="btn-primary" style={{ flex: 2 }} onClick={handleSave}>
            Save Routine <Check size={18} />
          </button>
        </div>
      </div>
    </div>
  );
};

export default RoutineForm;
