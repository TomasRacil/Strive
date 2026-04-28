import React from 'react';
import { X } from 'lucide-react';
import ExerciseForm from './ExerciseForm';

const NewExerciseModal = ({ onSave, onClose }) => {
  return (
    <div className="modal-overlay">
      <div className="glass modal-content fade-in" style={{ maxHeight: '90vh', overflowY: 'auto' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
          <h2 className="premium-gradient-text">New Exercise</h2>
          <button className="btn-secondary" style={{ padding: '10px', borderRadius: '50%', minWidth: '40px', height: '40px' }} onClick={onClose}>
            <X size={20} />
          </button>
        </div>
        <ExerciseForm onSubmit={onSave} />
      </div>
    </div>
  );
};

export default NewExerciseModal;
