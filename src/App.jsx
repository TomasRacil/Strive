import React, { useState, useEffect } from 'react';
import Navigation from './components/Navigation';
import Dashboard from './pages/Dashboard';
import Training from './pages/Training';
import Profile from './pages/Profile';
import Exercises from './pages/Exercises';
import ApiKeyModal from './components/ApiKeyModal';
import { DialogProvider } from './context/DialogContext';
import './index.css';

function App() {
  const [activeTab, setActiveTab] = useState('dashboard');
  const [apiKey, setApiKey] = useState(localStorage.getItem('strive_api_key') || '');
  
  // Check if setup is complete (Core biometrics are mandatory, API key is optional)
  const isSetupComplete = !!localStorage.getItem('strive_weight') && 
                          !!localStorage.getItem('strive_sex') &&
                          !!localStorage.getItem('strive_birth_date') &&
                          !!localStorage.getItem('strive_height');
                          
  const [showApiModal, setShowApiModal] = useState(!isSetupComplete);
  const [activeSession, setActiveSession] = useState(false);

  // Sync API key if changed in Profile
  useEffect(() => {
    const syncInterval = setInterval(() => {
      const storedKey = localStorage.getItem('strive_api_key') || '';
      if (storedKey !== apiKey) {
        setApiKey(storedKey);
      }
    }, 1000);
    return () => clearInterval(syncInterval);
  }, [apiKey]);

  const handleSaveSetup = ({ key, weight, sex, birthDate, height, bodyFat, muscleMass }) => {
    if (key) {
      localStorage.setItem('strive_api_key', key);
      setApiKey(key);
    }
    if (weight) localStorage.setItem('strive_weight', weight);
    if (sex) localStorage.setItem('strive_sex', sex);
    if (birthDate) localStorage.setItem('strive_birth_date', birthDate);
    if (height) localStorage.setItem('strive_height', height);
    if (bodyFat) localStorage.setItem('strive_body_fat', bodyFat);
    if (muscleMass) localStorage.setItem('strive_muscle_mass', muscleMass);
    
    setShowApiModal(false);
  };

  const renderView = () => {
    switch (activeTab) {
      case 'dashboard':
        return <Dashboard setActiveTab={setActiveTab} />;
      case 'training':
        return <Training apiKey={apiKey} activeSession={activeSession} setActiveSession={setActiveSession} />;
      case 'profile':
        return <Profile />;
      case 'exercises':
        return <Exercises />;
      default:
        return <Dashboard setActiveTab={setActiveTab} />;
    }
  };

  return (
    <DialogProvider>
      <div className="app-wrapper">
        {renderView()}
        {!activeSession && (
          <Navigation activeTab={activeTab} setActiveTab={setActiveTab} />
        )}
        {showApiModal && <ApiKeyModal onSave={handleSaveSetup} onSkip={() => setShowApiModal(false)} />}
      </div>
    </DialogProvider>
  );
}

export default App;
