import React, { useState } from 'react';
import { Plus, X, ListPlus } from 'lucide-react';
import CustomSelect from './CustomSelect';

const ExerciseForm = ({ initialData, onSubmit }) => {
  const [name, setName] = useState(initialData?.name || '');
  const [type, setType] = useState(initialData?.type || 'weight_only');
  const [muscles, setMuscles] = useState(initialData?.muscles || [{ name: '', engagement: 100 }]);
  const [forms, setForms] = useState(initialData?.forms || ['Strict']);
  const [newForm, setNewForm] = useState('');

  const addMuscle = () => setMuscles([...muscles, { name: '', engagement: 0 }]);
  const removeMuscle = (index) => setMuscles(muscles.filter((_, i) => i !== index));
  
  const updateMuscle = (index, field, value) => {
    const updated = [...muscles];
    updated[index][field] = field === 'engagement' ? parseInt(value) || 0 : value;
    setMuscles(updated);
  };

  const addForm = () => {
    if (newForm && !forms.includes(newForm)) {
      setForms([...forms, newForm]);
      setNewForm('');
    }
  };

  const removeForm = (f) => setForms(forms.filter(item => item !== f));

  const handleSubmit = (e) => {
    e.preventDefault();
    if (!name || muscles.some(m => !m.name)) return;
    onSubmit({ name, type, muscles, forms });
  };

  return (
    <form style={{ display: 'flex', flexDirection: 'column', gap: '20px' }} onSubmit={handleSubmit}>
      <div className="input-group">
        <label style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>Exercise Name</label>
        <input 
          type="text" 
          placeholder="e.g. Incline DB Press" 
          value={name}
          onChange={(e) => setName(e.target.value)}
          required
        />
      </div>

      <CustomSelect 
        label="Load Type"
        value={type}
        onChange={setType}
        options={[
          { value: 'weight_only', label: 'Weight Only' },
          { value: 'bodyweight_plus_weight', label: 'Bodyweight + Added Weight' },
          { value: 'bodyweight_only', label: 'Bodyweight Only' }
        ]}
      />

      <div>
        <label style={{ display: 'block', marginBottom: '10px', fontSize: '12px', color: 'var(--text-secondary)' }}>Targeted Muscles & Engagement (%)</label>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
          {muscles.map((m, i) => (
            <div key={i} style={{ display: 'flex', gap: '10px', alignItems: 'center' }}>
              <input 
                type="text" 
                placeholder="Muscle" 
                style={{ flex: 2 }}
                value={m.name}
                onChange={(e) => updateMuscle(i, 'name', e.target.value)}
              />
              <input 
                type="number" 
                placeholder="%" 
                style={{ flex: 1 }}
                value={m.engagement}
                onChange={(e) => updateMuscle(i, 'engagement', e.target.value)}
              />
              {muscles.length > 1 && (
                <button type="button" onClick={() => removeMuscle(i)} style={{ background: 'none', border: 'none', color: '#ef4444' }}>
                  <X size={18} />
                </button>
              )}
            </div>
          ))}
          <button type="button" className="btn-secondary" onClick={addMuscle} style={{ padding: '10px', fontSize: '14px', borderRadius: '12px' }}>
            <Plus size={16} /> Add Muscle
          </button>
        </div>
      </div>

      <div>
        <label style={{ display: 'block', marginBottom: '10px', fontSize: '12px', color: 'var(--text-secondary)' }}>Exercise Forms</label>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: '8px', marginBottom: '10px' }}>
          {forms.map(f => (
            <span key={f} className="glass" style={{ padding: '6px 12px', fontSize: '12px', display: 'flex', alignItems: 'center', gap: '8px', borderRadius: '10px' }}>
              {f} <X size={14} style={{ cursor: 'pointer', color: '#ef4444' }} onClick={() => removeForm(f)} />
            </span>
          ))}
        </div>
        <div style={{ display: 'flex', gap: '10px' }}>
          <input 
            type="text" 
            placeholder="New form (e.g. Paused)" 
            style={{ flex: 1 }}
            value={newForm}
            onChange={(e) => setNewForm(e.target.value)}
          />
          <button type="button" className="btn-secondary" style={{ padding: '10px', minWidth: '45px' }} onClick={addForm}>
            <ListPlus size={18} />
          </button>
        </div>
      </div>

      <button type="submit" className="btn-primary" style={{ marginTop: '10px', padding: '15px' }}>
        {initialData ? 'Update Exercise' : 'Save Exercise'}
      </button>
    </form>
  );
};

export default ExerciseForm;
