import { useMemo } from 'react';
import { X, TrendingUp } from 'lucide-react';
import { estimate1RM } from '../utils/engine';
import { exerciseProgress } from '../utils/stats';

/**
 * Estimated 1RM per session for one exercise, oldest to newest.
 * Progress is shown as an e1RM trend rather than raw top-set weight, because
 * raw weight hides rep progress (100x8 -> 100x12 is a real gain).
 */
const ExerciseProgressModal = ({ exercise, history, onClose }) => {
  const points = useMemo(
    () => exerciseProgress(history, exercise.id, set => estimate1RM(set.weight, set.reps, set.rir)),
    [history, exercise.id]
  );

  const W = 320;
  const H = 120;
  const PAD = 10;

  const chart = useMemo(() => {
    if (points.length === 0) return null;

    const values = points.map(p => p.value);
    const min = Math.min(...values);
    const max = Math.max(...values);
    const range = max - min || 1;

    const coords = points.map((point, index) => {
      const x = points.length === 1
        ? W / 2
        : PAD + (index / (points.length - 1)) * (W - PAD * 2);
      const y = H - PAD - ((point.value - min) / range) * (H - PAD * 2);
      return [Math.round(x), Math.round(y)];
    });

    return { min, max, coords };
  }, [points]);

  const first = points[0];
  const latest = points[points.length - 1];
  const delta = first && latest ? latest.value - first.value : 0;

  return (
    <div className="modal-overlay">
      <div className="glass modal-content fade-in">
        <header style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <TrendingUp size={20} className="premium-gradient-text" />
            <h2 style={{ fontSize: '18px', fontWeight: '700' }}>{exercise.name}</h2>
          </div>
          <button className="btn-secondary" style={{ padding: '8px', borderRadius: '50%' }} onClick={onClose}>
            <X size={18} />
          </button>
        </header>

        {points.length === 0 ? (
          <p style={{ color: 'var(--text-secondary)', fontSize: '14px', textAlign: 'center', padding: '30px 0' }}>
            No sessions logged for this exercise yet.
          </p>
        ) : (
          <>
            <div style={{ display: 'flex', gap: '20px', marginBottom: '20px' }}>
              <div>
                <div style={{ fontSize: '22px', fontWeight: '800' }}>{latest.value}<span style={{ fontSize: '12px' }}> kg</span></div>
                <div style={{ fontSize: '11px', color: 'var(--text-secondary)' }}>Estimated 1RM</div>
              </div>
              <div>
                <div style={{ fontSize: '22px', fontWeight: '800', color: delta > 0 ? '#22c55e' : delta < 0 ? '#ef4444' : 'inherit' }}>
                  {delta > 0 ? '+' : ''}{delta}<span style={{ fontSize: '12px' }}> kg</span>
                </div>
                <div style={{ fontSize: '11px', color: 'var(--text-secondary)' }}>Since first session</div>
              </div>
              <div>
                <div style={{ fontSize: '22px', fontWeight: '800' }}>{points.length}</div>
                <div style={{ fontSize: '11px', color: 'var(--text-secondary)' }}>Sessions</div>
              </div>
            </div>

            <svg viewBox={`0 0 ${W} ${H}`} width="100%" height={H} style={{ display: 'block' }}>
              <defs>
                <linearGradient id="progressFill" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor="#3b82f6" stopOpacity="0.35" />
                  <stop offset="100%" stopColor="#3b82f6" stopOpacity="0" />
                </linearGradient>
              </defs>

              {chart && (
                <>
                  <polygon
                    points={`${chart.coords[0][0]},${H} ${chart.coords.map(c => c.join(',')).join(' ')} ${chart.coords[chart.coords.length - 1][0]},${H}`}
                    fill="url(#progressFill)"
                  />
                  <polyline
                    points={chart.coords.map(c => c.join(',')).join(' ')}
                    fill="none"
                    stroke="#3b82f6"
                    strokeWidth="2"
                    strokeLinejoin="round"
                    strokeLinecap="round"
                  />
                  {chart.coords.map(([x, y], index) => (
                    <circle key={index} cx={x} cy={y} r="2.5" fill="#8b5cf6" />
                  ))}
                </>
              )}
            </svg>

            <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '10px', color: 'var(--text-secondary)', marginTop: '6px' }}>
              <span>{new Date(first.date).toLocaleDateString()}</span>
              <span>Best: {chart?.max} kg</span>
              <span>{new Date(latest.date).toLocaleDateString()}</span>
            </div>

            <div className="glass" style={{ padding: '12px', marginTop: '18px', fontSize: '12px' }}>
              Latest session top set:{' '}
              <strong>{latest.weight} kg × {latest.reps}</strong>
            </div>
          </>
        )}
      </div>
    </div>
  );
};

export default ExerciseProgressModal;
