import { useState, useEffect } from 'react';
import { calculateStreak } from '../utils/stats';

const HISTORY_KEY = 'strive_workout_history';

const readHistory = () => {
  try {
    const parsed = JSON.parse(localStorage.getItem(HISTORY_KEY) || '[]');
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
};

export const useHistory = () => {
  const [history, setHistory] = useState([]);

  useEffect(() => {
    setHistory(readHistory());
  }, []);

  const saveSession = (sets, metadata = {}) => {
    if (!sets || sets.length === 0) return;
    const currentHistory = readHistory();
    const newSession = {
      id: Date.now().toString(),
      timestamp: new Date().toISOString(),
      sets,
      goal: metadata.goal || 'build_muscle',
      duration: metadata.duration || 0,
      routineName: metadata.routineName || null,
      source: metadata.source || 'strive',
      version: '1.1'
    };
    const updatedHistory = [newSession, ...currentHistory];
    localStorage.setItem(HISTORY_KEY, JSON.stringify(updatedHistory));
    setHistory(updatedHistory);
  };

  const getStreak = () => calculateStreak(history);

  const deleteSession = (id) => {
    const updatedHistory = readHistory().filter(s => s.id !== id);
    localStorage.setItem(HISTORY_KEY, JSON.stringify(updatedHistory));
    setHistory(updatedHistory);
  };

  const updateSession = (id, updatedSession) => {
    const updatedHistory = readHistory().map(s => s.id === id ? updatedSession : s);
    localStorage.setItem(HISTORY_KEY, JSON.stringify(updatedHistory));
    setHistory(updatedHistory);
  };

  /**
   * Merge externally produced sessions (e.g. pulled from Garmin) into history.
   * Duplicates are dropped by id so re-importing the same file is a no-op.
   * Returns how many sessions were actually added.
   */
  const importSessions = (sessions) => {
    if (!Array.isArray(sessions) || sessions.length === 0) return 0;

    const current = readHistory();
    const known = new Set(current.map(s => s.id));
    const incoming = sessions.filter(s =>
      s && s.id && !known.has(s.id) && Array.isArray(s.sets) && s.sets.length > 0
    );

    if (incoming.length === 0) return 0;

    const updatedHistory = [...incoming, ...current]
      .sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));

    localStorage.setItem(HISTORY_KEY, JSON.stringify(updatedHistory));
    setHistory(updatedHistory);
    return incoming.length;
  };

  return { history, saveSession, getStreak, deleteSession, updateSession, importSessions };
};
