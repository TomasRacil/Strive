import React from 'react';
import { Save, Trash2, Star, X } from 'lucide-react';

const FinishExerciseModal = ({ onSaveWithTemplate, onSaveOnly, onDiscard, onCancel, exerciseName }) => {
  return (
    <div className="modal-overlay">
      <div className="glass modal-content fade-in" style={{ textAlign: 'center' }}>
        <div style={{ display: 'flex', justifyContent: 'flex-end', marginBottom: '10px' }}>
          <button className="btn-secondary" style={{ padding: '8px', borderRadius: '50%' }} onClick={onCancel}>
            <X size={18} />
          </button>
        </div>
        
        <div style={{ marginBottom: '25px' }}>
          <h2 className="premium-gradient-text" style={{ fontSize: '22px', marginBottom: '10px' }}>Finish {exerciseName}</h2>
          <p style={{ color: 'var(--text-secondary)', fontSize: '14px' }}>
            How would you like to record your performance?
          </p>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
          <button className="btn-primary" style={{ width: '100%', gap: '12px' }} onClick={onSaveWithTemplate}>
            <Star size={18} /> Save & Set as Template
          </button>
          
          <button className="btn-secondary" style={{ width: '100%', gap: '12px' }} onClick={onSaveOnly}>
            <Save size={18} /> Just Save Performance
          </button>
          
          <button 
            className="btn-secondary" 
            style={{ width: '100%', gap: '12px', color: '#ef4444', borderColor: 'rgba(239, 68, 68, 0.2)' }} 
            onClick={onDiscard}
          >
            <Trash2 size={18} /> Discard These Sets
          </button>
        </div>
      </div>
    </div>
  );
};

export default FinishExerciseModal;
