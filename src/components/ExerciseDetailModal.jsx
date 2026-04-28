import React, { useState } from 'react';
import { Info, Target, Move, Settings, Check } from 'lucide-react';
import ExerciseForm from './ExerciseForm';
import Modal from './Modal';

const ExerciseDetailModal = ({ exercise, onSave, onClose }) => {
  const [mode, setMode] = useState('view'); // 'view' or 'edit'
  const [selectedFormIndex, setSelectedFormIndex] = useState(0);

  if (!exercise) return null;

  const currentForm = exercise.forms?.[selectedFormIndex] || { name: 'Default', cues: [], hasVisualization: false };
  const showVisualization = currentForm.hasVisualization ?? !!currentForm.tutorialId;
  const imageSrc = currentForm.customImage || `/tutorials/${exercise.id}.png`;

  const handleSave = (updatedData) => {
    onSave(updatedData);
    setMode('view');
  };

  const headerActions = (
    <button 
      onClick={() => setMode(mode === 'view' ? 'edit' : 'view')} 
      style={{ 
        background: 'rgba(255,255,255,0.05)', 
        border: 'none', 
        color: mode === 'edit' ? 'var(--primary-color)' : 'var(--text-secondary)', 
        cursor: 'pointer',
        width: '36px',
        height: '36px',
        borderRadius: '50%',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        transition: 'all 0.2s'
      }}
      title={mode === 'view' ? 'Edit Exercise' : 'View Guide'}
    >
      {mode === 'view' ? <Settings size={18} /> : <Info size={18} />}
    </button>
  );

  return (
    <Modal 
      isOpen={!!exercise} 
      onClose={onClose}
      maxWidth={mode === 'edit' ? '600px' : '500px'}
      title={exercise.name || 'New Exercise'}
      subtitle={mode === 'view' ? 'Technical Guide' : 'Configuration'}
      headerActions={headerActions}
    >
      <div style={{ position: 'relative' }}>
        {mode === 'view' ? (
          <div className="fade-in">
            {/* Form Selector */}
            <div style={{ display: 'flex', gap: '10px', overflowX: 'auto', paddingBottom: '15px', marginBottom: '15px', borderBottom: '1px solid rgba(255,255,255,0.05)' }}>
              {exercise.forms?.map((f, idx) => (
                <button
                  key={idx}
                  onClick={() => setSelectedFormIndex(idx)}
                  className={selectedFormIndex === idx ? 'btn-primary' : 'btn-secondary'}
                  style={{ 
                    padding: '6px 14px', 
                    fontSize: '11px', 
                    whiteSpace: 'nowrap',
                    borderRadius: '20px',
                    fontWeight: '700',
                    border: selectedFormIndex === idx ? 'none' : '1px solid var(--glass-border)'
                  }}
                >
                  {f.name}
                </button>
              ))}
            </div>

            {/* Visualization */}
            {showVisualization && (
              <div className="glass" style={{ borderRadius: '15px', overflow: 'hidden', marginBottom: '25px', position: 'relative' }}>
                <img 
                  src={imageSrc} 
                  alt={`${exercise.name} tutorial`} 
                  style={{ width: '100%', display: 'block' }}
                  onError={(e) => {
                    e.target.style.display = 'none';
                    e.target.nextSibling.style.display = 'flex';
                  }}
                />
                <div style={{ 
                  display: 'none', 
                  height: '250px', 
                  alignItems: 'center', 
                  justifyContent: 'center', 
                  background: 'rgba(255,255,255,0.02)',
                  color: 'var(--text-secondary)',
                  flexDirection: 'column',
                  gap: '10px'
                }}>
                  <Move size={48} opacity={0.2} />
                  <p style={{ fontSize: '12px' }}>Technique visualization active.</p>
                </div>
              </div>
            )}

            {/* Technical Details */}
            <div style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
              <div className="glass" style={{ padding: '15px', borderRadius: '12px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '15px', color: 'var(--primary-color)' }}>
                  <Target size={16} />
                  <span style={{ fontWeight: '700', fontSize: '13px', textTransform: 'uppercase' }}>Activation Pattern</span>
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
                  {exercise.muscles?.map(m => (
                    <div key={m.name}>
                      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '12px', marginBottom: '5px' }}>
                        <span>{m.name}</span>
                        <span style={{ color: 'var(--text-secondary)', fontWeight: '700' }}>{m.engagement}%</span>
                      </div>
                      <div style={{ height: '4px', background: 'rgba(255,255,255,0.05)', borderRadius: '2px', overflow: 'hidden' }}>
                        <div style={{ 
                          height: '100%', 
                          width: `${m.engagement}%`, 
                          background: 'var(--primary-color)',
                          boxShadow: '0 0 10px var(--primary-color)'
                        }} />
                      </div>
                    </div>
                  ))}
                </div>
              </div>

              <div className="glass" style={{ padding: '15px', borderRadius: '12px' }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '12px', color: '#10b981' }}>
                  <Check size={16} />
                  <span style={{ fontWeight: '700', fontSize: '13px', textTransform: 'uppercase' }}>Technical Cues: {currentForm.name}</span>
                </div>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
                  {currentForm.cues?.length > 0 ? currentForm.cues.map((cue, idx) => (
                    <div key={idx} style={{ display: 'flex', gap: '12px', fontSize: '13px', color: 'var(--text-secondary)', lineHeight: '1.5' }}>
                      <span style={{ color: 'var(--primary-color)', fontWeight: '900' }}>•</span>
                      <span>{cue}</span>
                    </div>
                  )) : (
                    <p style={{ fontSize: '12px', color: 'var(--text-secondary)', fontStyle: 'italic' }}>
                      No technical cues defined for this variant.
                    </p>
                  )}
                </div>
              </div>
            </div>
          </div>
        ) : (
          <div className="fade-in">
            <ExerciseForm 
              initialData={exercise} 
              onSubmit={handleSave} 
            />
          </div>
        )}
      </div>
    </Modal>
  );
};

export default ExerciseDetailModal;
