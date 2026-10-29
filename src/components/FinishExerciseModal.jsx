import { Save, Trash2, Star, X } from 'lucide-react';

/**
 * Two different questions get asked at two different moments:
 *  - mode="exercise": "what do I do with this exercise's sets?" (keep + template,
 *    keep, or discard before moving to the next lift)
 *  - mode="session": "what do I do with the whole workout?" (save or discard)
 *
 * These used to be one modal, so ending a session asked you to "Finish Bench
 * Press" and offered a template option that silently saved everything.
 */
const FinishExerciseModal = ({
  mode = 'exercise',
  onSaveWithTemplate,
  onSaveOnly,
  onDiscard,
  onCancel,
  exerciseName
}) => {
  const isSession = mode === 'session';

  return (
    <div className="modal-overlay">
      <div className="glass modal-content fade-in" style={{ textAlign: 'center' }}>
        <div style={{ display: 'flex', justifyContent: 'flex-end', marginBottom: '10px' }}>
          <button className="btn-secondary" style={{ padding: '8px', borderRadius: '50%' }} onClick={onCancel}>
            <X size={18} />
          </button>
        </div>

        <div style={{ marginBottom: '25px' }}>
          <h2 className="premium-gradient-text" style={{ fontSize: '22px', marginBottom: '10px' }}>
            {isSession ? 'Finish Session' : `Finish ${exerciseName || 'Exercise'}`}
          </h2>
          <p style={{ color: 'var(--text-secondary)', fontSize: '14px' }}>
            {isSession
              ? 'Save this workout to your history?'
              : 'Keep these sets and move on to the next exercise?'}
          </p>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
          {!isSession && (
            <button className="btn-primary" style={{ width: '100%', gap: '12px' }} onClick={onSaveWithTemplate}>
              <Star size={18} /> Keep & Set as Template
            </button>
          )}

          <button
            className={isSession ? 'btn-primary' : 'btn-secondary'}
            style={{ width: '100%', gap: '12px' }}
            onClick={onSaveOnly}
          >
            <Save size={18} /> {isSession ? 'Save Session' : 'Keep Sets'}
          </button>

          <button
            className="btn-secondary"
            style={{ width: '100%', gap: '12px', color: '#ef4444', borderColor: 'rgba(239, 68, 68, 0.2)' }}
            onClick={onDiscard}
          >
            <Trash2 size={18} /> {isSession ? 'Discard Session' : "Discard This Exercise's Sets"}
          </button>
        </div>
      </div>
    </div>
  );
};

export default FinishExerciseModal;
