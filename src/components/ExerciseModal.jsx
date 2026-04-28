import React from 'react';
import { X } from 'lucide-react';
import ExerciseForm from './ExerciseForm';

const ExerciseModal = ({ initialData, onSave, onClose, title }) => {
  return (
    <div className="modal-overlay">
      <div className="glass modal-content fade-in">
        <header style={{ 
          display: 'flex', 
          justifyContent: 'space-between', 
          alignItems: 'center', 
          marginBottom: '5px',
          borderBottom: '1px solid rgba(255,255,255,0.1)',
          paddingBottom: '15px'
        }}>
          <h2 className="premium-gradient-text" style={{ fontSize: '24px' }}>
            {title || (initialData ? 'Edit Exercise' : 'New Exercise')}
          </h2>
          <button 
            className="btn-secondary" 
            style={{ padding: '8px', borderRadius: '50%', minWidth: '36px', height: '36px' }} 
            onClick={onClose}
          >
            <X size={18} />
          </button>
        </header>

        <ExerciseForm 
          initialData={initialData} 
          onSubmit={onSave} 
        />
      </div>
    </div>
  );
};

export default ExerciseModal;
