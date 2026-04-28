import React, { useState } from 'react';
import { Key } from 'lucide-react';

const ApiKeyModal = ({ onSave, onSkip }) => {
  const [key, setKey] = useState('');

  return (
    <div className="modal-overlay">
      <div className="glass modal-content fade-in">
        <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
          <Key className="premium-gradient-text" size={32} />
          <h2 className="premium-gradient-text">Setup API Key</h2>
        </div>
        <p style={{ color: 'var(--text-secondary)', fontSize: '14px' }}>
          Enter your Google AI Console API key to unlock intelligent training features.
        </p>
        <div className="input-group">
          <input
            type="password"
            placeholder="AI Console API Key"
            value={key}
            onChange={(e) => setKey(e.target.value)}
          />
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
          <button className="btn-primary" onClick={() => onSave(key)}>
            Save & Continue
          </button>
          <button className="btn-secondary" onClick={onSkip}>
            Skip for now
          </button>
        </div>
      </div>
    </div>
  );
};

export default ApiKeyModal;
