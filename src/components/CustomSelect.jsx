import React, { useState, useRef, useEffect } from 'react';
import { ChevronDown } from 'lucide-react';

const CustomSelect = ({ value, onChange, options, label, disabled = false }) => {
  const [isOpen, setIsOpen] = useState(false);
  const selectRef = useRef(null);

  const selectedOption = options.find(opt => opt.value === value);

  useEffect(() => {
    const handleClickOutside = (event) => {
      if (selectRef.current && !selectRef.current.contains(event.target)) {
        setIsOpen(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  return (
    <div className="custom-select-container" ref={selectRef} style={{ opacity: disabled ? 0.6 : 1, pointerEvents: disabled ? 'none' : 'auto' }}>
      {label && <label style={{ fontSize: '12px', color: 'var(--text-secondary)', marginBottom: '8px', display: 'block' }}>{label}</label>}
      <div 
        className="glass custom-select-header" 
        onClick={() => !disabled && setIsOpen(!isOpen)}
        style={{ 
          padding: '12px 15px', 
          display: 'flex', 
          justifyContent: 'space-between', 
          alignItems: 'center',
          cursor: disabled ? 'not-allowed' : 'pointer',
          border: isOpen ? '1px solid var(--primary-color)' : '1px solid var(--glass-border)',
          background: disabled ? 'rgba(255,255,255,0.02)' : 'var(--glass-bg)'
        }}
      >
        <span style={{ fontSize: '14px', fontWeight: '500' }}>{selectedOption ? selectedOption.label : 'Select option'}</span>
        {!disabled && <ChevronDown size={18} style={{ transform: isOpen ? 'rotate(180deg)' : 'rotate(0deg)', transition: 'transform 0.3s' }} />}
      </div>

      {isOpen && !disabled && (
        <div className="dropdown-glass custom-select-options fade-in" style={{ 
          position: 'absolute', 
          top: '100%', 
          left: 0, 
          right: 0, 
          marginTop: '8px',
          zIndex: 100,
          maxHeight: '200px',
          overflowY: 'auto',
          borderRadius: '12px',
          overflow: 'hidden'
        }}>
          {options.map(option => (
            <div 
              key={option.value}
              className="custom-option"
              onClick={() => {
                onChange(option.value);
                setIsOpen(false);
              }}
              style={{ 
                padding: '12px 15px',
                cursor: 'pointer',
                fontSize: '13px',
                background: value === option.value ? 'rgba(59, 130, 246, 0.1)' : 'transparent',
                borderBottom: '1px solid var(--glass-border)',
                transition: 'all 0.2s'
              }}
            >
              {option.label}
            </div>
          ))}
        </div>
      )}
    </div>
  );
};

export default CustomSelect;
