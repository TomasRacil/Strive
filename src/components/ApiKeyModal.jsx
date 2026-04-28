import React, { useState } from 'react';
import { Key, User, Weight, Users, Calendar, Ruler, Activity, Droplet } from 'lucide-react';
import Modal from './Modal';
import CustomSelect from './CustomSelect';

const ApiKeyModal = ({ onSave, onSkip }) => {
  const [key, setKey] = useState(localStorage.getItem('strive_api_key') || '');
  const [weight, setWeight] = useState(localStorage.getItem('strive_weight') || '');
  const [sex, setSex] = useState(localStorage.getItem('strive_sex') || '');
  const [birthDate, setBirthDate] = useState(localStorage.getItem('strive_birth_date') || '');
  const [height, setHeight] = useState(localStorage.getItem('strive_height') || '');
  const [bodyFat, setBodyFat] = useState(localStorage.getItem('strive_body_fat') || '');
  const [muscleMass, setMuscleMass] = useState(localStorage.getItem('strive_muscle_mass') || '');

  const handleSave = () => {
    onSave({ key, weight, sex, birthDate, height, bodyFat, muscleMass });
  };

  return (
    <Modal 
      isOpen={true} 
      onClose={onSkip}
      title="Intelligence Setup"
      subtitle="Calibration & Core"
      maxWidth="500px"
    >
      <div style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
        <div style={{ textAlign: 'center', marginBottom: '10px' }}>
          <p style={{ color: 'var(--text-secondary)', fontSize: '13px' }}>
            To unlock intelligent load suggestions and accurate calibration, we need some basic environment data.
          </p>
        </div>

        <div className="input-group">
          <label style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '12px', color: 'var(--text-secondary)' }}>
            <Key size={14} /> Intelligence API Key
          </label>
          <input
            type="password"
            placeholder="AI Console API Key (Optional)"
            value={key}
            onChange={(e) => setKey(e.target.value)}
            style={{ background: 'rgba(255,255,255,0.02)' }}
          />
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '15px' }}>
          <div className="input-group">
            <label style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '12px', color: 'var(--text-secondary)' }}>
              <Weight size={14} /> Weight (kg) *
            </label>
            <input
              type="number"
              placeholder="75"
              value={weight}
              onChange={(e) => setWeight(e.target.value)}
            />
          </div>
          <div className="input-group">
            <label style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '12px', color: 'var(--text-secondary)' }}>
              <Ruler size={14} /> Height (cm) *
            </label>
            <input
              type="number"
              placeholder="180"
              value={height}
              onChange={(e) => setHeight(e.target.value)}
            />
          </div>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '15px' }}>
          <CustomSelect 
            label={<span style={{ display: 'flex', alignItems: 'center', gap: '8px' }}><Users size={14} /> Biological Sex *</span>}
            value={sex}
            onChange={setSex}
            options={[
              { value: 'male', label: 'Male' },
              { value: 'female', label: 'Female' },
              { value: 'other', label: 'Other' }
            ]}
          />
          <div className="input-group">
            <label style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '12px', color: 'var(--text-secondary)' }}>
              <Calendar size={14} /> Birth Date *
            </label>
            <input
              type="date"
              value={birthDate}
              onChange={(e) => setBirthDate(e.target.value)}
              style={{ colorScheme: 'dark' }}
            />
          </div>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '15px' }}>
          <div className="input-group">
            <label style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '12px', color: 'var(--text-secondary)' }}>
              <Droplet size={14} /> Body Fat % (Optional)
            </label>
            <input
              type="number"
              placeholder="e.g. 15"
              value={bodyFat}
              onChange={(e) => setBodyFat(e.target.value)}
            />
          </div>
          <div className="input-group">
            <label style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '12px', color: 'var(--text-secondary)' }}>
              <Activity size={14} /> Muscle Mass % (Optional)
            </label>
            <input
              type="number"
              placeholder="e.g. 45"
              value={muscleMass}
              onChange={(e) => setMuscleMass(e.target.value)}
            />
          </div>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: '10px', marginTop: '10px' }}>
          <button 
            className="btn-primary" 
            onClick={handleSave}
            disabled={!weight || !sex || !birthDate || !height}
            style={{ padding: '15px', opacity: (!weight || !sex || !birthDate || !height) ? 0.5 : 1 }}
          >
            Finalize Calibration
          </button>
          <button className="btn-secondary" onClick={onSkip} style={{ fontSize: '12px', border: 'none', background: 'none' }}>
            Skip setup for now
          </button>
        </div>
      </div>
    </Modal>
  );
};

export default ApiKeyModal;
