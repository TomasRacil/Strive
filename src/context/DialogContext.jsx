import React, { createContext, useContext, useState, useCallback } from 'react';
import { AlertCircle, CheckCircle2, Info, AlertTriangle, X, Check } from 'lucide-react';
import Modal from '../components/Modal';

const DialogContext = createContext(null);

export const useDialog = () => {
  const context = useContext(DialogContext);
  if (!context) {
    throw new Error('useDialog must be used within a DialogProvider');
  }
  return context;
};

export const DialogProvider = ({ children }) => {
  const [dialogConfig, setDialogConfig] = useState(null);

  const closeDialog = useCallback(() => {
    setDialogConfig(null);
  }, []);

  const showAlert = useCallback((title, message, type = 'info') => {
    setDialogConfig({
      type: 'alert',
      title,
      message,
      alertType: type,
      onConfirm: closeDialog
    });
  }, [closeDialog]);

  const showConfirm = useCallback((title, message, onConfirmCallback) => {
    setDialogConfig({
      type: 'confirm',
      title,
      message,
      onConfirm: () => {
        onConfirmCallback();
        closeDialog();
      },
      onCancel: closeDialog
    });
  }, [closeDialog]);

  const getIcon = (type) => {
    switch (type) {
      case 'success': return <CheckCircle2 size={24} color="#10b981" />;
      case 'error': return <AlertCircle size={24} color="#ef4444" />;
      case 'warning': return <AlertTriangle size={24} color="#f59e0b" />;
      default: return <Info size={24} color="var(--primary-color)" />;
    }
  };

  return (
    <DialogContext.Provider value={{ showAlert, showConfirm }}>
      {children}
      
      {dialogConfig && (
        <Modal
          isOpen={true}
          onClose={dialogConfig.type === 'alert' ? dialogConfig.onConfirm : dialogConfig.onCancel}
          title={dialogConfig.title}
          maxWidth="400px"
        >
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', padding: '10px 0' }}>
            {dialogConfig.type === 'alert' && (
              <div style={{ marginBottom: '15px' }}>
                {getIcon(dialogConfig.alertType)}
              </div>
            )}
            
            <p style={{ color: 'var(--text-secondary)', fontSize: '14px', lineHeight: '1.6', marginBottom: '25px' }}>
              {dialogConfig.message}
            </p>

            <div style={{ display: 'flex', gap: '10px', width: '100%', justifyContent: 'center' }}>
              {dialogConfig.type === 'confirm' ? (
                <>
                  <button 
                    className="btn-secondary" 
                    onClick={dialogConfig.onCancel}
                    style={{ flex: 1, padding: '12px' }}
                  >
                    <X size={16} /> Cancel
                  </button>
                  <button 
                    className="btn-primary" 
                    onClick={dialogConfig.onConfirm}
                    style={{ flex: 1, padding: '12px', background: 'linear-gradient(135deg, #ef4444, #b91c1c)' }}
                  >
                    <Check size={16} /> Confirm
                  </button>
                </>
              ) : (
                <button 
                  className="btn-primary" 
                  onClick={dialogConfig.onConfirm}
                  style={{ width: '100%', padding: '12px' }}
                >
                  Got it
                </button>
              )}
            </div>
          </div>
        </Modal>
      )}
    </DialogContext.Provider>
  );
};
