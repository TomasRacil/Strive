import React, { useState } from 'react';
import { Plus, X, ListPlus, ChevronDown, ChevronUp, Move, Upload, Image as ImageIcon } from 'lucide-react';
import CustomSelect from './CustomSelect';
import { useDialog } from '../context/DialogContext';

const ExerciseForm = ({ initialData, onSubmit }) => {
  const { showAlert } = useDialog();
  const [name, setName] = useState(initialData?.name || '');
  const [type, setType] = useState(initialData?.type || 'weight_only');
  const [muscles, setMuscles] = useState(initialData?.muscles || [{ name: '', engagement: 100 }]);
  const [forms, setForms] = useState(
    initialData?.forms?.map(f => {
      if (typeof f === 'string') return { name: f, cues: [], hasVisualization: false, customImage: '' };
      return {
        ...f,
        hasVisualization: f.hasVisualization ?? !!f.tutorialId,
        customImage: f.customImage || ''
      };
    }) ||
    [{ name: 'Strict', cues: [], hasVisualization: false, customImage: '' }]
  );
  const [expandedForm, setExpandedForm] = useState(null);
  const [newFormName, setNewFormName] = useState('');

  const addMuscle = () => setMuscles([...muscles, { name: '', engagement: 0 }]);
  const removeMuscle = (index) => setMuscles(muscles.filter((_, i) => i !== index));

  const updateMuscle = (index, field, value) => {
    const updated = [...muscles];
    updated[index][field] = field === 'engagement' ? parseInt(value) || 0 : value;
    setMuscles(updated);
  };

  const handleImageUpload = (formIndex, e) => {
    const file = e.target.files[0];
    if (file) {
      if (file.size > 1024 * 1024) {
        showAlert('Error', 'Image too large. Please keep it under 1MB.');
        return;
      }
      const reader = new FileReader();
      reader.onloadend = () => {
        const updated = [...forms];
        updated[formIndex].customImage = reader.result;
        updated[formIndex].hasVisualization = true;
        setForms(updated);
      };
      reader.readAsDataURL(file);
    }
  };

  const addForm = () => {
    if (newFormName && !forms.find(f => f.name === newFormName)) {
      setForms([...forms, { name: newFormName, cues: [], hasVisualization: false, customImage: '' }]);
      setNewFormName('');
    }
  };

  const updateForm = (index, field, value) => {
    const updated = [...forms];
    updated[index][field] = value;
    setForms(updated);
  };

  const addCue = (formIndex, cue) => {
    if (!cue) return;
    const updated = [...forms];
    updated[formIndex].cues = [...(updated[formIndex].cues || []), cue];
    setForms(updated);
  };

  const removeCue = (formIndex, cueIndex) => {
    const updated = [...forms];
    updated[formIndex].cues = updated[formIndex].cues.filter((_, i) => i !== cueIndex);
    setForms(updated);
  };

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

      <div className="glass" style={{ padding: '20px', borderRadius: '15px' }}>
        <label style={{ display: 'block', marginBottom: '15px', fontSize: '14px', fontWeight: '700' }}>Muscles & Engagement</label>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
          {muscles.map((m, i) => (
            <div key={i} style={{ display: 'flex', gap: '10px', alignItems: 'center' }}>
              <input
                type="text"
                placeholder="Muscle"
                style={{ flex: 2, padding: '12px' }}
                value={m.name}
                onChange={(e) => updateMuscle(i, 'name', e.target.value)}
              />
              <div style={{ flex: 1, position: 'relative', display: 'flex', alignItems: 'center' }}>
                <input
                  type="number"
                  placeholder="%"
                  style={{ width: '100%', padding: '12px' }}
                  value={m.engagement}
                  onChange={(e) => updateMuscle(i, 'engagement', e.target.value)}
                />
                <span style={{ position: 'absolute', right: '12px', fontSize: '12px', color: 'var(--text-secondary)' }}>%</span>
              </div>
              {muscles.length > 1 && (
                <button type="button" onClick={() => removeMuscle(i)} style={{ background: 'none', border: 'none', color: '#ef4444' }}>
                  <X size={18} />
                </button>
              )}
            </div>
          ))}
          <button type="button" className="btn-secondary" onClick={addMuscle} style={{ padding: '10px', fontSize: '13px', border: '1px dashed var(--glass-border)' }}>
            <Plus size={16} /> Add Muscle Component
          </button>
        </div>
      </div>

      <div className="glass" style={{ padding: '20px', borderRadius: '15px' }}>
        <label style={{ display: 'block', marginBottom: '15px', fontSize: '14px', fontWeight: '700' }}>Technical Forms & Guides</label>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
          {forms.map((f, i) => (
            <div key={i} className="glass" style={{ background: 'rgba(255,255,255,0.03)', borderRadius: '12px', overflow: 'hidden' }}>
              <div
                onClick={() => setExpandedForm(expandedForm === i ? null : i)}
                style={{ padding: '12px 15px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: 'pointer' }}
              >
                <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                  <Move size={16} className="premium-gradient-text" />
                  <span style={{ fontWeight: '600', fontSize: '14px' }}>{f.name}</span>
                </div>
                <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                  {f.hasVisualization && <ImageIcon size={14} className="premium-gradient-text" />}
                  {expandedForm === i ? <ChevronUp size={18} /> : <ChevronDown size={18} />}
                </div>
              </div>

              {expandedForm === i && (
                <div style={{ padding: '15px', borderTop: '1px solid var(--glass-border)', display: 'flex', flexDirection: 'column', gap: '15px' }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <div className="input-group" style={{ flex: 1 }}>
                      <label style={{ fontSize: '11px', color: 'var(--text-secondary)' }}>Form Name</label>
                      <input
                        type="text"
                        value={f.name}
                        onChange={(e) => updateForm(i, 'name', e.target.value)}
                        style={{ background: 'rgba(255,255,255,0.05)' }}
                      />
                    </div>
                    <label style={{ marginLeft: '15px', display: 'flex', alignItems: 'center', gap: '8px', cursor: 'pointer', fontSize: '12px' }}>
                      <input
                        type="checkbox"
                        checked={f.hasVisualization}
                        onChange={(e) => updateForm(i, 'hasVisualization', e.target.checked)}
                      />
                      Active Visualization
                    </label>
                  </div>

                  {/* Form Specific Image Upload */}
                  <div style={{ display: 'flex', alignItems: 'center', gap: '12px', background: 'rgba(255,255,255,0.02)', padding: '10px', borderRadius: '10px' }}>
                    <div className="glass" style={{ width: '50px', height: '50px', borderRadius: '8px', overflow: 'hidden', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                      {f.customImage ? (
                        <img src={f.customImage} alt="Form Preview" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                      ) : (
                        <ImageIcon size={20} opacity={0.2} />
                      )}
                    </div>
                    <div style={{ flex: 1 }}>
                      <label style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '11px', color: 'var(--primary-color)', cursor: 'pointer' }}>
                        <Upload size={14} /> Upload Custom Guide
                        <input type="file" accept="image/*" onChange={(e) => handleImageUpload(i, e)} style={{ display: 'none' }} />
                      </label>
                      {f.customImage && (
                        <button type="button" onClick={() => updateForm(i, 'customImage', '')} style={{ background: 'none', border: 'none', color: '#ef4444', fontSize: '10px', marginTop: '4px' }}>
                          Remove
                        </button>
                      )}
                    </div>
                  </div>

                  <div>
                    <label style={{ fontSize: '11px', color: 'var(--text-secondary)', display: 'block', marginBottom: '8px' }}>Technique Cues</label>
                    <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px', marginBottom: '10px' }}>
                      {f.cues?.map((cue, ci) => (
                        <span key={ci} style={{ fontSize: '11px', padding: '4px 10px', borderRadius: '20px', background: 'var(--primary-color)', color: 'white', display: 'flex', alignItems: 'center', gap: '6px' }}>
                          {cue} <X size={12} style={{ cursor: 'pointer' }} onClick={() => removeCue(i, ci)} />
                        </span>
                      ))}
                    </div>
                    <div style={{ display: 'flex', gap: '8px' }}>
                      <input
                        type="text"
                        placeholder="Add cue..."
                        style={{ fontSize: '12px', padding: '8px' }}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter') {
                            e.preventDefault();
                            addCue(i, e.target.value);
                            e.target.value = '';
                          }
                        }}
                      />
                    </div>
                  </div>

                  <button
                    type="button"
                    onClick={() => setForms(forms.filter((_, fi) => fi !== i))}
                    style={{ color: '#ef4444', fontSize: '12px', background: 'none', border: 'none', textAlign: 'left', padding: '0', marginTop: '5px' }}
                  >
                    Remove Form Variant
                  </button>
                </div>
              )}
            </div>
          ))}

          <div style={{ display: 'flex', gap: '10px', marginTop: '5px' }}>
            <input
              type="text"
              placeholder="New variant name..."
              value={newFormName}
              onChange={(e) => setNewFormName(e.target.value)}
              style={{ flex: 1 }}
            />
            <button type="button" className="btn-secondary" style={{ padding: '0 15px' }} onClick={addForm}>
              <ListPlus size={18} />
            </button>
          </div>
        </div>
      </div>

      <button type="submit" className="btn-primary" style={{ marginTop: '10px', padding: '18px', fontWeight: '800', letterSpacing: '1px' }}>
        {initialData ? 'UPDATE CONFIGURATION' : 'INITIALIZE EXERCISE'}
      </button>
    </form>
  );
};

export default ExerciseForm;
