import React, { useEffect } from 'react';
import { createPortal } from 'react-dom';
import { X } from 'lucide-react';

const Modal = ({ isOpen, onClose, title, subtitle, children, maxWidth = '500px', headerActions, footer }) => {
  useEffect(() => {
    if (isOpen) {
      document.body.style.overflow = 'hidden';
      // Optional: Add a class to body to handle pointer events if needed
      // document.body.style.pointerEvents = 'none'; // This would block everything including the modal
    } else {
      document.body.style.overflow = 'unset';
    }
    return () => { document.body.style.overflow = 'unset'; };
  }, [isOpen]);

  if (!isOpen) return null;

  return createPortal(
    <div className="modal-overlay" style={{ 
      position: 'fixed',
      top: 0,
      left: 0,
      right: 0,
      bottom: 0,
      background: 'rgba(0, 0, 0, 0.5)',
      backdropFilter: 'blur(12px)',
      display: 'flex',
      alignItems: 'flex-start', // Better for tall modals
      justifyContent: 'center',
      zIndex: 10000,
      padding: '40px 20px', // Vertical padding for mobile
      pointerEvents: 'auto',
      overflowY: 'auto' // Allow overlay to scroll if modal is too tall
    }} onClick={onClose}>
      <div className="glass modal-content fade-in" style={{ 
        maxWidth: maxWidth, 
        width: '100%', 
        margin: 'auto',
        padding: '0', 
        overflow: 'hidden',
        maxHeight: '90vh', // Contain within viewport
        display: 'flex',
        flexDirection: 'column',
        boxShadow: '0 25px 50px -12px rgba(0, 0, 0, 0.6)',
        pointerEvents: 'auto'
      }} onClick={e => e.stopPropagation()}>
        
        {/* Header */}
        <header style={{ 
          padding: '20px 25px', 
          display: 'flex', 
          justifyContent: 'space-between', 
          alignItems: 'center',
          background: 'rgba(255,255,255,0.03)',
          borderBottom: '1px solid var(--glass-border)'
        }}>
          <div style={{ flex: 1 }}>
            <h2 style={{ fontSize: '20px', fontWeight: '800', margin: 0 }}>{title}</h2>
            {subtitle && (
              <span style={{ fontSize: '11px', color: 'var(--text-secondary)', textTransform: 'uppercase', letterSpacing: '1px', fontWeight: '600' }}>
                {subtitle}
              </span>
            )}
          </div>
          
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            {headerActions}
            <button 
              onClick={onClose} 
              className="glass"
              style={{ 
                border: 'none', 
                color: 'var(--text-secondary)', 
                cursor: 'pointer',
                width: '36px',
                height: '36px',
                borderRadius: '50%',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                transition: 'all 0.2s'
              }}
            >
              <X size={20} />
            </button>
          </div>
        </header>

        {/* Content */}
        <div style={{ 
          padding: '25px', 
          overflowY: 'auto',
          flex: 1,
          WebkitOverflowScrolling: 'touch' // Smooth scroll on iOS
        }}>
          {children}
        </div>

        {/* Footer */}
        {footer && (
          <footer style={{ 
            padding: '20px 25px',
            background: 'rgba(255,255,255,0.03)',
            borderTop: '1px solid var(--glass-border)',
            display: 'flex',
            justifyContent: 'flex-end',
            gap: '12px'
          }}>
            {footer}
          </footer>
        )}
      </div>
    </div>,
    document.body
  );
};

export default Modal;
