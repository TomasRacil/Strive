import React, { useState, useEffect } from 'react';
import Navigation from './components/Navigation';
import Dashboard from './pages/Dashboard';
import Training from './pages/Training';
import Profile from './pages/Profile';
import Exercises from './pages/Exercises';
import ApiKeyModal from './components/ApiKeyModal';
import './index.css';

function App() {
  const [activeTab, setActiveTab] = useState('dashboard');
  const [apiKey, setApiKey] = useState(localStorage.getItem('strive_api_key') || '');
  const [showApiModal, setShowApiModal] = useState(!localStorage.getItem('strive_api_key'));
  const [activeSession, setActiveSession] = useState(false);

  const handleSaveApiKey = (key) => {
    localStorage.setItem('strive_api_key', key);
    setApiKey(key);
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
    <div className="app-wrapper">
      {renderView()}
      {!activeSession && (
        <Navigation activeTab={activeTab} setActiveTab={setActiveTab} />
      )}
      {showApiModal && <ApiKeyModal onSave={handleSaveApiKey} onSkip={() => setShowApiModal(false)} />}
    </div>
  );
}

export default App;
