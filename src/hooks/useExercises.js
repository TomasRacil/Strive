import { useState, useEffect } from 'react';
import defaultExercises from '../data/exercises.json';

const STORAGE_KEY = 'strive_custom_exercises';

export const useExercises = () => {
  const [exercises, setExercises] = useState([]);

  useEffect(() => {
    const custom = JSON.parse(localStorage.getItem(STORAGE_KEY) || '[]');
    const deleted = JSON.parse(localStorage.getItem('strive_deleted_defaults') || '[]');
    
    // Filter out defaults that are either deleted or shadowed by custom updates
    const customIds = custom.map(c => c.id);
    const filteredDefaults = defaultExercises.filter(e => 
      !deleted.includes(e.id) && !customIds.includes(e.id)
    );
    
    setExercises([...filteredDefaults, ...custom]);
  }, []);

  const addExercise = (exercise) => {
    const custom = JSON.parse(localStorage.getItem(STORAGE_KEY) || '[]');
    const newExercise = { ...exercise, id: Date.now().toString() };
    const updatedCustom = [...custom, newExercise];
    localStorage.setItem(STORAGE_KEY, JSON.stringify(updatedCustom));
    
    const deleted = JSON.parse(localStorage.getItem('strive_deleted_defaults') || '[]');
    const filteredDefaults = defaultExercises.filter(e => !deleted.includes(e.id));
    setExercises([...filteredDefaults, ...updatedCustom]);
  };

  const deleteExercise = (id) => {
    const isDefault = defaultExercises.find(e => e.id === id);
    const custom = JSON.parse(localStorage.getItem(STORAGE_KEY) || '[]');
    const deleted = JSON.parse(localStorage.getItem('strive_deleted_defaults') || '[]');
    
    let updatedCustom = custom.filter(e => e.id !== id);
    let updatedDeleted = deleted;

    if (isDefault) {
      updatedDeleted = [...new Set([...deleted, id])];
      localStorage.setItem('strive_deleted_defaults', JSON.stringify(updatedDeleted));
    }
    
    localStorage.setItem(STORAGE_KEY, JSON.stringify(updatedCustom));
    
    const customIds = updatedCustom.map(c => c.id);
    const filteredDefaults = defaultExercises.filter(e => 
      !updatedDeleted.includes(e.id) && !customIds.includes(e.id)
    );
    setExercises([...filteredDefaults, ...updatedCustom]);
  };

  const updateExercise = (id, data) => {
    const custom = JSON.parse(localStorage.getItem(STORAGE_KEY) || '[]');
    const isDefault = defaultExercises.find(e => e.id === id);
    const deleted = JSON.parse(localStorage.getItem('strive_deleted_defaults') || '[]');
    
    let updatedCustom;
    if (isDefault) {
      // Find existing shadow or create new
      const existingShadow = custom.find(e => e.id === id);
      const base = existingShadow || isDefault;
      updatedCustom = [...custom.filter(e => e.id !== id), { ...base, ...data }];
    } else {
      updatedCustom = custom.map(e => e.id === id ? { ...e, ...data } : e);
    }
    
    localStorage.setItem(STORAGE_KEY, JSON.stringify(updatedCustom));
    
    const customIds = updatedCustom.map(c => c.id);
    const filteredDefaults = defaultExercises.filter(e => 
      !deleted.includes(e.id) && !customIds.includes(e.id)
    );
    setExercises([...filteredDefaults, ...updatedCustom]);
  };

  return { exercises, addExercise, deleteExercise, updateExercise };
};
