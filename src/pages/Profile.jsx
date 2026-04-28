import React, { useState, useEffect } from 'react';
import { Ruler, Weight, Download, Upload, Database, Calendar } from 'lucide-react';

const Profile = () => {
  const [height, setHeight] = useState('');
  const [weight, setWeight] = useState('');
  const [birthDate, setBirthDate] = useState('');
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    setHeight(localStorage.getItem('strive_height') || '');
    setWeight(localStorage.getItem('strive_weight') || '');
    setBirthDate(localStorage.getItem('strive_birth_date') || '');
  }, []);

  const handleSave = () => {
    localStorage.setItem('strive_height', height);
    localStorage.setItem('strive_weight', weight);
    localStorage.setItem('strive_birth_date', birthDate);
    setSaved(true);
    setTimeout(() => setSaved(false), 2000);
  };

  const handleExport = () => {
    const data = {
      version: '1.1',
      export_date: new Date().toISOString(),
      exercises: localStorage.getItem('strive_custom_exercises'),
      deleted_defaults: localStorage.getItem('strive_deleted_defaults'),
      history: localStorage.getItem('strive_workout_history'),
      routines: localStorage.getItem('strive_routines'),
      metrics: {
        height: localStorage.getItem('strive_height'),
        weight: localStorage.getItem('strive_weight'),
        birthDate: localStorage.getItem('strive_birth_date')
      }
    };
    
    const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `strive_backup_${new Date().toISOString().split('T')[0]}.json`;
    a.click();
  };

  const handleImport = (e) => {
    const file = e.target.files[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = (event) => {
      try {
        const data = JSON.parse(event.target.result);
        
        // Basic migration logic
        if (data.exercises) localStorage.setItem('strive_custom_exercises', data.exercises);
        if (data.deleted_defaults) localStorage.setItem('strive_deleted_defaults', data.deleted_defaults);
        
        // Handle legacy history key if present
        const historyData = data.history || data.strive_history;
        if (historyData) localStorage.setItem('strive_workout_history', historyData);
        
        if (data.routines) localStorage.setItem('strive_routines', data.routines);
        if (data.metrics) {
          localStorage.setItem('strive_height', data.metrics.height);
          localStorage.setItem('strive_weight', data.metrics.weight);
          if (data.metrics.birthDate) localStorage.setItem('strive_birth_date', data.metrics.birthDate);
        }
        
        alert('Data imported successfully! The app will refresh to apply changes.');
        window.location.reload();
      } catch (err) {
        alert('Failed to import data. Please ensure the file is a valid Strive backup.');
      }
    };
    reader.readAsText(file);
  };

  return (
    <div className="page-container fade-in">
      <header style={{ marginBottom: '30px' }}>
        <h1 className="premium-gradient-text" style={{ fontSize: '32px' }}>Profile</h1>
        <p style={{ color: 'var(--text-secondary)' }}>Manage your body metrics and data.</p>
      </header>

      <div className="glass" style={{ padding: '25px', marginBottom: '25px' }}>
        <h2 style={{ fontSize: '18px', fontWeight: '700', marginBottom: '20px', display: 'flex', alignItems: 'center', gap: '10px' }}>
          My Metrics
        </h2>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
          <div className="input-group">
            <label style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '14px', color: 'var(--text-secondary)' }}>
              <Ruler size={16} /> Height (cm)
            </label>
            <input 
              type="number" 
              placeholder="180" 
              value={height} 
              onChange={(e) => setHeight(e.target.value)}
            />
          </div>
          <div className="input-group">
            <label style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '14px', color: 'var(--text-secondary)' }}>
              <Weight size={16} /> Weight (kg)
            </label>
            <input 
              type="number" 
              placeholder="75" 
              value={weight} 
              onChange={(e) => setWeight(e.target.value)}
            />
          </div>
          <div className="input-group">
            <label style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '14px', color: 'var(--text-secondary)' }}>
              <Calendar size={16} /> Birth Date
            </label>
            <input 
              type="date" 
              value={birthDate} 
              onChange={(e) => setBirthDate(e.target.value)}
              style={{ colorScheme: 'dark' }}
            />
          </div>
          <button 
            className="btn-primary" 
            onClick={handleSave}
            style={{ marginTop: '10px' }}
          >
            {saved ? 'Metrics Saved!' : 'Save Metrics'}
          </button>
        </div>
      </div>

      <div className="glass" style={{ padding: '25px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '20px' }}>
          <Database size={20} className="premium-gradient-text" />
          <h2 style={{ fontSize: '18px' }}>Data Management</h2>
        </div>
        
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '15px' }}>
          <button className="btn-secondary" onClick={handleExport} style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px', padding: '15px' }}>
            <Download size={18} /> Export Data
          </button>
          
          <div style={{ position: 'relative' }}>
            <button className="btn-secondary" style={{ width: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px', padding: '15px' }}>
              <Upload size={18} /> Import Data
            </button>
            <input 
              type="file" 
              accept=".json" 
              onChange={handleImport}
              style={{ position: 'absolute', top: 0, left: 0, width: '100%', height: '100%', opacity: 0, cursor: 'pointer' }}
            />
          </div>
        </div>
        <p style={{ fontSize: '11px', color: 'var(--text-secondary)', marginTop: '15px', textAlign: 'center' }}>
          Back up your history, routines, and custom exercises to a JSON file.
        </p>
      </div>
    </div>
  );
};

export default Profile;
