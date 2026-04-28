import React from 'react';
import { Target, Move } from 'lucide-react';
import Modal from './Modal';

const TutorialModal = ({ exercise, onClose }) => {
  if (!exercise) return null;

  const tutorialImage = `/tutorials/${exercise.id}.png`;

  return (
    <Modal
      isOpen={true}
      onClose={onClose}
      title={exercise.name}
      subtitle="Technical Guide"
      maxWidth="600px"
    >
      <div className="glass" style={{ borderRadius: '15px', overflow: 'hidden', marginBottom: '25px', position: 'relative' }}>
         <img 
           src={tutorialImage} 
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
           <p>Tutorial visualization coming soon for this exercise.</p>
         </div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '15px', marginBottom: '20px' }}>
        <div className="glass" style={{ padding: '15px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '10px', color: 'var(--primary-color)' }}>
            <Target size={16} />
            <span style={{ fontWeight: '700', fontSize: '14px' }}>Target Muscles</span>
          </div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px' }}>
            {exercise.muscles?.map(m => (
              <span key={m.name} style={{ fontSize: '11px', padding: '4px 8px', borderRadius: '6px', background: 'rgba(255,255,255,0.05)' }}>
                {m.name}
              </span>
            ))}
          </div>
        </div>
        <div className="glass" style={{ padding: '15px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '10px', color: '#10b981' }}>
            <Move size={16} />
            <span style={{ fontWeight: '700', fontSize: '14px' }}>Key Form Cues</span>
          </div>
          <ul style={{ fontSize: '12px', color: 'var(--text-secondary)', paddingLeft: '15px', margin: '0' }}>
            <li>Keep core tight</li>
            <li>Controlled tempo</li>
            <li>Full ROM</li>
          </ul>
        </div>
      </div>

      <p style={{ fontSize: '13px', color: 'var(--text-secondary)', lineHeight: '1.6', background: 'rgba(255,255,255,0.02)', padding: '15px', borderRadius: '12px', margin: 0 }}>
        Follow the anatomical map to ensure maximum muscle recruitment. Focus on the mind-muscle connection in the highlighted areas during the eccentric phase.
      </p>
    </Modal>
  );
};

export default TutorialModal;
