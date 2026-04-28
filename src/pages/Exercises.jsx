import React, { useState } from 'react';
import { Plus, Search, Trash2, Settings, Info } from 'lucide-react';
import { useExercises } from '../hooks/useExercises';
import ExerciseDetailModal from '../components/ExerciseDetailModal';
import { useDialog } from '../context/DialogContext';

const Exercises = () => {
  const { exercises, addExercise, deleteExercise, updateExercise } = useExercises();
  const { showConfirm } = useDialog();
  const [searchTerm, setSearchTerm] = useState('');
  const [showNewModal, setShowNewModal] = useState(false);
  const [selectedExercise, setSelectedExercise] = useState(null);

  const filteredExercises = exercises.filter(e =>
    e.name.toLowerCase().includes(searchTerm.toLowerCase())
  );

  return (
    <div className="page-container" style={{ height: '100vh', display: 'flex', flexDirection: 'column', paddingBottom: '0' }}>
      <div style={{ flex: 1, overflowY: 'auto', paddingBottom: '120px' }}>
        <div className="sticky-header" style={{ paddingBottom: '10px' }}>
          <header style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
            <div>
              <h1 className="premium-gradient-text" style={{ fontSize: '32px' }}>Library</h1>
              <p style={{ color: 'var(--text-secondary)', fontSize: '14px' }}>Customize your movements.</p>
            </div>
            <button className="btn-primary" style={{ padding: '12px' }} onClick={() => setShowNewModal(true)}>
              <Plus size={24} />
            </button>
          </header>

          <div className="glass" style={{ display: 'flex', alignItems: 'center', padding: '0 15px' }}>
            <Search size={18} color="var(--text-secondary)" />
            <input
              type="text"
              placeholder="Search exercises..."
              style={{ background: 'none', border: 'none', width: '100%', padding: '15px' }}
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
            />
          </div>
        </div>

        <div style={{ padding: '10px 10px 0 10px', display: 'flex', flexDirection: 'column', gap: '15px' }}>
          {filteredExercises.map(exercise => (
            <div
              key={exercise.id}
              className="glass"
              style={{ padding: '15px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: 'pointer' }}
              onClick={() => setSelectedExercise(exercise)}
            >
              <div style={{ flex: 1 }}>
                <h3 style={{ fontSize: '16px', fontWeight: '700' }}>{exercise.name}</h3>
                <p style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>
                  {exercise.muscles?.map(m => m.name).join(', ')}
                </p>
              </div>
              <div style={{ display: 'flex', gap: '15px', alignItems: 'center' }} onClick={e => e.stopPropagation()}>
                <button
                  onClick={() => setSelectedExercise(exercise)}
                  style={{ background: 'none', border: 'none', color: 'var(--primary-color)', cursor: 'pointer' }}
                >
                  <Info size={18} />
                </button>
                <button
                  onClick={() => {
                    showConfirm('Delete Exercise', `Are you sure you want to delete ${exercise.name}?`, () => {
                      deleteExercise(exercise.id);
                    });
                  }}
                  style={{ background: 'none', border: 'none', color: '#ef4444', cursor: 'pointer' }}
                >
                  <Trash2 size={18} />
                </button>
              </div>
            </div>
          ))}
        </div>

        {/* Unified Detail & Config Modal */}
        {selectedExercise && (
          <ExerciseDetailModal
            exercise={selectedExercise}
            onSave={(data) => {
              updateExercise(selectedExercise.id, data);
              setSelectedExercise(null);
            }}
            onClose={() => setSelectedExercise(null)}
          />
        )}

        {/* New Exercise Modal */}
        {showNewModal && (
          <ExerciseDetailModal
            exercise={{ name: '', type: 'weight_only', muscles: [{ name: '', engagement: 100 }], forms: [{ name: 'Strict', cues: [] }] }}
            onSave={(data) => {
              addExercise(data);
              setShowNewModal(false);
            }}
            onClose={() => setShowNewModal(false)}
          />
        )}
      </div>
    </div>
  );
};

export default Exercises;
