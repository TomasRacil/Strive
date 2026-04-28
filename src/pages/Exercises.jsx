import React, { useState } from 'react';
import { Plus, Search, Trash2, List } from 'lucide-react';
import { useExercises } from '../hooks/useExercises';
import ExerciseModal from '../components/ExerciseModal';

const Exercises = () => {
  const { exercises, addExercise, deleteExercise, updateExercise } = useExercises();
  const [searchTerm, setSearchTerm] = useState('');
  const [showModal, setShowModal] = useState(false);
  const [editingExercise, setEditingExercise] = useState(null);

  const filteredExercises = exercises.filter(e => 
    e.name.toLowerCase().includes(searchTerm.toLowerCase())
  );

  return (
    <div className="page-container fade-in">
      <header style={{ marginBottom: '30px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div>
          <h1 className="premium-gradient-text" style={{ fontSize: '32px' }}>Library</h1>
          <p style={{ color: 'var(--text-secondary)' }}>Customize your movements.</p>
        </div>
        <button className="btn-primary" style={{ padding: '12px' }} onClick={() => setShowModal(true)}>
          <Plus size={24} />
        </button>
      </header>

      {/* ... search and list ... */}

      <div className="glass" style={{ display: 'flex', alignItems: 'center', padding: '0 15px', marginBottom: '20px' }}>
        <Search size={18} color="var(--text-secondary)" />
        <input 
          type="text" 
          placeholder="Search exercises..." 
          style={{ background: 'none', border: 'none', width: '100%', padding: '15px' }}
          value={searchTerm}
          onChange={(e) => setSearchTerm(e.target.value)}
        />
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: '15px', padding: '10px', overflowX: 'hidden' }}>
        {filteredExercises.map(exercise => (
          <div key={exercise.id} className="glass" style={{ padding: '15px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div style={{ flex: 1, cursor: 'pointer' }} onClick={() => setEditingExercise(exercise)}>
              <h3 style={{ fontSize: '16px' }}>{exercise.name}</h3>
              <p style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>
                {exercise.muscles.map(m => m.name).join(', ')}
              </p>
            </div>
            <div style={{ display: 'flex', gap: '12px', alignItems: 'center' }}>
              <span style={{ fontSize: '10px', background: 'rgba(255,255,255,0.05)', padding: '4px 8px', borderRadius: '4px' }}>
                {exercise.type.replace(/_/g, ' ')}
              </span>
              <button 
                onClick={() => setEditingExercise(exercise)}
                style={{ background: 'none', border: 'none', color: 'var(--text-secondary)', cursor: 'pointer' }}
              >
                <List size={18} />
              </button>
              <button 
                onClick={() => {
                  if (window.confirm(`Delete ${exercise.name}?`)) {
                    deleteExercise(exercise.id);
                  }
                }}
                style={{ background: 'none', border: 'none', color: '#ef4444', cursor: 'pointer' }}
              >
                <Trash2 size={18} />
              </button>
            </div>
          </div>
        ))}
      </div>

      {(showModal || editingExercise) && (
        <ExerciseModal 
          initialData={editingExercise}
          onSave={(data) => {
            if (editingExercise) {
              updateExercise(editingExercise.id, data);
            } else {
              addExercise(data);
            }
            setShowModal(false);
            setEditingExercise(null);
          }}
          onClose={() => {
            setShowModal(false);
            setEditingExercise(null);
          }}
        />
      )}
    </div>
  );
};

export default Exercises;
