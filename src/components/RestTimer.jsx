import React, { useState, useEffect } from 'react';
import { Timer } from 'lucide-react';

const RestTimer = ({ startTime, label }) => {
  const [seconds, setSeconds] = useState(0);

  useEffect(() => {
    if (!startTime) return;
    
    const interval = setInterval(() => {
      const diff = Math.floor((new Date() - new Date(startTime)) / 1000);
      setSeconds(diff);
    }, 1000);

    return () => clearInterval(interval);
  }, [startTime]);

  if (!startTime) return null;

  const formatTime = (s) => {
    const mins = Math.floor(s / 60);
    const secs = s % 60;
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };

  return (
    <div className="glass fade-in" style={{ 
      padding: '10px 15px', 
      display: 'flex', 
      alignItems: 'center', 
      gap: '10px',
      borderRadius: '12px',
      marginBottom: '15px',
      border: '1px solid rgba(255,255,255,0.1)'
    }}>
      <Timer size={16} className="premium-gradient-text" />
      <span style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>{label || 'Rest'}:</span>
      <span style={{ fontSize: '14px', fontWeight: '700', fontFamily: 'monospace' }}>{formatTime(seconds)}</span>
    </div>
  );
};

export default RestTimer;
