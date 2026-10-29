import { useState, useEffect } from 'react';
import { Ruler, Weight, Download, Upload, Database, Calendar, Watch, CheckCircle2, RefreshCw } from 'lucide-react';
import { useHistory } from '../hooks/useHistory';
import { checkForUpdate } from '../pwa.js';

const Profile = () => {
  const [height, setHeight] = useState('');
  const [weight, setWeight] = useState('');
  const [birthDate, setBirthDate] = useState('');
  const [saved, setSaved] = useState(false);
  const [garminStatus, setGarminStatus] = useState('');
  const [updateState, setUpdateState] = useState({ checking: false, message: '' });
  const { importSessions } = useHistory();

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
      } catch {
        alert('Failed to import data. Please ensure the file is a valid Strive backup.');
      }
    };
    reader.readAsText(file);
  };

  // Download routines in the shape garmin/bridge.py consumes.
  const handleGarminExport = () => {
    let routines;
    try {
      routines = JSON.parse(localStorage.getItem('strive_routines') || '[]');
    } catch {
      routines = [];
    }

    if (routines.length === 0) {
      setGarminStatus('No routines to export yet. Create one on the Training tab first.');
      return;
    }

    const payload = {
      version: '1.2',
      exported: new Date().toISOString(),
      routines
    };

    const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'strive_garmin_routines.json';
    a.click();
    URL.revokeObjectURL(url);

    setGarminStatus(`${routines.length} routine(s) exported. Run: python garmin/bridge.py push strive_garmin_routines.json`);
  };

  // Import sessions produced by `bridge.py pull`.
  const handleGarminImport = (e) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = (event) => {
      try {
        const data = JSON.parse(event.target.result);
        const sessions = data.sessions || (Array.isArray(data) ? data : []);
        const added = importSessions(sessions);

        if (added === 0) {
          setGarminStatus('Nothing new to import — these sessions are already in your history.');
        } else {
          setGarminStatus(`Imported ${added} session(s) from Garmin.`);
        }
      } catch {
        setGarminStatus('Could not read that file. Expected the JSON produced by bridge.py pull.');
      }
      e.target.value = '';
    };
    reader.readAsText(file);
  };

  const handleCheckUpdate = async () => {
    setUpdateState({ checking: true, message: '' });
    const result = await checkForUpdate();

    if (result === 'updated') {
      setUpdateState({ checking: false, message: 'New version found — reloading…' });
      setTimeout(() => window.location.reload(), 1200);
      return;
    }

    setUpdateState({
      checking: false,
      message: result === 'current'
        ? `You are on the latest build (${__BUILD_ID__}).`
        : 'This browser has no service worker registered, so there is nothing to update.'
    });
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

      <div className="glass" style={{ padding: '25px', marginTop: '25px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '15px' }}>
          <Watch size={20} className="premium-gradient-text" />
          <h2 style={{ fontSize: '18px' }}>Garmin</h2>
        </div>

        <p style={{ fontSize: '12px', color: 'var(--text-secondary)', marginBottom: '18px', lineHeight: '1.6' }}>
          Export your routines as structured Garmin strength workouts, then push them to
          Garmin Connect with the bridge in <code>garmin/</code>. They appear on the watch
          in the native strength app. Pull completed sessions back the same way.
        </p>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '15px' }}>
          <button
            className="btn-secondary"
            onClick={handleGarminExport}
            style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px', padding: '15px' }}
          >
            <Download size={18} /> Routines for Garmin
          </button>

          <div style={{ position: 'relative' }}>
            <button className="btn-secondary" style={{ width: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px', padding: '15px' }}>
              <Upload size={18} /> Import Garmin Sessions
            </button>
            <input
              type="file"
              accept=".json"
              onChange={handleGarminImport}
              style={{ position: 'absolute', top: 0, left: 0, width: '100%', height: '100%', opacity: 0, cursor: 'pointer' }}
            />
          </div>
        </div>

        {garminStatus && (
          <div style={{ display: 'flex', alignItems: 'flex-start', gap: '8px', marginTop: '15px' }}>
            <CheckCircle2 size={14} style={{ marginTop: '2px', flexShrink: 0, color: 'var(--primary-color)' }} />
            <p style={{ fontSize: '11px', color: 'var(--text-secondary)', lineHeight: '1.5' }}>{garminStatus}</p>
          </div>
        )}

        <p style={{ fontSize: '10px', color: 'var(--text-secondary)', marginTop: '15px', lineHeight: '1.6' }}>
          Sets recorded on the watch keep their Garmin exercise names when they are not in
          your library. See <code>garmin/README.md</code> for first-run setup.
        </p>
      </div>

      <div className="glass" style={{
        padding: '20px',
        marginTop: '25px',
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        gap: '15px',
        flexWrap: 'wrap'
      }}>
        <div>
          <div style={{ fontSize: '14px', fontWeight: '700' }}>App version</div>
          <div style={{ fontSize: '11px', color: 'var(--text-secondary)' }}>Build {__BUILD_ID__}</div>
          {updateState.message && (
            <div style={{ fontSize: '11px', color: 'var(--primary-color)', marginTop: '6px' }}>
              {updateState.message}
            </div>
          )}
        </div>
        <button
          className="btn-secondary"
          onClick={handleCheckUpdate}
          disabled={updateState.checking}
          style={{ padding: '10px 16px', fontSize: '13px', display: 'flex', alignItems: 'center', gap: '8px' }}
        >
          <RefreshCw size={14} /> {updateState.checking ? 'Checking…' : 'Check for updates'}
        </button>
      </div>
    </div>
  );
};

export default Profile;
