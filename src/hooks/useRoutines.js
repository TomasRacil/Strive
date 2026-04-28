import { useState, useEffect } from 'react';

const STORAGE_KEY = 'strive_routines';

export const useRoutines = () => {
  const [routines, setRoutines] = useState([]);

  useEffect(() => {
    setRoutines(JSON.parse(localStorage.getItem(STORAGE_KEY) || '[]'));
  }, []);

  const addRoutine = (routine) => {
    const current = JSON.parse(localStorage.getItem(STORAGE_KEY) || '[]');
    const newRoutine = { ...routine, id: Date.now().toString() };
    const updated = [...current, newRoutine];
    localStorage.setItem(STORAGE_KEY, JSON.stringify(updated));
    setRoutines(updated);
  };

  const deleteRoutine = (id) => {
    const current = JSON.parse(localStorage.getItem(STORAGE_KEY) || '[]');
    const updated = current.filter(r => r.id !== id);
    localStorage.setItem(STORAGE_KEY, JSON.stringify(updated));
    setRoutines(updated);
  };

  return { routines, addRoutine, deleteRoutine };
};
