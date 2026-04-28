# Strive - Premium Fitness Training Engine ⚡🏆

Strive is a high-performance, intelligent training application designed for athletes who demand more than just a digital logbook. It combines modern UI aesthetics with a powerful intelligence engine to provide real-time coaching, telemetry, and progress calibration.

## 🚀 Fully Implemented Features

### 💎 Premium Experience & UI
- [x] **Glassmorphism Design System**: A state-of-the-art dark theme with vibrant gradients and subtle micro-animations.
- [x] **Universal Dialog System**: Replaced all browser alerts with a custom, glassmorphic `DialogContext` for a cohesive premium feel.
- [x] **Advanced Modal Architecture**: Standardized modals with sticky headers, scrollable internal content, and fixed footer action areas.
- [x] **Mobile-First Responsiveness**: Optimized for one-handed use. Features `100dvh` viewport handling and a floating-to-fixed responsive navigation system.
- [x] **PWA (Installable App)**: Fully configured Progressive Web App. Install Strive directly to your home screen for a native experience.

### 🧠 Strive Intelligence Engine
- [x] **Global Benchmark Calibration**: The "Big 5" benchmark tests (Squat, Bench, Deadlift, OHP, Row) now calibrate the entire app. Your starting weight for any exercise is estimated based on your primary muscle group strength.
- [x] **Goal-Oriented Progressions**: Specialized logic for **Build Muscle** (Hypertrophy focus), **Build Strength** (Power focus), and **Maintenance**.
- [x] **Phase Shift Logic**: Automatic detection of transitions (e.g., from low-rep benchmarks to high-volume training) with safe weight down-regulation.
- [x] **Smart 1RM Estimation**: Real-time calculation of your estimated One-Rep Max using the Brzycki formula.
- [x] **Reps in Reserve (RIR) Calibration**: Fine-tuning suggestions based on proximity to failure.

### ⏱️ Session Telemetry & Logging
- [x] **Dual Real-Time Timers**: Concurrent tracking of **Rest Time** and **Total Session Duration**.
- [x] **Categorized Session Logs**: Sets are automatically grouped by exercise with descriptive session naming (e.g., "Benchmark Test", "Free Training").
- [x] **Form & Performance Tracking**: Log form quality and technical cues for every set.
- [x] **Smart Auto-fill**: Intelligent memory system that prioritized specific history over global benchmarks.

### 💾 Data Integrity & Privacy
- [x] **100% Local Storage**: Your data never leaves your device. Total privacy by design.
- [x] **Full Vault Backups (v1.2)**: Export/Import entire training history, biometrics, custom exercises, and routines in a single package.
- [x] **Migration Layer**: Future-proof import logic that handles older data formats.

## 🚧 Partially Implemented
- [/] **Volume Analytics**: Detailed heatmaps and weekly volume tracking per muscle group.
- [/] **Routine Management**: Advanced planning features like split-cycles (PPL, Upper/Lower) are currently basic.

## 📅 Future Roadmap
- [ ] **Personal Best Celebrations**: Visual rewards for hitting new estimated 1RMs.
- [ ] **Strength Standards**: Comparison of your current strength against global athletic standards (Beginner, Intermediate, Elite).

---

### 🛠️ Technical Stack
- **Core**: React 19 + Vite
- **State**: React Hooks (useHistory, useExercises, useRoutines) + Context API (Dialog/Modal)
- **Logic**: Strive Engine (Brzycki estimation + Cross-Muscle Calibration)
- **Styling**: Vanilla CSS (Modern CSS Variables + HSL Colors)
- **Deployment**: GitHub Actions + GitHub Pages
