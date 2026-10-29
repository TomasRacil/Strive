import { useState, useEffect, useRef } from 'react';
import { Timer, Check } from 'lucide-react';
import { playBeep, vibrate } from '../utils/audio';

/**
 * Counts up when given only a start time (session duration), or counts down to
 * `targetSeconds` and alerts when rest is over. The alert fires once per start
 * time, so a re-render or a paused phone does not turn it into a repeating alarm.
 */
const RestTimer = ({ startTime, targetSeconds = null, label = 'Rest' }) => {
  const [seconds, setSeconds] = useState(0);
  const alertedRef = useRef(false);

  useEffect(() => {
    alertedRef.current = false;

    if (!startTime) {
      setSeconds(0);
      return;
    }

    const tick = () => {
      setSeconds(Math.floor((Date.now() - new Date(startTime).getTime()) / 1000));
    };

    tick();
    const interval = setInterval(tick, 1000);
    return () => clearInterval(interval);
  }, [startTime]);

  const remaining = targetSeconds ? Math.max(0, targetSeconds - seconds) : null;
  const isDone = remaining === 0;

  useEffect(() => {
    if (!targetSeconds || remaining !== 0 || alertedRef.current) return;
    alertedRef.current = true;
    playBeep();
    vibrate();
  }, [remaining, targetSeconds]);

  if (!startTime) return null;

  const formatTime = (total) => {
    const safe = Math.max(0, total);
    const mins = Math.floor(safe / 60);
    const secs = safe % 60;
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };

  const progress = targetSeconds ? Math.min(100, (seconds / targetSeconds) * 100) : 0;

  return (
    <div className="glass fade-in" style={{ 
      padding: '10px 15px', 
      display: 'flex', 
      alignItems: 'center', 
      gap: '10px',
      borderRadius: '12px',
      marginBottom: '15px',
      border: `1px solid ${isDone ? 'rgba(34, 197, 94, 0.45)' : 'rgba(255,255,255,0.1)'}`,
      position: 'relative',
      overflow: 'hidden'
    }}>
      {targetSeconds && (
        <div style={{
          position: 'absolute',
          left: 0,
          top: 0,
          bottom: 0,
          width: `${progress}%`,
          background: isDone ? 'rgba(34, 197, 94, 0.12)' : 'rgba(59, 130, 246, 0.10)',
          transition: 'width 1s linear'
        }} />
      )}

      {isDone
        ? <Check size={16} style={{ color: '#22c55e', position: 'relative' }} />
        : <Timer size={16} className="premium-gradient-text" style={{ position: 'relative' }} />}

      <span style={{ fontSize: '12px', color: 'var(--text-secondary)', position: 'relative' }}>
        {isDone ? 'Ready' : `${label || 'Rest'}:`}
      </span>

      <span style={{
        fontSize: '14px',
        fontWeight: '700',
        fontFamily: 'monospace',
        position: 'relative',
        color: isDone ? '#22c55e' : 'inherit'
      }}>
        {formatTime(remaining !== null ? remaining : seconds)}
      </span>
    </div>
  );
};

export default RestTimer;
