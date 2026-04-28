import React from 'react';
import { Target, Dumbbell, Zap, ShieldCheck } from 'lucide-react';

const TrainingGoalModal = ({ onSelect }) => {
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
    <div className="modal-overlay">
      <div className="glass modal-content fade-in">
        <header style={{ textAlign: 'center', marginBottom: '10px' }}>
          <Target size={40} className="premium-gradient-text" style={{ marginBottom: '15px' }} />
          <h2 style={{ fontSize: '22px', fontWeight: '800' }}>Select Session Goal</h2>
          <p style={{ color: 'var(--text-secondary)', fontSize: '14px' }}>How should Strive suggest your loads today?</p>
        </header>

        <div style={{ display: 'flex', flexDirection: 'column', gap: '15px', marginTop: '10px' }}>
          {goals.map(goal => (
            <div 
              key={goal.id} 
              className="glass clickable-card" 
              style={{ 
                flexDirection: 'row', 
                justifyContent: 'flex-start', 
                gap: '20px', 
                padding: '20px',
                textAlign: 'left'
              }}
              onClick={() => onSelect(goal.id)}
            >
              <div style={{ 
                width: '50px', 
                height: '50px', 
                borderRadius: '12px', 
                background: `${goal.color}22`, 
                display: 'flex', 
                alignItems: 'center', 
                justifyContent: 'center',
                color: goal.color,
                border: `1px solid ${goal.color}44`
              }}>
                {goal.icon}
              </div>
              <div>
                <div style={{ fontWeight: '700', fontSize: '16px' }}>{goal.label}</div>
                <div style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>{goal.desc}</div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

export default TrainingGoalModal;
