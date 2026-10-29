import { useState } from 'react';
import Navigation from './components/Navigation';
import Dashboard from './pages/Dashboard';
import Training from './pages/Training';
import Profile from './pages/Profile';
import Exercises from './pages/Exercises';
import './index.css';

// If the app was closed mid-workout, come back to it instead of the dashboard.
const hasActiveSession = () => {
  try {
    const saved = JSON.parse(localStorage.getItem('strive_active_session') || 'null');
    return Boolean(saved && ((saved.sets?.length ?? 0) > 0 || saved.sessionStartTime));
  } catch {
    return false;
  }
};

function App() {
  const [activeTab, setActiveTab] = useState(() => (hasActiveSession() ? 'training' : 'dashboard'));
  const [activeSession, setActiveSession] = useState(hasActiveSession);

  const renderView = () => {
    switch (activeTab) {
      case 'dashboard':
        return <Dashboard setActiveTab={setActiveTab} />;
      case 'training':
        return <Training activeSession={activeSession} setActiveSession={setActiveSession} />;
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
    </div>
  );
}

export default App;
