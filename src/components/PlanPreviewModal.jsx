import { useMemo, useState } from 'react';
import { X, Target, Download, TrendingUp } from 'lucide-react';
import { buildSessionPlan, planToGarminRoutine, planVolume } from '../utils/plan.js';

const GOALS = [
  { id: 'build_muscle', label: 'Muscle' },
  { id: 'build_strength', label: 'Strength' },
  { id: 'maintain', label: 'Maintain' }
];

/**
 * Shows the next session with the load the engine recommends for each lift, and
 * exports it in the shape the Garmin bridge turns into a structured workout.
 * Garmin's strength app displays the planned weight but never chooses it.
 */
const PlanPreviewModal = ({ routine, history, onClose }) => {
  const [goal, setGoal] = useState('build_muscle');
  const [saved, setSaved] = useState(false);

  const plan = useMemo(
    () => buildSessionPlan(routine, history, goal),
    [routine, history, goal]
  );

  const tonnage = planVolume(plan);
  const weighted = plan.filter(item => item.weight).length;

  const handleDownload = () => {
    const payload = {
      version: '1.2',
      exported: new Date().toISOString(),
      goal,
      routines: [planToGarminRoutine(routine.name, plan)]
    };

    const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `strive_plan_${routine.name.toLowerCase().replace(/[^a-z0-9]+/g, '_')}.json`;
    a.click();
    URL.revokeObjectURL(url);

    setSaved(true);
  };

  return (
    <div className="modal-overlay">
      <div className="glass modal-content fade-in">
        <header style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '18px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <Target size={20} className="premium-gradient-text" />
            <div>
              <h2 style={{ fontSize: '18px', fontWeight: '700' }}>{routine.name}</h2>
              <p style={{ fontSize: '11px', color: 'var(--text-secondary)' }}>Next session with recommended loads</p>
            </div>
          </div>
          <button className="btn-secondary" style={{ padding: '8px', borderRadius: '50%' }} onClick={onClose}>
            <X size={18} />
          </button>
        </header>

        <div style={{ display: 'flex', gap: '8px', marginBottom: '18px' }}>
          {GOALS.map(option => (
            <button
              key={option.id}
              onClick={() => setGoal(option.id)}
              style={{
                flex: 1,
                padding: '9px',
                fontSize: '12px',
                borderRadius: '10px',
                cursor: 'pointer',
                background: goal === option.id ? 'var(--primary-color)' : 'var(--glass-bg)',
                border: `1px solid ${goal === option.id ? 'var(--primary-color)' : 'var(--glass-border)'}`,
                color: goal === option.id ? 'white' : 'var(--text-primary)',
                transition: 'all 0.2s ease'
              }}
            >
              {option.label}
            </button>
          ))}
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: '12px', maxHeight: '45vh', overflowY: 'auto' }}>
          {plan.map(item => (
            <div key={item.id} className="glass" style={{ padding: '14px', borderRadius: '14px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', gap: '10px' }}>
                <div style={{ fontSize: '14px', fontWeight: '600' }}>{item.name}</div>
                <div style={{ fontSize: '14px', fontWeight: '800', color: item.weight ? 'var(--primary-color)' : 'var(--text-secondary)' }}>
                  {item.weight ? `${item.weight} kg` : '—'}
                </div>
              </div>
              <div style={{ fontSize: '12px', color: 'var(--text-secondary)', marginTop: '4px' }}>
                {item.sets} × {item.reps} · rest {item.restSeconds}s
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: '5px', fontSize: '10px', color: 'var(--text-secondary)', marginTop: '6px' }}>
                <TrendingUp size={11} />
                {item.reason}
              </div>
            </div>
          ))}
        </div>

        <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '11px', color: 'var(--text-secondary)', margin: '16px 0' }}>
          <span>{weighted} of {plan.length} lifts have a target weight</span>
          {tonnage > 0 && <span>~{Math.round(tonnage).toLocaleString()} kg planned</span>}
        </div>

        <button className="btn-primary" style={{ width: '100%', gap: '10px' }} onClick={handleDownload}>
          <Download size={18} /> {saved ? 'Downloaded — push it with the bridge' : 'Download for Garmin'}
        </button>

        <p style={{ fontSize: '10px', color: 'var(--text-secondary)', marginTop: '14px', lineHeight: '1.6' }}>
          Garmin Connect cannot import workout files, so this goes to the watch through the
          bridge: <code>python garmin/bridge.py push &lt;file&gt;</code>. On the watch it runs as a
          structured strength workout, which is the only mode that shows a planned weight.
        </p>
      </div>
    </div>
  );
};

export default PlanPreviewModal;
