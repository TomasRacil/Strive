import React, { useState, useEffect, useRef } from 'react';
import { Ruler, Weight, Download, Upload, Database, Calendar, Users, Key, Droplet, Activity, History, Maximize, Circle } from 'lucide-react';
import CustomSelect from '../components/CustomSelect';
import Modal from '../components/Modal';
import { useDialog } from '../context/DialogContext';

const Profile = () => {
  const { showAlert } = useDialog();
  const [height, setHeight] = useState('');
  const [weight, setWeight] = useState('');
  const [birthDate, setBirthDate] = useState('');
  const [sex, setSex] = useState('');
  const [apiKey, setApiKey] = useState('');
  const [bodyFat, setBodyFat] = useState('');
  const [muscleMass, setMuscleMass] = useState('');
  const [waist, setWaist] = useState('');
  const [neck, setNeck] = useState('');
  const [biceps, setBiceps] = useState('');
  const [thighs, setThighs] = useState('');
  const [saved, setSaved] = useState(false);
  const [showHistory, setShowHistory] = useState(false);
  const [biometricLog, setBiometricLog] = useState([]);
  const initialLoadDone = useRef(false);

  useEffect(() => {
    setHeight(localStorage.getItem('strive_height') || '');
    setWeight(localStorage.getItem('strive_weight') || '');
    setBirthDate(localStorage.getItem('strive_birth_date') || '');
    setSex(localStorage.getItem('strive_sex') || '');
    setApiKey(localStorage.getItem('strive_api_key') || '');
    setBodyFat(localStorage.getItem('strive_body_fat') || '');
    setMuscleMass(localStorage.getItem('strive_muscle_mass') || '');
    setWaist(localStorage.getItem('strive_waist') || '');
    setNeck(localStorage.getItem('strive_neck') || '');
    setBiceps(localStorage.getItem('strive_biceps') || '');
    setThighs(localStorage.getItem('strive_thighs') || '');

    try {
      const logs = JSON.parse(localStorage.getItem('strive_biometric_log')) || [];
      setBiometricLog(logs);
    } catch (e) {
      setBiometricLog([]);
    }

    // Give state a moment to settle before enabling auto-save
    setTimeout(() => { initialLoadDone.current = true; }, 500);
  }, []);

  // Debounced Auto-Save
  useEffect(() => {
    if (!initialLoadDone.current) return;

    const timeoutId = setTimeout(() => {
      localStorage.setItem('strive_height', height);
      localStorage.setItem('strive_weight', weight);
      localStorage.setItem('strive_birth_date', birthDate);
      localStorage.setItem('strive_sex', sex);
      localStorage.setItem('strive_api_key', apiKey);
      localStorage.setItem('strive_body_fat', bodyFat);
      localStorage.setItem('strive_muscle_mass', muscleMass);
      localStorage.setItem('strive_waist', waist);
      localStorage.setItem('strive_neck', neck);
      localStorage.setItem('strive_biceps', biceps);
      localStorage.setItem('strive_thighs', thighs);

      // Update Daily Log
      const today = new Date().toISOString().split('T')[0];
      const newLogEntry = {
        date: today, weight, bodyFat, muscleMass, waist, neck, biceps, thighs
      };

      setBiometricLog(prevLogs => {
        const existingIndex = prevLogs.findIndex(log => log.date === today);
        let updatedLogs = [...prevLogs];

        if (existingIndex >= 0) {
          updatedLogs[existingIndex] = newLogEntry; // Overwrite today
        } else {
          updatedLogs.push(newLogEntry); // Add new day
        }

        updatedLogs = updatedLogs.sort((a, b) => new Date(b.date) - new Date(a.date)); // Sort newest first
        localStorage.setItem('strive_biometric_log', JSON.stringify(updatedLogs));
        return updatedLogs;
      });

      setSaved(true);
      setTimeout(() => setSaved(false), 2000);
    }, 800); // 800ms debounce

    return () => clearTimeout(timeoutId);
  }, [height, weight, birthDate, sex, apiKey, bodyFat, muscleMass, waist, neck, biceps, thighs]);

  const handleExport = () => {
    const data = {
      version: '1.2',
      export_date: new Date().toISOString(),
      exercises: localStorage.getItem('strive_custom_exercises'),
      deleted_defaults: localStorage.getItem('strive_deleted_defaults'),
      history: localStorage.getItem('strive_workout_history'),
      routines: localStorage.getItem('strive_routines'),
      biometricLog: localStorage.getItem('strive_biometric_log'),
      metrics: {
        height: localStorage.getItem('strive_height'),
        weight: localStorage.getItem('strive_weight'),
        birthDate: localStorage.getItem('strive_birth_date'),
        sex: localStorage.getItem('strive_sex'),
        bodyFat: localStorage.getItem('strive_body_fat'),
        muscleMass: localStorage.getItem('strive_muscle_mass'),
        waist: localStorage.getItem('strive_waist'),
        neck: localStorage.getItem('strive_neck'),
        biceps: localStorage.getItem('strive_biceps'),
        thighs: localStorage.getItem('strive_thighs')
      },
      apiKey: localStorage.getItem('strive_api_key')
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

        localStorage.setItem('strive_custom_exercises', data.exercises || '[]');
        localStorage.setItem('strive_deleted_defaults', data.deleted_defaults || '[]');

        const historyData = data.history || data.strive_history;
        localStorage.setItem('strive_workout_history', historyData || '[]');

        localStorage.setItem('strive_routines', data.routines || '[]');
        localStorage.setItem('strive_biometric_log', data.biometricLog || '[]');

        if (data.apiKey) localStorage.setItem('strive_api_key', data.apiKey);
        else localStorage.removeItem('strive_api_key');

        if (data.metrics) {
          localStorage.setItem('strive_height', data.metrics.height || '');
          localStorage.setItem('strive_weight', data.metrics.weight || '');
          localStorage.setItem('strive_birth_date', data.metrics.birthDate || '');
          localStorage.setItem('strive_sex', data.metrics.sex || 'male');
          localStorage.setItem('strive_body_fat', data.metrics.bodyFat || '');
          localStorage.setItem('strive_muscle_mass', data.metrics.muscleMass || '');
          localStorage.setItem('strive_waist', data.metrics.waist || '');
          localStorage.setItem('strive_neck', data.metrics.neck || '');
          localStorage.setItem('strive_biceps', data.metrics.biceps || '');
          localStorage.setItem('strive_thighs', data.metrics.thighs || '');
        }

        showAlert('Import Successful', 'Data imported successfully! The app will refresh.', 'success');
        setTimeout(() => window.location.reload(), 2000);
      } catch (err) {
        showAlert('Import Failed', 'Failed to import data. Please ensure the file is valid.', 'error');
      }
    };
    reader.readAsText(file);
  };

  return (
    <div className="page-container" style={{ height: '100vh', display: 'flex', flexDirection: 'column', paddingBottom: '0' }}>
      <div style={{ flex: 1, overflowY: 'auto', paddingBottom: '120px' }}>
        <header className="sticky-header" style={{ flexShrink: 0 }}>
          <h1 className="premium-gradient-text" style={{ fontSize: '32px' }}>Profile</h1>
          <p style={{ color: 'var(--text-secondary)' }}>Manage your biology and environment.</p>
        </header>

        <div className="glass" style={{ padding: '25px', marginBottom: '25px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
            <h2 style={{ fontSize: '18px', fontWeight: '700', display: 'flex', alignItems: 'center', gap: '10px' }}>
              Biometric Data
            </h2>
            <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
              <span style={{ fontSize: '12px', color: saved ? '#10b981' : 'var(--text-secondary)', transition: 'color 0.3s' }}>
                {saved ? 'Saved.' : 'Auto-saving...'}
              </span>
              <button className="btn-secondary" onClick={() => setShowHistory(true)} style={{ padding: '8px 12px', fontSize: '12px', gap: '5px' }}>
                <History size={14} /> View Log
              </button>
            </div>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
            <div className="responsive-grid">
              <div className="input-group">
                <label style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '12px', color: 'var(--text-secondary)' }}>
                  <Ruler size={14} /> Height (cm)
                </label>
                <input type="number" value={height} onChange={(e) => setHeight(e.target.value)} placeholder="180" />
              </div>
              <div className="input-group">
                <label style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '12px', color: 'var(--text-secondary)' }}>
                  <Weight size={14} /> Weight (kg)
                </label>
                <input type="number" value={weight} onChange={(e) => setWeight(e.target.value)} placeholder="75" />
              </div>
            </div>

            <div className="responsive-grid asymmetric">
              <div className="input-group">
                <label style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '12px', color: 'var(--text-secondary)' }}>
                  <Calendar size={14} /> Birth Date
                </label>
                <input type="date" value={birthDate} onChange={(e) => setBirthDate(e.target.value)} style={{ colorScheme: 'dark' }} />
              </div>
              <CustomSelect
                label={<span style={{ display: 'flex', alignItems: 'center', gap: '8px' }}><Users size={14} /> Sex</span>}
                value={sex}
                onChange={setSex}
                options={[
                  { value: 'male', label: 'Male' },
                  { value: 'female', label: 'Female' },
                  { value: 'other', label: 'Other' }
                ]}
              />
            </div>

            <div className="responsive-grid">
              <div className="input-group">
                <label style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '12px', color: 'var(--text-secondary)' }}>
                  <Droplet size={14} /> Body Fat %
                </label>
                <input type="number" value={bodyFat} onChange={(e) => setBodyFat(e.target.value)} placeholder="e.g. 15" />
              </div>
              <div className="input-group">
                <label style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '12px', color: 'var(--text-secondary)' }}>
                  <Activity size={14} /> Muscle Mass %
                </label>
                <input type="number" value={muscleMass} onChange={(e) => setMuscleMass(e.target.value)} placeholder="e.g. 45" />
              </div>
            </div>

            <div className="responsive-grid">
              <div className="input-group">
                <label style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '12px', color: 'var(--text-secondary)' }}>
                  <Circle size={14} /> Waist (cm)
                </label>
                <input type="number" value={waist} onChange={(e) => setWaist(e.target.value)} placeholder="e.g. 80" />
              </div>
              <div className="input-group">
                <label style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '12px', color: 'var(--text-secondary)' }}>
                  <Maximize size={14} /> Neck (cm)
                </label>
                <input type="number" value={neck} onChange={(e) => setNeck(e.target.value)} placeholder="e.g. 38" />
              </div>
            </div>

            <div className="responsive-grid">
              <div className="input-group">
                <label style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '12px', color: 'var(--text-secondary)' }}>
                  <Activity size={14} /> Biceps (cm)
                </label>
                <input type="number" value={biceps} onChange={(e) => setBiceps(e.target.value)} placeholder="e.g. 35" />
              </div>
              <div className="input-group">
                <label style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '12px', color: 'var(--text-secondary)' }}>
                  <Activity size={14} /> Thighs (cm)
                </label>
                <input type="number" value={thighs} onChange={(e) => setThighs(e.target.value)} placeholder="e.g. 55" />
              </div>
            </div>

            <div className="input-group" style={{ marginTop: '5px', paddingTop: '15px', borderTop: '1px solid rgba(255,255,255,0.05)' }}>
              <label style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '12px', color: 'var(--text-secondary)' }}>
                <Key size={14} /> Intelligence API Key
              </label>
              <input
                type="password"
                value={apiKey}
                onChange={(e) => setApiKey(e.target.value)}
                placeholder="Google AI Console Key"
                style={{ background: 'rgba(255,255,255,0.02)' }}
              />
            </div>
          </div>
        </div>

        <div className="glass" style={{ padding: '25px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '20px' }}>
            <Database size={20} className="premium-gradient-text" />
            <h2 style={{ fontSize: '18px' }}>Vault Management</h2>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '15px' }}>
            <button className="btn-secondary" onClick={handleExport} style={{ gap: '8px', padding: '15px' }}>
              <Download size={18} /> Export
            </button>
            <div style={{ position: 'relative' }}>
              <button className="btn-secondary" style={{ width: '100%', gap: '8px', padding: '15px' }}>
                <Upload size={18} /> Import
              </button>
              <input type="file" accept=".json" onChange={handleImport} style={{ position: 'absolute', top: 0, left: 0, width: '100%', height: '100%', opacity: 0, cursor: 'pointer' }} />
            </div>
          </div>
        </div>

        {showHistory && (
          <Modal
            isOpen={true}
            onClose={() => setShowHistory(false)}
            title="Biometric History"
            subtitle="Track your evolution over time."
            maxWidth="600px"
          >
            {biometricLog.length === 0 ? (
              <div style={{ textAlign: 'center', padding: '30px', color: 'var(--text-secondary)' }}>
                No history yet. Start tracking your measurements!
              </div>
            ) : (
              <div style={{ overflowX: 'auto' }}>
                <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '13px' }}>
                  <thead>
                    <tr style={{ borderBottom: '1px solid rgba(255,255,255,0.1)', textAlign: 'left', color: 'var(--text-secondary)' }}>
                      <th style={{ padding: '10px' }}>Date</th>
                      <th style={{ padding: '10px' }}>Weight</th>
                      <th style={{ padding: '10px' }}>Body Fat</th>
                      <th style={{ padding: '10px' }}>Waist</th>
                      <th style={{ padding: '10px' }}>Neck</th>
                    </tr>
                  </thead>
                  <tbody>
                    {biometricLog.map((log, index) => (
                      <tr key={index} style={{ borderBottom: '1px solid rgba(255,255,255,0.05)' }}>
                        <td style={{ padding: '12px 10px' }}>{log.date}</td>
                        <td style={{ padding: '12px 10px' }}>{log.weight ? `${log.weight}kg` : '-'}</td>
                        <td style={{ padding: '12px 10px' }}>{log.bodyFat ? `${log.bodyFat}%` : '-'}</td>
                        <td style={{ padding: '12px 10px' }}>{log.waist ? `${log.waist}cm` : '-'}</td>
                        <td style={{ padding: '12px 10px' }}>{log.neck ? `${log.neck}cm` : '-'}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </Modal>
        )}
      </div>
    </div>
  );
};

export default Profile;
