import { useState } from 'react';
import { Flame, Trophy, Plus, Clock, ChevronRight } from 'lucide-react';
import { useHistory } from '../hooks/useHistory';
import { useExercises } from '../hooks/useExercises';
import SessionDetailsModal from '../components/SessionDetailsModal';
import { sessionVolume, volumeByMuscle, sessionsInLastDays } from '../utils/stats';

const Dashboard = ({ setActiveTab }) => {
  const { history, getStreak, deleteSession } = useHistory();
  const { exercises } = useExercises();
  const [selectedSession, setSelectedSession] = useState(null);
  const [showFullHistory, setShowFullHistory] = useState(false);

  const streak = getStreak();
  const totalWorkouts = history.length;

  // Locale-safe: some locales format a date without a space ("10/29"), which
  // made the old `split(' ')[1].toUpperCase()` throw and blank the dashboard.
  const formatMonth = (dateString) =>
    new Date(dateString).toLocaleDateString(undefined, { month: 'short' }).toUpperCase();
  const formatDay = (dateString) =>
    new Date(dateString).toLocaleDateString(undefined, { day: 'numeric' });

  const weekVolume = volumeByMuscle(history, exercises, 7).slice(0, 4);
  const weekSessions = sessionsInLastDays(history, 7);

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

      {weekVolume.length > 0 && (
        <div className="glass" style={{ padding: '20px', marginBottom: '25px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: '15px' }}>
            <h2 style={{ fontSize: '16px', fontWeight: '700' }}>This Week</h2>
            <span style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>
              {weekSessions} {weekSessions === 1 ? 'session' : 'sessions'}
            </span>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
            {weekVolume.map(({ muscle, volume }) => {
              const max = weekVolume[0].volume || 1;
              return (
                <div key={muscle} style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                  <span style={{ width: '85px', fontSize: '12px', color: 'var(--text-secondary)' }}>{muscle}</span>
                  <div style={{ flex: 1, height: '8px', background: 'rgba(255,255,255,0.06)', borderRadius: '4px', overflow: 'hidden' }}>
                    <div style={{ width: `${Math.round((volume / max) * 100)}%`, height: '100%', background: 'linear-gradient(90deg, #3b82f6, #8b5cf6)' }} />
                  </div>
                  <span style={{ fontSize: '11px', color: 'var(--text-secondary)', width: '62px', textAlign: 'right' }}>
                    {volume >= 1000 ? `${(volume / 1000).toFixed(1)} t` : `${volume} kg`}
                  </span>
                </div>
              );
            })}
          </div>
          <p style={{ fontSize: '10px', color: 'var(--text-secondary)', marginTop: '12px' }}>
            Volume is split across muscle groups by each exercise's engagement weighting.
          </p>
        </div>
      )}

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
                    {formatMonth(session.timestamp)}
                  </span>
                  <span style={{ fontSize: '16px', fontWeight: '800' }}>
                    {formatDay(session.timestamp)}
                  </span>
                </div>
                <div>
                  <div style={{ fontSize: '15px', fontWeight: '700' }}>
                    {session.sets.length} Sets Completed
                  </div>
                  <div style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>
                    {Array.from(new Set(session.sets.map(s => s.exerciseName || exercises.find(e => e.id === s.exerciseId)?.name)))
                      .filter(Boolean)
                      .slice(0, 2)
                      .join(', ')}
                    {new Set(session.sets.map(s => s.exerciseId)).size > 2 ? '...' : ''}
                    {' · '}
                    {Math.round(sessionVolume(session.sets)).toLocaleString()} kg
                    {session.duration ? ` · ${session.duration < 60 ? `${session.duration}s` : `${Math.round(session.duration / 60)} min`}` : ''}
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
