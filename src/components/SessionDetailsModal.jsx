import React from 'react';
import { X, Trash2, Calendar, Clock } from 'lucide-react';

const SessionDetailsModal = ({ session, onClose, onDelete, exercises }) => {
  if (!session) return null;

  // Group sets by exercise
  const groups = session.sets.reduce((acc, set) => {
    if (!acc[set.exerciseId]) acc[set.exerciseId] = [];
    acc[set.exerciseId].push(set);
    return acc;
  }, {});

  const formatDate = (dateString) => {
    return new Date(dateString).toLocaleDateString('en-GB', { 
      weekday: 'long', 
      day: 'numeric', 
      month: 'long', 
      year: 'numeric' 
    });
  };

  const formatTime = (dateString) => {
    return new Date(dateString).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  };

  return (
    <div className="modal-overlay">
      <div className="glass modal-content fade-in">
        <header style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <Calendar size={20} className="premium-gradient-text" />
            <h2 style={{ fontSize: '18px', fontWeight: '700' }}>Session Details</h2>
          </div>
          <button className="btn-secondary" style={{ padding: '8px', borderRadius: '50%' }} onClick={onClose}>
            <X size={18} />
          </button>
        </header>

        <div style={{ marginBottom: '25px', padding: '15px', background: 'rgba(255,255,255,0.03)', borderRadius: '15px' }}>
          <div style={{ fontSize: '14px', fontWeight: '600', marginBottom: '4px' }}>{formatDate(session.timestamp)}</div>
          <div style={{ fontSize: '12px', color: 'var(--text-secondary)', display: 'flex', alignItems: 'center', gap: '5px' }}>
            <Clock size={12} /> {formatTime(session.timestamp)}
          </div>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: '20px', flex: 1, overflowY: 'auto' }}>
          {Object.entries(groups).map(([exId, exSets]) => {
            const ex = exercises.find(e => e.id === exId);
            return (
              <div key={exId}>
                <h3 style={{ fontSize: '14px', fontWeight: '700', marginBottom: '10px', color: 'var(--primary-color)' }}>
                  {ex?.name || 'Unknown Exercise'}
                </h3>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                  {exSets.map((set, i) => (
                    <div key={i} style={{ 
                      display: 'flex', 
                      justifyContent: 'space-between', 
                      fontSize: '13px',
                      padding: '8px 12px',
                      background: 'rgba(255,255,255,0.02)',
                      borderRadius: '8px'
                    }}>
                      <span>Set {i + 1}: <strong>{set.weight}kg</strong> × {set.reps}</span>
                      <span style={{ color: 'var(--text-secondary)', fontSize: '11px' }}>{set.rir} RIR • {set.form}</span>
                    </div>
                  ))}
                </div>
              </div>
            );
          })}
        </div>

        <div style={{ marginTop: '25px', display: 'flex', gap: '10px' }}>
          <button 
            className="btn-secondary" 
            style={{ flex: 1, color: '#ef4444', border: '1px solid rgba(239, 68, 68, 0.2)' }}
            onClick={() => {
              if (window.confirm('Are you sure you want to delete this session?')) {
                onDelete(session.id);
                onClose();
              }
            }}
          >
            <Trash2 size={16} /> Delete Session
          </button>
          <button className="btn-primary" style={{ flex: 2 }} onClick={onClose}>Close</button>
        </div>
      </div>
    </div>
  );
};

export default SessionDetailsModal;
