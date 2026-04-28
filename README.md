# Strive - Premium Fitness Training Engine ⚡🏆

Strive is a high-performance, intelligent training application designed for athletes who demand more than just a digital logbook. It combines modern UI aesthetics with a powerful intelligence engine to provide real-time coaching, telemetry, and progress calibration.

## 🚀 Fully Implemented Features

### 💎 Premium Experience & UI
- [x] **Glassmorphism Design System**: A state-of-the-art dark theme with vibrant gradients and subtle micro-animations.
- [x] **Mobile-First Responsiveness**: Every modal and form is optimized for one-handed use in the gym, featuring bottom sheets on mobile and centered glass cards on desktop.
- [x] **PWA (Installable App)**: Fully configured Progressive Web App. Install Strive directly to your home screen for a native, full-screen experience without browser chrome.
- [x] **Interactive Navigation**: Seamless transitions between the Dashboard, Training, Exercise Library, and Profile.

### 🧠 Strive Intelligence Engine
- [x] **Goal-Oriented Suggestions**: Select your path (**Build Muscle**, **Build Strength**, or **Maintenance**). The engine mathematically adapts weight and rep suggestions based on your objective.
- [x] **Strength Test (Evolution Mode)**: A dynamic "Big 5" testing battery (Bench, Squat, Pull-up, overhead Press, Deadlift). It evolves based on your power level, using bodyweight-proportional starting loads and RIR-based ramping.
- [x] **Smart 1RM Estimation**: Real-time calculation of your estimated One-Rep Max using the Brzycki formula, updating instantly as you log sets.
- [x] **Reps in Reserve (RIR) Calibration**: The app learns your proximity to failure to fine-tune future suggestions.

### ⏱️ Session Telemetry & Logging
- [x] **Dual Real-Time Timers**: Concurrent tracking of **Rest Time** (between sets) and **Total Session Duration**.
- [x] **Categorized Session Logs**: Sets are automatically grouped by exercise, showing you your latest results at the top for immediate context.
- [x] **Form & Performance Tracking**: Log the quality of your form (Clean, Grinded, Failure) for every set.
- [x] **Smart Auto-fill**: Intelligent memory system that suggests weights and reps based on your chosen goal and historical data.

### 💾 Data Integrity & Privacy
- [x] **100% Local Storage**: Your data never leaves your device. Total privacy by design.
- [x] **Versioned JSON Backups (v1.1)**: Export your entire training history, metrics, and routines into a structured JSON file.
- [x] **Migration Layer**: Future-proof import logic that handles older data formats and ensures your history survives app updates.
- [x] **Comprehensive Metrics**: Track Height, Weight, and Birth Date to feed the Strive Engine's calibration.

## 🚧 Partially Implemented
- [/] **Recent Activity Feed**: The dashboard feed is interactive and allows deletion/viewing, but detailed line-charts for specific exercise progress are still in the lab.
- [/] **Routine Management**: You can create, edit, and start routines. Advanced planning features like split-cycles (PPL, Upper/Lower) are currently basic.

## 📅 Future Roadmap
- [ ] **Volume Analytics**: Detailed heatmaps and weekly volume tracking per muscle group.
- [ ] **Personal Best Celebrations**: Visual rewards for hitting new estimated 1RMs.
- [ ] **Strength Benchmarks**: Comparison of your current strength against athletic standards (Beginner, Intermediate, Elite).

---

### 🛠️ Technical Stack
- **Core**: React 19 + Vite
- **State**: React Hooks (Custom useHistory, useExercises, useRoutines)
- **Logic**: Strive Engine (Brzycki estimation + Progressive Overload logic)
- **Styling**: Vanilla CSS (Premium Glassmorphism System)
- **Deployment**: GitHub Actions + GitHub Pages (Automated CI/CD)
