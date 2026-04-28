import { useState, useEffect } from 'react';

const HISTORY_KEY = 'strive_workout_history';

export const useHistory = () => {
  const [history, setHistory] = useState([]);

  useEffect(() => {
    setHistory(JSON.parse(localStorage.getItem(HISTORY_KEY) || '[]'));
  }, []);

  const saveSession = (sets, metadata = {}) => {
    if (sets.length === 0) return;
    const currentHistory = JSON.parse(localStorage.getItem(HISTORY_KEY) || '[]');
    const newSession = {
      id: Date.now().toString(),
      timestamp: new Date().toISOString(),
      sets,
      goal: metadata.goal || 'build_muscle',
      duration: metadata.duration || 0,
      version: '1.0' // Storage versioning
    };
    const updatedHistory = [newSession, ...currentHistory];
    localStorage.setItem(HISTORY_KEY, JSON.stringify(updatedHistory));
    setHistory(updatedHistory);
  };

  const getStreak = () => {
    if (history.length === 0) return 0;
    
    let streak = 0;
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    
    let checkDate = new Date(today);
    
    // Sort history by date descending
    const sortedHistory = [...history].sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
    
    for (let i = 0; i < sortedHistory.length; i++) {
      const workoutDate = new Date(sortedHistory[i].timestamp);
      workoutDate.setHours(0, 0, 0, 0);
      
      const diffDays = Math.floor((checkDate - workoutDate) / (1000 * 60 * 60 * 24));
      
      if (diffDays === 0) {
        streak++;
        checkDate.setDate(checkDate.getDate() - 1);
      } else if (diffDays > 1) {
        break;
      }
    }
    return streak;
  };

  const deleteSession = (id) => {
    const updatedHistory = history.filter(s => s.id !== id);
    localStorage.setItem(HISTORY_KEY, JSON.stringify(updatedHistory));
    setHistory(updatedHistory);
  };

  const updateSession = (id, updatedSession) => {
    const updatedHistory = history.map(s => s.id === id ? updatedSession : s);
    localStorage.setItem(HISTORY_KEY, JSON.stringify(updatedHistory));
    setHistory(updatedHistory);
  };

  return { history, saveSession, getStreak, deleteSession, updateSession };
};
