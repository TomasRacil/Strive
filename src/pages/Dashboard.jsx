import React, { useState } from 'react';
import { Flame, Trophy, Calendar, Plus, Clock, ChevronRight } from 'lucide-react';
import { useHistory } from '../hooks/useHistory';
import { useExercises } from '../hooks/useExercises';
import SessionDetailsModal from '../components/SessionDetailsModal';

const Dashboard = ({ setActiveTab }) => {
  const { history, getStreak, deleteSession } = useHistory();
  const { exercises } = useExercises();
  const [selectedSession, setSelectedSession] = useState(null);
  const [showFullHistory, setShowFullHistory] = useState(false);
  
  const streak = getStreak();
  const totalWorkouts = history.length;

  const formatDate = (dateString) => {
    const options = { month: 'short', day: 'numeric' };
    return new Date(dateString).toLocaleDateString(undefined, options);
  };

  return (
    <div className="page-container fade-in">
      <header style={{ marginBottom: '30px' }}>
        <h1 className="premium-gradient-text" style={{ fontSize: '32px' }}>Strive</h1>
        <p style={{ color: 'var(--text-secondary)' }}>Welcome back, Athlete.</p>
      </header>

      <div className="glass" style={{ padding: '20px', marginBottom: '25px', display: 'flex', gap: '15px' }}>
        <div className="stat-card">
          <Flame color={streak > 0 ? "#ef4444" : "var(--text-secondary)"} size={20} />
          <div className="stat-info">
            <span className="stat-value">{streak}</span>
            <span className="stat-label">Day Streak</span>
          </div>
        </div>
        <div className="stat-card">
          <Trophy color={totalWorkouts > 0 ? "#f59e0b" : "var(--text-secondary)"} size={20} />
          <div className="stat-info">
            <span className="stat-value">{totalWorkouts}</span>
            <span className="stat-label">Total Workouts</span>
          </div>
        </div>
      </div>

      <h2 style={{ fontSize: '18px', marginBottom: '15px', fontWeight: '700' }}>Quick Actions</h2>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '15px', marginBottom: '30px' }}>
        <div className="glass clickable-card" onClick={() => setActiveTab('exercises')}>
          <Plus size={24} style={{ marginBottom: '8px', color: 'var(--text-secondary)' }} />
          <span>New Exercise</span>
        </div>
        <div 
          className="glass clickable-card" 
          style={{ border: '1px solid var(--primary-color)' }}
          onClick={() => setActiveTab('training')}
        >
          <Flame size={24} color="var(--primary-color)" style={{ marginBottom: '8px' }} />
          <span className="premium-gradient-text">Start Training</span>
        </div>
      </div>

      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '15px' }}>
        <h2 style={{ fontSize: '18px', fontWeight: '700' }}>Recent Activity</h2>
        {history.length > 5 && (
          <span 
            style={{ fontSize: '12px', color: 'var(--primary-color)', cursor: 'pointer' }}
            onClick={() => setShowFullHistory(true)}
          >
            View All
          </span>
        )}
      </div>

      {history.length === 0 ? (
        <div className="glass" style={{ padding: '30px', textAlign: 'center', color: 'var(--text-secondary)' }}>
          <Clock size={32} style={{ marginBottom: '12px', opacity: 0.5 }} />
          <p>No workouts recorded yet.</p>
          <p style={{ fontSize: '12px' }}>Start your first session to see it here!</p>
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
          {(showFullHistory ? history : history.slice(0, 5)).map((session) => (
            <div 
              key={session.id} 
              className="glass" 
              style={{ 
                padding: '15px 20px', 
                display: 'flex', 
                justifyContent: 'space-between', 
                alignItems: 'center',
                cursor: 'pointer',
                transition: 'all 0.2s ease',
                border: '1px solid var(--glass-border)'
              }}
              onClick={() => setSelectedSession(session)}
            >
              <div style={{ display: 'flex', gap: '20px', alignItems: 'center' }}>
                <div style={{ 
                  width: '50px', 
                  height: '50px', 
                  borderRadius: '12px', 
                  background: 'rgba(59, 130, 246, 0.1)', 
                  display: 'flex', 
                  flexDirection: 'column', 
                  alignItems: 'center', 
                  justifyContent: 'center',
                  border: '1px solid rgba(59, 130, 246, 0.2)',
                  lineHeight: '1.1'
                }}>
                  <span style={{ fontSize: '10px', color: 'var(--primary-color)', fontWeight: '800' }}>
                    {formatDate(session.timestamp).split(' ')[1].toUpperCase()}
                  </span>
                  <span style={{ fontSize: '16px', fontWeight: '800' }}>
                    {formatDate(session.timestamp).split(' ')[0]}
                  </span>
                </div>
                <div>
                  <div style={{ fontSize: '15px', fontWeight: '700' }}>
                    {session.sets.length} Sets Completed
                  </div>
                  <div style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>
                    {Array.from(new Set(session.sets.map(s => exercises.find(e => e.id === s.exerciseId)?.name)))
                      .filter(Boolean)
                      .slice(0, 2)
                      .join(', ')}
                    {new Set(session.sets.map(s => s.exerciseId)).size > 2 ? '...' : ''}
                  </div>
                </div>
              </div>
              <ChevronRight size={20} color="var(--text-secondary)" />
            </div>
          ))}
          
          {showFullHistory && (
            <button 
              className="btn-secondary" 
              style={{ marginTop: '10px', width: '100%' }}
              onClick={() => setShowFullHistory(false)}
            >
              Show Less
            </button>
          )}
        </div>
      )}

      {selectedSession && (
        <SessionDetailsModal 
          session={selectedSession}
          exercises={exercises}
          onClose={() => setSelectedSession(null)}
          onDelete={deleteSession}
        />
      )}
    </div>
  );
};

export default Dashboard;
