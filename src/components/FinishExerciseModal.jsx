import React from 'react';
import { Save, Trash2, Star } from 'lucide-react';
import Modal from './Modal';

const FinishExerciseModal = ({ onSaveWithTemplate, onSaveOnly, onDiscard, onCancel, exerciseName, isBenchmarkMode = false }) => {
  return (
    <Modal 
      isOpen={true} 
      onClose={onCancel}
      title="Complete Exercise"
      subtitle={exerciseName}
      maxWidth="400px"
    >
      <div style={{ textAlign: 'center', marginBottom: '25px' }}>
        <p style={{ color: 'var(--text-secondary)', fontSize: '13px' }}>
          Select how you want to record your performance.
        </p>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
        {!isBenchmarkMode && (
          <button 
            className="btn-primary" 
            style={{ width: '100%', gap: '12px', padding: '15px' }} 
            onClick={onSaveWithTemplate}
          >
            <Star size={18} /> Save & Set as Template
          </button>
        )}
        
        <button 
          className="btn-secondary" 
          style={{ width: '100%', gap: '12px', padding: '15px' }} 
          onClick={onSaveOnly}
        >
          <Save size={18} /> Just Save Performance
        </button>
        
        <button 
          className="btn-secondary" 
          style={{ 
            width: '100%', 
            gap: '12px', 
            padding: '15px',
            color: '#ef4444', 
            borderColor: 'rgba(239, 68, 68, 0.2)',
            background: 'rgba(239, 68, 68, 0.05)'
          }} 
          onClick={onDiscard}
        >
          <Trash2 size={18} /> Discard These Sets
        </button>
      </div>
    </Modal>
  );
};

export default FinishExerciseModal;
