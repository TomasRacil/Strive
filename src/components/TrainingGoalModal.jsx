import React from 'react';
import { Target, Dumbbell, Zap, ShieldCheck } from 'lucide-react';
import Modal from './Modal';

const TrainingGoalModal = ({ onSelect, onCancel }) => {
  const goals = [
    { 
      id: 'build_muscle', 
      label: 'Build Muscle', 
      desc: 'Focus on volume and hypertrophy.', 
      icon: <Dumbbell size={24} />,
      color: 'var(--primary-color)'
    },
    { 
      id: 'build_strength', 
      label: 'Build Strength', 
      desc: 'Focus on heavy loads and power.', 
      icon: <Zap size={24} />,
      color: '#f59e0b'
    },
    { 
      id: 'maintain', 
      label: 'Maintenance', 
      desc: 'Focus on form and consistency.', 
      icon: <ShieldCheck size={24} />,
      color: '#10b981'
    }
  ];

  return (
    <Modal 
      isOpen={true} 
      onClose={onCancel}
      title="Session Focus"
      subtitle="Engine Calibration"
      maxWidth="450px"
    >
      <div style={{ textAlign: 'center', marginBottom: '25px' }}>
        <Target size={40} className="premium-gradient-text" style={{ marginBottom: '10px' }} />
        <p style={{ color: 'var(--text-secondary)', fontSize: '13px' }}>Choose how Strive should calculate your load suggestions today.</p>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
        {goals.map(goal => (
          <div 
            key={goal.id} 
            className="glass clickable-card" 
            style={{ 
              flexDirection: 'row', 
              justifyContent: 'flex-start', 
              gap: '15px', 
              padding: '15px',
              textAlign: 'left',
              border: '1px solid rgba(255,255,255,0.05)'
            }}
            onClick={() => onSelect(goal.id)}
          >
            <div style={{ 
              width: '44px', 
              height: '44px', 
              borderRadius: '10px', 
              background: `${goal.color}15`, 
              display: 'flex', 
              alignItems: 'center', 
              justifyContent: 'center',
              color: goal.color,
              border: `1px solid ${goal.color}33`
            }}>
              {goal.icon}
            </div>
            <div>
              <div style={{ fontWeight: '700', fontSize: '15px' }}>{goal.label}</div>
              <div style={{ fontSize: '11px', color: 'var(--text-secondary)' }}>{goal.desc}</div>
            </div>
          </div>
        ))}
      </div>
    </Modal>
  );
};

export default TrainingGoalModal;
