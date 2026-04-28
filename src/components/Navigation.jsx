import React from 'react';
import { LayoutDashboard, Dumbbell, User, List } from 'lucide-react';

const Navigation = ({ activeTab, setActiveTab }) => {
  const tabs = [
    { id: 'dashboard', label: 'Home', icon: LayoutDashboard },
    { id: 'training', label: 'Train', icon: Dumbbell },
    { id: 'exercises', label: 'Library', icon: List },
    { id: 'profile', label: 'Profile', icon: User },
  ];

  return (
    <nav className="fixed-bottom-nav">
      {tabs.map((tab) => {
        const Icon = tab.icon;
        const isActive = activeTab === tab.id;
        return (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            className={`nav-item ${isActive ? 'active' : ''}`}
          >
            <Icon size={24} color={isActive ? 'var(--primary-color)' : 'var(--text-secondary)'} />
            <span className={isActive ? 'premium-gradient-text' : ''}>{tab.label}</span>
          </button>
        );
      })}
    </nav>
  );
};

export default Navigation;

// Add styles to index.css for this component
